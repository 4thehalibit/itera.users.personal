# `keybinds-popup` — fzf cheat sheet of the current mango keybinds. Bound to
# Super+F1 (see mango-keybinds.nix). Adapted from eiros
# applications/keybindings_cheatsheet.nix; the old zsh-alias section was dropped
# (personal commands are now real binaries, and the login shell is nushell).
{ pkgs, ... }:
{
  environment.systemPackages = [
    (pkgs.writeShellScriptBin "keybinds-popup" ''
      dms keybinds show mangowc | ${pkgs.python3}/bin/python3 -c "
import json, sys
data = json.load(sys.stdin)
binds = data.get('binds', {})
ESC = chr(27)
R   = ESC + '[0m'
B   = ESC + '[1m'
CAT = ESC + '[1;96m'
KEY = ESC + '[93m'
order = ['Window', 'Tags', 'Monitor', 'Overview', 'System', 'Execute']
cats = sorted(binds.keys(), key=lambda c: order.index(c) if c in order else 99)
print()
for cat in cats:
    items = binds[cat]
    print('  ' + CAT + B + cat.upper() + R)
    for b in items:
        key = b.get('key') or str()
        desc = b.get('desc') or b.get('action') or str()
        print('    ' + KEY + key.ljust(28) + R + desc)
    print()
      " | ${pkgs.fzf}/bin/fzf --ansi --no-sort --layout=reverse \
            --header="  Keybindings  (type to search, Esc to close)" \
            --header-first --no-info --no-preview --bind="esc:abort,enter:abort"
    '')
  ];
}
