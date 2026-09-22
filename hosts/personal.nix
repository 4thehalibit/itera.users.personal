# personal — no corporate infrastructure. For life after L&S Electric: same
# hardware-agnostic base as hosts/generic.nix, but without netskope (SASE),
# falcon-sensor (EDR), or ninjarmm (RMM). Reuse this attr on any machine once
# corp access is no longer relevant.
{ lib, ... }:
{
  itera = {
    networking.hostName = "vwestberg-personal";

    # "auto": itera detects AMD/Intel live via facter at rebuild time, no
    # per-machine CPU guess needed. mkForce because common.nix plainly sets
    # "amd" for the framework host.
    hardware.cpu = lib.mkForce "auto";

    # nixosConfigurations attr is `personal`; hostname differs, so set
    # explicitly (else `itera update`/`rebuild` would miss `#personal`).
    update.configuration = "personal";

    # Placeholder — disko-install's --disk flag overrides this at install time.
    disko.device = "/dev/disk/by-id/CHANGE-ME-disko-install-overrides-this";
    disko.swapSize = "16G"; # trim to actual RAM if hibernation isn't needed

    disko.encryption.enable = false;

    # No monitor config, no board-specific quirks.
  };

  # common.nix enables the NinjaOne ncplayer (registers ninjarmm:// handler) for
  # every host by default; it's corp RMM infrastructure, so turn it off here.
  # mkForce: common.nix sets it plainly.
  programs.ninjarmm-ncplayer.enable = lib.mkForce false;
}
