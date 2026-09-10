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
#   flake-news          print the latest report
#   flake-update-apply  apply what the report found (prompts, then deploys)
#
# The dank-bar pill for the same report lives in ./dms-flake-news (registered
# below). Its widget id has to appear in a bar config's widget list too — that
# layout is in ../../common.nix next to the other DMS settings.
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
          echo "To apply: press the rocket button on the flakeNews bar pill,"
          echo "or run the same thing yourself:"
          echo "  flake-update-apply"
          echo ""
          echo "It shows this list, asks to confirm, then runs nix flake update"
          echo "followed by deploy (commit, push, and itera update)."
          echo ""
          echo "NOTE that is a SWITCH, not update-boot. If one of the inputs above"
          echo "moved the kernel, reboot afterwards to actually run it."
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

  # The other half of the pill: actually APPLY what the report found.
  #
  # The checker above deliberately never touches the live config, which left a
  # gap — the report just ends in a block of commands to retype by hand. This
  # runs them, gated on the report itself. The flakeNews widget's update button
  # spawns this in a wezterm popup (see the appid:flake-update windowrule in
  # ./mango-keybinds.nix).
  #
  # WHY A TERMINAL AND NOT A SILENT BUTTON: `itera update` calls
  # itera_facter_refresh before nh starts, and with ITERA_FACTER_AUTOGEN=1 (set
  # in /etc/itera/facter.env on this host) that is three interactive sudo calls
  # — mkdir, nixos-facter -o, chmod. nixos-facter is in NO NOPASSWD rule
  # (../../common.nix exempts only /run/current-system/sw/bin/nixos-rebuild),
  # and nh then needs sudo of its own. Up to four password prompts, so this
  # needs a tty; a headless version dies on the first one with
  # "sudo: a terminal is required to read the password".
  flakeUpdateApply = pkgs.writeShellScriptBin "flake-update-apply" ''
    report=${reportFile}

    hold() {
      printf '\n[press enter to close] '
      read -r _ || true
    }

    if [ ! -r "$report" ]; then
      echo "No flake report at $report."
      echo "Run a check first:  systemctl --user start flake-update-check"
      hold
      exit 1
    fi

    head -n 2 "$report"

    # Report shape 1: nothing moved.
    if grep -q '^Up to date: no inputs moved' "$report"; then
      echo ""
      echo "Nothing to do — no inputs have moved since the last check."
      hold
      exit 0
    fi

    # Report shape 2: inputs moved but the result does not evaluate. The report
    # says "DO NOT update yet" and it is right — this is the one real safety
    # gate here, so refuse rather than warn.
    if ! grep -qx 'Config eval: OK' "$report"; then
      echo ""
      echo "REFUSING: the report says the updated inputs do not evaluate."
      echo ""
      sed -n '/^Config eval:/,/^$/p' "$report"
      echo "Fix the eval error first, then re-check with:"
      echo "  systemctl --user start flake-update-check"
      hold
      exit 1
    fi

    # Collect the moved input names from the DIFF section only — the eval
    # detail below it is indented the same 2 spaces. Field-split rather than
    # awk, matching this file's existing avoid-gawk-for-one-line stance. The
    # "N of M inputs moved." summary line has no " -> ", so it drops out.
    section=$(sed -n '/^Source: /,/^Config eval:/p' "$report")
    names=""
    count=0
    while IFS= read -r line; do
      case "$line" in
        "  "*" -> "*)
          set -- $line
          names="$names $1"
          count=$((count + 1))
          ;;
      esac
    done <<<"$section"

    if [ "$count" -eq 0 ]; then
      echo ""
      echo "Could not find any moved inputs in the report. Re-check with:"
      echo "  systemctl --user start flake-update-check"
      hold
      exit 1
    fi

    # Keep the subject line readable when a 3-week jump moves a dozen inputs.
    if [ "$count" -le 4 ]; then
      msg="chore(flake): update$names"
    else
      msg="chore(flake): update $count inputs"
    fi

    echo ""
    echo "Moved inputs ($count):"
    printf '  %s\n' $names
    echo ""
    echo "This will:"
    echo "  nix flake update          in ~/Documents/itera.users.personal"
    echo "  deploy \"$msg\""
    echo "    -> git add -A, commit, push to GitHub"
    echo "    -> itera update: builds and ACTIVATES a new system generation"
    echo ""
    printf 'Proceed? [y/N] '
    read -r reply
    case "$reply" in
      y | Y | yes | YES) ;;
      *)
        echo "Aborted. Nothing changed."
        hold
        exit 0
        ;;
    esac

    cd "$HOME/Documents/itera.users.personal" || {
      echo "FAILED: no checkout at ~/Documents/itera.users.personal"
      hold
      exit 1
    }

    echo ""
    echo "==> nix flake update"
    if ! nix flake update; then
      echo "FAILED: nix flake update"
      hold
      exit 1
    fi

    # deploy = git add -A + commit + push + exec itera update. It already
    # passes --refresh (ITERA_UPDATE_REMOTE=1 in /etc/itera/update.env), which
    # is what stops the 1h flake tarball cache re-applying the previous commit.
    echo ""
    echo "==> deploy"
    if ! deploy "$msg"; then
      echo "FAILED: deploy"
      hold
      exit 1
    fi

    # Re-run the check so the pill stops advertising what we just applied. The
    # report is the widget's only source of truth and nothing else rewrites it,
    # so without this the pill keeps offering the same 11 inputs after they are
    # already in. A fresh check against the pushed lock reports "no inputs
    # moved" and the pill goes quiet.
    #
    # No shell or plugin restart is needed: the report is a real file, not a
    # store symlink, and the widget's FileView watches it (onFileChanged ->
    # reload), so the pill updates itself when the new report lands.
    #
    # --no-block because the check shallow-clones the repo, runs its own
    # `nix flake update` and evaluates the whole config -- minutes, not the
    # seconds the toast claims. Nothing here needs to wait for it.
    echo ""
    echo "==> refreshing the flake report"
    if systemctl --user start --no-block flake-update-check; then
      echo "    started; the bar pill will clear itself once it finishes"
    else
      echo "    could not trigger it -- run this by hand to clear the pill:"
      echo "      systemctl --user start flake-update-check"
    fi

    echo ""
    echo "Done. New generation activated."
    hold
  '';
in
{
  environment.systemPackages = [
    pkgs.libnotify # notify-send: was only in the store as a dep, not on PATH
    checkScript
    flakeNews
    flakeUpdateApply
  ];

  # Dank-bar pill reading ${reportFile}. The attr name must match the `id` in
  # plugin.json — DMS looks its enabled flag up by manifest id, so a mismatch
  # ships the plugin but leaves it off.
  itera.programs.dankMaterialShell.plugins.flakeNews.src = ./dms-flake-news;

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
