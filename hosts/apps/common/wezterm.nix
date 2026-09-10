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
#
# Also carries the terminal half of the Astros palette (see hosts/common.nix for
# the shell/DMS half). DMS's matugen generates
# ~/.config/wezterm/colors/dank-theme.toml on every theme change, which WezTerm
# would pick up via `color_scheme = "dank-theme"` — but that file derives its
# ANSI ramp from Material tonal steps, which washes the 16 colors out into
# near-identical navies. These are set explicitly instead so ordinary command
# output stays readable.
{ ... }:
{
  itera.users.vwestberg.programs.wezterm.settings = {
    front_end = "OpenGL";
    enable_wayland = false;

    # Astros: navy #002D62 base ramp, orange #EB6E1F accent. The renderer's
    # toLua is recursive, so nested tables/lists serialize fine.
    #
    # ANSI 3/11 are deliberately GOLD, not orange: orange is reserved for UI
    # accent (cursor, mango focus border, DMS primary), and a second orange in
    # the 16-color ramp makes it stop reading as an accent.
    colors = {
      background = "#000E1E";
      foreground = "#EEF3FA";
      cursor_bg = "#EB6E1F";
      cursor_border = "#EB6E1F";
      cursor_fg = "#000E1E";
      selection_bg = "#14508F";
      selection_fg = "#EEF3FA";
      # black      red        green      yellow     blue       magenta    cyan       white
      ansi = [
        "#0A2340"
        "#C42B3D"
        "#2F8F57"
        "#D99A22"
        "#2E76B0"
        "#A04C7C"
        "#2A8C99"
        "#B4C4DA"
      ];
      brights = [
        "#14508F"
        "#EF4D5E"
        "#3FA96B"
        "#F5B335"
        "#3E8FD0"
        "#C05B8C"
        "#33A8B5"
        "#EEF3FA"
      ];
    };
  };
}
