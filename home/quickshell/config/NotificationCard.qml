pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Notifications
import Quickshell.Widgets
import "Theme.js" as Theme

Rectangle {
    id: root

    required property var notification
    required property var shellState
    property bool toast: false
    property bool timerEnabled: true
    property bool compact: false
    readonly property bool valid: notification !== null

    readonly property color urgencyColor: valid
        && notification.urgency === NotificationUrgency.Critical ? Theme.error
        : valid && notification.urgency === NotificationUrgency.Low ? Theme.info : Theme.accent

    visible: valid
    implicitWidth: 380
    implicitHeight: valid ? content.implicitHeight + 22 : 0
    radius: Theme.radius
    color: Theme.panel
    border.width: 1
    border.color: urgencyColor

    HoverHandler { id: hover }

    ColumnLayout {
        id: content
        anchors.fill: parent
        anchors.margins: 11
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Item {
                Layout.preferredWidth: 34
                Layout.preferredHeight: 34

                Image {
                    anchors.fill: parent
                    visible: root.valid && (root.notification.image ?? "") !== ""
                    source: root.valid ? (root.notification.image ?? "") : ""
                    fillMode: Image.PreserveAspectCrop
                    sourceSize.width: 34
                    sourceSize.height: 34
                    asynchronous: true
                }

                IconImage {
                    id: appIconImage
                    anchors.fill: parent
                    visible: root.valid && (root.notification.image ?? "") === ""
                        && (root.notification.appIcon ?? "") !== ""
                    source: root.valid && (root.notification.appIcon ?? "") !== ""
                        ? (Quickshell.iconPath(root.notification.appIcon) ?? "") : ""
                    implicitSize: 34
                }

                Text {
                    anchors.centerIn: parent
                    visible: root.valid && (root.notification.image ?? "") === ""
                        && appIconImage.source.toString() === ""
                    text: "󰂚"
                    color: Theme.info
                    font.family: Theme.fontFamily
                    font.pixelSize: 22
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                Text {
                    Layout.fillWidth: true
                    text: root.valid
                        ? (root.notification.summary || root.notification.appName || "Notification") : ""
                    color: Theme.emphasized
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }

                Text {
                    Layout.fillWidth: true
                    text: root.valid ? root.notification.appName : ""
                    visible: root.valid && text !== "" && text !== root.notification.summary
                    color: Theme.muted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.smallFontSize
                    elide: Text.ElideRight
                }
            }

            GruvboxButton {
                Layout.preferredWidth: 26
                Layout.preferredHeight: 26
                icon: "󰅖"
                foreground: Theme.muted
                tooltip: "Dismiss"
                onClicked: {
                    if (root.valid)
                        root.notification.dismiss()
                }
            }
        }

        Text {
            Layout.fillWidth: true
            visible: text !== ""
            text: root.valid ? root.notification.body : ""
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: Theme.smallFontSize
            textFormat: Text.StyledText
            wrapMode: Text.Wrap
            maximumLineCount: root.compact ? 3 : 2147483647
            elide: Text.ElideRight
            lineHeight: 1.15
        }

        Flow {
            Layout.fillWidth: true
            visible: actionRepeater.count > 0
            spacing: 6

            Repeater {
                id: actionRepeater
                model: !root.valid ? []
                    : root.compact ? root.notification.actions.slice(0, 2)
                    : root.notification.actions

                GruvboxButton {
                    required property var modelData
                    height: 28
                    text: modelData.text
                    foreground: Theme.accent
                    onClicked: modelData.invoke()
                }
            }
        }
    }

    Timer {
        interval: {
            if (!root.valid)
                return 6000
            if (root.notification.urgency === NotificationUrgency.Critical)
                return 10000
            if (root.notification.expireTimeout > 0)
                return Math.max(2500, root.notification.expireTimeout)
            return 6000
        }
        running: root.valid && root.toast && root.timerEnabled && !hover.hovered
        onTriggered: {
            if (!root.valid)
                return
            root.shellState.hideToast(root.notification)
            if (root.notification.transient)
                root.notification.expire()
        }
    }

    Connections {
        target: root.notification
        function onClosed() {
            if (root.valid)
                root.shellState.hideToast(root.notification)
        }
    }
}
