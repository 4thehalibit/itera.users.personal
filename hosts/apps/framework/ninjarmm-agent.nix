# NinjaOne (NinjaRMM) agent — the corporate RMM agent. Framework-only for the
# same reason as netskope.nix and falcon-sensor.nix: the tenant is work
# infrastructure, so this file is imported from hosts/framework.nix rather than
# hosts/common.nix.
#
# Unlike those two there is no upstream flake for this one, and there cannot
# easily be a public one: NinjaOne builds a per-organisation installer with the
# tenant's ClientUID compiled into it, served only from the authenticated
# console. So the .deb is staged BY HAND, out of tree, and this module unpacks
# it. Nothing tenant-identifying lands in this (public) repository.
#
# STAGE THE INSTALLER BEFORE THE FIRST REBUILD:
#
#   sudo install -m 0400 -D \
#     ~/Downloads/NinjaOne-Agent-LS-Corporate-LINUX-x86-64.deb \
#     /persist/ninjarmm-agent.deb
#
# Without it ninjarmm-agent-setup.service fails at boot. The config still
# evaluates and the rest of the system comes up fine, so a rebuild is safe —
# the agent simply will not install.
#
# WHY NO PATCHELF, WHICH IS THE INTERESTING PART. The vendor binaries are
# ordinary glibc ELFs asking for /lib64/ld-linux-x86-64.so.2 and nothing beyond
# glibc + libgcc. programs.nix-ld (already on, from itera) provides exactly that
# interpreter, and it resolves every dependency here even under an empty
# environment — verified with LD_TRACE_LOADED_OBJECTS on this host.
#
# That is not merely the lazier option, it is the only one that survives. The
# agent self-updates: ninjarmm-patcher runs every five minutes and replaces
# ninjarmm-linagent in place with a freshly downloaded, FHS-linked binary. A
# patchelf'd or store-resident install would work exactly until the first patch
# and then fail to exec. nix-ld fixes the loader for whatever binary happens to
# be sitting at that path, so self-updates keep working.
#
# The corollary is that the agent tree MUST be mutable and MUST be persisted —
# it is not a build artefact, it is state that rewrites itself. See the
# impermanence block at the bottom.
{ pkgs, ... }:
let
  # Staged by hand, see the header. Deliberately a plain runtime path and not a
  # `path` / store copy: the installer is non-redistributable and this repo is
  # public, and under flakes an absolute path cannot be read at eval time
  # anyway ("access to absolute path ... is forbidden in pure evaluation mode").
  debFile = "/persist/ninjarmm-agent.deb";

  agentDir = "/opt/NinjaRMMAgent";
  programfiles = "${agentDir}/programfiles";

  # The tools the agent needs to find, as one directory of symlinks. This is
  # both the unit PATH and the content bind-mounted over /usr/bin and /bin for
  # the agent's own mount namespace, so the two can never drift: add a package
  # here and it appears in both places.
  #
  # coreutils carries `env` and bashInteractive carries `sh`, which the bind
  # would otherwise hide — the real /usr/bin and /bin hold nothing else on this
  # host, so this set is a superset of what it replaces.
  #
  # file / networkmanager (nmcli) / parted are for the monitoring inventory; the
  # rest is so console-dispatched scripts have a working userland.
  fhsTools = pkgs.buildEnv {
    name = "ninjarmm-fhs-tools";
    paths = with pkgs; [
      bashInteractive
      coreutils
      curl
      file
      gawk
      gnugrep
      gnused
      gnutar
      gzip
      iproute2
      networkmanager
      parted
      procps
      systemd
      util-linux
    ];
    pathsToLink = [ "/bin" ];
  };

  # Give the unit an FHS /usr/bin and /bin, visible ONLY inside its own mount
  # namespace. Nothing changes for the rest of the system.
  #
  # This exists because the agent's util check does not consult $PATH. It walks
  # a compiled-in FHS list — /usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:
  # /sbin:/bin, verified in the binary's strings — and on stock NixOS /usr/bin
  # holds only `env` and /bin only `sh`, so every probe misses and the console
  # reports the host as unmonitorable:
  #
  #   Target machine distributive is not ready to collect monitoring data,
  #   because of missing utils: file, nmcli, top, parted, bash, ls, pgrep, who.
  #
  # bash, ls, top, pgrep and who were in the unit PATH when that fired. That is
  # the whole point: extending PATH alone can never fix it.
  #
  # It also covers what the check does not report — the agent hardcodes
  # /bin/bash, and the console's scripts are Debian-flavoured, so they arrive
  # with #!/bin/bash shebangs.
  #
  # WHY NOT services.envfs, which is the usual NixOS answer here. envfs resolves
  # /usr/bin/<name> against the requesting process's PATH, and it reads that PATH
  # by ptrace-attaching to the caller. itera sets
  # boot.kernel.sysctl."kernel.yama.ptrace_scope" = 3, which disables ptrace
  # outright, so every lookup fails. It was tried on this host and the kernel
  # logged the refusal for each one:
  #
  #   ptrace attach of "/opt/NinjaRMMAgent/programfiles/ninjarmm-linagent"
  #     was attempted by ".../mount.envfs none /usr/bin -o ..."
  #
  # Worse than merely not working: envfs force-disables the activation scripts
  # that create /usr/bin/env and /bin/sh and serves them from the mount instead,
  # so with ptrace blocked the host loses /bin/sh entirely. Do not re-enable it
  # here. Scope 3 is a one-way latch that cannot be lowered without a reboot,
  # and lowering a kernel hardening setting system-wide to satisfy one agent is
  # the wrong trade on a machine that also runs corporate EDR.
  fhsBinds = [
    "${fhsTools}/bin:/usr/bin"
    "${fhsTools}/bin:/bin"
  ];
