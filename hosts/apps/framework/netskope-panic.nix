# One-click "turn Netskope off" for when the network is broken.
#
# The client has no runtime off-switch worth relying on: this tenant sets
# allowClientDisabling=false, so `stAgentCli disable` is refused, and the unit is
# Restart=always, so the daemon reinstates its rules whenever it restarts. The
# documented recovery is four commands run in a specific order, which is exactly the
# thing nobody remembers while the network is down. So it gets a button.
#
# Two halves, because stopping it once is not enough if the next boot starts it again:
#
#   1. Runtime teardown — stop-then-KILL the daemon and undo its plumbing by hand.
#   2. A persistent flag at /persist/netskope-off, checked by an ExecCondition on
#      stagentd, so it stays off across reboots.
#
# Why a flag and not `systemctl mask`: this host has an ephemeral root
# (impermanence), and /etc/systemd/system is regenerated from the store on every
# activation, so a mask would silently vanish at the next boot — the worst possible
# time to discover it. /persist survives, and ExecCondition is the right systemd
# primitive: a failing condition SKIPS the unit cleanly, where a failing ExecStartPre
# would fight Restart=always in a loop.
{ config, pkgs, ... }:
let
  # Lives directly on /persist, which is a real filesystem that survives this host's
  # ephemeral root. Deliberately NOT declared in itera.impermanence.files: that option
  # is for paths OUTSIDE /persist which need bind-mounting back from it, so listing a
  # /persist path there would ask for /persist/persist/netskope-off. Nothing to declare
  # — being on /persist IS the persistence.
  flag = "/persist/netskope-off";

  # Shared teardown. Order is load-bearing and the reasons are in netskope.nix:
  # `systemctl stop` alone does not stop it promptly (its shutdown path does network
  # work that hangs precisely when the network is down), and `kill -s KILL` alone
  # gets restarted (Restart=always). Marking it stopping first is what prevents that.
  netskopeOff = pkgs.writeShellScriptBin "netskope-off" ''
    set -u
    # Every binary the script uses, spelled out. getent is glibc (NOT coreutils) and
    # grep is gnugrep; leaving either out fails only on the DNS-verification and
    # rule-cleanup paths, i.e. exactly when this script is being relied on.
    PATH=${
      pkgs.lib.makeBinPath [
        pkgs.systemd
        pkgs.iproute2
        pkgs.coreutils
        pkgs.util-linux
        pkgs.gnugrep
        pkgs.getent
      ]
    }

    if [ "$(id -u)" != 0 ]; then
      # sudo is a setuid wrapper, not a package binary, so it is never on a
      # makeBinPath PATH and must be called by absolute path.
      exec ${config.security.wrapperDir}/sudo "$0" "$@"
    fi

    echo "==> Turning Netskope OFF"

    # Persist first, so a reboot mid-teardown still comes up clean.
    mkdir -p "$(dirname ${flag})" && : > ${flag}
    echo "  flag set: ${flag} (survives reboot)"

    # Tray units belong to the desktop user, not root.
    for u in $(loginctl list-users --no-legend 2>/dev/null | ${pkgs.gawk}/bin/awk '$2 != "root" { print $1 }'); do
      name=$(loginctl show-user "$u" -p Name --value 2>/dev/null || true)
      [ -n "$name" ] || continue
      runuser -u "$name" -- env XDG_RUNTIME_DIR="/run/user/$u" \
        systemctl --user stop stagentui stagentapp 2>/dev/null || true
    done

    systemctl stop --no-block stagentd 2>/dev/null || true
    systemctl kill -s KILL stagentd 2>/dev/null || true
    echo "  daemon: $(systemctl is-active stagentd 2>&1)"

    # A killed client cleans up nothing, so undo its plumbing directly.
    for _ in 1 2 3 4 5; do
      ip rule list 2>/dev/null | grep -q "fwmark 0x5" || break
      ip rule del fwmark 0x5 table 9 2>/dev/null || break
    done
    ip route flush table 9 2>/dev/null || true
    ip link del sta0 2>/dev/null || true
    systemctl restart firewall.service 2>/dev/null || true
    resolvectl flush-caches 2>/dev/null || true
    echo "  sta0=$(ip -o link show sta0 2>/dev/null | wc -l) fwmark-rules=$(ip rule list | grep -c fwmark)"

    # Say whether it actually worked rather than just claiming success.
    for i in 1 2 3 4 5 6 7 8; do
      if getent hosts example.com >/dev/null 2>&1; then
        echo "  DNS OK after $((i * 2))s"
        echo
        echo "Netskope is OFF and will stay off across reboots."
        echo "Re-enable with:  netskope-on"
        exit 0
      fi
      sleep 2
    done

    echo "  DNS still down -- restarting NetworkManager"
    systemctl restart NetworkManager.service 2>/dev/null || true
    for i in 1 2 3 4 5 6; do
      if getent hosts example.com >/dev/null 2>&1; then
        echo "  DNS OK after NetworkManager restart"
        echo
        echo "Netskope is OFF and will stay off across reboots."
        echo "Re-enable with:  netskope-on"
        exit 0
      fi
      sleep 2
    done

    echo
    echo "Netskope is OFF but DNS is STILL down, so it was probably not the cause."
    echo "Check: systemctl status unbound; resolvectl status"
    echo "Wifi on this host also stalls periodically -- suspect that on a wireless link."
    exit 1
  '';

  netskopeOn = pkgs.writeShellScriptBin "netskope-on" ''
    set -u
    # curl is here for the enforcement probe at the end, and is as load-bearing as
    # the rest: without it the script goes back to claiming success it never checked.
    PATH=${
      pkgs.lib.makeBinPath [
        pkgs.systemd
        pkgs.iproute2
        pkgs.coreutils
        pkgs.util-linux
        pkgs.gnugrep
        pkgs.getent
        pkgs.curl
      ]
    }

    if [ "$(id -u)" != 0 ]; then
      # See netskope-off: sudo is a setuid wrapper, absolute path required.
      exec ${config.security.wrapperDir}/sudo "$0" "$@"
    fi

    echo "==> Turning Netskope ON"
    rm -f ${flag}

    # restart, NOT start. `start` is a no-op on an already-active unit, which is the
    # common case: the daemon can be running while steering is not actually engaged
    # (a failed steering-config download leaves it up but enforcing nothing, and a
    # firewall.service restart flushes the rules it installed out from under it).
    # `start` then prints "active" and changes nothing, which is precisely the
    # "netskope-on did nothing" failure this script exists to prevent. A restart
    # rebuilds the plumbing unconditionally.
    systemctl restart stagentd || true
    echo "  daemon: $(systemctl is-active stagentd 2>&1)"

    # The daemon alone never builds a tunnel: with no per-user agent registered it
    # has no active user session. The tray units are what give it one.
    probe_user=""
    for u in $(loginctl list-users --no-legend 2>/dev/null | ${pkgs.gawk}/bin/awk '$2 != "root" { print $1 }'); do
      name=$(loginctl show-user "$u" -p Name --value 2>/dev/null || true)
      [ -n "$name" ] || continue
      probe_user="$name"
      runuser -u "$name" -- env XDG_RUNTIME_DIR="/run/user/$u" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$u/bus" \
        systemctl --user start stagentapp stagentui 2>/dev/null || true
    done

    # Verify enforcement instead of asserting it. TLS to a bare IP is the right probe:
    # under steering the cert is reissued by the tenant CA
    # (CN=ns-swg.ca.lselectric.goskope.com), so a goskope.com issuer means traffic is
    # genuinely being intercepted. Deliberately NOT a fetch of a blocked category --
    # that would work too, but it files an Acceptable Use Policy violation against the
    # user in the Netskope console every single time the script runs.
    #
    # Probe as the desktop user, not root: root has no session and its traffic is not
    # a representative sample of what the browser will get.
    probe() {
      if [ -n "$probe_user" ]; then
        runuser -u "$probe_user" -- curl -sv --max-time 5 https://1.1.1.1 -o /dev/null 2>&1
      else
        curl -sv --max-time 5 https://1.1.1.1 -o /dev/null 2>&1
      fi
    }

    echo "  waiting for steering to engage..."
    for i in 1 2 3 4 5 6 7 8 9 10; do
      if probe | grep -qi "issuer:.*goskope.com"; then
        echo "  ENFORCEMENT VERIFIED after $((i * 3))s (TLS reissued by tenant CA)"
        echo
        echo "Netskope is ON and enforcing."
        echo "NOTE: an already-open browser may still serve cached pages or reuse a"
        echo "      connection opened before steering engaged, which looks exactly like"
        echo "      Netskope being off. Hard-reload (Ctrl+Shift+R) or restart it."
        exit 0
      fi
      sleep 3
    done

    echo
    echo "Netskope is running but steering did NOT engage within 30s."
    echo "  sta0=$(ip -o link show sta0 2>/dev/null | wc -l) table9=$(ip route show table 9 2>/dev/null | wc -l)"
    echo "Check: journalctl -u stagentd -n 50"
    echo "  and: grep -iE 'steering|tunnel' /opt/netskope/stagent/logs/nsdebuglog.log | tail -20"
    exit 1
  '';

  # The bit that runs inside the terminal window: do the teardown, then hold the
  # window open so the verdict is actually readable. Separate script rather than an
  # inline `bash -c` because the desktop-entry spec forbids `;` and `\'` in Exec
  # outside quotes, and desktop-file-validate rejects the build outright.
  panicWindow = pkgs.writeShellScriptBin "netskope-off-window" ''
    ${netskopeOff}/bin/netskope-off
    rc=$?
    echo
    if [ "$rc" = 0 ]; then
      echo "Done. Netskope is off and will stay off until you run: netskope-on"
    else
      echo "Netskope was turned off, but DNS did not come back -- see above."
    fi
    echo
    printf '[press enter to close] '
    read -r _ || true
  '';

  # Launcher entry. An explicit terminal rather than Terminal=true, because that key
  # needs launcher cooperation and this has to work first try, while panicking, with
  # the network down.
  panicItem = pkgs.makeDesktopItem {
    name = "netskope-off";
    desktopName = "Netskope OFF (fix my internet)";
    comment = "Kill the Netskope client and undo its network plumbing. Persists across reboots.";
    icon = "network-offline";
    categories = [ "System" ];
    terminal = false;
    exec = "${pkgs.wezterm}/bin/wezterm start --always-new-process -- ${panicWindow}/bin/netskope-off-window";
  };
