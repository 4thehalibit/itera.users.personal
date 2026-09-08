// Dank bar pill for the weekly flake-update-check report (apps/common/flake-update-check.nix).
//
// The report file is the single source of truth — no state of its own, no
// process polling. FileView watches it, so the pill flips the moment the
// timer rewrites it. Report shapes the parser keys off (see the check script):
//   "Up to date: no inputs moved …"   nothing to do
//   "nix flake update FAILED:"        the check itself broke
//   "Config eval: FAILED"             inputs moved but the config does not eval
//   otherwise                         inputs moved, eval OK
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
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

    readonly property string tooltip: ({
            none: "No flake check has run yet",
            ok: "Flake inputs up to date",
            updates: movedCount + " flake inputs moved, eval OK",
            broken: "Flake inputs moved but the config does not evaluate",
            error: "The flake check itself failed"
        })[state]

    FileView {
        path: root.reportPath
        watchChanges: true
        printErrors: false
        onLoaded: root.report = text()
        onLoadFailed: root.report = ""
    }

    // Right click re-runs the check instead of waiting for Monday. The unit is
    // a oneshot, so a second click while it runs is a no-op.
    pillRightClickAction: () => Quickshell.execDetached(["systemctl", "--user", "start", "flake-update-check"])

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
            detailsText: root.tooltip
            showCloseButton: true

            // Re-run the check without waiting for Monday, same as a right
            // click on the pill. The unit is a oneshot, so a second press
            // while it runs is a no-op.
            headerActions: Component {
                DankActionButton {
                    iconName: "refresh"
                    iconColor: Theme.surfaceVariantText
                    tooltipText: "Check now"
                    onClicked: Quickshell.execDetached(["systemctl", "--user", "start", "flake-update-check"])
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
