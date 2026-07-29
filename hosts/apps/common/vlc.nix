# VLC media player, installed per-user. Used to play voicemail audio
# (mp3 and any other format voicemails arrive as: wav, m4a, amr).
{ pkgs, ... }:
{
  itera.users.vwestberg.packages = [ pkgs.vlc ];
}
