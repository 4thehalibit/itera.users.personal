# Settings shared by every host (currently just `framework`). itera's opinionated
# defaults are already on (opt-out via mkDefault); this file sets what deviates
# plus the single user. Structure mirrors lcleveland/itera.personal.
#
# Scope decision: only genuinely personal items are ported from eiros. Shell,
# terminal, editor and desktop theme adopt itera's defaults (nushell, wezterm,
# zed, default DMS theme) rather than porting the old eiros customizations.
{ pkgs, ... }:
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
    ./apps/common/vlc.nix
    ./apps/common/uxplay.nix # AirPlay receiver: iPhone screen-cast to this machine (run `airplay`)
    ./apps/common/nautilus.nix
    ./apps/common/eml-viewer.nix # lightweight .eml viewer (renders to browser)
    ./apps/common/phisher-triage.nix # `phisher` PhishER triage CLI (~/Documents/phisher-triage)
    ./apps/common/dev-tools.nix

    # Kept personal automations / tools.
    ./apps/common/teams-music-pause.nix # pause music when Teams grabs the mic
    ./apps/common/vonage-directory.nix # Super+Shift+P Linphone-contacts lookup
    ./apps/common/keybinds-cheatsheet.nix # Super+F1 keybind/alias popup
    ./apps/common/personal-commands.nix # fixhdmi, claude, freshworks, deploy, rebuild
    ./apps/common/mango-keybinds.nix # personal mango keybinds (hardware-agnostic)
    ./apps/common/wezterm.nix # force OpenGL front-end (WebGpu crashes 2nd window on amdgpu)
    ./apps/common/wallpaper.nix # Astros wallpaper + lock/greeter wallpaper paths
    ./apps/common/flake-update-check.nix # weekly upstream flake check + `flake-news`
  ];

  # Git identity. No upstream itera battery for this yet, so write ~/.gitconfig
  # directly through hjem — it is re-linked every boot, so it needs NO
  # impermanence persistence.
  hjem.users.vwestberg.files.".gitconfig".text = ''
    [user]
    	name = Vincent Westberg
    	email = vwestberg@lselectric.com
  '';

  # GTK: consume DMS's generated palette. DMS's internal matugen writes
  # ~/.config/gtk-{3.0,4.0}/dank-colors.css (32 @define-color entries) on every
  # theme change, but nothing imported it, so GTK apps were themed only by the
  # `GTK_THEME=Adwaita:dark` env var itera sets in desktop/theme.nix — i.e. they
  # ignored the palette entirely. These two one-line stylesheets are the missing
  # consumer. Adwaita stays the theme; the import just re-points its named
  # colors at the Astros palette. There is no upstream itera option for gtk.css,
  # hence hjem directly (same as .gitconfig above, re-linked every boot so it
  # needs no impermanence entry).
  hjem.users.vwestberg.files = {
    ".config/gtk-3.0/gtk.css".text = ''
      @import url("dank-colors.css");
    '';
    ".config/gtk-4.0/gtk.css".text = ''
      @import url("dank-colors.css");
    '';
  };

  # NinjaOne remote session player: installs ncplayer + registers the ninjarmm://
  # URL handler. Replaces the old impure ~/private/*.deb + --impure workflow.
  programs.ninjarmm-ncplayer.enable = true;

  # Allow vesktop's pinned electron (see apps/common/vesktop.nix note).
  nixpkgs.config.permittedInsecurePackages = [ "electron-40.10.5" ];

  # wl-clipboard: wl-copy/wl-paste for CLI clipboard access (already referenced
  # by apps/common/vonage-directory.nix via store path). NOTE: `wtype` was added
  # here on 2026-07-22 to feed the CTRL+SHIFT+V `dms cl paste | wtype -` keybind,
  # but wtype garbled the text (keymap mismatch); the keybind was removed in
  # favour of native app paste, so wtype is gone too. See mango-keybinds.nix.
  environment.systemPackages = with pkgs; [ wl-clipboard ];

  # Run Electron/Chromium apps as native Wayland instead of XWayland. This is the
  # switch teams-for-linux's wrapper gates its screen-share flags on: with
  # NIXOS_OZONE_WL set it launches with --ozone-platform-hint=auto and
  # --enable-features=...,WebRTCPipeWireCapturer, so Teams/Vivaldi screen sharing
  # can reach the wlroots PipeWire screencast portal (xdg-desktop-portal-wlr).
  # Without it Teams fell back to XWayland and screen share silently did nothing.
  # sessionVariables apply at login, so log out/in after deploying.
  environment.sessionVariables.NIXOS_OZONE_WL = "1";

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

    # Auto idle: lock after 8 minutes, suspend after 10 (DMS owns idle/lock/
    # suspend via ~/.config/DankMaterialShell/settings.json; timeouts are in
    # SECONDS, 0 = never). Same on AC and battery. lockBeforeSuspend also locks
    # on any suspend path. DMS respects idle-inhibitors, so a Teams/Zoom call or
    # video playback keeps it awake. Adjust the seconds to change the timeouts.
    programs.dankMaterialShell.settings = {
      # Palette: Houston Astros (modern era) — navy #002D62 + orange #EB6E1F.
      # DMS otherwise falls back to its stock `purple` theme, which is what this
      # replaces. A custom theme is two keys plus one JSON file (DMS
      # Common/Theme.qml switchTheme -> loadCustomThemeFromFile); loading it also
      # runs buildMatugenColorsFromTheme, so DMS's internal matugen regenerates
      # ~/.config/{mango/dms,wezterm/colors,gtk-*,zed/themes}/ from these colors.
      # Of those only the GTK CSS and the Zed theme are actually consumed (see
      # the gtk.css written below and the zed theme override further down) —
      # mango and wezterm get explicit values in their own files instead, since
      # the mango template emits only 3 of its 11 colors and the wezterm one
      # derives its ANSI ramp from Material tones rather than a tuned 16.
      #
      # NOTE ~/.config/DankMaterialShell/settings.json is a read-only nix store
      # symlink, and DMS detects that and refuses to persist — so the in-shell
      # theme picker and `dms ipc call settings set` will NOT stick. Nix is the
      # only working lever. Colors live in the JSON, not here.
      currentThemeName = "custom";
      customThemeFile = "${./apps/common/astros-theme.json}";

      acLockTimeout = 480;
      batteryLockTimeout = 480;
      acSuspendTimeout = 600;
      batterySuspendTimeout = 600;
      lockBeforeSuspend = true;

      # Bar layout. itera ships this list as an mkDefault, and it is one whole
      # value rather than a merged attrset, so adding a single widget means
      # restating the layout here. Kept identical to itera's default apart from
      # the two additions below.
      #
      #   caffeine       click-to-toggle idle inhibitor — the timeouts above
      #                  suspend mid-presentation otherwise. DMS honours
      #                  idle-inhibitors from Teams/Zoom automatically, but a
      #                  slide deck in a browser tab does not take one, which is
      #                  exactly the case this covers. Replaces DMS's built-in
      #                  `idleInhibitor` purely for the icon (see the plugin dir
      #                  registered below); the toggle underneath is the same
      #                  SessionService call, so this pill, the Control Center
      #                  tile and `dms ipc call inhibit toggle` stay in sync.
      #   flakeNews      upstream flake-input report (apps/common/flake-update-check.nix)
      barConfigs = [
        {
          id = "default";
          name = "Main Bar";
          enabled = true;
          position = 0;
          screenPreferences = [ "all" ];
          showOnLastDisplay = true;
          leftWidgets = [
            "launcherButton"
            "workspaceSwitcher"
            "focusedWindow"
          ];
          centerWidgets = [
            "music"
            "clock"
            "weather"
          ];
          rightWidgets = [
            "systemTray"
            "clipboard"
            "cpuUsage"
            "memUsage"
            "ipIndicator"
            "flakeNews"
            "caffeine"
            "notificationButton"
            "battery"
            "controlCenterButton"
          ];
        }
      ];
    };

    # Coffee-cup idle inhibitor referenced by barConfigs above. Attr name must
    # match the `id` in its plugin.json — DMS looks the enabled flag up by
    # manifest id.
    programs.dankMaterialShell.plugins.caffeine.src = ./apps/common/dms-caffeine;

    # Extra home dirs to persist beyond itera's curated set (which already keeps
    # .config/.local/.cache/.ssh/.claude/Documents/Downloads/Pictures). This holds
    # data restored from the Ventoy backup by install.sh — without persisting it
    # the restored copy would vanish on the first wiped-root boot.
    #   Vonage — Linphone contacts CSV/VCF used by the Super+Shift+P popup
    #            (see apps/common/vonage-directory.nix, which flagged this gap)
    #
    # Pictures used to be listed here too. itera adopted it into the curated
    # default set (2026-08-19, core/impermanence.nix), with the same
    # never-auto-cleared semantics, and environment.persistence asserts on
    # duplicate directories — so listing it here now fails the build outright.
    impermanence.users.vwestberg.directories = [
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

      # Editor palette. itera pins Zed to its built-in One Dark/One Light
      # (mkDefault, modules/programs/zed.nix), while DMS's matugen has been
      # generating ~/.config/zed/themes/dank-zed-theme.json from the live
      # palette all along with nothing selecting it. Point Zed at that instead
      # so it follows the Astros theme. `settings` merges SHALLOW per key
      # (system // per-user), so the whole `theme` attrset has to be restated,
      # not just the one field. Theme names come from the generated file's
      # `themes[].name`, NOT the filename.
      programs.zed.settings.theme = {
        mode = "dark";
        dark = "DankShell Dark";
        light = "DankShell Light";
      };
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
