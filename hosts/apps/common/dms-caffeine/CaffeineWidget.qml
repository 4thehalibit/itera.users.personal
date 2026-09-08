// Coffee-cup replacement for DMS's built-in idleInhibitor bar widget.
//
// Identical behaviour — it calls the same SessionService.toggleIdleInhibit(),
// so the Control Center toggle, `dms ipc call inhibit toggle` and this pill all
// stay in sync. Only the icon differs: the built-in uses motion_sensor_active /
// motion_sensor_idle, which reads as a hardware sensor rather than "your
// machine will not sleep".
//
// One glyph for both states, because two different cups would not say which is
// which: filled + accent while awake is held, hollow + muted when idle is free
// to run.
import QtQuick
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    readonly property bool active: SessionService.idleInhibited

    pillClickAction: () => SessionService.toggleIdleInhibit()

    horizontalBarPill: Component {
        DankIcon {
            name: "local_cafe"
            filled: root.active
            size: Theme.barIconSize(root.barThickness, -4, root.barConfig?.maximizeWidgetIcons, root.barConfig?.iconScale)
            color: root.active ? Theme.primary : Theme.widgetTextColor
        }
    }

    verticalBarPill: Component {
        DankIcon {
            name: "local_cafe"
            filled: root.active
            size: Theme.barIconSize(root.barThickness, -4, root.barConfig?.maximizeWidgetIcons, root.barConfig?.iconScale)
            color: root.active ? Theme.primary : Theme.widgetTextColor
        }
    }
}
