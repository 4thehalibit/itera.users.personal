# UxPlay: AirPlay 2 mirroring receiver, so an iPhone/iPad (or Mac) can screen-
# cast video + audio to this machine over the LAN. Launch it from a terminal
# with `uxplay -p`; the machine then appears as an AirPlay target in the
# iPhone's Screen Mirroring list. Quit with `q` or Ctrl-C.
#
# The `-p` flag pins UxPlay to the legacy fixed ports the firewall opens below.
# WITHOUT -p it picks random ports the firewall would block, so always use -p.
#
# Discovery uses Avahi (mDNS): UxPlay advertises itself through the running
# avahi-daemon, so publishing must be enabled. The iPhone and this machine must
# be on the same LAN/subnet (mDNS does not cross VLANs or subnets).
#
# Wayland (mango): the default autovideosink should pick a wlroots-friendly
# sink. If the window misbehaves, launch `uxplay -p -vs waylandsink` (or
# `-vs glimagesink`) instead.
{ pkgs, ... }:
{
  itera.users.vwestberg.packages = [ pkgs.uxplay ];

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
