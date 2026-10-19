# exo: Exchange Online PowerShell as the signed-in admin (device-code login).
#   exo                      interactive session, stays open
#   exo 'Get-Mailbox bob'    run one command, then exit
# ExchangeOnlineManagement installs to ~/.local/share/powershell/Modules, which
# itera persists by default (.local), so the install happens once. The app-only
# automation path (cert in ~/.config/exchange) is separate and unaffected.
{ pkgs, ... }:
let
  exo = pkgs.writeShellScriptBin "exo" ''
    init='
      if (-not (Get-Module -ListAvailable ExchangeOnlineManagement)) {
        Install-Module ExchangeOnlineManagement -Scope CurrentUser -Force
      }
      Connect-ExchangeOnline -UserPrincipalName vwestberg@lselectric.com -Device -ShowBanner:$false
    '
    if [ $# -eq 0 ]; then
      exec ${pkgs.powershell}/bin/pwsh -NoProfile -NoExit -Command "$init"
    else
      exec ${pkgs.powershell}/bin/pwsh -NoProfile -Command "$init; $*; Disconnect-ExchangeOnline -Confirm:\$false"
    fi
  '';
in
{
  environment.systemPackages = [ exo ];
}
