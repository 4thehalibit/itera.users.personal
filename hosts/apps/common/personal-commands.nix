# Personal commands from eiros, re-expressed as real executables on PATH instead
# of zsh aliases/functions — so they work under itera's default shell (nushell)
# or any other. Replaces eiros applications/aliases.nix.
{ pkgs, lib, ... }:
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

  # claude: run the Claude Code CLI from the ~/claude working dir. The dir keys
  # the Claude "project" (memory/history live under -home-vwestberg-claude), so
  # ensure it exists — impermanence wipes $HOME each boot and ~/claude is not on
  # the persist allowlist, so mkdir it here rather than relying on it surviving.
  claudeCmd = pkgs.writeShellScriptBin "claude" ''
    mkdir -p "$HOME/claude"
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

  # ninjaone-update: bump the ninjarmm-ncplayer flake input to latest and deploy.
  ninjaoneUpdate = pkgs.writeShellScriptBin "ninjaone-update" ''
    set -e
    cd "$HOME/Documents/itera.users.personal"
    ${pkgs.nix}/bin/nix flake lock --update-input ninjarmm-ncplayer
    exec deploy "chore: bump ninjarmm-ncplayer"
  '';

  # ninjaone-pin [rev]: lock ninjarmm-ncplayer to a specific git rev and deploy.
  # No arg prints the currently locked rev (note it down before updating, so
  # there is something to pin back to if the update breaks).
  ninjaonePin = pkgs.writeShellScriptBin "ninjaone-pin" ''
    set -e
    cd "$HOME/Documents/itera.users.personal"
    if [ -z "''${1:-}" ]; then
      ${pkgs.jq}/bin/jq -r '.nodes["ninjarmm-ncplayer"].locked.rev' flake.lock
      exit 0
    fi
    ${pkgs.nix}/bin/nix flake lock --override-input ninjarmm-ncplayer "github:lcleveland/ninjarmm-ncplayer/$1"
    exec deploy "chore: pin ninjarmm-ncplayer to $1"
  '';

  # deploy [msg]: commit + push the local checkout, then update + rebuild.
  # Expects the checkout at ~/Documents/itera.users.personal (a persisted path).
  deploy = pkgs.writeShellScriptBin "deploy" ''
    set -e
    cd "$HOME/Documents/itera.users.personal"
    ${pkgs.git}/bin/git add -A
    # Preflight: `itera update` below builds from the REMOTE, so without this a
    # config that does not evaluate is already pushed by the time the build
    # fails. flake-eval comes from apps/common/flake-preflight.nix.
    #
    # AFTER `git add -A`, not before: nix's git fetcher cannot see UNTRACKED
    # files in a dirty tree, so a brand-new module would be invisible to an
    # earlier eval and the check would pass on a config that is not the one
    # about to be pushed. Staging makes it visible. A failure here leaves the
    # files staged but uncommitted, which the next deploy re-adds anyway.
    if [ -z "''${DEPLOY_SKIP_CHECK:-}" ]; then
      echo "preflight: evaluating config..."
      flake-eval . >/dev/null || {
        echo "config does not evaluate — nothing committed or pushed." >&2
        exit 1
      }
    fi
    ${pkgs.git}/bin/git diff --cached --quiet || ${pkgs.git}/bin/git commit -m "''${1:-update config}"
    ${pkgs.git}/bin/git push
    exec itera update
  '';

  # upgrade: one-shot itera update. Preflight, bump the itera input, eval-check,
  # push the lock, then stage the build for the next boot (reboot applies it).
  # A live `itera update` can restart systemd mid-switch and blank /etc/machine-id,
  # so this uses `update on-reboot`. Use `deploy` for your own config edits.
  upgrade = pkgs.writeShellScriptBin "upgrade" ''
    set -e
    cd "$HOME/Documents/itera.users.personal"
    flake=github:4thehalibit/itera.users.personal

    # Blank machine-id (empty tmpfs copy) makes the bootloader step die with an
    # IndexError. The persisted copy is the real one.
    if [ ! -s /etc/machine-id ]; then
      echo "preflight: /etc/machine-id is blank, restoring from /persist"
      sudo cp /persist/etc/machine-id /etc/machine-id
    fi

    # Only the lock may change here, so anything else dirty belongs to `deploy`.
    if ! ${pkgs.git}/bin/git diff --quiet || ! ${pkgs.git}/bin/git diff --cached --quiet; then
      echo "uncommitted changes in the config checkout, run deploy first." >&2
      exit 1
    fi
    ${pkgs.git}/bin/git pull --ff-only

    before=$(${pkgs.jq}/bin/jq -r .nodes.itera.locked.rev flake.lock)
    ${pkgs.nix}/bin/nix flake update itera
    after=$(${pkgs.jq}/bin/jq -r .nodes.itera.locked.rev flake.lock)
    echo "itera: ''${before:0:7} -> ''${after:0:7}"

    echo "preflight: evaluating config..."
    flake-eval . >/dev/null || {
      echo "config does not evaluate with the bumped lock, nothing pushed." >&2
      ${pkgs.git}/bin/git checkout flake.lock
      exit 1
    }
    if ! ${pkgs.git}/bin/git diff --quiet; then
      ${pkgs.git}/bin/git commit -am "chore: bump itera to ''${after:0:7}"
      ${pkgs.git}/bin/git push
    fi

    # nix caches the remote flake ref for an hour, so refresh and confirm it sees
    # the commit just pushed, or `itera update` silently rebuilds the old tree.
    seen=$(${pkgs.nix}/bin/nix flake metadata "$flake" --refresh --json | ${pkgs.jq}/bin/jq -r .locked.rev)
    if [ "$seen" != "$(${pkgs.git}/bin/git rev-parse HEAD)" ]; then
      echo "remote flake is at $seen, not HEAD. Wait a minute and re-run." >&2
      exit 1
    fi

    itera update on-reboot

    if [ "$(readlink -f /run/current-system)" != "$(readlink -f /nix/var/nix/profiles/system)" ]; then
      echo "update staged. Reboot to apply."
    else
      echo "already up to date, no reboot needed."
    fi
  '';
in
{
  environment.systemPackages = [
    fixhdmi
    # hiPri so this "claude" wins the PATH collision against the claude-code that
    # itera.ai.claude.enable also installs — otherwise the raw package shadows the
    # wrapper and `claude` no longer cd's into ~/claude first.
    (lib.hiPrio claudeCmd)
    freshworks
    rebuild
    deploy
    upgrade
    ninjaoneUpdate
    ninjaonePin
    pkgs.distrobox
    pkgs.wlr-randr
    pkgs.jq
  ];
}
