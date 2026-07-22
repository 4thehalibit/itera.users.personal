# Caprine (Facebook Messenger client), installed per-user.
{ pkgs, ... }:
{
  itera.users.vwestberg.packages = [ pkgs.caprine-bin ];
}
