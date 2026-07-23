# framework — Framework 16 (AMD Ryzen 7040) work laptop, hostname LS-04391.
{ itera, pkgs, ... }:
{
  imports = [
    # Framework 16 hardware quirks, re-exported by itera from nixos-hardware.
    # Board selection is an import-time choice, so it lives in `imports`.
    itera.hardwareModules.framework-16-7040-amd
    # Framework-only modules (LED matrix effects, Thunderbolt dock rescan).
    ./apps/framework/kbd-typing-leds.nix
    ./apps/framework/thunderbolt-dock.nix
  ];

  itera = {
    networking.hostName = "LS-04391";
    hardware.cpu = "amd";

    # nixosConfigurations attr is `framework`; hostname (LS-04391) differs, so
    # set it explicitly (else `itera update`/`rebuild` would miss `#framework`).
    update.configuration = "framework";

    # Deliberately-invalid placeholder so the config still evaluates. The real
    # target is chosen at install time with `disko-install --disk main /dev/<disk>`,
    # so you never edit this file to install — and a forgotten `--disk` fails safe.
    disko.device = "/dev/disk/by-id/CHANGE-ME-disko-install-overrides-this";
    disko.swapSize = "32G"; # >= RAM for hibernation

    fingerprint.enable = true;
    printing.enable = true; # hplipWithPlugin + mDNS + GUI (matches eiros work)

    # Plain US QWERTY (eiros xkb_rules_layout = "us", model pc104; no variant).
    keyboard.layout = "us";

    # Three-monitor layout, translated from eiros mangowc.nix monitorrule.
    # Home = single VX3211-4K 4K panel; work = two stacked ViewSonics + laptop.
    # NOTE verify DP-10 rotation direction after first boot (eiros `rr:2`).
    programs.mango.monitors = {
      # Home: single 4K monitor (matched by EDID model, not connector name).
      "VX3211-4K" = {
        model = "VX3211-4K";
        width = 3840;
        height = 2160;
        refresh = 60;
        x = 0;
        y = 0;
        scale = 1.5;
      };
      # Work: DP-10 on top, rotated; DP-9 below.
      "DP-10" = {
        name = "^DP-10$";
        width = 1920;
        height = 1080;
        refresh = 60;
        x = 0;
        y = 0;
        scale = 1;
        transform = "180"; # eiros rr:2 — CONFIRM visually, may be "90"/"270"
      };
      "DP-9" = {
        name = "^DP-9$";
        width = 1920;
        height = 1080;
        refresh = 60;
        x = 0;
        y = 1080;
        scale = 1;
      };
      # Laptop panel: default work position (x=1920); SUPER+h moves it for home.
      "eDP-1" = {
        name = "^eDP-1$";
        width = 2560;
        height = 1600;
        refresh = 165;
        x = 1920;
        y = 580;
        scale = 1.6;
      };
    };
    # nvidia stays OFF (itera.nvidia is opt-in) — matches eiros.

    # Home startup fix: after login, re-sync the VX3211-4K (off/on) so it doesn't
    # come up blank, then move the laptop panel to its home position (2560,220).
    # Harmless at the office (grep finds no VX3211-4K, so the cycle is skipped).
    # wlr-randr is on PATH via apps/common/personal-commands.nix.
    users.vwestberg.programs.mango.extraConfig = ''
      exec-once=sh -c 'sleep 15 && output=$(wlr-randr | grep VX3211-4K | awk "{print \$1}") && [ -n "$output" ] && wlr-randr --output "$output" --off && sleep 2 && wlr-randr --output "$output" --on && sleep 1 && wlr-randr --output eDP-1 --pos 2560,220'
    '';
  };

  # Boot splash: itera's hardening boots fully silent (`quiet loglevel=0
  # udev.log_level=3`), so from bootloader handoff until the DMS greeter paints
  # there was only a black screen — long enough (with all the IOMMU/mitigation
  # params) to look like the machine had hung. Plymouth fills that window with a
  # graphical splash. Plain NixOS option; composes over itera's kernel params.
  #
  # Theme: adi1090x's `deus_ex` — black + gold HUD ring around the OS logo with
  # a subtle rotating arc (warm, futuristic, understated). Override builds ONLY
  # this theme instead of the full ~200-theme pack. Browse alternatives at
  # https://github.com/adi1090x/plymouth-themes then swap the name in both the
  # `theme` string and `selected_themes` list.
  boot.plymouth = {
    enable = true;
    theme = "deus_ex";
    themePackages = [
      (pkgs.adi1090x-plymouth-themes.override { selected_themes = [ "deus_ex" ]; })
    ];
  };

  # MT7922 Bluetooth: eiros pinned kernels to dodge a btmtk Oops; the fix was
  # expected upstream. On itera/unstable it is likely already fixed — VERIFY BT
  # after first boot and only pin a kernel here if it regresses (see eiros memory
  # note). itera.personal deliberately dropped these quirks too.
}
