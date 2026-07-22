#!/usr/bin/env bash
#
# Remote installer for this flake, run from a booted NixOS live ISO. Picks the
# disk to install onto, confirms the destructive wipe, hands off to
# disko-install (partition + format + mount + nixos-install, in one), then
# restores the personal backup from the Ventoy into the impermanence /persist
# subvolume so the first boot already has home data + saved Wi-Fi. Adapted
# from lcleveland/itera.personal.
#
#   curl -sSL https://raw.githubusercontent.com/4thehalibit/itera.users.personal/main/install.sh | sudo bash
#   curl -sSL .../install.sh | sudo bash -s -- /dev/nvme0n1       # non-interactive disk
#   curl -sSL .../install.sh | sudo FLAKE=. bash                  # install from a local clone
#   curl -sSL .../install.sh | sudo RESTORE=0 bash                # install only, no restore
#   curl -sSL .../install.sh | sudo BACKUP_DIR=/mnt/x bash        # restore from an explicit dir

set -euo pipefail

export NIX_CONFIG="extra-experimental-features = nix-command flakes
accept-flake-config = true
${NIX_CONFIG:-}"

FLAKE="${FLAKE:-github:4thehalibit/itera.users.personal}"
HOST="framework"     # the only nixosConfigurations attr
DISK_NAME="main"     # the disk key in itera.disko

# Restore knobs. RESTORE=0 skips the post-install restore entirely; BACKUP_DIR
# points restore at an already-mounted directory instead of auto-finding Ventoy.
RESTORE="${RESTORE:-1}"
BACKUP_DIR="${BACKUP_DIR:-}"
OWNER_UID=1000       # itera's first normal user (vwestberg) → uid 1000
OWNER_GID=100        # the `users` group → gid 100
USER_NAME="vwestberg"

if [ -r /dev/tty ]; then TTY=/dev/tty; else TTY=/dev/stdin; fi

if [ "$(id -u)" -ne 0 ]; then
  echo "error: must run as root (it partitions a disk). Pipe into 'sudo bash'." >&2
  exit 1
fi

# ---- restore helpers -------------------------------------------------------
# Copy a directory's CONTENTS into dest (creating dest), preserving times.
# Source lives on exfat (no unix ownership) — callers fix ownership after.
_seed_dir() {  # <src-dir> <dest-dir>
  [ -d "$1" ] || return 0
  mkdir -p "$2" && cp -a "$1/." "$2/" && echo "  + $2"
}
_seed_file() { # <src-file> <dest-file>
  [ -f "$1" ] || return 0
  mkdir -p "$(dirname "$2")" && cp -a "$1" "$2" && echo "  + $2"
}

