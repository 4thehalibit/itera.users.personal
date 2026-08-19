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

    # Start the daemon at boot. Steering is now the normal state of this host.
    #
    # Know what this commits to: the moment the tunnel connects the client takes
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
    # If that is not enough, boot the previous generation — with autoStart true
    # the daemon comes back on every boot of THIS one. netskope-client's
    # tools/steering-test.sh wraps the whole start/probe/back-out cycle in a
    # dead-man's switch and remains the right way to re-test after any client
    # version bump or tenant policy change.
    #
    # Caution specific to THIS host: the mt7921e wifi stalls every ~15-20 minutes
    # in a state that looks identical to a dead tunnel (associated, no packets).
    # Do not enable any fail-closed behaviour until that is resolved, and suspect
    # the wifi first when steering looks dead on a wireless link.
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
