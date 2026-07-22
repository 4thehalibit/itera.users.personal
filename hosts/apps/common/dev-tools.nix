# Developer toolset carried over from eiros (gh, python, PlatformIO, make, etc.).
# PlatformIO needs nix-ld so its downloaded prebuilt toolchains can run.
{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    gh
    python3
    platformio-core
    gnumake
    nixfmt
    fastfetch
  ];

  programs.nix-ld = {
    enable = true;
    libraries = with pkgs; [
      stdenv.cc.cc.lib
      zlib
      libgcc
    ];
  };
}
