# WezTerm rendering backend.
#
# itera ships WezTerm with no `front_end` set, so it uses WezTerm's default —
# WebGpu (Vulkan). On this Framework 16 (AMD Radeon 780M / amdgpu) under mango
# (wlroots), WebGpu fails to stand up a second GPU context: opening a SECOND
# terminal window crashes. (itera's own dev/vm.nix flags WebGpu/GL context
# fragility here.) Force OpenGL instead — still GPU-accelerated, much more
# robust. If a crash somehow persists, drop to front_end = "Software".
#
# Rendered by itera's wezterm renderer as `config.front_end = 'OpenGL'` in
# ~/.config/wezterm/wezterm.lua.
{ ... }:
{
  itera.users.vwestberg.programs.wezterm.settings.front_end = "OpenGL";
}
