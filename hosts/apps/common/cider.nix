# Cider (Apple Music client), installed per-user.
{ pkgs, ... }:
{
  itera.users.vwestberg.packages = [ pkgs.cider-2 ];
}
