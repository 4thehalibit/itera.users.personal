# GNOME Files (nautilus), installed per-user. (itera's default file-manager
# battery is nemo; nautilus is kept as the preferred GUI file manager.)
{ pkgs, ... }:
{
  itera.users.vwestberg.packages = [ pkgs.nautilus ];
}
