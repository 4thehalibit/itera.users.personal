# YubiKey: PC/SC daemon + Yubico Authenticator (OATH TOTP).
{ pkgs, ... }:
{
  services.pcscd.enable = true;
  itera.users.vwestberg.packages = [ pkgs.yubioath-flutter ];
}