in
{
  # Unpack the vendor .deb into the persisted, mutable agent directory, doing by
  # hand the parts of the deb's postinst that are not systemd bookkeeping.
  #
  # Runs ONCE, guarded on the agent binary already existing. Re-running it on a
  # host the patcher has since updated would overwrite newer binaries with the
  # staged .deb's older ones, i.e. a silent downgrade every boot. To force a
  # genuine reinstall, remove /persist/opt/NinjaRMMAgent and rebuild.
  systemd.services.ninjarmm-agent-setup = {
    description = "Unpack the NinjaOne agent into ${agentDir}";
    wantedBy = [ "multi-user.target" ];
    requiredBy = [ "ninjarmm-agent.service" ];
    before = [ "ninjarmm-agent.service" ];

    unitConfig = {
      # Skip cleanly once installed. The patcher owns the tree from then on.
      ConditionPathExists = "!${programfiles}/ninjarmm-linagent";
      # Wait for the impermanence bind mount declared at the bottom of this
      # file, so we never unpack into the tmpfs that /opt otherwise is.
      RequiresMountsFor = agentDir;
    };

    path = [
      pkgs.dpkg
      pkgs.iproute2
      pkgs.gnused
      pkgs.gawk
    ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    script = ''
      set -eu

      tmp=$(mktemp -d)
      trap 'rm -rf "$tmp"' EXIT
      dpkg-deb -x ${debFile} "$tmp"

      cp -a "$tmp"${agentDir}/. ${agentDir}/

      # postinst copies these in from the deb's staging directories, which only
      # exist because dpkg unpacks them to /tmp. Same files, placed directly.
      #
      # The CA bundle matters more than it looks: the agent verifies TLS against
      # this file rather than the system trust store, which is what spares this
      # module the /etc/ssl/certs rehashing dance netskope.nix needs.
      install -m 0644 "$tmp"/tmp/ninja-startup/ninjarmm-curl-ca-bundle.crt ${programfiles}/

      # postinst stamps a MAC into agent.conf as the reported machine id. Its own
      # awk takes the first link/ether it sees, which on this host is wlp1s0's
      # RANDOMISED address (NetworkManager clones it per network) rather than the
      # hardware one — so prefer `permaddr` when the kernel reports it. The value
      # is written once and then persists in agent.conf, so a randomised address
      # captured here would be wrong for the life of the install.
      mac=$(ip link show | awk '$1 == "link/ether" {
        mac = $2
        for (i = 3; i <= NF; i++) if ($i == "permaddr") mac = $(i + 1)
        print mac; exit
      }')
      sed -i "/^MachineId/ s#=.*#=$mac#" ${programfiles}/config/agent.conf

      chown -R 0:0 ${agentDir}
      chmod 600 ${programfiles}/config/agent.conf
      chmod 600 ${programfiles}/config/server.conf
    '';
  };

  systemd.services.ninjarmm-agent = {
    description = "NinjaOne RMM agent";
    after = [
      "network.target"
      "ninjarmm-agent-setup.service"
    ];
    wantedBy = [ "multi-user.target" ];

    # The vendor unit writes Environment="DAEMON_RUN=1 LC_ALL=C", which systemd
    # reads as ONE variable DAEMON_RUN with the value "1 LC_ALL=C". Set both
    # properly instead; DAEMON_RUN is what puts the agent in foreground/daemon
    # mode for Type=simple.
    environment = {
      DAEMON_RUN = "1";
      LC_ALL = "C";
    };

    # An RMM agent's whole job is running scripts as root on demand, and it
    # inherits this unit's PATH when it does. Without one it gets systemd's
    # bare default and every console-dispatched script that calls anything at
    # all fails with "command not found".
    path = [ fhsTools ];

    serviceConfig = {
      Type = "simple";
      ExecStart = "${programfiles}/ninjarmm-linagent";
      Restart = "always";
      RestartSec = 5;
      TimeoutStartSec = 10;
      # The vendor's own value. It is generous because a shutdown mid-job waits
      # for the job.
      TimeoutStopSec = 90;

      # See fhsBinds above. Child processes inherit the namespace, so scripts
      # the console dispatches get the same FHS view the agent does.
      BindReadOnlyPaths = fhsBinds;
    };
  };

  # Self-update. This is what keeps the install current without ever bumping
  # anything in this repo — and, as the header notes, what rules out any
  # store-resident or patchelf'd packaging.
  systemd.services.ninjarmm-patcher = {
    description = "NinjaOne agent patcher";
    after = [ "network.target" ];
    path = [ fhsTools ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${programfiles}/ninjarmm-linagent-patcher";
      BindReadOnlyPaths = fhsBinds;
    };
    unitConfig.ConditionPathExists = "${programfiles}/ninjarmm-linagent-patcher";
  };

  systemd.timers.ninjarmm-patcher = {
    description = "Timer for ninjarmm-patcher.service";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "5m";
      OnUnitActiveSec = "5m";
      AccuracySec = "1s";
      Unit = "ninjarmm-patcher.service";
    };
  };

  # Impermanence. Everything about this agent is mutable state living under one
  # hard-coded path: the binaries (rewritten by the patcher), agent.conf (which
  # gains NodeId and Password when the device registers) and server.conf.
  #
  # WITHOUT THIS the wiped root throws the registration away on every boot, the
  # setup unit unpacks a fresh copy, and the machine enrols as a brand new
  # device — so the NinjaOne console fills with duplicates of LS-04391 and burns
  # a licence seat each time. Same failure mode as the Falcon AID.
  #
  # /opt is tmpfs on this host, so this bind is also what makes the tree
  # writable and executable at all: it comes off the /persist btrfs subvolume,
  # which carries no noexec (mount flags are per-mount, not inherited), whereas
  # /var is mounted noexec here — which is why the tree lives under /opt rather
  # than the more usual /var/lib.
  #
  # Note this is the opposite of netskope.nix's rule that nothing under /opt may
  # be persisted. That rule exists because netskope's /opt content is refreshed
  # from the nix store on every package change and a persisted copy would shadow
  # it. Nothing here comes from the store, so there is nothing to shadow.
  itera.impermanence.directories = [
    {
      directory = agentDir;
      mode = "0755";
    }
  ];
}
