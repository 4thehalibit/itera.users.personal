# Thunderbolt / dock support. Ported from eiros applications/bolt.nix.
# Workaround: StarTech TB3DK2DHV PCIe devices (USB controller, Ethernet) fail to
# enumerate on the first Thunderbolt authorization at boot on Framework 16 AMD.
# The udev rule triggers a PCIe rescan ~5s after the dock is authorized so the
# tunneled PCIe devices are discovered without an unplug/replug cycle.
{ ... }:
{
  services.hardware.bolt.enable = true;

  systemd.services.thunderbolt-pcie-rescan = {
    description = "Rescan PCIe bus after Thunderbolt dock authorization";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "/bin/sh -c 'sleep 5 && echo 1 > /sys/bus/pci/rescan'";
    };
  };

  services.udev.extraRules = ''
    SUBSYSTEM=="thunderbolt", ACTION=="change", ATTR{authorized}=="1", TAG+="systemd", ENV{SYSTEMD_WANTS}="thunderbolt-pcie-rescan.service"
  '';
}
