# Personal mango keybinds, ported from eiros mangowc.nix (Hyprland/Omarchy muscle
# memory: arrow-key focus/swap, Super+Shift app launchers, media cluster, web apps).
#
# WHY WE DISABLE THE ITERA DEFAULTS AND DECLARE THE WHOLE SET:
# itera merges per-user binds over its defaults BY ATTRIBUTE NAME, not by chord
# (effectiveKeybinds = systemKeybinds // userKeybinds). eiros muscle memory relocates
# many chords: focus hjkl -> arrows, close SUPER+q -> SUPER+w, quit SUPER+SHIFT+q ->
# SUPER+CTRL+q, screenshot SUPER+SHIFT+s -> Print, cycleLayout SUPER+SHIFT+n -> launch
# editor, terminal SUPER+t -> SUPER+Return, etc. A surviving default that sits on the
# SAME chord under a DIFFERENT name is NOT displaced by a rename, so it emits a second
# `bind=` line and the chord phantom-fires. Example collisions that would occur if the
# defaults stayed: itera focusleft (SUPER+h) vs our monitor_home (SUPER+h); itera
# closeWindow (SUPER+q) with nothing overriding the NAME; itera notifications is fine
# but cycleLayout (SUPER+SHIFT+n) vs our launch_editor. The purpose-built toggle
# `defaultKeybinds.enable = false` omits systemKeybinds entirely, so effectiveKeybinds =
# these binds ONLY -> exactly one action per chord, no phantoms. (No mkForce needed.)
#
# Field renames vs eiros: modifier_keys->modifierKeys, flag_modifiers->flagModifiers,
# key_symbol->keySymbol, mangowc_command->mangoCommand, command_arguments->commandArguments.
#
# Deviations from the eiros target (intentional itera app adoptions, kept on the eiros
# chords): launch_terminal spawns wezterm (was ghostty) on SUPER+Return; launch_editor
# spawns zeditor/Zed (was code) on SUPER+SHIFT+n. The two terminal-popups
# (keybinds_cheatsheet, vonage_directory) follow the terminal adoption and run under
# wezterm rather than ghostty so their float windowrules match wezterm's app_id.
{ lib, ... }:
let
  # Tag binds: SUPER+1..9 = view tag, SUPER+SHIFT+1..9 = move window to tag.
  # Generated instead of 18 hand-written lines. move_to_tag uses a KEYCODE match
  # (flagModifiers = [ ]), NOT a keysym match, because SHIFT+digit emits a punctuation
  # keysym (e.g. "exclam") on the US layout, so a keysym match on the digit would never
  # fire. This mirrors itera's own moveToTag default design.
  tagBinds = lib.listToAttrs (lib.concatMap (n:
    let s = toString n; in [
      (lib.nameValuePair "view_tag_${s}" {
        modifierKeys = [ "SUPER" ]; flagModifiers = [ "s" ]; keySymbol = s;
        mangoCommand = "view"; commandArguments = s;
      })
      (lib.nameValuePair "move_to_tag_${s}" {
        modifierKeys = [ "SUPER" "SHIFT" ]; flagModifiers = [ ]; keySymbol = s;
        mangoCommand = "tag"; commandArguments = s;
      })
    ]) (lib.range 1 9));
