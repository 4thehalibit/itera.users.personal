# ONLYOFFICE Desktop Editors, installed per-user.
{ pkgs, ... }:
{
  itera.users.vwestberg.packages = [ pkgs.onlyoffice-desktopeditors ];
}
