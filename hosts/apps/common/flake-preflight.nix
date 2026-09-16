# "Does this config still evaluate?" — one script, two callers.
#
# Split of concerns with upstream. itera's own `iteraUpdate` dank-bar pill
# (itera desktop/update-indicator.nix, listed in ../../common.nix barConfigs)
# answers "has itera moved?" — cheaply, read-only, with no checkout and no eval,
# and it is maintained upstream. It cannot answer "is the update SAFE", because
# it never evaluates anything and never looks at nixpkgs or the other inputs in
# this flake's lock. That second question is the only thing this file does, and
# it is the question that actually bit: on 2026-09-08 a blind 3-week jump broke
# eval outright when liblinphone 5.5.13 renamed its zxing-cpp argument.
#
# So `flake-eval` (below) is the whole payload, called from two places:
#
#   1. `deploy` — on the WORKING TREE, before commit+push. `itera update` builds
#      from the REMOTE, so without this a config that does not evaluate is
#      already pushed by the time the build fails. Skip with DEPLOY_SKIP_CHECK=1.
#   2. A weekly user timer — on a THROWAWAY clone with every input updated, so an
#      upstream break is found before you take it. Never touches the live config.
#
# Replaces the old flake-update-check.nix (434 lines) and its dms-flake-news QML
# pill (215 lines). Both of those duplicated the signal upstream now provides;
# the apply button they fronted is just `nix flake update && deploy`, which works
# in any terminal where sudo can prompt.
#
# Runs as a USER timer so it can reach the DMS notification daemon. Reads
# /var/lib/itera/facter.json for the --impure eval; itera chmods that 0644
# precisely so a non-root eval can read it.
{ pkgs, ... }:
let
  user = "vwestberg";
  flakeRepo = "https://github.com/4thehalibit/itera.users.personal";
  configName = "framework";
  reportDir = "/home/${user}/.local/state/flake-update-check";
  reportFile = "${reportDir}/latest.txt";

  # THE payload. Exits non-zero with the eval error on stderr, so both callers
  # can just branch on the status. --impure because the facter.json read escapes
  # the pure-eval sandbox.
  flakeEval = pkgs.writeShellApplication {
    name = "flake-eval";
    runtimeInputs = [ pkgs.nix ];
    text = ''
      nix eval --impure --raw \
        "''${1:-.}#nixosConfigurations.${configName}.config.system.build.toplevel.drvPath"
    '';
  };

  # Compare two flake.lock files by each node's locked rev. One
  # "name  olddate -> newdate" line per moved input; exit 1 when nothing moved,
  # so the caller stays silent instead of nagging.
  lockDiff = pkgs.writeText "flake-lock-diff.py" ''
    import json, sys, datetime

    def nodes(path):
        with open(path) as fh:
            data = json.load(fh)
        out = {}
        for name, node in data.get("nodes", {}).items():
            locked = node.get("locked", {})
            rev = locked.get("rev") or locked.get("narHash") or ""
            out[name] = (rev, locked.get("lastModified"))
        return out

    def when(ts):
        if not ts:
            return "?"
        return datetime.datetime.fromtimestamp(ts, datetime.UTC).strftime("%Y-%m-%d")

    before, after = nodes(sys.argv[1]), nodes(sys.argv[2])
    moved = [n for n in after if n in before and before[n][0] != after[n][0]]
    added = [n for n in after if n not in before]

    # Inputs the user actually reasons about go first; the rest are transitive.
    priority = ["nixpkgs", "itera", "hjem", "dms", "mango", "netskope"]
    moved.sort(key=lambda n: (priority.index(n) if n in priority else 99, n))

    for name in moved:
        print("  %-22s %s -> %s" % (name, when(before[name][1]), when(after[name][1])))
    for name in added:
        print("  %-22s NEW (%s)" % (name, when(after[name][1])))
    print("")
    print("%d of %d inputs moved." % (len(moved), len(after)))
    sys.exit(0 if (moved or added) else 1)
  '';

  checkScript = pkgs.writeShellApplication {
    name = "flake-update-check";
    runtimeInputs = with pkgs; [
      git
      nix
      libnotify
      python3
      coreutils
      flakeEval
    ];
    text = ''
      set -uo pipefail

      work=$(mktemp -d)
      trap 'rm -rf "$work"' EXIT
      mkdir -p ${reportDir}

      # urgency, summary, body — best effort; a headless run must not fail here.
      notify() { notify-send -a "flake-update-check" -u "$1" "$2" "$3" || true; }

      if ! git clone --quiet --depth 1 ${flakeRepo} "$work/repo" 2>"$work/clone.err"; then
        notify normal "Flake check could not run" "git clone failed."
        exit 0
      fi

      cd "$work/repo"
      head_rev=$(git rev-parse --short HEAD)
      cp flake.lock "$work/before.lock"

      if ! nix flake update >"$work/update.log" 2>&1; then
        {
          echo "flake update check — $(date '+%Y-%m-%d %H:%M %Z')"
          echo "nix flake update FAILED:"
          tail -n 30 "$work/update.log"
        } >${reportFile}
        notify critical "Flake check failed" "nix flake update errored. Run: flake-news"
        exit 0
      fi

      # No moved inputs → exit 1 from the differ → stay quiet. Nothing to decide.
      if ! python3 ${lockDiff} "$work/before.lock" flake.lock >"$work/diff.txt" 2>&1; then
        {
          echo "flake update check — $(date '+%Y-%m-%d %H:%M %Z')"
          echo "Up to date: no inputs moved since origin/main @ $head_rev."
        } >${reportFile}
        exit 0
      fi

      # The payoff, and the entire reason this file still exists.
      if flake-eval . >/dev/null 2>"$work/eval.err"; then
        eval_status="OK"
        eval_detail=""
      else
        eval_status="FAILED"
        eval_detail=$(tail -n 25 "$work/eval.err")
      fi

      {
        echo "flake update check — $(date '+%Y-%m-%d %H:%M %Z')"
        echo "Source: ${flakeRepo} (origin/main @ $head_rev)"
        echo ""
        cat "$work/diff.txt"
        echo ""
        echo "Config eval: $eval_status"
        if [ "$eval_status" = "OK" ]; then
          echo ""
          echo "Safe to take. In the config checkout:"
          echo "  nix flake update && deploy \"chore: flake update\""
          echo ""
          echo "That is a SWITCH, not update-boot. If one of the inputs above"
          echo "moved the kernel, reboot afterwards to actually run it."
        else
          echo ""
          while IFS= read -r line; do echo "  $line"; done <<<"$eval_detail"
          echo ""
          echo "DO NOT update yet — the new inputs do not evaluate."
          echo "Re-check after upstream fixes it:"
          echo "  systemctl --user start flake-update-check"
        fi
      } >${reportFile}

      count=$(grep -c '^  ' "$work/diff.txt" || echo "some")
      if [ "$eval_status" = "OK" ]; then
        notify normal "Flake updates available" \
          "$count inputs moved, eval OK. Run: flake-news"
      else
        notify critical "Flake updates available — EVAL BROKEN" \
          "$count inputs moved but the config does not evaluate. Run: flake-news"
      fi
    '';
  };

  flakeNews = pkgs.writeShellScriptBin "flake-news" ''
    if [ -r ${reportFile} ]; then
      cat ${reportFile}
    else
      echo "No report yet. The check runs Mondays at 09:00, or force one now with:"
      echo "  systemctl --user start flake-update-check"
    fi
  '';
in
{
  environment.systemPackages = [
    flakeEval
    checkScript
    flakeNews
  ];

  systemd.user.services.flake-update-check = {
    description = "Check whether upstream flake inputs moved, and whether the update still evaluates";
    # notify-send needs the session bus; the user manager does not always export
    # it to timer-driven units, so point at it explicitly (%t = /run/user/UID).
    environment.DBUS_SESSION_BUS_ADDRESS = "unix:path=%t/bus";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${checkScript}/bin/flake-update-check";
    };
  };

  systemd.user.timers.flake-update-check = {
    description = "Weekly upstream flake-input check";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "Mon 09:00"; # America/Chicago
      # Laptop is often asleep/off Monday morning — run on next login instead of
      # silently skipping the week.
      Persistent = true;
      RandomizedDelaySec = "30m";
    };
  };
}
