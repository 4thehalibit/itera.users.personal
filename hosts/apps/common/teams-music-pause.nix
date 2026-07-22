# Pause the active media player while Teams is using the microphone, resume when
# it releases it. Ported verbatim from eiros applications/teams_music_pause.nix.
{ pkgs, ... }:
let
  script = pkgs.writeShellScript "teams-music-pause" ''
    paused_by_us=false

    while true; do
      if ${pkgs.pulseaudio}/bin/pactl list source-outputs 2>/dev/null | grep -qi "teams"; then
        if [ "$paused_by_us" = "false" ]; then
          if ${pkgs.playerctl}/bin/playerctl status 2>/dev/null | grep -q "Playing"; then
            ${pkgs.playerctl}/bin/playerctl pause
            paused_by_us=true
          fi
        fi
      else
        if [ "$paused_by_us" = "true" ]; then
          ${pkgs.playerctl}/bin/playerctl play 2>/dev/null || true
          paused_by_us=false
        fi
      fi
      sleep 2
    done
  '';
in
{
  systemd.user.services.teams-music-pause = {
    description = "Pause music when Teams activates microphone";
    wantedBy = [ "default.target" ];
    after = [
      "pipewire.service"
      "pipewire-pulse.service"
    ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${script}";
      Restart = "on-failure";
      RestartSec = "5s";
    };
  };
}
