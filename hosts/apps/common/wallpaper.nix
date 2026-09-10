# Astros wallpaper (see hosts/common.nix for the rest of the palette).
#
# WHY THIS FILE EXISTS RATHER THAN A SETTING IN common.nix:
# the desktop wallpaper is NOT a DMS setting. DMS keeps it in SessionData
# (~/.local/state/DankMaterialShell/session.json, `monitorWallpapers`, keyed per
# monitor), not in settings.json, and itera exposes no wallpaper option either.
# So the desktop wallpaper cannot be declared here at all — it is set ONCE at
# runtime with
#
#     dms ipc call wallpaper set /home/vwestberg/Pictures/Wallpapers/astros-arc.png
#
# and DMS persists it. session.json is a real writable file (not a store
# symlink like settings.json), and itera persists `.local/state`, so that one
# call survives both a reboot and a wiped-root boot.
#
# The LOCK SCREEN and GREETER wallpapers *are* settings.json keys, so those two
# are declared below and need no manual step.
#
# WHY THE IMAGE IS LINKED INTO ~/Pictures INSTEAD OF USED FROM THE STORE:
# session.json would then hold a /nix/store path, and editing the image changes
# that path — the old one gets garbage-collected and the desktop wallpaper
# silently breaks, with no way for nix to fix it (nix does not own that file).
# Linking to a stable path under ~/Pictures means the image can be re-rendered
# and redeployed freely; the path DMS recorded never changes.
#
# REGENERATING THE IMAGE: ./astros-wallpaper-render.sh out.png, which needs
# imagemagick — not installed system-wide, so run it under
# `nix shell nixpkgs#imagemagick`. The script documents the crop constraints
# (the same file has to survive 4K, 32:9 and 16:10 fill-crops).
{ ... }:
let
  wallpaper = "/home/vwestberg/Pictures/Wallpapers/astros-arc.png";
in
{
  # ~/Pictures is on itera's curated persist list, and hjem re-links every boot,
  # so this needs no impermanence entry of its own.
  hjem.users.vwestberg.files."Pictures/Wallpapers/astros-arc.png".source =
    ./astros-wallpaper.png;

  itera.programs.dankMaterialShell.settings = {
    lockScreenWallpaperPath = wallpaper;
    greeterWallpaperPath = wallpaper;
    # "Fill" (crop to cover) is DMS's default and what the image is composed
    # for; stated explicitly so a future default change cannot letterbox it.
    lockScreenWallpaperFillMode = "Fill";
    greeterWallpaperFillMode = "Fill";
  };
}
