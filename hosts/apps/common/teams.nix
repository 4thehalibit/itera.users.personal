# Microsoft Teams (unofficial Linux client), installed per-user.
{ pkgs, ... }:
{
  itera.users.vwestberg.packages = [ pkgs.teams-for-linux ];
}