in
{
  itera.users.vwestberg.programs.mango = {
    # Clean slate: drop all itera default keybinds, declare the full set below.
    defaultKeybinds.enable = false;

    layout = "scroller"; # eiros ran scroller on every tag (tagrule id:N,layout_name:scroller)

    keybinds = tagBinds // {
      # --- focus (arrows instead of hjkl) ------------------------------------
      switch_focus_left         = { modifierKeys = [ "SUPER" ];         flagModifiers = [ "s" ]; keySymbol = "Left";  mangoCommand = "focusdir"; commandArguments = "left"; };
      switch_focus_right        = { modifierKeys = [ "SUPER" ];         flagModifiers = [ "s" ]; keySymbol = "Right"; mangoCommand = "focusdir"; commandArguments = "right"; };
      switch_focus_up           = { modifierKeys = [ "SUPER" ];         flagModifiers = [ "s" ]; keySymbol = "Up";    mangoCommand = "focusdir"; commandArguments = "up"; };
      switch_focus_down         = { modifierKeys = [ "SUPER" ];         flagModifiers = [ "s" ]; keySymbol = "Down";  mangoCommand = "focusdir"; commandArguments = "down"; };

      # --- swap window (arrows) ----------------------------------------------
      swap_window_left          = { modifierKeys = [ "SUPER" "SHIFT" ]; flagModifiers = [ "s" ]; keySymbol = "Left";  mangoCommand = "exchange_client"; commandArguments = "left"; };
      swap_window_right         = { modifierKeys = [ "SUPER" "SHIFT" ]; flagModifiers = [ "s" ]; keySymbol = "Right"; mangoCommand = "exchange_client"; commandArguments = "right"; };
      swap_window_up            = { modifierKeys = [ "SUPER" "SHIFT" ]; flagModifiers = [ "s" ]; keySymbol = "Up";    mangoCommand = "exchange_client"; commandArguments = "up"; };
      swap_window_down          = { modifierKeys = [ "SUPER" "SHIFT" ]; flagModifiers = [ "s" ]; keySymbol = "Down";  mangoCommand = "exchange_client"; commandArguments = "down"; };

      # --- move window to monitor (arrows) -----------------------------------
      move_window_monitor_left  = { modifierKeys = [ "CTRL" "SHIFT" ];  flagModifiers = [ "s" ]; keySymbol = "Left";  mangoCommand = "tagmon"; commandArguments = "left,1"; };
      move_window_monitor_right = { modifierKeys = [ "CTRL" "SHIFT" ];  flagModifiers = [ "s" ]; keySymbol = "Right"; mangoCommand = "tagmon"; commandArguments = "right,1"; };
      move_window_monitor_up    = { modifierKeys = [ "CTRL" "SHIFT" ];  flagModifiers = [ "s" ]; keySymbol = "Up";    mangoCommand = "tagmon"; commandArguments = "up,1"; };
      move_window_monitor_down  = { modifierKeys = [ "CTRL" "SHIFT" ];  flagModifiers = [ "s" ]; keySymbol = "Down";  mangoCommand = "tagmon"; commandArguments = "down,1"; };

      # --- focus monitor (arrows) --------------------------------------------
      focus_monitor_left        = { modifierKeys = [ "SUPER" "ALT" ];   flagModifiers = [ "s" ]; keySymbol = "Left";  mangoCommand = "focusmon"; commandArguments = "left"; };
      focus_monitor_right       = { modifierKeys = [ "SUPER" "ALT" ];   flagModifiers = [ "s" ]; keySymbol = "Right"; mangoCommand = "focusmon"; commandArguments = "right"; };
      focus_monitor_up          = { modifierKeys = [ "SUPER" "ALT" ];   flagModifiers = [ "s" ]; keySymbol = "Up";    mangoCommand = "focusmon"; commandArguments = "up"; };
      focus_monitor_down        = { modifierKeys = [ "SUPER" "ALT" ];   flagModifiers = [ "s" ]; keySymbol = "Down";  mangoCommand = "focusmon"; commandArguments = "down"; };

      # --- window / session --------------------------------------------------
      close_window              = { modifierKeys = [ "SUPER" ];         flagModifiers = [ "s" ]; keySymbol = "w";      mangoCommand = "killclient";           commandArguments = null; }; # eiros override q -> w
      quit_mangowc              = { modifierKeys = [ "SUPER" "CTRL" ];  flagModifiers = [ "s" ]; keySymbol = "q";      mangoCommand = "quit";                 commandArguments = null; }; # eiros override SHIFT -> CTRL
      window_toggle_float       = { modifierKeys = [ "SUPER" ];         flagModifiers = [ "s" ]; keySymbol = "g";      mangoCommand = "togglefloating";       commandArguments = null; };
      window_toggle_maximize    = { modifierKeys = [ "SUPER" ];         flagModifiers = [ "s" ]; keySymbol = "m";      mangoCommand = "togglemaximizescreen"; commandArguments = null; };
      window_fullscreen         = { modifierKeys = [ "SUPER" ];         flagModifiers = [ "s" ]; keySymbol = "f";      mangoCommand = "togglemaximizescreen"; commandArguments = null; }; # Omarchy addition (2nd maximize)
      overview_toggle           = { modifierKeys = [ "SUPER" ];         flagModifiers = [ "s" ]; keySymbol = "Tab";    mangoCommand = "toggleoverview";       commandArguments = null; };
      reload_configuration      = { modifierKeys = [ "SUPER" "SHIFT" ]; flagModifiers = [ "s" ]; keySymbol = "r";      mangoCommand = "reload_config";        commandArguments = null; };
      suspend_system            = { modifierKeys = [ "SUPER" "SHIFT" ]; flagModifiers = [ "s" ]; keySymbol = "s";      mangoCommand = "spawn_shell";          commandArguments = "systemctl suspend"; }; # reuses old screenshot chord (screenshot -> Print)

      # --- app launchers -----------------------------------------------------
      launch_terminal           = { modifierKeys = [ "SUPER" ];         flagModifiers = [ "s" ]; keySymbol = "Return"; mangoCommand = "spawn"; commandArguments = "wezterm start"; }; # itera adoption: wezterm (was ghostty)
      launch_browser            = { modifierKeys = [ "SUPER" "SHIFT" ]; flagModifiers = [ "s" ]; keySymbol = "Return"; mangoCommand = "spawn"; commandArguments = "vivaldi"; };
      launch_file_browser       = { modifierKeys = [ "SUPER" "SHIFT" ]; flagModifiers = [ "s" ]; keySymbol = "f";      mangoCommand = "spawn"; commandArguments = "nautilus"; };
      launch_vivaldi            = { modifierKeys = [ "SUPER" "SHIFT" ]; flagModifiers = [ "s" ]; keySymbol = "v";      mangoCommand = "spawn"; commandArguments = "vivaldi"; };
      launch_teams              = { modifierKeys = [ "SUPER" "SHIFT" ]; flagModifiers = [ "s" ]; keySymbol = "t";      mangoCommand = "spawn"; commandArguments = "teams-for-linux"; };
      launch_editor             = { modifierKeys = [ "SUPER" "SHIFT" ]; flagModifiers = [ "s" ]; keySymbol = "n";      mangoCommand = "spawn"; commandArguments = "zeditor"; }; # itera adoption: Zed (was code)
      launch_cider              = { modifierKeys = [ "SUPER" "SHIFT" ]; flagModifiers = [ "s" ]; keySymbol = "m";      mangoCommand = "spawn"; commandArguments = "cider-2"; };

      # --- DMS actions -------------------------------------------------------
      launch_spotlight          = { modifierKeys = [ "SUPER" ];         flagModifiers = [ "s" ]; keySymbol = "d";      mangoCommand = "spawn_shell"; commandArguments = "dms ipc call spotlight toggle"; };
      lock_screen               = { modifierKeys = [ "SUPER" ];         flagModifiers = [ "s" ]; keySymbol = "Escape"; mangoCommand = "spawn_shell"; commandArguments = "dms ipc call lock lock"; };
      notifications             = { modifierKeys = [ "SUPER" ];         flagModifiers = [ "s" ]; keySymbol = "n";      mangoCommand = "spawn_shell"; commandArguments = "dms ipc call notifications toggle"; };
      clipboard_toggle          = { modifierKeys = [ "SUPER" ];         flagModifiers = [ "s" ]; keySymbol = "v";      mangoCommand = "spawn_shell"; commandArguments = "dms ipc call clipboard toggle"; };
      paste_clipboard           = { modifierKeys = [ "CTRL" "SHIFT" ]; flagModifiers = [ "s" ]; keySymbol = "v";      mangoCommand = "spawn_shell"; commandArguments = "dms cl paste | wtype -"; };
      open_settings             = { modifierKeys = [ "SUPER" ];         flagModifiers = [ "s" ]; keySymbol = "comma";  mangoCommand = "spawn_shell"; commandArguments = "dms ipc call settings toggle"; };
      night_mode                = { modifierKeys = [ "SUPER" "CTRL" ];  flagModifiers = [ "s" ]; keySymbol = "n";      mangoCommand = "spawn_shell"; commandArguments = "dms ipc call night toggle"; }; # eiros override SHIFT -> CTRL
      screenshot                = { modifierKeys = [ ];                 flagModifiers = [ "s" ]; keySymbol = "Print";  mangoCommand = "spawn_shell"; commandArguments = "dms screenshot -d ~/Pictures/Screenshots"; }; # eiros override SUPER+SHIFT+s -> Print
      wallpaper_carousel_toggle = { modifierKeys = [ "SUPER" ];         flagModifiers = [ "s" ]; keySymbol = "b";      mangoCommand = "spawn_shell"; commandArguments = "dms ipc wallpaperCarousel toggle"; }; # reclaims SUPER+b (browser now on SUPER+SHIFT+Return)

      # --- laptop monitor reposition (home vs office) ------------------------
      monitor_home              = { modifierKeys = [ "SUPER" ];         flagModifiers = [ "s" ]; keySymbol = "h";      mangoCommand = "spawn_shell"; commandArguments = "wlr-randr --output eDP-1 --pos 2560,220"; };
      monitor_office            = { modifierKeys = [ "SUPER" ];         flagModifiers = [ "s" ]; keySymbol = "o";      mangoCommand = "spawn_shell"; commandArguments = "wlr-randr --output eDP-1 --pos 1920,580"; };

      # --- web apps ----------------------------------------------------------
      webapp_chatgpt            = { modifierKeys = [ "SUPER" "SHIFT" ]; flagModifiers = [ "s" ]; keySymbol = "a";      mangoCommand = "spawn"; commandArguments = "vivaldi --app=https://chatgpt.com"; };
      webapp_email              = { modifierKeys = [ "SUPER" "SHIFT" ]; flagModifiers = [ "s" ]; keySymbol = "e";      mangoCommand = "spawn"; commandArguments = "vivaldi --app=https://outlook.office.com"; };
      webapp_youtube            = { modifierKeys = [ "SUPER" "SHIFT" ]; flagModifiers = [ "s" ]; keySymbol = "y";      mangoCommand = "spawn"; commandArguments = "vivaldi --app=https://youtube.com"; };

      # --- popups (launched in wezterm; matched floating via extraConfig) ----
      keybinds_cheatsheet       = { modifierKeys = [ "SUPER" ];         flagModifiers = [ "s" ]; keySymbol = "F1";     mangoCommand = "spawn"; commandArguments = "wezterm start --class keybinds-popup -- keybinds-popup"; };
      vonage_directory          = { modifierKeys = [ "SUPER" "SHIFT" ]; flagModifiers = [ "s" ]; keySymbol = "p";      mangoCommand = "spawn"; commandArguments = "wezterm start --class vonage-directory -- vonage-directory-popup"; };

      # --- keyboard LED matrix brightness (was dropped in the prior port) ----
      kbd_brightness_down       = { modifierKeys = [ "SUPER" ];         flagModifiers = [ "s" ]; keySymbol = "F7";     mangoCommand = "spawn_shell"; commandArguments = "kbd-brightness-down"; };
      kbd_brightness_up         = { modifierKeys = [ "SUPER" ];         flagModifiers = [ "s" ]; keySymbol = "F8";     mangoCommand = "spawn_shell"; commandArguments = "kbd-brightness-up"; };

      # --- media / brightness hardware keys (XF86) ---------------------------
      volume_up                 = { modifierKeys = [ ]; flagModifiers = [ "s" ]; keySymbol = "XF86AudioRaiseVolume"; mangoCommand = "spawn_shell"; commandArguments = "pactl set-sink-volume @DEFAULT_SINK@ +5%"; };
      volume_down               = { modifierKeys = [ ]; flagModifiers = [ "s" ]; keySymbol = "XF86AudioLowerVolume"; mangoCommand = "spawn_shell"; commandArguments = "pactl set-sink-volume @DEFAULT_SINK@ -5%"; };
      volume_mute               = { modifierKeys = [ ]; flagModifiers = [ "s" ]; keySymbol = "XF86AudioMute";        mangoCommand = "spawn_shell"; commandArguments = "pactl set-sink-mute @DEFAULT_SINK@ toggle"; };
      media_play                = { modifierKeys = [ ]; flagModifiers = [ "s" ]; keySymbol = "XF86AudioPlay";        mangoCommand = "spawn_shell"; commandArguments = "playerctl play-pause"; };
      media_prev                = { modifierKeys = [ ]; flagModifiers = [ "s" ]; keySymbol = "XF86AudioPrev";        mangoCommand = "spawn_shell"; commandArguments = "playerctl previous"; };
      brightness_up             = { modifierKeys = [ ]; flagModifiers = [ "s" ]; keySymbol = "XF86MonBrightnessUp";  mangoCommand = "spawn_shell"; commandArguments = "brightnessctl set +10%"; };
      brightness_down           = { modifierKeys = [ ]; flagModifiers = [ "s" ]; keySymbol = "XF86MonBrightnessDown";mangoCommand = "spawn_shell"; commandArguments = "brightnessctl set 10%-"; };

      # --- media cluster (Insert/Home/PageUp/Delete/End/PageDown) ------------
      # media_next is the eiros override of XF86AudioNext -> Prior (PageUp).
      media_next                = { modifierKeys = [ ]; flagModifiers = [ "s" ]; keySymbol = "Prior";  mangoCommand = "spawn_shell"; commandArguments = "playerctl next"; };
      media_previous            = { modifierKeys = [ ]; flagModifiers = [ "s" ]; keySymbol = "Insert"; mangoCommand = "spawn_shell"; commandArguments = "playerctl previous"; };
      media_play_pause          = { modifierKeys = [ ]; flagModifiers = [ "s" ]; keySymbol = "Home";   mangoCommand = "spawn_shell"; commandArguments = "playerctl play-pause"; };
      media_vol_down            = { modifierKeys = [ ]; flagModifiers = [ "s" ]; keySymbol = "Delete"; mangoCommand = "spawn_shell"; commandArguments = "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"; };
      media_mute                = { modifierKeys = [ ]; flagModifiers = [ "s" ]; keySymbol = "End";    mangoCommand = "spawn_shell"; commandArguments = "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"; };
      media_vol_up              = { modifierKeys = [ ]; flagModifiers = [ "s" ]; keySymbol = "Next";   mangoCommand = "spawn_shell"; commandArguments = "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+"; };
    };

    # Free-form mango settings appended verbatim to config.conf. Reproduces the eiros
    # `settings` block (minus tagrule, handled by `layout = "scroller"`, and xkb, driven
    # by itera.keyboard). Float the two popup terminals: mango matches wezterm's app_id
    # to --class; VERIFY the match key after first boot (may be `title:` not `appid:`).
    extraConfig = ''
      # eiros misc mango settings
      enable_hotarea=0
      ov_tab_mode=1
      idleinhibit_ignore_visible=1
      edge_scroller_pointer_focus=0
      numlockon=1

      # popup float rules
      windowrule=isfloating:1,width:960,height:720,appid:keybinds-popup
      windowrule=isfloating:1,width:1100,height:800,appid:vonage-directory

      # environment
      env=GTK_THEME,Adwaita:dark

      # home monitor auto-reset (eiros exec-once): power-cycle the 4K, then reposition laptop
      exec-once=sh -c 'sleep 15 && output=$(wlr-randr | grep VX3211-4K | awk "{print \$1}") && [ -n "$output" ] && wlr-randr --output "$output" --off && sleep 2 && wlr-randr --output "$output" --on && sleep 1 && wlr-randr --output eDP-1 --pos 2560,220'

      # NOTE: xkb (us / pc104) is driven by itera.keyboard, not set here -- itera renders
      # xkb before extraConfig, so a duplicate line here would risk a conflicting override.
      # NOTE: tagrule scroller-on-every-tag is reproduced by `layout = "scroller"` above.
    '';
  };
}
