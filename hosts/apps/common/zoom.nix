# Zoom. Uses the NixOS program module (Wayland wrapper etc.) rather than a bare
# package.
{ ... }:
{
  programs.zoom-us.enable = true;
}
