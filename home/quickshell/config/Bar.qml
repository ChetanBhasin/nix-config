pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import "Theme.js" as Theme

// PanelWindow is created through Quickshell's active Wayland backend.
// qmllint disable uncreatable-type
PanelWindow {
    id: root

    required property var modelData
    required property var shellState
    required property var notificationServer

    readonly property var monitor: Hyprland.monitorFor(screen)
    readonly property bool screenFocused: monitor !== null && monitor.focused
    readonly property real sideEnvelope: Math.max(leftIsland.width, rightIsland.width)

    screen: modelData
    anchors {
        top: true
        left: true
        right: true
    }
    implicitHeight: Theme.barHeight
    exclusiveZone: Theme.barHeight
    color: "transparent"

    Rectangle {
        id: leftIsland

        anchors.left: parent.left
        anchors.leftMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        width: leftContent.implicitWidth + 12
        height: Theme.islandHeight
        radius: Theme.radius
        color: Theme.panel
        border.width: 1
        border.color: root.screenFocused ? Theme.activeBorder : Theme.border

        Row {
            id: leftContent
            anchors.centerIn: parent
            spacing: 4

            GruvboxButton {
                width: 28
                height: 28
                icon: "󰍜"
                checked: root.shellState.launcherOpen && root.screenFocused
                foreground: checked ? Theme.accent : Theme.text
                tooltip: "Applications · Super+Space"
                onClicked: root.shellState.toggleLauncher()
            }

            Rectangle {
                width: 1
                height: 16
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.border
            }

            WorkspaceStrip {
                width: implicitWidth
                height: 28
                screen: root.screen
            }
        }
    }

    Rectangle {
        id: centerIsland

        anchors.centerIn: parent
        width: Math.min(520, Math.max(0, root.width - (root.sideEnvelope * 2) - 48))
        height: Theme.islandHeight
        visible: width >= 180
        radius: Theme.radius
        color: Theme.panel
        border.width: 1
        border.color: Theme.border

        Text {
            anchors.fill: parent
            anchors.leftMargin: 18
            anchors.rightMargin: 18
            verticalAlignment: Text.AlignVCenter
            horizontalAlignment: Text.AlignHCenter
            text: root.screenFocused && Hyprland.activeToplevel !== null
                ? Hyprland.activeToplevel.title
                : root.monitor !== null ? root.monitor.name : ""
            color: root.screenFocused ? Theme.text : Theme.muted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.smallFontSize
            elide: Text.ElideMiddle
            maximumLineCount: 1
        }
    }

    Rectangle {
        id: rightIsland

        anchors.right: parent.right
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        width: status.implicitWidth + 12
        height: Theme.islandHeight
        radius: Theme.radius
        color: Theme.panel
        border.width: 1
        border.color: root.screenFocused ? Theme.activeBorder : Theme.border

        StatusCluster {
            id: status
            anchors.centerIn: parent
            width: implicitWidth
            height: 28
            shellState: root.shellState
            notificationServer: root.notificationServer
        }
    }

    Launcher {
        barWindow: root
        shellState: root.shellState
    }

    ControlCenter {
        barWindow: root
        shellState: root.shellState
        notificationServer: root.notificationServer
    }

    NotificationToasts {
        barWindow: root
        shellState: root.shellState
    }
}
