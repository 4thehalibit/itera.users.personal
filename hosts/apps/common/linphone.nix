# Linphone SIP softphone, installed per-user. (Contacts workflow: the Vonage
# directory popup — Super+Shift+P — see apps/common/vonage-directory.nix.)
{ pkgs, ... }:
let
  # nixos-unstable bumped zxing-cpp to 3.x, which removed the pre-2.0 writer
  # API (MultiFormatWriter / BitMatrix / TextUtfEncoding) that liblinphone
  # 5.4.85's factory.cpp still uses. Pin an old zxing-cpp for liblinphone only.
  # liblinphone now lives in the linphonePackages scope (pkgs.linphone =
  # linphonePackages.linphone-desktop), so override the scope member, not the
  # top-level alias (which is a throw).
  zxingPin = final: prev: {
    linphonePackages = prev.linphonePackages.overrideScope (
      _fScope: pScope: {
        liblinphone = pScope.liblinphone.override {
          zxing-cpp = final.zxing-cpp.overrideAttrs (_old: {
            version = "1.4.0";
            src = final.fetchFromGitHub {
              owner = "zxing-cpp";
              repo = "zxing-cpp";
              tag = "v1.4.0";
              hash = "sha256-MTu8tvJXpo6+Z0aSIZ27nmerNtNBOwnL/jDkGedIiM8=";
            };
            # 1.4.0 predates the bundled-zint inputs/flags in the current package
            buildInputs = [ ];
            cmakeFlags = [
              "-DBUILD_EXAMPLES=OFF"
              "-DBUILD_BLACKBOX_TESTS=OFF"
            ];
            # 1.4.0's CMake emits a malformed zxing.pc (${exec_prefix}//nix/store
            # doubled paths) that nixpkgs' validatePkgConfig hook rejects
            # (NixOS/nixpkgs#144170). Rewrite the two offending lines.
            postInstall = ''
              sed -i \
                -e "s|^libdir=.*|libdir=$out/lib|" \
                -e "s|^includedir=.*|includedir=$out/include|" \
                "$out/lib/pkgconfig/zxing.pc"
            '';
          });
        };
      }
    );
  };
in
{
  nixpkgs.overlays = [ zxingPin ];
  itera.users.vwestberg.packages = [ pkgs.linphone ];
}
