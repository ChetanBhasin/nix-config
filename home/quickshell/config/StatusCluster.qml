pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.SystemTray as Tray
import Quickshell.Services.Pipewire
import "Theme.js" as Theme

Item {
    id: root

    required property var shellState
    required property var notificationServer

    readonly property var audio: Pipewire.defaultAudioSink ? Pipewire.defaultAudioSink.audio : null
    readonly property var wifiDevice: shellState.wifiDevice
    readonly property var wiredDevice: shellState.wiredDevice
    readonly property var connectedWifi: wifiDevice === null
        ? null
        : wifiDevice.networks.values.find(network => network.connected) ?? null
    readonly property int notificationCount: notificationServer.trackedNotifications.values
        .filter(notification => !notification.transient).length

    function volumeIcon() {
        if (audio === null || audio.muted)
            return "󰝟"
        if (audio.volume < 0.34)
            return "󰕿"
        if (audio.volume < 0.67)
            return "󰖀"
        return "󰕾"
    }

    function networkIcon() {
        if (connectedWifi !== null)
            return "󰤨"
        if (wiredDevice !== null && wiredDevice.connected)
            return "󰈀"
        return "󰤭"
    }

    function networkName() {
        if (connectedWifi !== null) {
            const name = connectedWifi.name
            return name.length > 16 ? name.substring(0, 15) + "…" : name
        }
        if (wiredDevice !== null && wiredDevice.connected)
            return "Ethernet"
        return "Offline"
    }

    function batteryIcon() {
        const percentage = shellState.batteryPercentage
        if (shellState.batteryCharging)
            return "󰂄"
        if (percentage < 0.15)
            return "󰁺"
        if (percentage < 0.4)
            return "󰁼"
        if (percentage < 0.7)
            return "󰁾"
        return "󰁹"
    }

    implicitWidth: statusRow.implicitWidth
    implicitHeight: 28

    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink]
    }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    RowLayout {
        id: statusRow
        anchors.centerIn: parent
        spacing: 3

        SystemTray {
            Layout.preferredWidth: implicitWidth
            Layout.preferredHeight: 26
        }

        Rectangle {
            visible: Tray.SystemTray.items.values.length > 0
            Layout.preferredWidth: 1
            Layout.preferredHeight: 16
            color: Theme.border
        }

        Item {
            Layout.preferredWidth: volumeButton.implicitWidth
            Layout.preferredHeight: 26

            GruvboxButton {
                id: volumeButton
                anchors.fill: parent
                icon: root.volumeIcon()
                text: root.audio === null ? "--" : Math.round(root.audio.volume * 100) + "%"
                foreground: root.audio !== null && root.audio.muted ? Theme.muted : Theme.text
                tooltip: root.audio === null ? "Audio unavailable"
                    : root.audio.muted ? "Muted · click to unmute · scroll to adjust"
                    : "Audio · click to mute · scroll to adjust"
                onClicked: {
                    if (root.audio !== null)
                        root.audio.muted = !root.audio.muted
                }
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.NoButton
                onWheel: wheel => {
                    if (root.audio !== null) {
                        root.audio.volume = Math.max(0, Math.min(1, root.audio.volume
                            + (wheel.angleDelta.y > 0 ? 0.05 : -0.05)))
                        root.audio.muted = false
                    }
                    wheel.accepted = true
                }
            }
        }

        GruvboxButton {
            icon: root.networkIcon()
            text: root.networkName()
            foreground: root.connectedWifi !== null
                || (root.wiredDevice !== null && root.wiredDevice.connected) ? Theme.info : Theme.muted
            checked: root.shellState.dashboardOpen && root.shellState.dashboardPage === 0
            tooltip: "Network controls"
            onClicked: root.shellState.toggleDashboardPage(0)
        }

        GruvboxButton {
            visible: root.shellState.batteryAvailable
            icon: root.batteryIcon()
            text: Math.round(root.shellState.batteryPercentage * 100) + "%"
            foreground: !root.shellState.batteryCharging && root.shellState.batteryPercentage < 0.2
                ? Theme.error : Theme.text
            checked: root.shellState.dashboardOpen && root.shellState.dashboardPage === 0
            tooltip: root.shellState.batteryCharging ? "Charging" : "Battery"
            onClicked: root.shellState.toggleDashboardPage(0)
        }

        Rectangle {
            Layout.preferredWidth: 1
            Layout.preferredHeight: 16
            color: Theme.border
        }

        GruvboxButton {
            icon: root.shellState.doNotDisturb ? "󰂛" : "󰂚"
            text: root.notificationCount > 0 ? root.notificationCount.toString() : ""
            foreground: root.shellState.doNotDisturb ? Theme.purple
                : root.notificationCount > 0 ? Theme.accent : Theme.muted
            checked: root.shellState.dashboardOpen && root.shellState.dashboardPage === 1
            tooltip: root.shellState.doNotDisturb ? "Do not disturb is on" : "Notifications"
            onClicked: root.shellState.toggleDashboardPage(1)
        }

        GruvboxButton {
            text: Qt.formatDateTime(clock.date, "ddd, MMM d  HH:mm")
            checked: root.shellState.dashboardOpen && root.shellState.dashboardPage === 0
            tooltip: "Open controls and notifications"
            onClicked: root.shellState.toggleDashboardPage(0)
        }
    }
}
