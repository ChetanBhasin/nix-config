pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import "Theme.js" as Theme

PopupWindow {
    id: root

    required property var barWindow
    required property var shellState

    readonly property var monitor: Hyprland.monitorFor(screen)
    readonly property bool screenFocused: monitor !== null && monitor.focused

    anchor.window: barWindow
    anchor.rect.x: Math.max(8, barWindow.width - implicitWidth - 8)
    anchor.rect.y: Theme.barHeight + 4

    implicitWidth: 400
    implicitHeight: Math.max(1, Math.min(toastList.contentHeight, screen.height - Theme.barHeight - 24))
    color: "transparent"
    visible: screenFocused
        && !shellState.dashboardOpen
        && shellState.toastNotifications.length > 0

    ListView {
        id: toastList
        anchors.fill: parent
        spacing: 8
        clip: true
        interactive: contentHeight > height
        model: root.shellState.toastNotifications

        delegate: NotificationCard {
            required property var modelData

            width: toastList.width
            notification: modelData
            shellState: root.shellState
            toast: true
            timerEnabled: root.visible
            compact: true
        }
    }
}
