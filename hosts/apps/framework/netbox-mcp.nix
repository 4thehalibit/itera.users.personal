# NetBox MCP server — github:lcleveland/netbox-mcp. Framework-only for the
# same reason as falcon-sensor.nix / freshservice-mcp.nix: the tenant is work
# infrastructure.
#
# CLI-only, no systemd service: this is a single-user workstation tool used by
# Claude Code over stdio, not a shared HTTP endpoint, so `enable` (the
# systemd service) stays off and only the binary goes on PATH.
#
# NetBox: http://netbox.lselectric.local
#
# API TOKEN SETUP (manual, one-time):
#   1. In NetBox admin, create a dedicated user with object permissions scoped
#      to read-only, rather than using a personal token.
#   2. Generate a v2 token (nbt_<key>.<token>) for that user.
#   3. install -Dm400 /dev/stdin ~/.config/netbox-mcp/token   (paste the
#      token, Ctrl-D). ~/.config is persisted by itera's impermanence list, so
#      this survives reboots without a /persist/secrets entry.
#   4. Register it with Claude Code:
#        claude mcp add netbox \
#          -e NETBOX_URL=http://netbox.lselectric.local \
#          -e NETBOX_API_TOKEN_FILE=$HOME/.config/netbox-mcp/token \
#          -- netbox-mcp
#
# Read-only by default (no --allow-* flags passed): the server refuses every
# write until a capability is turned on. Add `extraArgs` here (or pass them in
# the `claude mcp add` command above) to unlock one, e.g.
# services.netbox-mcp.extraArgs = [ "--allow-create" "--allow-update" ];
{ netbox-mcp, ... }:
{
  imports = [ netbox-mcp.nixosModules.default ];

  services.netbox-mcp.installCli = true;
}
