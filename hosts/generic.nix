# generic — emergency spare-hardware host. No board-specific quirks: boots on
# any UEFI x86_64 machine via plain NixOS/systemd-boot, no nixos-hardware board
# module. Use this when the Framework is dead/lost/stolen and a replacement
# laptop (any brand) needs corp access fast.
#
# Corp modules (netskope/falcon-sensor/ninjarmm-agent) live physically under
# apps/framework/ but aren't actually Framework-specific — they only ended up
# there because framework was the only host. Reused here by path rather than
# moved, to keep this diff small.
{ itera, lib, ... }:
{
  imports = [
    ./apps/framework/netskope.nix
    ./apps/framework/falcon-sensor.nix
    ./apps/framework/ninjarmm-agent.nix # needs /persist/ninjarmm-agent.deb staged manually
  ];

  itera = {
    # Rename once IT assigns a real asset tag; this just needs to be unique.
    networking.hostName = "LS-EMERGENCY";

    # "auto" is itera's hardware-agnostic mode: enables both AMD and Intel
    # microcode (harmless on the non-matching vendor) via facter's live
    # detection at rebuild time, no per-machine CPU guess needed. mkForce
    # because common.nix plainly sets "amd" for the framework host.
    hardware.cpu = lib.mkForce "auto";

    # nixosConfigurations attr is `generic`; hostname differs, so set explicitly
    # (else `itera update`/`rebuild` would miss `#generic`).
    update.configuration = "generic";

    # Placeholder — disko-install's --disk flag overrides this at install time.
    disko.device = "/dev/disk/by-id/CHANGE-ME-disko-install-overrides-this";
    disko.swapSize = "16G"; # trim to actual RAM if hibernation isn't needed

    disko.encryption.enable = false;

    # No monitor config: single-panel default is fine for an emergency box.
    # No LED/thunderbolt/wifi/amdgpu quirks: those were Framework-16-specific.
  };
}