in
{
  environment.systemPackages = [
    netskopeOff
    netskopeOn
    panicWindow
    panicItem
  ];

  # The button is useless if it needs a password nobody can see the prompt for, but a
  # blanket passwordless root would be worse. Scope it to these two exact store paths:
  # they only stop/start this one service and undo its own routing, and being store
  # paths they are immutable — the rule cannot be widened by editing the script.
  #
  # Note this is deliberately in tension with the tenant setting
  # allowClientDisabling=false. The justification is recovery, not evasion: without it
  # a broken tunnel means an unusable laptop, and netskope.nix already documents the
  # same teardown as the supported recovery path.
  security.sudo.extraRules = [
    {
      users = [ "vwestberg" ];
      commands = [
        {
          command = "${netskopeOff}/bin/netskope-off";
          options = [ "NOPASSWD" ];
        }
        {
          command = "${netskopeOn}/bin/netskope-on";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];

  # The persistent half. A failing ExecCondition skips the unit without marking it
  # failed and without triggering Restart=always, which is exactly the semantic
  # wanted: "not now, and not on the next boot either, until someone clears the flag".
  systemd.services.stagentd.serviceConfig.ExecCondition = [
    "${pkgs.bash}/bin/bash -c '! test -e ${flag}'"
  ];
}