# Seed the freshly installed /persist subvolume from the Ventoy backup. Purely
# best-effort: any missing piece (no Ventoy, no backup dir, no btrfs) prints a
# note and returns cleanly. Called inside a `set +e` subshell so it can never
# fail the (already-completed) OS install.
restore_backup() {
  device="$1"
  ventoy_mnt=""; owned_mnt=0; persist=""

  if [ "$RESTORE" != "1" ]; then echo "restore: skipped (RESTORE=0)."; return 0; fi

  # --- locate the backup directory ---
  backup=""
  if [ -n "$BACKUP_DIR" ]; then
    backup="$BACKUP_DIR"
  else
    vdev="$(blkid -L Ventoy 2>/dev/null || true)"
    if [ -z "$vdev" ]; then echo "restore: no Ventoy drive found — skipping."; return 0; fi
    # Reuse an existing mount if the live env already mounted it; else mount RO.
    ventoy_mnt="$(findmnt -nfro TARGET "$vdev" 2>/dev/null | head -1 || true)"
    if [ -z "$ventoy_mnt" ]; then
      ventoy_mnt="$(mktemp -d)"; owned_mnt=1
      if ! mount -o ro "$vdev" "$ventoy_mnt" 2>/dev/null; then
        echo "restore: could not mount Ventoy ($vdev) — skipping."; rmdir "$ventoy_mnt"; return 0
      fi
    fi
    # newest nixos-backup-* directory (lexical sort works for YYYY-MM-DD names)
    backup="$(ls -d "$ventoy_mnt"/nixos-backup-* 2>/dev/null | sort | tail -1 || true)"
  fi
  if [ -z "$backup" ] || [ ! -d "$backup" ]; then
    echo "restore: no nixos-backup-* directory found — skipping."
    [ "$owned_mnt" = 1 ] && { umount "$ventoy_mnt" 2>/dev/null || true; rmdir "$ventoy_mnt" 2>/dev/null || true; }
    return 0
  fi
  echo; echo "restore: using backup $backup"

  # --- mount the just-installed /persist subvolume ---
  btrfs_part="$(lsblk -pnro NAME,FSTYPE "$device" 2>/dev/null | awk '$2=="btrfs"{print $1; exit}')"
  if [ -z "$btrfs_part" ]; then
    echo "restore: no btrfs partition on $device — skipping."
    [ "$owned_mnt" = 1 ] && { umount "$ventoy_mnt" 2>/dev/null || true; rmdir "$ventoy_mnt" 2>/dev/null || true; }
    return 0
  fi
  persist="$(mktemp -d)"
  if ! mount -o subvol=persist "$btrfs_part" "$persist" 2>/dev/null; then
    echo "restore: could not mount persist subvol on $btrfs_part — skipping."
    rmdir "$persist" 2>/dev/null || true
    [ "$owned_mnt" = 1 ] && { umount "$ventoy_mnt" 2>/dev/null || true; rmdir "$ventoy_mnt" 2>/dev/null || true; }
    return 0
  fi

  home="$persist/home/$USER_NAME"

  # --- home data (paths must match itera's persisted set; Pictures/Vonage are
  #     added by hosts/common.nix's itera.impermanence.users.vwestberg) ---
  echo "restore: seeding home ($home) ..."
  _seed_dir  "$backup/Documents"       "$home/Documents"
  _seed_dir  "$backup/Pictures"        "$home/Pictures"
  _seed_dir  "$backup/Vonage"          "$home/Vonage"
  _seed_dir  "$backup/.claude"         "$home/.claude"
  _seed_file "$backup/.claude.json"    "$home/.claude.json"
  _seed_dir  "$backup/vivaldi-profile" "$home/.config/vivaldi"   # ~/.config/vivaldi
  if [ -d "$persist/home" ]; then
    chown -R "$OWNER_UID:$OWNER_GID" "$persist/home"
    [ -d "$home/.ssh" ] && chmod 700 "$home/.ssh"
  fi

  # --- Wi-Fi: NetworkManager connection profiles (root:root, 0600, or NM
  #     ignores them). Lands in the same /persist path itera persists. ---
  echo "restore: seeding Wi-Fi ..."
  nmsrc="$backup/NetworkManager/system-connections"
  if [ -d "$nmsrc" ] && ls "$nmsrc"/*.nmconnection >/dev/null 2>&1; then
    nmdst="$persist/etc/NetworkManager/system-connections"
    mkdir -p "$nmdst"
    cp -a "$nmsrc"/*.nmconnection "$nmdst/"
    chown -R root:root "$nmdst"
    chmod 700 "$nmdst"
    chmod 600 "$nmdst"/*.nmconnection
    echo "  + $(ls -1 "$nmdst"/*.nmconnection 2>/dev/null | wc -l) network(s)"
  else
    echo "  (no .nmconnection files in backup — skipping Wi-Fi)"
  fi

  sync
  umount "$persist" 2>/dev/null || true; rmdir "$persist" 2>/dev/null || true
  [ "$owned_mnt" = 1 ] && { umount "$ventoy_mnt" 2>/dev/null || true; rmdir "$ventoy_mnt" 2>/dev/null || true; }
  echo "restore: done."
}

# ---- disk ------------------------------------------------------------------
device=""
if [ "$#" -gt 0 ] && [ "${1#-}" = "$1" ]; then device="$1"; shift; fi

if [ -z "$device" ]; then
  names=(); labels=()
  while read -r name type size model; do
    [ "$type" = "disk" ] || continue
    case "$name" in /dev/zram* | /dev/ram*) continue ;; esac
    names+=("$name"); labels+=("$name  ($size)  ${model:-unknown model}")
  done < <(lsblk -dpno NAME,TYPE,SIZE,MODEL)
  [ "${#names[@]}" -gt 0 ] || { echo "error: no disks found." >&2; exit 1; }

  echo; echo "Select the disk to install '$HOST' onto:"; echo
  i=1; for label in "${labels[@]}"; do printf "  %2d) %s\n" "$i" "$label"; i=$((i + 1)); done
  echo; printf "Enter a number [1-%d]: " "${#names[@]}"
  read -r choice <"$TTY"
  case "$choice" in '' | *[!0-9]*) echo "error: '$choice' is not a number." >&2; exit 1 ;; esac
  { [ "$choice" -ge 1 ] && [ "$choice" -le "${#names[@]}" ]; } || { echo "error: out of range." >&2; exit 1; }
  device="${names[$((choice - 1))]}"
fi

# ---- confirm + install -----------------------------------------------------
echo; echo "About to WIPE and install '$HOST' onto: $device"
lsblk -pno NAME,SIZE,TYPE,MOUNTPOINTS "$device" 2>/dev/null || true
echo; echo "This ERASES ALL DATA on $device. There is no undo."
printf "Type the device path exactly to confirm (%s): " "$device"
read -r confirm <"$TTY"
[ "$confirm" = "$device" ] || { echo "aborted: confirmation did not match." >&2; exit 1; }

echo; echo "Installing ${FLAKE}#${HOST} onto ${device} ..."
# Not `exec` — control must return so the restore step can run afterward.
nix run 'github:nix-community/disko/latest#disko-install' -- \
  --flake "${FLAKE}#${HOST}" --disk "${DISK_NAME}" "$device" "$@"

# ---- restore (best-effort; never fails a successful install) ----------------
( set +e; restore_backup "$device" ) || true

echo
echo "Done. Reboot, log in as ${USER_NAME} / changeme, then run 'passwd' to set a real password."
