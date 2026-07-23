# Settings shared by every host (currently just `framework`). itera's opinionated
# defaults are already on (opt-out via mkDefault); this file sets what deviates
# plus the single user. Structure mirrors lcleveland/itera.personal.
#
# Scope decision: only genuinely personal items are ported from eiros. Shell,
# terminal, editor and desktop theme adopt itera's defaults (nushell, wezterm,
# zed, default DMS theme) rather than porting the old eiros customizations.
{ ... }:
{
  imports = [
    # Apps actually used. GUI apps install per-user; CLI/services in their module.
    ./apps/common/teams.nix
    ./apps/common/zoom.nix
    ./apps/common/yubico.nix
    ./apps/common/onlyoffice.nix
    ./apps/common/cider.nix
    ./apps/common/vesktop.nix
    ./apps/common/caprine.nix
    ./apps/common/linphone.nix
    ./apps/common/nautilus.nix
    ./apps/common/dev-tools.nix

    # Kept personal automations / tools.
    ./apps/common/teams-music-pause.nix # pause music when Teams grabs the mic
    ./apps/common/vonage-directory.nix # Super+Shift+P Linphone-contacts lookup
    ./apps/common/keybinds-cheatsheet.nix # Super+F1 keybind/alias popup
    ./apps/common/personal-commands.nix # fixhdmi, claude, freshworks, deploy, rebuild
    ./apps/common/mango-keybinds.nix # personal mango keybinds (hardware-agnostic)
    ./apps/common/wezterm.nix # force OpenGL front-end (WebGpu crashes 2nd window on amdgpu)
  ];

  # Git identity. No upstream itera battery for this yet, so write ~/.gitconfig
  # directly through hjem — it is re-linked every boot, so it needs NO
  # impermanence persistence.
  hjem.users.vwestberg.files.".gitconfig".text = ''
    [user]
    	name = Vincent Westberg
    	email = vwestberg@lselectric.com
  '';

  # NinjaOne remote session player: installs ncplayer + registers the ninjarmm://
  # URL handler. Replaces the old impure ~/private/*.deb + --impure workflow.
  programs.ninjarmm-ncplayer.enable = true;

  # Allow vesktop's pinned electron (see apps/common/vesktop.nix note).
  nixpkgs.config.permittedInsecurePackages = [ "electron-40.10.5" ];

  # Recurring "DNS down" fix (memory: DNS/DNSSEC). systemd-resolved was rejecting
  # unsigned answers; disable DNSSEC validation. (New option path; the old
  # services.resolved.dnssec was renamed.)
  services.resolved.settings.Resolve.DNSSEC = "false";

  itera = {
    # Claude Code CLI, system-wide + ~/.claude / ~/.claude.json state persisted
    # across the wiped root. Also wires Claude into itera's default Zed editor.
    ai.claude.enable = true;

    # Pin the NixOS release the stateful data matches. Set ONCE at install time.
    nix.stateVersion = "25.11";

    # The `itera` command's rebuild/update verbs build from this flake. Point it
    # at the GitHub remote so rebuilds need no checkout on disk.
    # CHANGE if the repo lands somewhere other than 4thehalibit.
    update.flake = "github:4thehalibit/itera.users.personal";

    hardware.cpu = "amd";

    # Desktop: mango (dwl/wlroots) + DankMaterialShell. mango is opt-in.
    desktop.mango.enable = true;

    # Extra home dirs to persist beyond itera's curated set (which already keeps
    # .config/.local/.cache/.ssh/.claude/Documents/Downloads). These two hold
    # data restored from the Ventoy backup by install.sh — without persisting
    # them the restored copies would vanish on the first wiped-root boot.
    #   Pictures — screenshots + saved images
    #   Vonage   — Linphone contacts CSV/VCF used by the Super+Shift+P popup
    #              (see apps/common/vonage-directory.nix, which flagged this gap)
    impermanence.users.vwestberg.directories = [
      "Pictures"
      "Vonage"
    ];

    users.vwestberg = {
      description = "Vincent Westberg";
      extraGroups = [
        "wheel"
        "networkmanager"
        "libvirtd"
        "docker"
        "input"
        "dialout" # LED-matrix serial + kbd backlight (framework)
      ];
      # First-boot password (defaults to the username otherwise). CHANGE after
      # first login with `passwd`. A secrets-managed password can be added later
      # (agenix + users.users.vwestberg.hashedPasswordFile).
      initialPassword = "changeme";
      # GUI apps are installed per-app under ./apps/common/*.nix via
      # `itera.users.vwestberg.packages`, matching itera.personal's idiom.
    };
  };

  # nixos-rebuild without a password prompt (eiros applications/sudo.nix).
  security.sudo.extraRules = [
    {
      users = [ "vwestberg" ];
      commands = [
        {
          command = "/run/current-system/sw/bin/nixos-rebuild";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];

  # DankMaterialShell greeter/lock should not require a fingerprint
  # (eiros applications/dankshell_pam.nix).
  security.pam.services.dankshell.fprintAuth = false;

  # earlyoom: prefer killing browsers under memory pressure
  # (eiros applications/earlyoom.nix, re-expressed as the plain NixOS module).
  services.earlyoom = {
    enable = true;
    extraArgs = [
      "--prefer"
      "(^|/)(firefox|chromium|vivaldi)$"
    ];
  };
}
