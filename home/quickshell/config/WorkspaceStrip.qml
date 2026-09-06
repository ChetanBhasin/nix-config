pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Hyprland
import "Theme.js" as Theme

Item {
    id: root

    required property var screen

    readonly property var monitor: Hyprland.monitorFor(screen)
    readonly property var magicWorkspace: Hyprland.workspaces.values.find(workspace =>
        workspace.name === "special:magic" && workspace.monitor === monitor) ?? null

    function workspaceFor(number) {
        return Hyprland.workspaces.values.find(workspace =>
            workspace.id === number && workspace.monitor === monitor) ?? null
    }

    function activate(number) {
        if (monitor)
            Hyprland.dispatch("focusmonitor " + monitor.name)
        Hyprland.dispatch("focusworkspaceoncurrentmonitor " + number)
    }

    function cycle(delta) {
        if (monitor)
            Hyprland.dispatch("focusmonitor " + monitor.name)
        Hyprland.dispatch(delta > 0
            ? "focusworkspaceoncurrentmonitor e+1"
            : "focusworkspaceoncurrentmonitor e-1")
    }

    implicitWidth: workspaces.implicitWidth
    implicitHeight: 28

    Row {
        id: workspaces
        anchors.centerIn: parent
        spacing: 2

        Repeater {
            model: 10

            Rectangle {
                id: workspaceButton

                required property int index
                readonly property int workspaceNumber: index + 1
                readonly property var workspace: root.workspaceFor(workspaceNumber)
                readonly property bool active: workspace !== null && workspace.active
                readonly property bool occupied: workspace !== null && workspace.toplevels.values.length > 0
                readonly property bool urgent: workspace !== null && workspace.urgent

                width: 24
                height: 26
                radius: 7
                color: active ? Theme.accentSurface : (pointer.containsMouse ? Theme.elevated : "transparent")
                border.width: active || urgent ? 1 : 0
                border.color: urgent ? Theme.error : Theme.accent

                Text {
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: workspaceButton.occupied && !workspaceButton.active ? -1 : 0
                    text: workspaceButton.workspaceNumber
                    color: workspaceButton.urgent ? Theme.error
                        : workspaceButton.active ? Theme.accent
                        : workspaceButton.occupied ? Theme.text
                        : Theme.dimNeutral
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.smallFontSize
                    font.weight: workspaceButton.active ? Font.DemiBold : Font.Normal
                }

                Rectangle {
                    visible: workspaceButton.occupied && !workspaceButton.active
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 3
                    width: 3
                    height: 3
                    radius: 2
                    color: workspaceButton.urgent ? Theme.error : Theme.dim
                }

                MouseArea {
                    id: pointer
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.activate(workspaceButton.workspaceNumber)
                    onWheel: wheel => {
                        root.cycle(-wheel.angleDelta.y)
                        wheel.accepted = true
                    }
                }

                Behavior on color {
                    ColorAnimation { duration: 120 }
                }
            }
        }

        Rectangle {
            width: 1
            height: 16
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.border
        }

        GruvboxButton {
            width: 26
            height: 26
            icon: "󰓎"
            checked: root.magicWorkspace !== null && root.magicWorkspace.active
            foreground: checked ? Theme.purple : Theme.dim
            tooltip: "Toggle the magic workspace"
            onClicked: {
                if (root.monitor)
                    Hyprland.dispatch("focusmonitor " + root.monitor.name)
                Hyprland.dispatch("togglespecialworkspace magic")
            }
        }
    }
}
