# WezTerm rendering + windowing backend.
#
# Two separate second-window crashes on this Framework 16 (AMD Radeon 780M /
# amdgpu) under mango (wlroots):
#
#   1. GPU context (fixed): itera's default front_end is WebGpu (Vulkan), which
#      fails to stand up a SECOND GPU context here — opening a second terminal
#      window crashed. Forcing OpenGL (still GPU-accelerated, more robust) fixed
#      that. (itera's own dev/vm.nix flags WebGpu/GL context fragility here.)
#
#   2. Wayland protocol (this fix): with the GPU crash gone, opening a second
#      window still died — this time with "Protocol error 2 on object
#      wl_surface@N" followed by "Broken pipe (os error 32)". That's WezTerm's
#      NATIVE Wayland client mishandling the second window's surface against a
#      wlroots compositor (a WezTerm-side bug, not a mango misconfig). Disable
#      the native Wayland backend so WezTerm runs via Xwayland (X11 backend),
#      which handles multiple windows reliably. OpenGL acceleration still applies.
#
# Rendered by itera's wezterm renderer into ~/.config/wezterm/wezterm.lua as
# `config.front_end = 'OpenGL'` and `config.enable_wayland = false`.
{ ... }:
{
  itera.users.vwestberg.programs.wezterm.settings = {
    front_end = "OpenGL";
    enable_wayland = false;
  };
}
