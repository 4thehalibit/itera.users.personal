# Vesktop (Discord client), installed per-user. Pins electron_40, marked insecure
# in nixpkgs past EOL — allowlisted in hosts/common.nix
# (nixpkgs.config.permittedInsecurePackages). Remove that allowlist once vesktop
# moves to a newer electron.
{ pkgs, ... }:
{
  itera.users.vwestberg.packages = [ pkgs.vesktop ];
}
