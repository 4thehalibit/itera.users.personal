# Watchtower: read-only security dashboard (~/Documents/control-center) plus its
# tray icon. tray.py owns the dashboard server, so this one unit is all that
# runs: icon colour = overall health (grey means the server is down), left click
# opens the page, right click offers refresh / restart / stop.
#
# Python comes from nix (ldap3 for the AD tiles, dbus-next for the tray) rather
# than the project's .venv, so a nixpkgs bump cannot leave a dangling interpreter.
# The server child is in the unit's cgroup, so stopping the unit stops it too.
{ pkgs, ... }:
let
  py = pkgs.python3.withPackages (ps: [
    ps.ldap3
    ps.dbus-next
  ]);
in
{
  systemd.user.services.watchtower = {
    description = "Watchtower security dashboard tray icon (owns the dashboard server)";
    wantedBy = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    # ss (find the server pid) and xdg-open (left click) are not in a user unit's PATH.
    path = [
      pkgs.iproute2
      pkgs.xdg-utils
      pkgs.coreutils
    ];
    serviceConfig = {
      ExecStart = "${py}/bin/python %h/Documents/control-center/tray.py";
      Restart = "on-failure";
      RestartSec = 10;
    };
  };
}
