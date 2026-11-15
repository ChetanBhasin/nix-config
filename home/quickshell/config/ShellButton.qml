pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import "Theme.js" as Theme

Rectangle {
    id: root

    property string icon: ""
    property string text: ""
    property string tooltip: ""
    property bool checked: false
    property bool danger: false
    property bool quiet: false
    property color foreground: danger ? Theme.error : (checked ? Theme.accent : Theme.text)

    signal clicked

    implicitWidth: content.implicitWidth + 18
    implicitHeight: 32
    radius: Theme.smallRadius
    color: checked ? Theme.accentSurface : (pointer.containsMouse || activeFocus ? Theme.elevated : "transparent")
    border.width: checked || activeFocus ? 1 : 0
    border.color: checked ? Theme.accent : Theme.border
    activeFocusOnTab: true

    Row {
        id: content
        anchors.centerIn: parent
        spacing: root.icon !== "" && root.text !== "" ? 7 : 0

        Text {
            visible: root.icon !== ""
            text: root.icon
            color: root.foreground
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize + 1
        }

        Text {
            visible: root.text !== ""
            text: root.text
            color: root.foreground
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            font.weight: root.checked ? Font.DemiBold : Font.Normal
        }
    }

    MouseArea {
        id: pointer
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            root.clicked()
            event.accepted = true
        }
    }

    ToolTip.visible: pointer.containsMouse && root.tooltip !== ""
    ToolTip.delay: 550
    ToolTip.text: root.tooltip

    Behavior on color {
        ColorAnimation { duration: 110 }
    }
}
