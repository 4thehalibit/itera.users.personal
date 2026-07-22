# itera.users.personal

vwestberg's NixOS configuration, built on [itera](https://github.com/lcleveland/itera)
(a batteries-included, opt-out layer using hjem, disko, impermanence, and the
mango/DankMaterialShell desktop). Migrated from the old `eiros` config.

Tracks **nixos-unstable** (itera's channel).

## Host

| Flake attr  | Hostname   | Machine                 | Notes                                        |
|-------------|------------|-------------------------|----------------------------------------------|
| `framework` | `LS-04391` | Framework 16 (7040 AMD) | fingerprint, printing, three monitors, LED matrix |

Uses itera's declarative disk layout (`disko`) + tmpfs root (`impermanence`) —
**installing wipes the target disk.** The disk is chosen at install time with
`disko-install --disk main /dev/<disk>`; the `itera.disko.device` value in
`hosts/framework.nix` is a fail-safe placeholder the install command overrides.

## What survives a reboot (impermanence)

Root `/` is a tmpfs wiped every boot. Persisted `$HOME` paths (itera defaults):
`.config` (incl. `~/.config/vivaldi` = **browser history**), `.local/share`,
`.local/state`, `.cache`, `.ssh`, `.claude`, `Documents`, `Downloads`, `.claude.json`.
Anything else in `~` is gone on reboot — see the migration plan for the backup
checklist and any extra persist paths (`Pictures`, `Vonage`, config checkout).

## What was ported from eiros (personal items)

- Monitor layout (home VX3211-4K; work stacked DP-9/DP-10 + laptop) — `hosts/framework.nix`
- Mango keybinds (arrow focus/swap, app launchers, media cluster, web apps) — `hosts/apps/common/mango-keybinds.nix`
- NinjaOne (via the `ninjarmm-ncplayer` flake, no more impure `.deb`)
- Git identity, DNSSEC "DNS down" fix, `deploy`/`rebuild`/`fixhdmi`/`claude`/`freshworks` commands
- Vonage directory popup (Super+Shift+P), keybind cheatsheet (Super+F1)
- Framework LED-matrix typing effects **+ a new toggle** (Super+Shift+L), F7/F8 brightness
- Teams auto-pause music, Thunderbolt-dock PCIe rescan
- Apps: teams, zoom, linphone, vesktop, caprine, cider, yubico, onlyoffice, nautilus, dev tools

## What was dropped in favor of itera defaults

- **Shell**: zsh → nushell (personal commands are now real binaries, shell-agnostic)
- **Terminal**: ghostty → wezterm
- **Editor**: VS Code + pinned extensions → Zed (itera's editor battery, Claude wired in)
- **DMS theme**: custom rainbow/°F overrides → itera's default DMS theme (already °F)

## Install (from a NixOS unstable live ISO)

Back up first (see the migration plan). Then:

```sh
curl -sSL https://raw.githubusercontent.com/4thehalibit/itera.users.personal/main/install.sh | sudo bash
```

It prompts for the disk, confirms the wipe, and runs `disko-install`. After it
finishes: reboot, log in as `vwestberg` / `changeme`, then **`passwd`** to set a
real password.

## Rebuild

```sh
itera rebuild   # nh os switch from the configured remote flake + host
itera update    # --refresh to the newest pushed revision, then rebuild
deploy "msg"    # commit + push the local checkout, then itera update
```

## Verify (this repo evaluates)

```sh
nix flake metadata
nix eval --impure '.#nixosConfigurations.framework.config.system.build.toplevel.drvPath'
```
