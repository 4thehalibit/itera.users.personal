#!/usr/bin/env bash
#
# Remote installer for this flake, run from a booted NixOS live ISO. Picks the
# disk to install onto, confirms the destructive wipe, then hands off to
# disko-install (partition + format + mount + nixos-install, in one). Adapted
# from lcleveland/itera.personal.
#
#   curl -sSL https://raw.githubusercontent.com/4thehalibit/itera.users.personal/main/install.sh | sudo bash
#   curl -sSL .../install.sh | sudo bash -s -- /dev/nvme0n1       # non-interactive disk
#   curl -sSL .../install.sh | sudo FLAKE=. bash                  # install from a local clone

set -euo pipefail

export NIX_CONFIG="extra-experimental-features = nix-command flakes
accept-flake-config = true
${NIX_CONFIG:-}"

FLAKE="${FLAKE:-github:4thehalibit/itera.users.personal}"
HOST="framework"     # the only nixosConfigurations attr
DISK_NAME="main"     # the disk key in itera.disko

if [ -r /dev/tty ]; then TTY=/dev/tty; else TTY=/dev/stdin; fi

if [ "$(id -u)" -ne 0 ]; then
  echo "error: must run as root (it partitions a disk). Pipe into 'sudo bash'." >&2
  exit 1
fi

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
exec nix run 'github:nix-community/disko/latest#disko-install' -- \
  --flake "${FLAKE}#${HOST}" --disk "${DISK_NAME}" "$device" "$@"
