# Weekly upstream-change watcher.
#
# Nothing on this machine used to watch for upstream flake changes, so a
# `nix flake update` was always a blind 3-week jump (2026-09-08: one such jump
# broke eval outright — liblinphone 5.5.13 renamed its zxing-cpp argument, see
# apps/common/linphone.nix). This checks in a throwaway clone, so it NEVER
# touches the live config or applies anything: it reports, you decide.
#
# Runs as a USER timer so it can talk to the DMS notification daemon. Reads
# /var/lib/itera/facter.json for the --impure eval; itera chmods that 0644
# precisely so a non-root eval can read it.
#
#   flake-news   print the latest report
{ pkgs, ... }:
let
  user = "vwestberg";
  flakeRepo = "https://github.com/4thehalibit/itera.users.personal";
  configName = "framework";
  reportDir = "/home/${user}/.local/state/flake-update-check";
  reportFile = "${reportDir}/latest.txt";

  # Compare two flake.lock files by each node's locked rev. Prints one
  # "name  olddate -> newdate" line per moved input, and exits 1 when nothing
  # moved so the caller can stay silent instead of nagging.
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
    ];
    text = ''
      set -uo pipefail

      work=$(mktemp -d)
      trap 'rm -rf "$work"' EXIT
      mkdir -p ${reportDir}

      notify() {
        # urgency, summary, body — best effort; a headless run must not fail here.
        notify-send -a "flake-update-check" -u "$1" "$2" "$3" || true
      }

      if ! git clone --quiet --depth 1 ${flakeRepo} "$work/repo" 2>"$work/clone.err"; then
        notify normal "Flake check could not run" "git clone failed. See $work/clone.err"
        exit 0
      fi

      cd "$work/repo"
      head_rev=$(git rev-parse --short HEAD)
      cp flake.lock "$work/before.lock"

      if ! nix flake update >"$work/update.log" 2>&1; then
        notify critical "Flake check failed" "nix flake update errored. Report: ${reportFile}"
        {
          echo "itera flake update check — $(date '+%Y-%m-%d %H:%M %Z')"
          echo "nix flake update FAILED:"
          tail -n 30 "$work/update.log"
        } >${reportFile}
        exit 0
      fi

      # No moved inputs → exit 1 from the differ → stay quiet. Nothing to decide.
      if ! python3 ${lockDiff} "$work/before.lock" flake.lock >"$work/diff.txt" 2>&1; then
        {
          echo "itera flake update check — $(date '+%Y-%m-%d %H:%M %Z')"
          echo "Up to date: no inputs moved since origin/main @ $head_rev."
        } >${reportFile}
        exit 0
      fi

      # The payoff: does the updated config still evaluate? This is the check
      # that would have caught the liblinphone zxing-cpp rename before a build.
      eval_status="OK"
      if drv=$(nix eval --impure --raw \
                 ".#nixosConfigurations.${configName}.config.system.build.toplevel.drvPath" \
                 2>"$work/eval.err"); then
        eval_detail="$drv"
      else
        eval_status="FAILED"
        eval_detail=$(tail -n 25 "$work/eval.err")
      fi

      {
        echo "itera flake update check — $(date '+%Y-%m-%d %H:%M %Z')"
        echo "Source: ${flakeRepo} (origin/main @ $head_rev)"
        echo ""
        cat "$work/diff.txt"
        echo ""
        echo "Config eval: $eval_status"
        # Indent each line without sed (shellcheck SC2001) and without pulling
        # gawk in just for a prefix.
        while IFS= read -r line; do echo "  $line"; done <<<"$eval_detail"
        echo ""
        if [ "$eval_status" = "OK" ]; then
          echo "To apply:"
          echo "  cd ~/Documents/itera.users.personal"
          echo "  nix flake update"
          echo "  git add flake.lock"
          echo "  git commit -m 'flake: refresh inputs'"
          echo "  git push"
          echo "  itera update-boot   # then reboot"
        else
          echo "DO NOT update yet — the new inputs do not evaluate."
          echo "Fix the error above first, then re-check with:"
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
    pkgs.libnotify # notify-send: was only in the store as a dep, not on PATH
    checkScript
    flakeNews
  ];

  systemd.user.services.flake-update-check = {
    description = "Check upstream flake inputs for changes (reports only, applies nothing)";
    # notify-send needs the session bus; the user manager does not always export
    # it to timer-driven units, so point at it explicitly (%t = /run/user/UID).
    environment.DBUS_SESSION_BUS_ADDRESS = "unix:path=%t/bus";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${checkScript}/bin/flake-update-check";
    };
  };

  systemd.user.timers.flake-update-check = {
    description = "Weekly upstream flake input check";
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
