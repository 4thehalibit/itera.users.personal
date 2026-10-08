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

    # CrowdStrike Falcon sensor — the corporate EDR agent. Exposes
    # nixosModules.default (options: services.falcon-sensor.*), an overlay for
    # the three helper packages, and a #find-sensor app that lists the sensors
    # the tenant can install. Work infrastructure, so host-scoped exactly like
    # netskope above: it rides in through specialArgs and is imported by
    # hosts/apps/framework/falcon-sensor.nix. Share our nixpkgs.
    falcon-sensor = {
      url = "github:lcleveland/falcon-sensor";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Freshservice MCP server (Go), stdio/HTTP. Exposes nixosModules.default
    # (options: services.freshservice-mcp.*). Work infrastructure (the L&S
    # Electric helpdesk tenant), so host-scoped exactly like netskope and
    # falcon-sensor above: it rides in through specialArgs and is imported by
    # hosts/apps/framework/freshservice-mcp.nix. Share our nixpkgs.
    freshservice-mcp = {
      url = "github:lcleveland/freshservice-mcp";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # NetBox MCP server (Go), stdio/HTTP. Exposes nixosModules.default
    # (options: services.netbox-mcp.*). Work infrastructure (L&S Electric's
    # NetBox instance), so host-scoped exactly like freshservice-mcp above: it
    # rides in through specialArgs and is imported by
    # hosts/apps/framework/netbox-mcp.nix. Share our nixpkgs.
    netbox-mcp = {
      url = "github:lcleveland/netbox-mcp";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Claude desktop app (Chat/Cowork/Claude Code GUI), official Linux .deb
    # repackaged for NixOS. Personal tool, not corp infra, so it rides in the
    # every-host `modules` list below like ninjarmm-ncplayer rather than being
    # host-scoped through specialArgs. Enabled in hosts/common.nix.
    claude-desktop = {
      url = "github:nmcbride/claude-desktop-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      nixpkgs,
      itera,
      ninjarmm-ncplayer,
      netskope,
      falcon-sensor,
      freshservice-mcp,
      netbox-mcp,
      claude-desktop,
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
          specialArgs = { inherit itera netskope falcon-sensor freshservice-mcp netbox-mcp; };
          modules = [
            itera.nixosModules.default
            ninjarmm-ncplayer.nixosModules.default
            claude-desktop.nixosModules.default
            # falcon-sensor's overlay makes pkgs.falcon-sensor-{fetch,status,tray}
            # resolve. The module falls back to callPackage without it, but the
            # tray icon override in hosts/apps/framework/falcon-sensor.nix needs
            # a pkgs handle to overrideAttrs.
            {
              nixpkgs.overlays = [
                itera.overlays.default
                falcon-sensor.overlays.default
              ];
            }
            ./hosts/common.nix
            hostModule
          ];
        };
    in
    {
      nixosConfigurations = {
        # Framework 16 (AMD 7040), hostname LS-04391.
        framework = mkHost ./hosts/framework.nix;
        # Emergency spare-hardware host, no board-specific quirks. See hosts/generic.nix.
        generic = mkHost ./hosts/generic.nix;
        # No corp modules (netskope/falcon-sensor/ninjarmm). See hosts/personal.nix.
        personal = mkHost ./hosts/personal.nix;
      };
    };
}
