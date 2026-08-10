# UxPlay: AirPlay 2 mirroring receiver, so an iPhone/iPad (or Mac) can screen-
# cast video + audio to this machine over the LAN. Use the `airplay` command
# (defined below); the machine then appears as an AirPlay target in the iPhone's
# Screen Mirroring list. Quit with `q` or Ctrl-C.
#
# The flags baked into `airplay` (found by trial on this AMD + mango setup):
#   -p            pin the legacy fixed ports the firewall opens below (without
#                 it UxPlay picks random ports the firewall would block)
#   -avdec        force libav SOFTWARE h264 decode (bypasses the AMD hardware
#                 vah264dec/VAAPI path).
#   -vs glimagesink  render video via OpenGL/EGL. NOTE: waylandsink (the
#                 wlroots-native sink) does NOT work here -- mango rejects its
#                 buffer stride ("[destroyed object]: error 1: Invalid stride"),
#                 which tore down the session and gave audio-but-no-video. The
#                 default autovideosink also failed. glimagesink is what works.
#
# Discovery uses Avahi (mDNS): UxPlay advertises through avahi-daemon, so
# publishing must be enabled. The iPhone and this machine must be on the same
# LAN/subnet (mDNS does not cross VLANs or subnets).
{ pkgs, ... }:
let
  # airplay: launch the AirPlay receiver with the flags that work on this box.
  airplay = pkgs.writeShellScriptBin "airplay" ''
    exec ${pkgs.uxplay}/bin/uxplay -p -avdec -vs glimagesink "$@"
  '';
in
{
  itera.users.vwestberg.packages = [ pkgs.uxplay ];

  # `airplay` on PATH for every user (matches personal-commands.nix idiom).
  environment.systemPackages = [ airplay ];

  # mDNS/DNS-SD so the iPhone can find this machine, plus service publishing so
  # UxPlay can advertise the AirPlay target. openFirewall (default true) opens
  # UDP 5353 for mDNS.
  services.avahi = {
    enable = true;
    publish = {
      enable = true;
      userServices = true;
    };
  };

  # AirPlay legacy fixed ports used by `uxplay -p`.
  networking.firewall = {
    allowedTCPPorts = [ 7000 7001 7100 ];
    allowedUDPPorts = [ 6000 6001 7011 ];
  };
}
