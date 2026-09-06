pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Networking
import Quickshell.Services.Pipewire
import "Theme.js" as Theme

PopupWindow {
    id: root

    required property var barWindow
    required property var shellState
    required property var notificationServer

    readonly property var monitor: Hyprland.monitorFor(screen)
    readonly property bool screenFocused: monitor !== null && monitor.focused
    readonly property var audio: Pipewire.defaultAudioSink ? Pipewire.defaultAudioSink.audio : null
    readonly property var wifiDevice: shellState.wifiDevice
    readonly property var wifiDevices: shellState.wifiDevices
    readonly property var wiredDevice: shellState.wiredDevice
    readonly property int page: shellState.dashboardPage

    function availableNetworks() {
        if (wifiDevices.length === 0)
            return []

        const strongestByName = new Map()
        for (const device of wifiDevices) {
            for (const network of device.networks.values) {
                if (network.name === "")
                    continue
                const existing = strongestByName.get(network.name)
                if (existing === undefined
                        || (network.connected && !existing.connected)
                        || (network.connected === existing.connected && network.known && !existing.known)
                        || (network.connected === existing.connected && network.known === existing.known
                            && network.signalStrength > existing.signalStrength))
                    strongestByName.set(network.name, network)
            }
        }

        const networks = [...strongestByName.values()]
        networks.sort((left, right) => {
            if (left.connected !== right.connected)
                return left.connected ? -1 : 1
            return right.signalStrength - left.signalStrength
        })
        return networks.slice(0, 6)
    }

    function connectNetwork(network) {
        if (network.connected) {
            network.disconnect()
        } else if (network.known || network.security === WifiSecurityType.Open) {
            network.connect()
        } else {
            shellState.dashboardOpen = false
            Qt.callLater(() => Quickshell.execDetached(["@nmConnectionEditor@"]))
        }
    }

    function strengthIcon(strength) {
        if (strength > 0.72)
            return "󰤨"
        if (strength > 0.48)
            return "󰤥"
        if (strength > 0.24)
            return "󰤢"
        return "󰤟"
    }

    anchor.window: barWindow
    anchor.rect.x: Math.max(8, barWindow.width - implicitWidth - 8)
    anchor.rect.y: Theme.barHeight + 4

    implicitWidth: Math.min(440, screen.width - 24)
    implicitHeight: Math.min(720, screen.height - Theme.barHeight - 24)
    color: "transparent"
    grabFocus: false
    visible: shellState.dashboardOpen && screenFocused

    onVisibleChanged: {
        if (visible) {
            Qt.callLater(() => panelFocus.forceActiveFocus())
        } else if (shellState.dashboardOpen && screenFocused) {
            shellState.dashboardOpen = false
        }
    }

    HyprlandFocusGrab {
        windows: [root]
        active: root.visible
        onCleared: {
            if (root.visible)
                root.shellState.dashboardOpen = false
        }
    }

    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink]
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radius + 2
        color: Theme.background
        border.width: 1
        border.color: Theme.activeBorder

        FocusScope {
            id: panelFocus
            anchors.fill: parent
            focus: true

            Keys.onEscapePressed: root.shellState.dashboardOpen = false

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        Text {
                            text: "Control Center"
                            color: Theme.emphasized
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.largeFontSize
                            font.weight: Font.DemiBold
                        }

                        Text {
                            text: root.page === 0 ? "System controls" : "Notification history"
                            color: Theme.muted
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.smallFontSize
                        }
                    }

                    GruvboxButton {
                        icon: "󰅖"
                        foreground: Theme.muted
                        tooltip: "Close"
                        onClicked: root.shellState.dashboardOpen = false
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    GruvboxButton {
                        Layout.fillWidth: true
                        text: "Controls"
                        icon: "󰒓"
                        checked: root.page === 0
                        onClicked: root.shellState.dashboardPage = 0
                    }

                    GruvboxButton {
                        Layout.fillWidth: true
                        text: "Notifications"
                        icon: root.shellState.doNotDisturb ? "󰂛" : "󰂚"
                        checked: root.page === 1
                        onClicked: root.shellState.dashboardPage = 1
                    }
                }

                StackLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    currentIndex: root.page

                    Flickable {
                        id: controlsScroll
                        clip: true
                        contentWidth: width
                        contentHeight: controlsColumn.implicitHeight
                        boundsBehavior: Flickable.StopAtBounds

                        ColumnLayout {
                            id: controlsColumn
                            width: controlsScroll.width
                            spacing: 10

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                GruvboxButton {
                                    Layout.fillWidth: true
                                    icon: "󰤨"
                                    text: "Wi-Fi"
                                    checked: Networking.wifiEnabled
                                    foreground: checked ? Theme.info : Theme.muted
                                    enabled: Networking.wifiHardwareEnabled
                                    onClicked: Networking.wifiEnabled = !Networking.wifiEnabled
                                }

                                GruvboxButton {
                                    Layout.fillWidth: true
                                    icon: root.shellState.doNotDisturb ? "󰂛" : "󰂚"
                                    text: "Focus"
                                    checked: root.shellState.doNotDisturb
                                    foreground: checked ? Theme.purple : Theme.muted
                                    onClicked: root.shellState.doNotDisturb = !root.shellState.doNotDisturb
                                }

                                GruvboxButton {
                                    Layout.fillWidth: true
                                    icon: "󰌾"
                                    text: "Lock"
                                    onClicked: Quickshell.execDetached(["loginctl", "lock-session"])
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: audioControls.implicitHeight + 22
                                radius: Theme.radius
                                color: Theme.panel
                                border.width: 1
                                border.color: Theme.border

                                ColumnLayout {
                                    id: audioControls
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.margins: 11
                                    spacing: 8

                                    RowLayout {
                                        Layout.fillWidth: true

                                        Text {
                                            text: "Audio"
                                            color: Theme.emphasized
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fontSize
                                            font.weight: Font.DemiBold
                                        }

                                        Item { Layout.fillWidth: true }

                                        GruvboxButton {
                                            icon: root.audio !== null && root.audio.muted ? "󰝟" : "󰕾"
                                            text: root.audio === null ? "Unavailable" : Math.round(root.audio.volume * 100) + "%"
                                            foreground: root.audio !== null && root.audio.muted ? Theme.muted : Theme.accent
                                            onClicked: {
                                                if (root.audio !== null)
                                                    root.audio.muted = !root.audio.muted
                                            }
                                        }
                                    }

                                    GruvboxSlider {
                                        Layout.fillWidth: true
                                        enabled: root.audio !== null
                                        value: root.audio === null ? 0 : root.audio.volume
                                        onMoved: {
                                            if (root.audio !== null) {
                                                root.audio.volume = value
                                                root.audio.muted = false
                                            }
                                        }
                                    }
                                }
                            }

                            Rectangle {
                                visible: root.shellState.brightnessAvailable
                                Layout.fillWidth: true
                                implicitHeight: brightnessControls.implicitHeight + 22
                                radius: Theme.radius
                                color: Theme.panel
                                border.width: 1
                                border.color: Theme.border

                                ColumnLayout {
                                    id: brightnessControls
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.margins: 11
                                    spacing: 8

                                    RowLayout {
                                        Layout.fillWidth: true

                                        Text {
                                            text: "Brightness"
                                            color: Theme.emphasized
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fontSize
                                            font.weight: Font.DemiBold
                                        }

                                        Item { Layout.fillWidth: true }

                                        Text {
                                            text: Math.round(root.shellState.brightness * 100) + "%"
                                            color: Theme.accent
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fontSize
                                        }
                                    }

                                    GruvboxSlider {
                                        Layout.fillWidth: true
                                        value: root.shellState.brightness
                                        accentColor: Theme.warning
                                        onMoved: root.shellState.setBrightness(value)
                                    }
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: networkControls.implicitHeight + 22
                                radius: Theme.radius
                                color: Theme.panel
                                border.width: 1
                                border.color: Theme.border

                                ColumnLayout {
                                    id: networkControls
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.margins: 11
                                    spacing: 7

                                    RowLayout {
                                        Layout.fillWidth: true

                                        Text {
                                            text: root.wifiDevice !== null ? "Wi-Fi networks" : "Network"
                                            color: Theme.emphasized
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fontSize
                                            font.weight: Font.DemiBold
                                        }

                                        Item { Layout.fillWidth: true }

                                        GruvboxButton {
                                            visible: root.wifiDevice !== null
                                            text: Networking.wifiEnabled ? "On" : "Off"
                                            checked: Networking.wifiEnabled
                                            foreground: checked ? Theme.info : Theme.muted
                                            onClicked: Networking.wifiEnabled = !Networking.wifiEnabled
                                        }
                                    }

                                    ScriptModel {
                                        id: networkModel
                                        values: root.availableNetworks()
                                    }

                                    Repeater {
                                        model: networkModel

                                        Rectangle {
                                            id: networkRow

                                            required property var modelData

                                            function activate() {
                                                root.connectNetwork(modelData)
                                            }

                                            activeFocusOnTab: true
                                            Accessible.role: Accessible.Button
                                            Accessible.name: `${modelData.connected ? "Disconnect from" : "Connect to"} ${modelData.name}`
                                            Layout.fillWidth: true
                                            implicitHeight: 34
                                            radius: Theme.smallRadius
                                            color: modelData.connected ? Theme.accentSurface
                                                : activeFocus || networkPointer.containsMouse ? Theme.elevated : "transparent"
                                            border.width: activeFocus ? 1 : 0
                                            border.color: Theme.accent

                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: 9
                                                anchors.rightMargin: 9
                                                spacing: 8

                                                Text {
                                                    text: root.strengthIcon(networkRow.modelData.signalStrength)
                                                    color: networkRow.modelData.connected ? Theme.info : Theme.muted
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: Theme.fontSize
                                                }

                                                Text {
                                                    Layout.fillWidth: true
                                                    text: networkRow.modelData.name
                                                    color: networkRow.modelData.connected ? Theme.emphasized : Theme.text
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: Theme.smallFontSize
                                                    font.weight: networkRow.modelData.connected ? Font.DemiBold : Font.Normal
                                                    elide: Text.ElideRight
                                                }

                                                Text {
                                                    text: networkRow.modelData.connected ? "Connected"
                                                        : networkRow.modelData.known || networkRow.modelData.security === WifiSecurityType.Open
                                                            ? "Connect" : "Configure"
                                                    color: networkRow.modelData.connected ? Theme.info : Theme.muted
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: Theme.smallFontSize
                                                }
                                            }

                                            Keys.onReturnPressed: activate()
                                            Keys.onEnterPressed: activate()
                                            Keys.onSpacePressed: activate()

                                            MouseArea {
                                                id: networkPointer
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    networkRow.forceActiveFocus()
                                                    networkRow.activate()
                                                }
                                            }
                                        }
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        visible: root.wifiDevice === null || !Networking.wifiEnabled
                                            || networkModel.values.length === 0
                                        text: root.wiredDevice !== null && root.wiredDevice.connected
                                            ? "Ethernet connected"
                                            : !Networking.wifiEnabled ? "Wi-Fi is disabled"
                                            : root.wifiDevice === null ? "No Wi-Fi device found"
                                            : "No nearby networks found"
                                        color: Theme.muted
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.smallFontSize
                                    }
                                }
                            }

                            Rectangle {
                                visible: root.shellState.batteryAvailable
                                Layout.fillWidth: true
                                implicitHeight: batteryControls.implicitHeight + 22
                                radius: Theme.radius
                                color: Theme.panel
                                border.width: 1
                                border.color: Theme.border

                                ColumnLayout {
                                    id: batteryControls
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.margins: 11
                                    spacing: 7

                                    RowLayout {
                                        Layout.fillWidth: true

                                        Text {
                                            text: root.shellState.batteryCharging ? "Charging" : "Battery"
                                            color: Theme.emphasized
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fontSize
                                            font.weight: Font.DemiBold
                                        }

                                        Item { Layout.fillWidth: true }

                                        Text {
                                            text: Math.round(root.shellState.batteryPercentage * 100) + "%"
                                            color: !root.shellState.batteryCharging
                                                && root.shellState.batteryPercentage < 0.2 ? Theme.error : Theme.muted
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.smallFontSize
                                        }
                                    }

                                    ProgressBar {
                                        Layout.fillWidth: true
                                        value: root.shellState.batteryPercentage

                                        background: Rectangle {
                                            implicitHeight: 5
                                            radius: 3
                                            color: Theme.elevated
                                        }

                                        contentItem: Item {
                                            implicitHeight: 5

                                            Rectangle {
                                                width: parent.width * root.shellState.batteryPercentage
                                                height: parent.height
                                                radius: 3
                                                color: root.shellState.batteryPercentage < 0.2
                                                    ? Theme.error : Theme.success
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Item {
                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 8

                            RowLayout {
                                Layout.fillWidth: true

                                GruvboxButton {
                                    icon: root.shellState.doNotDisturb ? "󰂛" : "󰂚"
                                    text: root.shellState.doNotDisturb ? "Focus on" : "Focus off"
                                    checked: root.shellState.doNotDisturb
                                    foreground: checked ? Theme.purple : Theme.muted
                                    onClicked: root.shellState.doNotDisturb = !root.shellState.doNotDisturb
                                }

                                Item { Layout.fillWidth: true }

                                GruvboxButton {
                                    icon: "󰆴"
                                    text: "Clear"
                                    danger: true
                                    enabled: notificationList.count > 0
                                    onClicked: root.shellState.clearNotifications()
                                }
                            }

                            ScriptModel {
                                id: notificationModel
                                values: root.notificationServer.trackedNotifications.values
                                    .filter(notification => !notification.transient)
                                    .slice().reverse()
                            }

                            ListView {
                                id: notificationList
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                spacing: 8
                                clip: true
                                boundsBehavior: Flickable.StopAtBounds
                                model: notificationModel

                                delegate: NotificationCard {
                                    required property var modelData

                                    width: notificationList.width
                                    notification: modelData
                                    shellState: root.shellState
                                    compact: false
                                }

                                Text {
                                    anchors.centerIn: parent
                                    visible: notificationList.count === 0
                                    text: root.shellState.doNotDisturb
                                        ? "Focus mode is quiet"
                                        : "You're all caught up"
                                    color: Theme.muted
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
