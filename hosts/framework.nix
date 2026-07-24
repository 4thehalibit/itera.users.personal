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

    # Full-disk encryption (LUKS): wraps the btrfs root (/, /nix, /persist) AND the
    # swap partition, so everything at rest — including the hibernation image — is
    # encrypted. The ESP stays plaintext (firmware must read it). Opt-in in itera.
    #
    # TPM2 auto-unlock: the machine's TPM2 unseals the volume on a trusted boot, so
    # ordinary boots type nothing; the install-time passphrase stays enrolled as a
    # RECOVERY fallback (used only if the sealed PCR state changes — firmware/Secure
    # Boot changes). Enrollment binds to the live TPM, so it happens once on THIS
    # machine: the first boot after an install falls back to the passphrase, then
    # `sudo itera-tpm2-enroll` binds the TPM and every boot after is passwordless.
    #
    # NOTE: TPM unlock without Secure Boot stops a PULLED disk from being read but
    # not a thief who powers the laptop on — enable itera.secureBoot too for that
    # (separate step, can layer on later). usbSupport auto-enables (itera flags the
    # Framework's built-in keyboard as USB-internal) so the recovery prompt is
    # typable — leave it on; do NOT override it to false.
   
    disko.encryption.enable = false;
    
    fingerprint.enable = true;
    printing.enable = true; # hplipWithPlugin + mDNS + GUI (matches eiros work)

    # Plain US QWERTY (eiros xkb_rules_layout = "us", model pc104; no variant).
    keyboard.layout = "us";

    # Three-monitor layout, translated from eiros mangowc.nix monitorrule.
    # Home = single VX3211-4K 4K panel; work = two stacked ViewSonics + laptop.
    # NOTE verify DP-10 rotation direction after first boot (eiros `rr:2`).
    programs.mango.monitors = {
      # Home: single 4K monitor. mango matches monitorrule by the `name:` token
      # against the CONNECTOR name, not the EDID model — a model-only rule never
      # fires (the panel then falls back to scale 1.0 = everything tiny). The
      # ViewSonic comes up on connector DP-4 (HDMI expansion card). `model` kept
      # as documentation/extra constraint. If the connector number ever changes
      # (cards reslotted), update ^DP-4$ — check `wlr-randr`.
      "VX3211-4K" = {
        name = "^DP-4$";
        model = "VX3211-4K";
        width = 3840;
        height = 2160;
        refresh = 60;
        x = 0;
        y = 0;
        scale = 1.5;
      };
      # Work: single 49" ZZY XG49DH16C ultrawide (32:9), native 5120x1440@120.
      # Comes up on connector DP-11 via the USB-C dock (DisplayPort in; the HDMI
      # cable is unplugged on purpose — a second cable makes the dock emit a
      # phantom MST output and splits bandwidth). If the connector number ever
      # changes (dock reslotted / different USB-C port), update ^DP-11$ — check
      # `wlr-randr`. Panel is ~108 PPI so scale 1.0 is native (no scaling).
      # NOTE: full 165Hz needs a DIRECT DisplayPort cable into a Framework DP
      # expansion card (no dock) — the dock's USB-C link caps this at 120Hz.
      # PBP/PIP (a 2nd machine on the monitor's other input) is a monitor-OSD
      # feature — no config change needed to switch inputs.
      "XG49DH16C" = {
        name = "^DP-11$";
        model = "XG49DH16C";
        width = 5120;
        height = 1440;
        refresh = 120;
        x = 0;
        y = 0;
        scale = 1;
      };
      # Laptop panel: work position is right of the 5120-wide ultrawide, vertically
      # centered against its 1440px height ((1440-1000)/2=220). SUPER+h / the home
      # startup hook below move it to the home position (2560,220).
      "eDP-1" = {
        name = "^eDP-1$";
        width = 2560;
        height = 1600;
        refresh = 165;
        x = 5120;
        y = 220;
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

  # MT7922 Wi-Fi (mt7921e): the card silently stalls every ~15-20 min — stays
  # associated but passes no packets, so NetworkManager logs nothing and only
  # `systemctl restart NetworkManager` (re-association) restores it. Every drop
  # is `reason=3 locally_generated=1`: the client gives up, the AP never deauths,
  # and there is NO firmware crash / driver reset / beacon-loss in the kernel log,
  # so mac80211 never notices the dead link.
  #
  # Disabling power-save (below) was the first fix but is INSUFFICIENT — re-checked
  # 2026-07-22, powersave=2 is applied yet the stall recurs. Next targeted attempt
  # is PCIe ASPM: force the mt7921e out of ASPM power management via a module
  # option (less blunt than a global `pcie_aspm=off`). `iw` is added so the runtime
  # power_state / beacon counters can be sampled live during a stall.
  networking.networkmanager.wifi.powersave = false;
  boot.extraModprobeConfig = "options mt7921e disable_aspm=1";
  environment.systemPackages = [ pkgs.iw ];

  # dhcpcd runs redundantly alongside NetworkManager (NM does its own DHCP for
  # managed interfaces). The standalone dhcpcd was segfaulting and fighting over
  # the DHCPv6 socket (`Address already in use`); disable it to remove the noise.
  networking.dhcpcd.enable = false;

  # Reboot safety net: a stuck final unmount (the always-connected Framework
  # exFAT storage module didn't unmount cleanly) once hung shutdown for ~40 min
  # with a no-limit stop job — invisible behind the Plymouth splash. Cap the
  # default stop timeout so a future hang is force-killed after 30s instead.
  systemd.settings.Manager.DefaultTimeoutStopSec = "30s";

  # Reboot hang, stage 2: with the unmount hang above fixed, shutdown now
  # completes cleanly in ~1s, but the machine then sits black-screen for ~40 min
  # before the next POST (journal 2026-07-22: boot -1 shut down 23:19:48, next
  # boot 00:00:32). The hang is in the firmware reset call itself — nothing logs
  # because journald is already down. FW16 AMD (BIOS 03.05, kernel 7.x) is prone
  # to hanging on the EFI ResetSystem path, made likelier here by the hardened
  # `efi=disable_early_pci_dma`. Force the ACPI reset method instead. Merges with
  # itera's kernelParams (listOf). If a hang recurs, try "reboot=pci"/"reboot=bios".
  boot.kernelParams = [ "reboot=acpi" ];

  # MT7922 Bluetooth: eiros pinned kernels to dodge a btmtk Oops; the fix was
  # expected upstream. On itera/unstable it is likely already fixed — VERIFY BT
  # after first boot and only pin a kernel here if it regresses (see eiros memory
  # note). itera.personal deliberately dropped these quirks too.
}
