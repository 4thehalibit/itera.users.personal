# `vonage-directory-popup` — fzf lookup over the Vonage phone directory CSV in
# ~/Vonage/, Enter copies the extension to the clipboard. Bound to Super+Shift+P
# (see mango-keybinds.nix). This is the Linphone-contacts workflow.
# Ported verbatim from eiros applications/vonage_directory.nix.
#
# NOTE: ~/Vonage/ is NOT on itera's default persist list — either keep the CSV in
# ~/Documents (persisted) and adjust the glob, or add "Vonage" to
# itera.impermanence.users.vwestberg.directories.
{ pkgs, ... }:
{
  environment.systemPackages = [
    (pkgs.writeShellScriptBin "vonage-directory-popup" ''
      csv=$(ls -1 "$HOME"/Vonage/*.csv 2>/dev/null | head -n1)
      if [ -z "$csv" ]; then
        printf '\n  No CSV found in ~/Vonage/\n\n' | \
          ${pkgs.fzf}/bin/fzf --ansi --layout=reverse --no-info --no-preview \
            --header="  Vonage Directory  (drop a .csv in ~/Vonage/)" \
            --header-first --bind="esc:abort,enter:abort"
        exit 0
      fi
      ${pkgs.python3}/bin/python3 -c "
import csv, sys
ESC = chr(27)
R   = ESC + '[0m'
B   = ESC + '[1m'
HDR = ESC + '[1;96m'
TAB = chr(9)
KEEP = ['User', 'Extension', 'Phone Number', 'Groups', 'Email']
with open(sys.argv[1], newline=str()) as f:
    rows = [r for r in csv.reader(f) if any(c.strip() for c in r)]
if not rows:
    sys.exit(0)
header = rows[0]
kept   = [h for h in KEEP if h in header] or header
idx    = [header.index(h) for h in kept]
rows   = [[r[i] if i < len(r) else str() for i in idx] for r in rows]
ncol   = len(idx)
epos   = kept.index('Extension') if 'Extension' in kept else -1
widths = [max(len(r[i]) for r in rows) for i in range(ncol)]
def fmt(r, color=str()):
    return '  ' + '  '.join(color + r[i].ljust(widths[i]) + R for i in range(ncol))
print(fmt(rows[0], HDR + B) + TAB)
for r in rows[1:]:
    print(fmt(r) + TAB + (r[epos] if epos >= 0 else str()))
      " "$csv" | ${pkgs.fzf}/bin/fzf --ansi --no-sort --layout=reverse --header-lines=1 \
            --delimiter="\t" --with-nth=1 \
            --header="  Vonage Directory  (type to search, Enter copies extension, Esc closes)" \
            --header-first --no-info --no-preview \
            --bind="esc:abort" \
            --bind="enter:execute-silent(printf '%s' {2} | ${pkgs.wl-clipboard}/bin/wl-copy)+abort"
    '')
  ];
}
