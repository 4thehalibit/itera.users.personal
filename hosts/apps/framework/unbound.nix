# Local recursive resolver, so DNS stops depending on whatever the network hands out.
#
# THE SPECIFIC PROBLEM. With Netskope steering live off-premises, all DNS died
# within seconds. Proven 2026-08-20 by a protocol x destination matrix taken under
# live steering (tools/steering-test.sh from the netskope-client source):
#
#   udp 53    -> 192.168.4.46 (home Pi-hole)   TIMEOUT   <- the only failure
#   tcp 53    -> 192.168.4.46 (same host)      OK
#   tcp 20720 -> 192.168.4.46 (its web UI)     HTTP 200
#   udp 53    -> 1.1.1.1                       OK
#   tcp 53    -> 1.1.1.1                       OK
#
# Only the intersection of UDP and a LAN destination fails. The client reads the
# uplink's resolver out of systemd-resolved (`nsDnsMgr::readSystemdResolvedUplink
# DnsServer`) and installs a /32 host route for it pointing into the tunnel:
#
#   192.168.4.46      dev sta0 scope link metric 100        <- /32, wins
#   192.168.0.0/16    via 192.168.4.1 dev eth0 metric 100   <- the LAN bypass, loses
#
# The bypass IS present and correct; a /32 simply beats a /16. `ip route get
# 192.168.4.46 mark 0x5` resolves to sta0 while the unmarked lookup resolves to
# eth0. Marked UDP goes into a tunnel whose far end cannot reach RFC1918 and is
# blackholed; unmarked TCP to the same host is untouched. That Pi-hole was the only
# resolver here, so one gap took down all name resolution and looked like total loss
# of internet.
#
# Ruled out, so nobody re-treads it: reverse-path filtering (TCP and ICMP stayed up
# throughout), the tenant exception list (`Local IP address range` is present and
# its 10/8 half installs correctly), private app scope (tested with a user-scoped
# steering config excluding `[DNS - AD Domain]` — no change), DNSSEC, and the web
# steering path (`Steer non-standard ports` is off, so nothing there sees port 53).
#
# Notably the client installs that /32 whatever the resolver is — pointing DNS at
# the gateway instead produced `192.168.4.1 dev sta0` and yet DNS kept working for
# a full 120s run. So the /32 alone is not the whole story; the client's own
# "bypass DNS query to uplink server" path evidently succeeds for a gateway and
# fails for an arbitrary LAN host. Unresolved, and worth reporting upstream.
#
# WHY A RECURSIVE RESOLVER RATHER THAN A ROUTE FIX OR A FORWARDER. This laptop
# travels: hotel and coffee-shop wifi. Three designs were measured on this host:
#
#   - Forward to the Pi-hole over TCP with forward-first fallback. Filtering worked
#     at home (mask.icloud.com -> NXDOMAIN in 2ms), but away from home the
#     unreachable forwarder stalled the first several lookups past 10s each. A TCP
#     connect to an unreachable LAN address hangs, and forward-first waits for it on
#     every new name. Lowering outbound-msg-retry and unknown-server-time-limit did
#     not fix it. Any config that statically depends on a home-only host does this
#     on every other network.
#   - Forwarding to public resolvers as well. Rejected: unbound spreads queries
#     across upstreams by RTT rather than treating list order as priority, so the
#     Pi-hole was bypassed at random and filtering became intermittent (verified:
#     mask.icloud.com came back with 9 real answers).
#   - Recursion. Measured 48-308ms cold, 0ms cached, every name resolved. No
#     dependency on a home-only host or on any third party to trust, be throttled
#     by, or be blocked from.
#
# Recursion won on reliability, which was the requirement. The cost is explicit and
# accepted: NO ad-blocking on this host. Other devices at home still get the
# Pi-hole via DHCP; this one no longer asks it. If filtering here matters later, the
# way to get it without the stall is a NetworkManager dispatcher that switches a
# Pi-hole forward-zone on only while actually on the home network — deliberately not
# done, because a dispatcher bug becomes a DNS bug.
{ config, ... }:
{
  services.unbound = {
    enable = true;

    # Deliberately NOT resolveLocalQueries. With resolved enabled it collapses to
    # `networking.nameservers = mkBefore [ "127.0.0.1" "::1" ]`, because resolved
    # sets networking.resolvconf.enable = false and owns /etc/resolv.conf. The
    # resolved options below say the same thing without the indirection.
    #
    # The interface list is left at its default, [ "127.0.0.1" "::1" ], and must
    # stay address-specific: resolved's stub holds 127.0.0.53:53 and libvirt's
    # dnsmasq holds 192.168.122.1:53. Binding 0.0.0.0 would collide with both, and
    # resolved silently drops its stub when its address is already taken — a race
    # decided by start order.
    resolveLocalQueries = false;

    # No DNSSEC validation, matching the resolved decision in hosts/common.nix and
    # for the same reason: validation kept rejecting unsigned answers and presented
    # as recurring "DNS down". Both halves are needed — dropping the trust anchor
    # without dropping the validator module just runs unbound-anchor for nothing.
    enableRootTrustAnchor = false;

    settings.server = {
      # Quotes are mandatory in unbound.conf and the module adds none. Without
      # this it is "validator iterator".
      module-config = ''"iterator"'';

      # No forward-zone at all: this is a full recursive resolver, talking to the
      # root servers and down. That is what makes it behave the same on every
      # network. Recursion goes out over UDP to public addresses, which the matrix
      # above proves is the half of steering that works.

      # The cache is what keeps recursion off the hot path — cold lookups are
      # 50-300ms, repeats are 0ms. prefetch refreshes popular entries before they
      # expire so the common case stays warm.
      cache-min-ttl = 60;
      cache-max-ttl = 86400;
      prefetch = true;

      # `.local` belongs to the Netskope tunnel while it is up (netskope-npa-dns
      # puts `~local` on sta0) and to mDNS via avahi otherwise, so resolved routes
      # those names away before unbound ever sees them. Anything that still reaches
      # here must be answered locally, NOT recursed: `local` is not one of unbound's
      # default local zones, so without this every stray `*.lselectric.local` lookup
      # would be sent to the root servers, leaking internal hostnames. `static`
      # answers NXDOMAIN from here and never leaves the host. (`nodefault` would be
      # wrong — it only disables default zone contents, which for `local` do not
      # exist, leaving the leak in place.)
      domain-insecure = "local";
      local-zone = [ ''"local." static'' ];
    };
  };

  # Resolved stays in front of unbound rather than being replaced. It is worth
  # keeping: `resolvectl` is what netskope-npa-dns is built on (it routes `.local`
  # to the tunnel resolver, and without resolved that unit fails and restart-loops),
  # per-link scoping keeps working, and itera wires resolved.suppressAAAA through to
  # nscd's RES_OPTIONS=no-aaaa.
  services.resolved.settings.Resolve = {
    # Send everything to unbound.
    DNS = [ "127.0.0.1" "::1" ];

    # THE line that makes this work, and the easiest one to leave out. A global
    # `DNS=` alone is not enough: resolved documents that global servers are used
    # *in parallel to* per-link servers, and a query matching no routing domain goes
    # to every link that is a default route AND to the global server, first answer
    # winning. So NetworkManager's DHCP-supplied 192.168.4.46 on eth0 would still be
    # queried directly, over UDP, and DNS would be intermittent rather than fixed.
    #
    # `~.` is a route-only domain for the DNS root, a suffix of every name, so all
    # queries match the global scope and eth0 is used only for names under its own
    # domains. Per-link DNS stays *visible* to resolvectl (which netskope-npa-dns
    # needs) while being unused for ordinary lookups. `~local` on sta0 has more
    # labels than `.`, so Private Access split-horizon still beats this.
    Domains = [ "~." ];

    # Kill the compiled-in fallback list (1.1.1.1/8.8.8.8/9.9.9.9). Those are
    # reached over UDP and would be a silent bypass of everything above.
    FallbackDNS = "";
  };

  # Resolved starts long before unbound: resolved is DefaultDependencies=no and
  # Before=sysinit.target, unbound is After=network.target. For that window the
  # global scope points at a closed port. Resolved caches per-server feature probing
  # and keeps talking to the same server until it sees an error, so it can sit on a
  # downgraded feature level for 127.0.0.1 long after unbound is healthy. Reset it
  # once unbound has signalled ready — safe because the unit is Type=notify, so
  # ExecStartPost runs after readiness. The `+` prefix is required: User=unbound.
  #
  # No After=/Wants= between the two on purpose. Their only coupling is a loopback
  # socket, which is retry-and-recover, and ordering unbound before resolved would
  # need it before network.target and risk a cycle. nss-lookup.target already
  # sequences anything that genuinely needs a working resolver.
  systemd.services.unbound.serviceConfig.ExecStartPost = [
    "+${config.systemd.package}/bin/resolvectl reset-server-features"
    "+${config.systemd.package}/bin/resolvectl flush-caches"
  ];
}
