{
  description = "vwestberg's NixOS configuration (itera + hjem)";

  inputs = {
    # itera tracks unstable; follow it (decision: stay on itera's channel).
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # hjem manages $HOME. itera's home modules are class-`hjem` submodules, so
    # itera MUST share this exact hjem (see `follows` below) or evaluation breaks.
    hjem = {
      url = "github:feel-co/hjem";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    itera = {
      url = "github:lcleveland/itera";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.hjem.follows = "hjem"; # CRITICAL: share one hjem
    };

    # NinjaOne remote session player (ncplayer) + the ninjarmm:// URL handler.
    # Replaces the old impure ~/private/*.deb approach from eiros. Enabled in
    # hosts/common.nix. Share our nixpkgs.
    ninjarmm-ncplayer = {
      url = "github:lcleveland/ninjarmm-ncplayer";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Netskope Client for Linux — the corporate SASE agent. Exposes
    # nixosModules.default (options: services.netskope.*) plus the packaging.
    # Work infrastructure, so it is host-scoped: it rides in through specialArgs
    # and is imported by hosts/apps/framework/netskope.nix, not by the every-host
    # `modules` list below. Share our nixpkgs.
    netskope = {
      url = "github:lcleveland/netskope-client";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      nixpkgs,
      itera,
      ninjarmm-ncplayer,
      netskope,
      ...
    }:
    let
      # A single import (itera.nixosModules.default) pulls in hjem and wires
      # itera's whole opinionated layer: disko + tmpfs-root impermanence, agenix,
      # the mango/DMS desktop, hardening, etc. Every default is a mkDefault.
      mkHost =
        hostModule:
        nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          # Expose the itera flake to host modules so they can select a
          # nixos-hardware board via `itera.hardwareModules.<board>`. `netskope`
          # rides along the same way: importing a flake's module is an
          # import-time choice, not a `config.*` option, and this one is
          # framework-only so it must not land in the `modules` list.
          specialArgs = { inherit itera netskope; };
          modules = [
            itera.nixosModules.default
            ninjarmm-ncplayer.nixosModules.default
            { nixpkgs.overlays = [ itera.overlays.default ]; }
            ./hosts/common.nix
            hostModule
          ];
        };
    in
    {
      nixosConfigurations = {
        # Framework 16 (AMD 7040), hostname LS-04391.
        framework = mkHost ./hosts/framework.nix;
      };
    };
}
