# eml-viewer: a lightweight *viewer* (not a mail client) for .eml files.
# `eml-view` renders the message to a self-contained HTML page (headers, body,
# inline images, attachments as download links) and opens it in the browser.
# A .desktop entry registers it as the message/rfc822 handler so double-clicking
# a .eml in Nautilus just works. See ./eml-view.py for the renderer.
{ pkgs, ... }:
let
  eml-view = pkgs.writeShellScriptBin "eml-view" ''
    export PATH=${pkgs.lib.makeBinPath [ pkgs.xdg-utils ]}:$PATH
    exec ${pkgs.python3}/bin/python3 ${./eml-view.py} "$@"
  '';

  eml-viewer-desktop = pkgs.makeDesktopItem {
    name = "eml-viewer";
    desktopName = "EML Viewer";
    comment = "View .eml email files in the browser";
    exec = "${eml-view}/bin/eml-view %f";
    icon = "mail-message";
    terminal = false;
    mimeTypes = [ "message/rfc822" ];
    categories = [ "Utility" "Email" ];
  };
in
{
  itera.users.vwestberg.packages = [ eml-view eml-viewer-desktop ];

  # Make it the default app for .eml (message/rfc822) files.
  xdg.mime.defaultApplications."message/rfc822" = "eml-viewer.desktop";
}
