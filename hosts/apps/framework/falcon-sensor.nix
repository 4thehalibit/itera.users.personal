# CrowdStrike Falcon sensor — the corporate EDR agent. Framework-only for the
# same reason as netskope.nix: the tenant is work infrastructure, so this file
# is imported from hosts/framework.nix rather than hosts/common.nix, and the
# flake module arrives through specialArgs instead of the every-host `modules`
# list.
#
# Module + packaging: github:lcleveland/falcon-sensor. The sensor itself is
# proprietary and non-redistributable, so nothing is vendored: the host fetches
# its own .deb from the tenant's API at activation time.
#
# THREE SECRETS, none of which may live in this repo (it is public) or in the
# nix store (the module asserts `!inStore` on every secret path). Same pattern
# as netskope.nix — hand-created under /persist/secrets, 0400, root-owned:
#
#   In the Falcon console: Support and resources -> API clients and keys ->
#   Create API client, named  LS-04391-sensor-download , with the single scope
#   "Sensor Download: read". Copy the client id and secret (the secret is shown
#   once). Then:
#
#     sudo bash -c 'install -d -m 0700 /persist/secrets; for f in \
#       falcon-api-client-id falcon-api-client-secret falcon-cid; do \
#       printf "%s: " "$f"; read -rs v; echo; \
#       printf %s "$v" > /persist/secrets/$f; chmod 0400 /persist/secrets/$f; done'
#
#   It prompts for the three values in that order, with the input hidden. Typed
#   at a prompt rather than passed as an argument on purpose: an argument lands
#   in shell history and is readable in /proc while the command runs, and the
#   API client secret is shown only once at creation, so leaking it means
#   generating a new one. `sudo bash -c` because the interactive shell here is
#   nushell, which does not take a POSIX pipeline.
#
#   `printf %s` writes no trailing newline, though one would in fact be
#   tolerated: the fetcher does `tr -d '\n'` on the API files, and the CID is
#   read through `$(cat ...)`, which strips trailing newlines itself.
#
#   The CID is the tenant's customer id, format 0123456789ABCDEF0123456789ABCDEF-01.
#   Get it from the console under Host setup and management -> Deploy -> Sensor
#   downloads, or from the find-sensor run below, which prints it.
#
# THE SECRETS MUST EXIST BEFORE ACTIVATION. Without them
# falcon-sensor-fetch.service fails at boot; the config still evaluates, so a
# rebuild is safe, but the sensor will not install.
#
# PINNING THE SENSOR VERSION. `hash` is left null below, which means the host
# installs whatever the tenant's update policy resolves to — convenient, but
# non-deterministic, and it asks the API on every boot which build to use. To
# pin, list what the tenant offers and paste one hash in:
#
#     nix run github:lcleveland/falcon-sensor#find-sensor -- \
#       --client-id-file /persist/secrets/falcon-api-client-id \
#       --client-secret-file /persist/secrets/falcon-api-client-secret
#
{
  falcon-sensor,
  pkgs,
  ...
}:
{
  imports = [ falcon-sensor.nixosModules.default ];

  services.falcon-sensor = {
    enable = true;

    # Never `cid = "..."` — this repo is public.
    cidFile = "/persist/secrets/falcon-cid";
    api.clientIdFile = "/persist/secrets/falcon-api-client-id";
    api.clientSecretFile = "/persist/secrets/falcon-api-client-secret";

    # eBPF rather than a kernel module. itera tracks nixos-unstable, so the
    # kernel moves faster than CrowdStrike's supported-kernel list; the kernel
    # backend would drop into Reduced Functionality Mode on every bump that
    # outruns them. The user-space backend has far looser kernel requirements.
    # Check with `/opt/CrowdStrike/falconctl -g --rfm-state --rfm-reason`.
    backend = "bpf";

    # Publish /run/falcon-sensor/status.json so an unprivileged session can read
    # the sensor's state without falconctl (which is root-only). Required by
    # tray.enable — the module asserts it.
    status.enable = true;

    # Deliberately NOT set: status.includeIdentifiers. It would publish the AID
    # and CID in a world-readable file, and the tray does not need either.

    tray = {
      enable = true;

      # Custom icons. The upstream package draws a coloured shield; these are a
      # falcon head instead, in the Astros palette's semantic state colours (see
      # hosts/apps/common/astros-theme.json) so they sit on the navy bar rather
      # than fighting it.
      #
      # NOTE the upstream icons are the flake author's own generic shield, NOT
      # CrowdStrike's falcon mark, so this is taste and theme fit — there is no
      # trademark problem being solved here.
      #
      # Overriding by postInstall rather than forking: the package bakes
      # FALCON_TRAY_ICON_PATH="$out/share/falcon-sensor/icons" into its wrapper
      # in preFixup, which runs after postInstall, so replacing the files at
      # that same path is all that is needed. Both locations are overwritten —
      # the flat dir is what StatusNotifierItem hosts read via IconThemePath,
      # and the hicolor copy covers hosts that resolve through the icon theme.
      # The four names come from ICONS in tools/falcon-sensor-tray.py.
      package = pkgs.falcon-sensor-tray.overrideAttrs (old: {
        postInstall = (old.postInstall or "") + ''
          for state in protected degraded inactive unknown; do
            src=${./falcon-icons}/falcon-sensor-$state.svg
            install -Dm644 "$src" "$out/share/falcon-sensor/icons/falcon-sensor-$state.svg"
            install -Dm644 "$src" "$out/share/icons/hicolor/scalable/status/falcon-sensor-$state.svg"
          done
        '';
      });
    };
  };

  # The sensor's device identity lives here. WITHOUT THIS the wiped root throws
  # the Agent ID away on every boot and the machine re-registers as a brand new
  # host — so the Falcon console fills up with duplicates of LS-04391 and its
  # detection history restarts daily.
  #
  # The upstream module deliberately does not set environment.persistence
  # itself, to avoid clashing with whatever the host already declares, and
  # itera's curated persist list does not cover /var/lib/falcon-sensor. So it is
  # ours to declare. statePath's default is this path; they must stay in step.
  itera.impermanence.directories = [ "/var/lib/falcon-sensor" ];
}
