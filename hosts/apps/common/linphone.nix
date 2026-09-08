# Linphone SIP softphone, installed per-user. (Contacts workflow: the Vonage
# directory popup — Super+Shift+P — see apps/common/vonage-directory.nix.)
#
# The zxingPin overlay that used to live here is gone (2026-09-08). It existed
# because zxing-cpp 3.x dropped the pre-2.0 writer API (MultiFormatWriter /
# BitMatrix / TextUtfEncoding) that liblinphone 5.4.85's factory.cpp still used,
# so we hand-pinned zxing-cpp 1.4.0 for liblinphone only. liblinphone 5.5.13
# takes a `bc-zxing-cpp` argument instead — Belledonne's own fork, packaged
# upstream as linphonePackages.bc-zxing-cpp (1.4.0-unstable-2026-08-08, the same
# 1.4.0 base we were pinning). Keeping the overlay broke eval outright:
#   error: function 'anonymous lambda' called with unexpected argument 'zxing-cpp'
{ pkgs, ... }:
{
  itera.users.vwestberg.packages = [ pkgs.linphone ];
}
