# Personal commands from eiros, re-expressed as real executables on PATH instead
# of zsh aliases/functions — so they work under itera's default shell (nushell)
# or any other. Replaces eiros applications/aliases.nix.
{ pkgs, ... }:
let
  # fixhdmi: force the ViewSonic 4K to re-sync (off/on) when it comes up blank.
  fixhdmi = pkgs.writeShellScriptBin "fixhdmi" ''
    output=$(${pkgs.wlr-randr}/bin/wlr-randr | grep 'VX3211-4K' | awk '{print $1}')
    if [ -n "$output" ]; then
      ${pkgs.wlr-randr}/bin/wlr-randr --output "$output" --off
      sleep 2
      ${pkgs.wlr-randr}/bin/wlr-randr --output "$output" --on
    else
      echo 'ViewSonic not detected'
    fi
  '';

  # claude: run the Claude Code CLI from the ~/claude working dir.
  claudeCmd = pkgs.writeShellScriptBin "claude" ''
    cd "$HOME/claude" 2>/dev/null || cd "$HOME"
    exec ${pkgs.claude-code}/bin/claude "$@"
  '';

  # freshworks: drop into the freshworks-dev distrobox container.
  # NOTE the container itself is imperative — recreate it after reinstall with
  # `distrobox create --name freshworks-dev ...`.
  freshworks = pkgs.writeShellScriptBin "freshworks" ''
    exec ${pkgs.distrobox}/bin/distrobox enter freshworks-dev "$@"
  '';

  # rebuild: build + switch this host from the configured remote flake.
  rebuild = pkgs.writeShellScriptBin "rebuild" ''
    exec itera rebuild "$@"
  '';

  # deploy [msg]: commit + push the local checkout, then update + rebuild.
  # Expects the checkout at ~/Documents/itera.users.personal (a persisted path).
  deploy = pkgs.writeShellScriptBin "deploy" ''
    set -e
    cd "$HOME/Documents/itera.users.personal"
    ${pkgs.git}/bin/git add -A
    ${pkgs.git}/bin/git diff --cached --quiet || ${pkgs.git}/bin/git commit -m "''${1:-update config}"
    ${pkgs.git}/bin/git push
    exec itera update
  '';
in
{
  environment.systemPackages = [
    fixhdmi
    claudeCmd
    freshworks
    rebuild
    deploy
    pkgs.distrobox
    pkgs.wlr-randr
  ];
}
