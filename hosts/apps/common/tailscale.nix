# Tailscale: reach the homelab (and let Claude reach it) from anywhere.
#
# Client only. Subnet routing for 192.168.4.0/22 is done by a node on the lab
# side, not by this laptop.
#
# DNS is deliberately left alone. unbound.nix owns resolution here and
# `Domains=~.` on resolved is load-bearing, so MagicDNS must not push its own
# resolver in. Reach nodes by tailnet IP or by the names in the admin console.
#
# The node key lives in /var/lib/tailscale. itera does not persist that by
# default, so without the entry below the laptop re-registers as a new device
# on every boot.
#
# First login is interactive: run `sudo tailscale up` and open the printed URL.
{ ... }:
{
  services.tailscale = {
    enable = true;
    useRoutingFeatures = "client";
    # --operator lets the bar toggle (apps/common/dms-tailscale) run `tailscale
    # up/down` without sudo. Keep it in step with the `up` command in that
    # widget: `up --reset` clears the operator unless it is named again.
    extraSetFlags = [ "--accept-dns=false" "--operator=vwestberg" ];
  };

  itera.impermanence.directories = [ "/var/lib/tailscale" ];
}
