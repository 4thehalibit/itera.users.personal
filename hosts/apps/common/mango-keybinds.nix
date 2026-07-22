# Personal mango keybinds, ported from eiros mangowc.nix (Hyprland/Omarchy muscle
# memory: arrow-key focus/swap, Super+Shift app launchers, media cluster, web
# apps). Set per-user so they merge over itera's default keybinds: a bind whose
# NAME matches an itera default REPLACES it; a new name is ADDED alongside.
#
# itera defaults kept as-is: tag view Super+1..9, tag move Super+Shift+1..9,
# close Super+q, overview Super+Tab, terminal Super+t (wezterm), etc.
#
# Field renames vs eiros: modifier_keys→modifierKeys, flag_modifiers→flagModifiers,
# key_symbol→keySymbol, mangowc_command→mangoCommand, command_arguments→commandArguments.
{ ... }:
{
  itera.users.vwestberg.programs.mango = {
    layout = "scroller"; # eiros ran the scroller layout on every tag

    keybinds = {
      # --- window / session ---------------------------------------------------
      close_window = { modifierKeys = [ "SUPER" ]; flagModifiers = [ "s" ]; keySymbol = "w"; mangoCommand = "killclient"; commandArguments = null; };
      launch_terminal = { modifierKeys = [ "SUPER" ]; flagModifiers = [ "s" ]; keySymbol = "Return"; mangoCommand = "spawn"; commandArguments = "wezterm start"; };
      launch_file_browser = { modifierKeys = [ "SUPER" "SHIFT" ]; flagModifiers = [ "s" ]; keySymbol = "f"; mangoCommand = "spawn"; commandArguments = "nautilus"; };
      launch_browser = { modifierKeys = [ "SUPER" "SHIFT" ]; flagModifiers = [ "s" ]; keySymbol = "Return"; mangoCommand = "spawn"; commandArguments = "vivaldi"; };
      quit_mangowc = { modifierKeys = [ "SUPER" "CTRL" ]; flagModifiers = [ "s" ]; keySymbol = "q"; mangoCommand = "quit"; commandArguments = null; };
      window_fullscreen = { modifierKeys = [ "SUPER" ]; flagModifiers = [ "s" ]; keySymbol = "f"; mangoCommand = "togglemaximizescreen"; commandArguments = null; };
      suspend_system = { modifierKeys = [ "SUPER" "SHIFT" ]; flagModifiers = [ "s" ]; keySymbol = "s"; mangoCommand = "spawn_shell"; commandArguments = "systemctl suspend"; };

      # --- DMS actions --------------------------------------------------------
      screenshot = { modifierKeys = [ ]; flagModifiers = [ "s" ]; keySymbol = "Print"; mangoCommand = "spawn_shell"; commandArguments = "dms screenshot -d ~/Pictures/Screenshots"; };
      night_mode = { modifierKeys = [ "SUPER" "CTRL" ]; flagModifiers = [ "s" ]; keySymbol = "n"; mangoCommand = "spawn_shell"; commandArguments = "dms ipc call night toggle"; };
      # `browser` REPLACES itera's default Super+b=vivaldi bind, reclaiming Super+b
      # for the wallpaper carousel (browser is launched via Super+Shift+Return / Super+Shift+v).
      browser = { modifierKeys = [ "SUPER" ]; flagModifiers = [ "s" ]; keySymbol = "b"; mangoCommand = "spawn_shell"; commandArguments = "dms ipc wallpaperCarousel toggle"; };

      # --- focus (arrows instead of hjkl) ------------------------------------
      switch_focus_left = { modifierKeys = [ "SUPER" ]; flagModifiers = [ "s" ]; keySymbol = "Left"; mangoCommand = "focusdir"; commandArguments = "left"; };
      switch_focus_right = { modifierKeys = [ "SUPER" ]; flagModifiers = [ "s" ]; keySymbol = "Right"; mangoCommand = "focusdir"; commandArguments = "right"; };
      switch_focus_up = { modifierKeys = [ "SUPER" ]; flagModifiers = [ "s" ]; keySymbol = "Up"; mangoCommand = "focusdir"; commandArguments = "up"; };
      switch_focus_down = { modifierKeys = [ "SUPER" ]; flagModifiers = [ "s" ]; keySymbol = "Down"; mangoCommand = "focusdir"; commandArguments = "down"; };

      # --- swap window --------------------------------------------------------
      swap_window_left = { modifierKeys = [ "SUPER" "SHIFT" ]; flagModifiers = [ "s" ]; keySymbol = "Left"; mangoCommand = "exchange_client"; commandArguments = "left"; };
      swap_window_right = { modifierKeys = [ "SUPER" "SHIFT" ]; flagModifiers = [ "s" ]; keySymbol = "Right"; mangoCommand = "exchange_client"; commandArguments = "right"; };
      swap_window_up = { modifierKeys = [ "SUPER" "SHIFT" ]; flagModifiers = [ "s" ]; keySymbol = "Up"; mangoCommand = "exchange_client"; commandArguments = "up"; };
      swap_window_down = { modifierKeys = [ "SUPER" "SHIFT" ]; flagModifiers = [ "s" ]; keySymbol = "Down"; mangoCommand = "exchange_client"; commandArguments = "down"; };

      # --- move window to monitor --------------------------------------------
      move_window_monitor_left = { modifierKeys = [ "CTRL" "SHIFT" ]; flagModifiers = [ "s" ]; keySymbol = "Left"; mangoCommand = "tagmon"; commandArguments = "left,1"; };
      move_window_monitor_right = { modifierKeys = [ "CTRL" "SHIFT" ]; flagModifiers = [ "s" ]; keySymbol = "Right"; mangoCommand = "tagmon"; commandArguments = "right,1"; };
      move_window_monitor_up = { modifierKeys = [ "CTRL" "SHIFT" ]; flagModifiers = [ "s" ]; keySymbol = "Up"; mangoCommand = "tagmon"; commandArguments = "up,1"; };
      move_window_monitor_down = { modifierKeys = [ "CTRL" "SHIFT" ]; flagModifiers = [ "s" ]; keySymbol = "Down"; mangoCommand = "tagmon"; commandArguments = "down,1"; };

      # --- focus monitor ------------------------------------------------------
      focus_monitor_left = { modifierKeys = [ "SUPER" "ALT" ]; flagModifiers = [ "s" ]; keySymbol = "Left"; mangoCommand = "focusmon"; commandArguments = "left"; };
      focus_monitor_right = { modifierKeys = [ "SUPER" "ALT" ]; flagModifiers = [ "s" ]; keySymbol = "Right"; mangoCommand = "focusmon"; commandArguments = "right"; };
      focus_monitor_up = { modifierKeys = [ "SUPER" "ALT" ]; flagModifiers = [ "s" ]; keySymbol = "Up"; mangoCommand = "focusmon"; commandArguments = "up"; };
      focus_monitor_down = { modifierKeys = [ "SUPER" "ALT" ]; flagModifiers = [ "s" ]; keySymbol = "Down"; mangoCommand = "focusmon"; commandArguments = "down"; };

      # --- app launchers (Omarchy shortcuts) ----------------------------------
      launch_vivaldi = { modifierKeys = [ "SUPER" "SHIFT" ]; flagModifiers = [ "s" ]; keySymbol = "v"; mangoCommand = "spawn"; commandArguments = "vivaldi"; };
      launch_teams = { modifierKeys = [ "SUPER" "SHIFT" ]; flagModifiers = [ "s" ]; keySymbol = "t"; mangoCommand = "spawn"; commandArguments = "teams-for-linux"; };
      launch_editor = { modifierKeys = [ "SUPER" "SHIFT" ]; flagModifiers = [ "s" ]; keySymbol = "n"; mangoCommand = "spawn"; commandArguments = "zeditor"; }; # itera default editor (Zed); was VS Code
      launch_cider = { modifierKeys = [ "SUPER" "SHIFT" ]; flagModifiers = [ "s" ]; keySymbol = "m"; mangoCommand = "spawn"; commandArguments = "cider-2"; };

      # --- laptop monitor reposition (home vs office) -------------------------
      monitor_home = { modifierKeys = [ "SUPER" ]; flagModifiers = [ "s" ]; keySymbol = "h"; mangoCommand = "spawn_shell"; commandArguments = "wlr-randr --output eDP-1 --pos 2560,220"; };
      monitor_office = { modifierKeys = [ "SUPER" ]; flagModifiers = [ "s" ]; keySymbol = "o"; mangoCommand = "spawn_shell"; commandArguments = "wlr-randr --output eDP-1 --pos 1920,580"; };

      # --- web apps -----------------------------------------------------------
      webapp_chatgpt = { modifierKeys = [ "SUPER" "SHIFT" ]; flagModifiers = [ "s" ]; keySymbol = "a"; mangoCommand = "spawn"; commandArguments = "vivaldi --app=https://chatgpt.com"; };
      webapp_email = { modifierKeys = [ "SUPER" "SHIFT" ]; flagModifiers = [ "s" ]; keySymbol = "e"; mangoCommand = "spawn"; commandArguments = "vivaldi --app=https://outlook.office.com"; };
      webapp_youtube = { modifierKeys = [ "SUPER" "SHIFT" ]; flagModifiers = [ "s" ]; keySymbol = "y"; mangoCommand = "spawn"; commandArguments = "vivaldi --app=https://youtube.com"; };

      # --- popups (launched in wezterm; matched floating via extraConfig) ------
      keybinds_cheatsheet = { modifierKeys = [ "SUPER" ]; flagModifiers = [ "s" ]; keySymbol = "F1"; mangoCommand = "spawn"; commandArguments = "wezterm start --class keybinds-popup -- keybinds-popup"; };
      vonage_directory = { modifierKeys = [ "SUPER" "SHIFT" ]; flagModifiers = [ "s" ]; keySymbol = "p"; mangoCommand = "spawn"; commandArguments = "wezterm start --class vonage-directory -- vonage-directory-popup"; };

      # --- media cluster (Insert/Home/PageUp/Delete/End/PageDown) -------------
      media_previous = { modifierKeys = [ ]; flagModifiers = [ "s" ]; keySymbol = "Insert"; mangoCommand = "spawn_shell"; commandArguments = "playerctl previous"; };
      media_play_pause = { modifierKeys = [ ]; flagModifiers = [ "s" ]; keySymbol = "Home"; mangoCommand = "spawn_shell"; commandArguments = "playerctl play-pause"; };
      media_next = { modifierKeys = [ ]; flagModifiers = [ "s" ]; keySymbol = "Prior"; mangoCommand = "spawn_shell"; commandArguments = "playerctl next"; };
      media_vol_down = { modifierKeys = [ ]; flagModifiers = [ "s" ]; keySymbol = "Delete"; mangoCommand = "spawn_shell"; commandArguments = "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"; };
      media_mute = { modifierKeys = [ ]; flagModifiers = [ "s" ]; keySymbol = "End"; mangoCommand = "spawn_shell"; commandArguments = "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"; };
      media_vol_up = { modifierKeys = [ ]; flagModifiers = [ "s" ]; keySymbol = "Next"; mangoCommand = "spawn_shell"; commandArguments = "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+"; };
    };

    # Float the two popup terminals. mango matches wezterm's app_id to --class;
    # VERIFY the match key after first boot (may be `title:` instead of `appid:`).
    extraConfig = ''
      windowrule=isfloating:1,width:960,height:720,appid:keybinds-popup
      windowrule=isfloating:1,width:1100,height:800,appid:vonage-directory
      env=GTK_THEME,Adwaita:dark
    '';
  };
}
