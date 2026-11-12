// Click-to-toggle Tailscale pill.
//
// Connected = `tailscale status --json` reports BackendState "Running". Click
// runs `tailscale down`, or `tailscale up` when it is off. One glyph for both
// states, as with the caffeine pill: filled + accent when connected, hollow +
// muted when off.
//
// Why `up` carries every flag it does: after `tailscale set --accept-routes`
// (what the homelab subnet route needs) plain `tailscale up` refuses with
// "changing settings via 'tailscale up' requires mentioning all non-default
// flags". `--reset` turns every flag not named back to its default, so the
// three non-default ones are named here: accept-routes (the LAN route), no
// accept-dns (unbound owns resolution, see apps/framework/unbound.nix), and the
// operator, which must match hosts/apps/common/tailscale.nix or the next
// `tailscale` call needs sudo again. --timeout stops a needs-login node from
// hanging the process waiting for a browser.
//
// Own Process per instance, not `Proc.runCommand`: DankBar creates one copy of
// this component per bar and Proc collapses callers that share an id, leaving
// all but one pill frozen. Same reasoning as dms-itera-update.
import QtQuick
import Quickshell.Io
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    property bool connected: false
    property bool busy: false

    function refresh() {
        if (!statusProcess.running)
            statusProcess.running = true;
    }

    function toggle() {
        if (busy)
            return;
        busy = true;
        toggleProcess.command = connected
            ? ["tailscale", "down"]
            : ["tailscale", "up", "--reset", "--accept-routes", "--accept-dns=false", "--operator=vwestberg", "--timeout=20s"];
        toggleProcess.running = true;
    }

    pillClickAction: () => root.toggle()

    Process {
        id: statusProcess
        command: ["tailscale", "status", "--json"]
        running: false
        stdout: StdioCollector {
            id: statusOutput
        }
        onExited: exitCode => {
            let state = "";
            try {
                state = JSON.parse(statusOutput.text).BackendState ?? "";
            } catch (e) {
                // no daemon, or no tailscale binary: show as off
            }
            root.connected = state === "Running";
        }
    }

    Process {
        id: toggleProcess
        running: false
        onExited: exitCode => {
            root.busy = false;
            root.refresh();
        }
    }

    Timer {
        interval: 5000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    horizontalBarPill: Component {
        DankIcon {
            name: "vpn_lock"
            filled: root.connected
            opacity: root.busy ? 0.5 : 1
            size: Theme.barIconSize(root.barThickness, -4, root.barConfig?.maximizeWidgetIcons, root.barConfig?.iconScale)
            color: root.connected ? Theme.primary : Theme.widgetTextColor
        }
    }

    verticalBarPill: Component {
        DankIcon {
            name: "vpn_lock"
            filled: root.connected
            opacity: root.busy ? 0.5 : 1
            size: Theme.barIconSize(root.barThickness, -4, root.barConfig?.maximizeWidgetIcons, root.barConfig?.iconScale)
            color: root.connected ? Theme.primary : Theme.widgetTextColor
        }
    }
}
