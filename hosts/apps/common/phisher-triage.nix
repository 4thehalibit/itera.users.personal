# PhishER triage tool. The engine lives in ~/Documents/phisher-triage (a
# persisted path, kept as an ordinary git repo so it can move to a server when
# the triage loop graduates to a scheduled job). This module only puts a
# launcher on PATH and supplies the interpreter.
#
# The tool is stdlib-only by design, with one exception: QR decoding for
# quishing detection needs pyzbar + pillow. Providing them here rather than
# vendoring them keeps `python3 phisher` working anywhere, and the code
# degrades honestly (it emits QR_NOT_SCANNED) when they are absent.
{ pkgs, ... }:
let
  pythonEnv = pkgs.python3.withPackages (ps: [
    ps.pyzbar   # QR decode; pulls zbar
    ps.pillow   # image loading for pyzbar
  ]);

  repo = "$HOME/Documents/phisher-triage";

  phisher = pkgs.writeShellScriptBin "phisher" ''
    if [ ! -d "${repo}" ]; then
      echo "phisher-triage checkout not found at ${repo}" >&2
      exit 1
    fi
    # Deliberately no cd: file arguments must resolve against the caller's
    # working directory. The CLI resolves its own repo-relative paths (samples/,
    # rules/) internally.
    exec ${pythonEnv}/bin/python3 "${repo}/phisher" "$@"
  '';
in
{
  environment.systemPackages = [ phisher ];
}
