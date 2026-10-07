# Freshservice MCP server — github:lcleveland/freshservice-mcp. Framework-only
# for the same reason as falcon-sensor.nix: the tenant is work infrastructure.
#
# CLI-only, no systemd service: this is a single-user workstation tool used by
# Claude Code over stdio, not a shared HTTP endpoint, so `enable` (the
# systemd service) stays off and only the binary goes on PATH.
#
# API KEY SETUP (manual, one-time):
#   1. In Freshservice admin, create a dedicated agent (e.g.
#      mcp@lselectric.com) with a role scoped to read-only, rather than using
#      a personal key.
#   2. Signed in as that agent: Profile settings -> copy the API key.
#   3. install -Dm400 /dev/stdin ~/.config/freshservice-mcp/api-key   (paste
#      the key, Ctrl-D). ~/.config is persisted by itera's impermanence list,
#      so this survives reboots without a /persist/secrets entry.
#   4. Register it with Claude Code:
#        claude mcp add freshservice \
#          -e FRESHSERVICE_DOMAIN=lselectric.freshservice.com \
#          -e FRESHSERVICE_API_KEY_FILE=$HOME/.config/freshservice-mcp/api-key \
#          -- freshservice-mcp
#
# Read-only by default (no --allow-* flags passed): the server refuses every
# write until a capability is turned on. Add `extraArgs` here (or pass them in
# the `claude mcp add` command above) to unlock one, e.g.
# services.freshservice-mcp.extraArgs = [ "--allow-tickets" ];
{ freshservice-mcp, ... }:
{
  imports = [ freshservice-mcp.nixosModules.default ];

  services.freshservice-mcp.installCli = true;
}
