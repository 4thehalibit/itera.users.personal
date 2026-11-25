# Stremio (media center client), installed per-user. The nixpkgs package is
# named stremio-linux-shell. Its license is GPL-3.0 plus unfree.
#
# Pinned to 1.3.0: nixpkgs still ships 1.2.2 and the client loads the live
# web UI, so the old shell can fall behind it. Since 1.3.0 build.rs reads its
# output dirs from env (GETTEXT_DIR, GSETTINGS_SCHEMA_DIR) instead of the
# paths nixpkgs' out-path.patch rewrote, so the patch is dropped and the same
# paths are set through env. Delete this override once nixpkgs reaches 1.3.0.
{ pkgs, ... }:
let
  stremio = pkgs.stremio-linux-shell.overrideAttrs (old: rec {
    version = "1.3.0";
    src = pkgs.fetchFromGitHub {
      owner = "Stremio";
      repo = "stremio-linux-shell";
      tag = "v${version}";
      hash = "sha256-+LVpDLb5hhOvwluuywQXTm9IH79+bgOAsFd/oZZsdAg=";
    };
    cargoDeps = pkgs.rustPlatform.fetchCargoVendor {
      inherit src;
      hash = "sha256-LA9nfAG4dROlfvjYvkyQZap5L/HVVq/Kvl/0D8NvNzI=";
    };
    patches = [ ];
    postPatch = ''
      substituteInPlace data/com.stremio.Stremio.service data/stremio.sh \
        --replace-fail /app/ "$out/"
    '';
    env = (old.env or { }) // {
      GETTEXT_DIR = "${placeholder "out"}/share/locale";
      GSETTINGS_SCHEMA_DIR = "${placeholder "out"}/share/glib-2.0/schemas";
      STREMIO_LOCALEDIR = "${placeholder "out"}/share/locale";
    };
  });
in
{
  itera.users.vwestberg.packages = [ stremio ];
}
