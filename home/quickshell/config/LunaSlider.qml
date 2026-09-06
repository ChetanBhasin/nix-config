pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import "Theme.js" as Theme

Slider {
    id: root

    property color accentColor: Theme.accent

    implicitHeight: 24

    background: Rectangle {
        x: root.leftPadding
        y: root.topPadding + (root.availableHeight - height) / 2
        implicitWidth: 200
        implicitHeight: 4
        width: root.availableWidth
        height: implicitHeight
        radius: 2
        color: Theme.elevated

        Rectangle {
            width: root.visualPosition * parent.width
            height: parent.height
            radius: parent.radius
            color: root.enabled ? root.accentColor : Theme.muted
        }
    }

    handle: Rectangle {
        x: root.leftPadding + root.visualPosition * (root.availableWidth - width)
        y: root.topPadding + (root.availableHeight - height) / 2
        implicitWidth: 14
        implicitHeight: 14
        radius: 7
        color: root.pressed ? Theme.strongest : Theme.emphasized
        border.width: 2
        border.color: root.enabled ? root.accentColor : Theme.muted

        Behavior on color {
            ColorAnimation { duration: 100 }
        }
    }
}
