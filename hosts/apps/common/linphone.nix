# Linphone SIP softphone, installed per-user. (Contacts workflow: the Vonage
# directory popup — Super+Shift+P — see apps/common/vonage-directory.nix.)
{ pkgs, ... }:
{
  itera.users.vwestberg.packages = [ pkgs.linphone ];
}
