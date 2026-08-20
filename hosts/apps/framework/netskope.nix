# Netskope Client for Linux — the corporate SASE/SSE endpoint agent (steers this
# machine's traffic through the lselectric tenant). Framework-only: the tenant is
# work infrastructure, so this file is imported from hosts/framework.nix rather
# than hosts/common.nix, and the flake module comes in through specialArgs
# (see flake.nix) instead of the every-host `modules` list.
#
# The module + packaging live in github:lcleveland/netskope-client. Modelled on
# lcleveland/itera.personal's hosts/apps/framework/netskope.nix, which is the
# host-verified reference for this same tenant on the same hardware.
#
# Enrolling from NixOS needed several upstream fixes, one of which is broadly
# relevant: the client verifies TLS with a compiled-in OpenSSL CApath of
# /etc/ssl/certs, and NixOS puts no hashed <subject-hash>.<seq> symlinks there, so
# it finds zero trust anchors and every request dies with "self-signed certificate
# in certificate chain". The module bind-mounts a rehashed trust dir over
# /etc/ssl/certs for its own units. SSL_CERT_DIR / SSL_CERT_FILE / CURL_CA_BUNDLE
# do not help.
{
  netskope,
  config,
  pkgs,
  ...
}:
{
  imports = [ netskope.nixosModules.default ];

  services.netskope = {
    enable = true;

    # Short tenant name. The module derives the installer URL from it
    # (https://download-lselectric.goskope.com/dlr/linux/get — public, no auth,
    # verified: plain HTTP 200, no credentials).
    tenant = "lselectric";

    # Hash of the fetched NSClient.run. NOT universal — Netskope rebuilds the
    # installer per tenant and version, so this pins the exact build upstream
    # packaged (v140.0.2.2763). It changes whenever the tenant is moved to a new
    # client release, and the fetch then fails loudly with a hash mismatch.
    # Re-pin with:
    #
    #   nix store prefetch-file --name NSClient.run \
    #     "https://download-lselectric.goskope.com/dlr/linux/get"
    #
    # Verified current: the endpoint still serves 25,234,620 bytes, last-modified
    # 2026-08-01, matching this pin. The client cannot self-update on NixOS
    # (immutable store), so bumping this hash IS the update path — which is why
    # `autoUpdate` is left at its default of false.
    hash = "sha256-lOAsV+/zV1KNZBraDw8qa7nL4SDu0GH3who7fgLhQTI=";

    # Tray UI — two per-user services wired to graphical-session.target:
    # stagentapp (the watchdog / session IPC broker) and stagentui (the GTK tray
    # icon). The tray is the only place the client surfaces its enrollment and
    # steering status, which is worth the GTK+WebKit closure on a desktop host.
    # DankMaterialShell provides the StatusNotifier host it registers against.
    enableTray = true;

    # Start at boot. Was false for part of 2026-08-20, after the first boot that
    # actually steered took the network down at home; set back to true the same day
    # once the cause was found and fixed. Read the next three paragraphs before
    # touching this, because the safety of `true` is conditional on that fix.
    #
    # What was learned that day, because it inverts the earlier reading of this
    # host: steering had never been exercised anywhere. The tenant runs
    # on-premises detection against http://10.20.100.254/#connection and
    # http://10.10.0.1/#connection. At the office those answer 200, the client
    # marks itself on-prem, and Internet Security stays Disabled, so it stands
    # down and does nothing. Every healthy-looking day at work was that, not a
    # working tunnel. Off-prem both probes fail, steering engages for real, and
    # on this host all name resolution dies within ~25s (getaddrinfo err 11,
    # EAI_AGAIN). That cascades: the client cannot resolve gateway.npa.goskope.com,
    # GSLB fetches time out, the steering config / exception list / bypass list
    # downloads all fail with Error -2, and the tunnel finally drops with
    # "Tunnel Down Due to SSL Error". Evidence is in app/eventcache.json and
    # app/logs/{nsdebuglog,npadebuglog}.log under statePath, which persist.
    #
    # Ruled out, so nobody re-treads them: home-subnet overlap (the exception list
    # bypasses 192.168.0.0-192.168.255.255, 10/8 and 172.16/12 outright, and home
    # is 192.168.4.0/22); DNSSEC (resolved.conf is byte-identical between the
    # working and broken generations); and the LAN resolver mishandling goskope.com
    # (192.168.4.46 resolves every Netskope endpoint correctly).
    #
    # SOLVED 2026-08-20, and this is why `true` is safe again. The client reads the
    # uplink's resolver out of systemd-resolved and installs a /32 host route for it
    # pointing into the tunnel. That /32 beats the LAN bypass on longest-prefix
    # match, so DNS to a LAN resolver is steered to a POP that cannot route RFC1918
    # and is blackholed:
    #
    #   192.168.4.46      dev sta0 scope link metric 100        <- /32, wins
    #   192.168.0.0/16    via 192.168.4.1 dev eth0 metric 100   <- bypass, loses
    #
    # Only marked UDP is affected; unmarked TCP to the same host is untouched, which
    # is why it presented as "all DNS dead, everything else fine". rpfilter is ruled
    # out (TCP and ICMP stayed up through the whole outage), as is private app scope
    # (tested with a user-scoped steering config excluding [DNS - AD Domain]).
    #
    # The fix is hosts/apps/framework/unbound.nix: a local recursive resolver on
    # 127.0.0.1, with resolved pinned to it via Domains=~.. The client still installs
    # its /32 — it becomes `127.0.0.1 dev sta0` — but that is inert, because rule
    # priority 0 (`lookup local`) always matches loopback before the fwmark rule at
    # priority 1 ever sees it. A loopback resolver is somewhere this defect
    # structurally cannot reach. Verified with a 120s steering run: dns=1 throughout
    # and TLSca=1 from t+17s, i.e. tunnel up and inspecting while the host stays
    # usable. So: do NOT move DNS back onto a LAN address on this host.
    #
    # Know what flipping this back to true commits to: the moment the tunnel
    # connects the client takes
    # over all web traffic, and this tenant sets allowClientDisabling=false, so
    # `stAgentCli disable` is refused and the daemon reinstates its rules whenever
    # it restarts. There is no runtime off-switch worth relying on.
    #
    # So if a boot comes up with the network broken, the recovery path is manual
    # and worth having memorised BEFORE it is needed. Stopping is not as simple as
    # it looks: `systemctl stop` alone does not do it, because its shutdown path
    # does network work that hangs precisely when the network is down, and
    # `kill -s KILL` alone does not either, because the unit is Restart=always.
    # Marking it stopping first is what prevents the restart:
    #
    #   systemctl stop --no-block stagentd && systemctl kill -s KILL stagentd
    #
    # A killed client cleans up nothing, so then undo its plumbing by hand:
    #
    #   ip rule del fwmark 0x5 table 9
    #   ip route flush table 9
    #   ip link del sta0
    #
    # With autoStart false a bad run costs one command rather than a reboot into
    # an older generation, which is why it is the right setting whenever the DNS
    # path above is in doubt — after a client version bump, a tenant policy change,
    # or any change to unbound.nix. netskope-client's
    # tools/steering-test.sh wraps the start/probe/back-out cycle in a dead-man's
    # switch and is the right way to test here and after any client version bump or
    # tenant policy change. Its icmp probe is the one to watch: ping surviving while
    # dns and tcp die means the return path is being dropped, not the link.
    #
    # Caution specific to THIS host: the mt7921e wifi stalls every ~15-20 minutes
    # in a state that looks identical to a dead tunnel (associated, no packets).
    # Do not enable any fail-closed behaviour until that is resolved, and suspect
    # the wifi first when steering looks dead on a wireless link. Note the tenant
    # already has it on: nsuser.conf carries "failCloseStatus": "true", which is
    # worth raising with the L&S Netskope admin alongside the off-prem failure.
    autoStart = true;

    # SSL-inspection CA. Netskope MITMs TLS, so once steering is live anything
    # that does not trust this CA gets certificate errors — under steering,
    # example.com is served by CN=ns-swg.ca.lselectric.goskope.com and plain curl
    # fails with "self-signed certificate in certificate chain".
    #
    # No caCertFile, deliberately. The certificate only exists as a file the
    # client fetches at runtime into /var/lib/netskope/ca-anchors, and a NixOS
    # trust store is assembled at build time — a runtime file cannot feed it, and
    # under flakes it cannot even be read at eval ("access to absolute path ... is
    # forbidden in pure evaluation mode"). Rather than commit this tenant's
    # inspection CA into a public repository, upstream assembles the bundle at
    # runtime and bind-mounts it over /etc/ssl/certs, rebuilding when the tenant
    # rotates. Inert until the client fetches anything: before then the mount is
    # byte-for-byte the system trust store.
    trustCA = true;

    # Declarative enrollment. The two tenant secrets — the org key (Windows
    # `token=`) and the secure-enrollment auth token (Windows `enrollauthtoken=`)
    # — stay OUT of this repo, in root-only files that survive the ephemeral root.
    # Create them BEFORE the first rebuild that enables this:
    #
    #   sudo install -d -m 0700 /persist/secrets
    #   printf %s '<org key>'    | sudo install -m 0400 /dev/stdin /persist/secrets/netskope-orgkey
    #   printf %s '<auth token>' | sudo install -m 0400 /dev/stdin /persist/secrets/netskope-authtoken
    #
    # These options are `str`, not `path`, precisely so the values are read at
    # runtime via systemd LoadCredential and never enter the world-readable store.
    # Without the files, netskope-enroll.service fails on every boot (the daemon
    # still starts — it only `wants` the enroll unit). The unit is self-verifying:
    # it checks that a branding file actually landed, because installerutil exits
    # 0 even when the tenant rejects the enrollment.
    #
    # `email` is not optional, and it is what the tenant enrolls the device
    # against. With neither email nor upn set, the client picks UPN mode and
    # resolves the AD domain through `realm list`, which fails on a host that is
    # not domain-joined. It must match the address provisioned in the tenant.
    #
    # Note also what is NOT set: tenantHost. Its default is the BARE tenant
    # hostname, lselectric.goskope.com, which is correct — the client prefixes
    # `addon-` itself. The Windows deployment string's
    # `host=addon-lselectric.goskope.com` is the addon host and must not be pasted
    # here; upstream asserts against the prefix at eval time.
    enrollment = {
      orgKeyFile = "/persist/secrets/netskope-orgkey";
      authTokenFile = "/persist/secrets/netskope-authtoken";
      email = "vwestberg@lselectric.com";
    };
  };

  # The package installs everything under $out/opt/netskope/stagent and ships no
  # $out/bin, so the module's `environment.systemPackages = [ cfg.package ]` puts
  # no commands on PATH — leaving no way to ask the client what it is doing.
  #
  # These symlinks MUST point at /opt/netskope/stagent rather than into the store.
  # The client's IPC layer (NSCom2) authenticates peers by resolving the
  # connecting process's /proc/<pid>/exe against a hard-coded allowlist of
  # /opt/netskope/stagent/{stAgentApp,stAgentCli,stAgentUI,nsdiag,bwansvc} — the
  # constraint that forced upstream to bind-mount the app dir instead of
  # symlinking binaries in from the store. Exec'ing through this symlink chain
  # makes /proc/<pid>/exe read back as /opt/netskope/stagent/stAgentCli, so the
  # peer check passes; a store-resident copy is rejected with "NSCOM2 invalid
  # client connection".
  #
  # Note when running it: stAgentCli rejects peers whose LD_LIBRARY_PATH contains
  # a /nix/store path as code injection, so use
  #   env -u LD_LIBRARY_PATH stAgentCli show-status
  environment.systemPackages = [
    (pkgs.runCommandLocal "netskope-cli" { } ''
      mkdir -p $out/bin
      ln -s /opt/netskope/stagent/stAgentCli $out/bin/stAgentCli
      ln -s /opt/netskope/stagent/nsdiag $out/bin/nsdiag
    '')
  ];

  # Impermanence. The client hard-codes /opt/netskope/stagent and writes its state
  # there, so upstream keeps the real directory at `statePath`/app and bind-mounts
  # it onto that path (a bind, not a symlink, so /proc/<pid>/exe keeps the
  # hard-coded path the IPC peer check demands — see the CLI note above). That
  # makes statePath the single thing an impermanent host has to persist: it holds
  # the device identity (.mid, provisioning), the config, the enrollment result,
  # and data/ + logs/. itera's curated persist list does not cover it, so declare
  # it here — otherwise every reboot looks like a fresh install to Netskope, which
  # re-registers the device in the tenant and can burn license seats.
  #
  # This entry is ALSO load-bearing for the daemon starting at all, which is easy
  # to miss. itera mounts /var noexec, and since upstream's rework the app dir
  # holds REAL ELF binaries (previously symlinks into /nix/store, which exec from
  # the store's own mount). Verified on this host: /var is tmpfs with noexec and a
  # binary under it fails to exec, while the persisted /var/lib/* binds come from
  # the exec-capable /persist btrfs subvolume with no noexec flag — mount flags
  # are per-mount and are NOT inherited from the parent mount — and
  # netskope-setup's second bind (app -> /opt) preserves that. Drop this entry and
  # stagentd dies on exec, not merely on lost state.
  #
  # Ordering is handled upstream: netskope-setup carries
  # RequiresMountsFor=/var/lib/netskope, so it waits for the bind mount below.
  #
  # Nothing under /opt is persisted, and it must stay that way — those files are
  # refreshed from the store whenever the package changes, and a persisted /opt
  # would shadow the bind mount. Mode 0700 on statePath is deliberate and safe:
  # nothing reaches the state through this path. The per-user stAgentUI/stAgentCli
  # read data/nsusercert.p12 via /opt/netskope/stagent/data, so they never
  # traverse statePath itself, and netskope-setup sets app/, data/ and logs/ to
  # 0755 inside.
  itera.impermanence.directories = [
    {
      # Tracks the module's own option so the two cannot drift apart.
      directory = config.services.netskope.statePath;
      mode = "0700";
    }
  ];
}
