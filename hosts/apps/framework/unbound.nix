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

      # This WAS a full recursive resolver, talking to the root servers and down.
      # That stopped working on 2026-09-10: the steering now drops both UDP/53 AND
      # TCP/53 to entire TLD server sets, so no transport toggle can help and every
      # delegation through an affected TLD SERVFAILs. Measured under live steering:
      #
      #   udp/tcp 53 -> 198.41.0.4     a.root-servers.net     OK   / OK
      #   udp/tcp 53 -> 192.5.6.30     a.gtld-servers.net     OK   / OK      (com, net)
      #   udp/tcp 53 -> 199.19.56.1    a0.org.afilias-nst     FAIL / FAIL    (org)
      #   udp/tcp 53 -> 199.249.112.1  a2.org.afilias-nst     FAIL / FAIL    (org)
      #   udp/tcp 53 -> 156.154.100.3  dns1.nic.uk            FAIL / FAIL    (uk)
      #   udp/tcp 53 -> 8.8.8.8                               OK   / OK
      #
      # github.com resolved fine throughout while example.org, www.wikipedia.org and
      # ns-1823.awsdns-35.co.uk all SERVFAILed. app.ninjarmm.com is a CNAME to an AWS
      # ELB whose nameserver set spans com/net/org/co.uk, so it SERVFAILed too and
      # NinjaOne remote broke. It presented as a kernel regression only because the
      # cache carried the old answers until the next reboot.
      #
      # So: forward the root zone to public resolvers reachable on both transports
      # rather than recursing. This is NOT the design rejected in the header — that
      # one mixed the home Pi-hole in with public resolvers and lost filtering to
      # unbound RTT-based upstream selection. No Pi-hole is listed here, so there is
      # nothing to lose to RTT and nothing reachable only at home. The accepted cost
      # is trusting a third party for resolution, taken over DNS that does not work.

      # Recurse over TCP, not UDP. The matrix above recorded `udp 53 -> 1.1.1.1 OK`
      # on 2026-08-20; that is no longer true. Re-measured 2026-09-10 under live
      # steering, UDP/53 to Cloudflare address space is now dropped, while TCP/53 to
      # the same addresses is untouched:
      #
      #   udp 53 -> 162.159.60.1   TIMEOUT   <- blue.foundationdns.com, authoritative
      #   tcp 53 -> 162.159.60.1   OK          for crowdstrike.com
      #   udp 53 -> 1.1.1.1        TIMEOUT   <- was OK in the 2026-08-20 matrix
      #   tcp 53 -> 1.1.1.1        OK
      #   udp 53 -> 216.239.32.10  OK        <- ns1.google.com, not Cloudflare
      #
      # So this is destination-scoped rather than a blanket UDP block, which is why
      # it presents as a handful of arbitrary sites being down rather than as "DNS is
      # down". Any zone whose authoritative servers are Cloudflare-hosted SERVFAILs:
      # falcon.us-2.crowdstrike.com was the report, discord.com, zendesk.com and
      # shopify.com were all failing at the same time, while google.com and
      # github.com were fine. unbound will not recover on its own — it falls back to
      # TCP on a truncated answer, never on a timeout.
      #
      # Global, not per-zone, because the blocked set is a moving tenant policy and
      # unbound has no per-destination transport toggle for recursion. The cost is
      # one extra round trip on a cold lookup; the cache and prefetch below keep it
      # off the hot path, and correctness beats a few ms on names that currently do
      # not resolve at all.
      tcp-upstream = true;

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
      #
      # ORDER OF MECHANISMS MATTERS HERE, and it is not intuitive: local-zone is
      # authoritative local data and is consulted BEFORE any forward-zone. So
      # `"local." static` alone swallows lselectric.local too and answers NXDOMAIN
      # in 0ms, silently defeating the forward-zone below (measured). The second,
      # more specific entry marks AD as `transparent`, which means "no local data
      # here, carry on with normal resolution" — that is what lets the forward-zone
      # see the query. Most-specific local-zone wins, so everything else under
      # `.local` is still answered locally and never leaks.
      local-zone = [
        ''"local." static''
        ''"lselectric.local." transparent''
      ];
    };

    # Active Directory lives at lselectric.local, reachable only through the
    # Netskope tunnel. Send it straight at the domain controllers rather than
    # relying on `netskope-npa-dns` (disabled below), which pushed whatever the
    # *uplink* handed out — at home that is the Pi-hole, which knows nothing about
    # lselectric.local.
    #
    # These two are `[Domain Controller - ENG]` and `[Domain Controller - CORP]`
    # from the tenant's App Definition. As private apps they get /32 host routes
    # into the tunnel while it is up (verified: `ip route get 10.2.75.10 mark 0x5`
    # -> dev sta0), and both answer over UDP through it (verified against
    # ls-corp-cluster.lselectric.local). Deliberately NOT forward-tcp-upstream:
    # the UDP-to-LAN defect that motivated this whole file does not apply here,
    # because these are tunnelled destinations rather than bypassed LAN ones, and
    # the DCs' TCP/53 behaved inconsistently in testing.
    #
    # More specific than the `local.` local-zone above, and unbound matches
    # most-specific-first, so this wins for lselectric.local while every other
    # `.local` name is still answered NXDOMAIN locally and never leaks.
    #
    # No forward-first: if the tunnel is down these are simply unreachable, and
    # falling back to recursion would leak internal hostnames to the root servers
    # for a guaranteed NXDOMAIN. SERVFAIL is the honest answer.
    settings.forward-zone = [
      {
        # Root zone. Inherits the global tcp-upstream above, so these are reached
        # over TCP/53, which the steering leaves alone at every destination measured.
        name = ".";
        forward-addr = [
          "8.8.8.8"
          "8.8.4.4"
          "9.9.9.9"
        ];
      }
      {
        name = "lselectric.local.";
        forward-addr = [
          "10.2.75.10"
          "10.10.80.31"
        ];
        # Opt this zone back out of the global tcp-upstream above, which per-zone
        # forward-tcp-upstream would otherwise inherit. Keeps the DCs on UDP, as the
        # comment above requires: these are tunnelled destinations rather than
        # blocked public ones, and their TCP/53 behaved inconsistently in testing.
        forward-tcp-upstream = false;
      }
    ];
  };

  # Disabled: it does the same job worse. The unit reads the *uplink* link's DNS
  # servers and pushes them onto sta0 as the Private Access resolver, which is only
  # correct when the uplink resolver happens to be a corporate one — never true
  # off-prem, which is the only time steering runs. At home it would nominate the
  # Pi-hole as the AD resolver, and `~local` on sta0 outranks the global `~.`, so it
  # would also override the forward-zone above. The forward-zone names the domain
  # controllers explicitly instead, which is what the unit was reaching for.
  systemd.services.netskope-npa-dns.enable = false;

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
    #
    # `lselectric.local` (no `~`) is a *search* domain, not just a routing one.
    # Without it `search .` is the only suffix list, so resolved refuses every
    # single-label name outright ("No appropriate name servers or networks for
    # name found") and bare corporate hostnames like `ls-corp-hycu` fail while
    # `ls-corp-hycu.lselectric.local` resolves fine. Two labels beats sta0's
    # `~local`, which is the same precedence the forward-zone above already
    # relies on, so Private Access split-horizon is unaffected.
    Domains = [ "~." "lselectric.local" ];

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

  # The mirror image of the above, and the failure it fixes is much easier to
  # misread as "the cluster is down". unbound starts at the same second as the
  # Netskope daemon and roughly 30s before the tunnel is actually bound, so its
  # outgoing sockets and its infra cache are both older than the steering they
  # depend on. Every forward to a domain controller then goes out over the uplink
  # instead of sta0, gets dropped by the gateway, and the whole lselectric.local
  # forward-zone answers SERVFAIL while the DCs themselves answer fine when asked
  # directly. Diagnosed 2026-08-28 against ls-pcs-cluster.lselectric.local:
  #
  #   host ... 10.2.75.10   -> 100.64.0.2    <- DC answers
  #   host ... 127.0.0.1    -> SERVFAIL      <- unbound cannot reach the same DC
  #   tcp 9440 -> 100.64.0.2                 <- and the target was up the whole time
  #
  # `systemctl restart unbound` fixes it, which is the tell that this is socket and
  # cache state rather than routing. The rebind unit is BindsTo=sta0.device and
  # Type=notify, so its ExecStartPost is the exact moment the tunnel is usable, and
  # it fires again on every uplink change - which happens several times a day on a
  # laptop, and re-broke it each time before this.
  #
  # try-restart, not restart: a no-op if unbound is stopped, rather than starting it
  # out of order. --no-block is load-bearing, not tidiness: a synchronous systemctl
  # call from inside another unit's ExecStartPost can deadlock on the job queue.
  systemd.services.netskope-tunnel-rebind.serviceConfig.ExecStartPost = [
    "${config.systemd.package}/bin/systemctl --no-block try-restart unbound.service"
  ];
}
