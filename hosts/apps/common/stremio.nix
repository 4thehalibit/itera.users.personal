# Stremio (media center client), installed per-user. The nixpkgs package is
# named stremio-linux-shell. Its license is GPL-3.0 plus unfree.
{ pkgs, ... }:
{
  itera.users.vwestberg.packages = [ pkgs.stremio-linux-shell ];
}
