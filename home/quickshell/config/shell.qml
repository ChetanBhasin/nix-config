pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import Quickshell.Services.Notifications

ShellRoot {
    id: root

    property bool launcherOpen: false
    property bool dashboardOpen: false
    property int dashboardPage: 0
    property bool doNotDisturb: false
    property var toastNotifications: []
    property real brightness: 0.5
    property bool brightnessAvailable: false
    property bool batteryAvailable: false
    property real batteryPercentage: 0
    property bool batteryCharging: false
    property var scannerDevices: []
    readonly property var wifiDevices: Networking.devices.values.filter(device => device.type === DeviceType.Wifi)
    readonly property var wifiDevice: preferredNetworkDevice(DeviceType.Wifi)
    readonly property var wiredDevice: preferredNetworkDevice(DeviceType.Wired)

    function preferredNetworkDevice(type) {
        const candidates = Networking.devices.values.filter(device => device.type === type)
        return candidates.find(device => device.connected) ?? candidates[0] ?? null
    }

    function updateWifiScanner() {
        const devices = [...root.wifiDevices]
        const shouldScan = root.dashboardOpen && root.dashboardPage === 0
        for (const device of root.scannerDevices) {
            if (device !== null && (!devices.includes(device) || !shouldScan))
                device.scannerEnabled = false
        }
        if (shouldScan) {
            for (const device of devices)
                device.scannerEnabled = true
        }
        root.scannerDevices = devices
    }

    function toggleLauncher() {
        dashboardOpen = false
        launcherOpen = !launcherOpen
    }

    function toggleDashboardPage(page: int): void {
        launcherOpen = false
        if (dashboardOpen && dashboardPage === page) {
            dashboardOpen = false
        } else {
            dashboardPage = page
            dashboardOpen = true
        }
    }

    function toggleDashboard(): void { toggleDashboardPage(0) }

    function pushToast(notification) {
        const pending = toastNotifications.filter(item => item !== notification)
        pending.push(notification)
        while (pending.length > 3) {
            const dropped = pending.shift()
            if (dropped.transient)
                dropped.expire()
        }
        toastNotifications = pending
    }

    function hideToast(notification) {
        toastNotifications = toastNotifications.filter(item => item !== notification)
    }

    function clearNotifications() {
        const notifications = [...notificationServer.trackedNotifications.values]
        for (const notification of notifications)
            notification.dismiss()
    }

    function setBrightness(value) {
        if (!brightnessAvailable)
            return
        brightness = Math.max(0.01, Math.min(1, value))
        brightnessApply.restart()
    }

    onDashboardOpenChanged: updateWifiScanner()
    onDashboardPageChanged: updateWifiScanner()
    onWifiDevicesChanged: updateWifiScanner()
    Component.onCompleted: updateWifiScanner()
    Component.onDestruction: {
        for (const device of root.scannerDevices) {
            if (device !== null)
                device.scannerEnabled = false
        }
    }

    NotificationServer {
        id: notificationServer
        keepOnReload: true
        bodySupported: true
        bodyMarkupSupported: true
        actionsSupported: true
        actionIconsSupported: false
        imageSupported: true
        persistenceSupported: true

        onNotification: notification => {
            notification.tracked = true
            const shouldToast = !root.doNotDisturb
                || notification.urgency === NotificationUrgency.Critical
            if (shouldToast) {
                root.pushToast(notification)
            } else if (notification.transient) {
                notification.expire()
            }
        }
    }

    Process {
        id: brightnessReader
        command: ["brightnessctl", "-m"]
        running: true

        stdout: StdioCollector {
            onStreamFinished: {
                const fields = text.trim().split(",")
                if (fields.length >= 4) {
                    const percentage = parseInt(fields[3])
                    if (!isNaN(percentage)) {
                        root.brightness = Math.max(0.01, Math.min(1, percentage / 100))
                        root.brightnessAvailable = true
                    }
                }
            }
        }

    }

    Timer {
        interval: 15000
        repeat: true
        running: true
        onTriggered: {
            if (!brightnessReader.running)
                brightnessReader.running = true
        }
    }

    Timer {
        id: brightnessApply
        interval: 60
        onTriggered: Quickshell.execDetached([
            "brightnessctl", "set", Math.round(root.brightness * 100) + "%"
        ])
    }

    Process {
        id: batteryReader
        command: ["sh", "-c", "for battery in /sys/class/power_supply/BAT*; do [ -r $battery/capacity ] || continue; capacity=$(cat $battery/capacity); status=$(cat $battery/status); printf '%s,%s\\n' \"$capacity\" \"$status\"; break; done"]
        running: true

        stdout: StdioCollector {
            onStreamFinished: {
                const fields = text.trim().split(",")
                if (fields.length >= 2 && fields[0] !== "") {
                    const percentage = parseInt(fields[0])
                    root.batteryAvailable = !isNaN(percentage)
                    root.batteryPercentage = root.batteryAvailable
                        ? Math.max(0, Math.min(1, percentage / 100)) : 0
                    root.batteryCharging = fields[1] === "Charging" || fields[1] === "Full"
                } else {
                    root.batteryAvailable = false
                }
            }
        }
    }

    Timer {
        interval: 30000
        repeat: true
        running: true
        onTriggered: {
            if (!batteryReader.running)
                batteryReader.running = true
        }
    }

    IpcHandler {
        target: "launcher"

        function toggle(): void { root.toggleLauncher() }
        function open(): void {
            root.dashboardOpen = false
            root.launcherOpen = true
        }
        function close(): void { root.launcherOpen = false }
        function isOpen(): bool { return root.launcherOpen }
    }

    IpcHandler {
        target: "dashboard"

        function toggle(): void { root.toggleDashboard() }
        function open(): void {
            root.launcherOpen = false
            root.dashboardPage = 0
            root.dashboardOpen = true
        }
        function notifications(): void {
            root.launcherOpen = false
            root.dashboardPage = 1
            root.dashboardOpen = true
        }
        function close(): void { root.dashboardOpen = false }
        function isOpen(): bool { return root.dashboardOpen }
        function currentPage(): int { return root.dashboardPage }
    }

    Variants {
        model: Quickshell.screens

        Bar {
            shellState: root
            notificationServer: notificationServer
        }
    }
}
