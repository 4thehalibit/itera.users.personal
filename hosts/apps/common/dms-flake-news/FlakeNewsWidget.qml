// Dank bar pill for the weekly flake-update-check report (apps/common/flake-update-check.nix).
//
// The report file is the single source of truth — no state of its own, no
// process polling. FileView watches it, so the pill flips the moment the
// timer rewrites it. Report shapes the parser keys off (see the check script):
//   "Up to date: no inputs moved …"   nothing to do
//   "nix flake update FAILED:"        the check itself broke
//   "Config eval: FAILED"             inputs moved but the config does not eval
//   otherwise                         inputs moved, eval OK
//
// Two header actions in the popout: refresh re-runs the check, and (only in the
// "updates" state) rocket_launch spawns `flake-update-apply` in a wezterm popup
// to actually apply it.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    readonly property string reportPath: (Quickshell.env("HOME") || "") + "/.local/state/flake-update-check/latest.txt"
    property string report: ""

    // "none" until the first check has ever run — the timer is weekly, so a
    // freshly installed machine sits here for days and that is not a fault.
    readonly property string state: {
        if (!report)
            return "none";
        if (report.indexOf("Up to date:") !== -1)
            return "ok";
        if (report.indexOf("nix flake update FAILED") !== -1)
            return "error";
        if (report.indexOf("Config eval: FAILED") !== -1)
            return "broken";
        return "updates";
    }

    // "3 of 47 inputs moved." — the differ's summary line.
    readonly property int movedCount: {
        const m = /(\d+) of \d+ inputs moved\./.exec(report);
        return m ? parseInt(m[1]) : 0;
    }

    readonly property string iconName: ({
            none: "help",
            ok: "check_circle",
            updates: "system_update",
            broken: "error",
            error: "cloud_off"
        })[state]

    readonly property color iconColor: ({
            none: Theme.surfaceVariantText,
            ok: Theme.surfaceVariantText,
            updates: Theme.primary,
            broken: Theme.error,
            error: Theme.error
        })[state]

    // "itera flake update check — 2026-09-08 12:20 CDT" — the report's header.
    readonly property string checkedAt: {
        const m = /— (.+)$/m.exec(report.split("\n")[0] || "");
        return m ? m[1] : "";
    }

    readonly property string tooltip: ({
            none: "No flake check has run yet",
            ok: "Flake inputs up to date",
            updates: movedCount + " flake inputs moved, eval OK",
            broken: "Flake inputs moved but the config does not evaluate",
            error: "The flake check itself failed"
        })[state]

    FileView {
        id: reportFile
        path: root.reportPath
        watchChanges: true
        printErrors: false
        onLoaded: root.report = text()
        onLoadFailed: root.report = ""
        // watchChanges only reports that the file moved; the re-read is ours to
        // ask for. Without this the pill keeps its first read forever and a
        // manual check looks like it did nothing.
        onFileChanged: reload()
    }

    // A clean check rewrites the report with identical text apart from its
    // timestamp, so without a toast a manual run looks like a dead button.
    // The unit is a oneshot; a second trigger while it runs is a no-op.
    function runCheck() {
        Quickshell.execDetached(["systemctl", "--user", "start", "flake-update-check"]);
        ToastService.showInfo("Checking flake inputs…", "Takes a few seconds. The pill updates itself.");
    }

    // Apply what the report found. Spawns a wezterm popup rather than running
    // headless because `itera update` needs a tty: itera_facter_refresh fires
    // three interactive sudo calls before nh even starts (mkdir,
    // nixos-facter -o, chmod) and nixos-facter is in no NOPASSWD rule, then nh
    // needs sudo of its own. The confirmation prompt and every safety check
    // live in flake-update-apply, not here — see apps/common/flake-update-check.nix.
    // No toast: a terminal window appearing is its own feedback.
    function runUpdate() {
        Quickshell.execDetached(["wezterm", "start", "--class", "flake-update", "--", "flake-update-apply"]);
    }

    pillRightClickAction: () => root.runCheck()

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS

            DankIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: root.iconName
                size: Theme.barIconSize(root.barThickness, -4, root.barConfig?.maximizeWidgetIcons, root.barConfig?.iconScale)
                color: root.iconColor
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.movedCount > 0
                text: root.movedCount
                color: root.iconColor
                font.pixelSize: Theme.fontSizeSmall
            }
        }
    }

    verticalBarPill: Component {
        DankIcon {
            name: root.iconName
            size: Theme.barIconSize(root.barThickness, -4, root.barConfig?.maximizeWidgetIcons, root.barConfig?.iconScale)
            color: root.iconColor
        }
    }

    popoutContent: Component {
        PopoutComponent {
            id: popout

            headerText: "Flake News"
            detailsText: root.checkedAt ? root.tooltip + " · checked " + root.checkedAt : root.tooltip
            showCloseButton: true

            // headerActions feeds a single Loader (PopoutComponent.qml:41-44),
            // so two buttons need a Row wrapper.
            headerActions: Component {
                Row {
                    spacing: Theme.spacingXS

                    // Only offered when there is something to apply. Hidden
                    // rather than disabled: "broken" and "error" states must
                    // not look like a button you could press anyway, and
                    // flake-update-apply refuses those reports regardless.
                    DankActionButton {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: root.state === "updates"
                        iconName: "rocket_launch"
                        iconColor: Theme.primary
                        tooltipText: "Update inputs and deploy"
                        // Dismiss the popout on the way out, or it sits over the
                        // terminal that just opened and steals the keyboard, so
                        // the confirm prompt cannot be answered until it is
                        // closed by hand. `closePopout` is a property the host
                        // assigns, so it is guarded the same way
                        // PopoutComponent's own close button guards it.
                        // NOTE the refresh button below deliberately does NOT
                        // close: a check rewrites the report in place and the
                        // point is to read the new one.
                        onClicked: {
                            root.runUpdate();
                            if (popout.closePopout)
                                popout.closePopout();
                        }
                    }

                    // Re-run the check without waiting for Monday, same as a
                    // right click on the pill. The unit is a oneshot, so a
                    // second press while it runs is a no-op.
                    DankActionButton {
                        anchors.verticalCenter: parent.verticalCenter
                        iconName: "refresh"
                        iconColor: Theme.surfaceVariantText
                        tooltipText: "Check now"
                        onClicked: root.runCheck()
                    }
                }
            }

            DankFlickable {
                width: parent.width
                height: root.popoutHeight - popout.headerHeight - popout.detailsHeight - Theme.spacingL
                contentHeight: reportText.implicitHeight
                clip: true

                StyledText {
                    id: reportText
                    width: parent.width
                    text: root.report || "No report yet. Press refresh to run the check now."
                    color: Theme.surfaceText
                    font.family: Theme.monoFontFamily
                    font.pixelSize: Theme.fontSizeSmall
                    wrapMode: Text.Wrap
                }
            }
        }
    }

    popoutWidth: 560
    popoutHeight: 460
}
