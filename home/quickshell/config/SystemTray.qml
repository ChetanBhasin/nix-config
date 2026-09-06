pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Services.SystemTray as Tray
import Quickshell.Widgets
import "Theme.js" as Theme

Item {
    id: root

    implicitWidth: trayItems.implicitWidth
    implicitHeight: 26
    visible: Tray.SystemTray.items.values.length > 0

    Row {
        id: trayItems
        anchors.centerIn: parent
        spacing: 3

        Repeater {
            model: Tray.SystemTray.items

            Item {
                id: trayButton

                required property var modelData

                width: visible ? 27 : 0
                height: 26
                visible: modelData.status !== Tray.Status.Passive

                Rectangle {
                    anchors.fill: parent
                    radius: Theme.smallRadius
                    color: pointer.containsMouse ? Theme.elevated : "transparent"
                }

                IconImage {
                    anchors.centerIn: parent
                    implicitSize: 17
                    source: trayButton.modelData.icon
                }

                MouseArea {
                    id: pointer
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor

                    function showMenu() {
                        const point = trayButton.QsWindow.mapFromItem(trayButton, 0, trayButton.height)
                        trayButton.modelData.display(trayButton.QsWindow.window, Math.round(point.x), Math.round(point.y))
                    }

                    onClicked: mouse => {
                        if (mouse.button === Qt.MiddleButton) {
                            trayButton.modelData.secondaryActivate()
                        } else if (mouse.button === Qt.RightButton || trayButton.modelData.onlyMenu) {
                            showMenu()
                        } else {
                            trayButton.modelData.activate()
                        }
                    }

                    onWheel: wheel => {
                        trayButton.modelData.scroll(wheel.angleDelta.y, false)
                        wheel.accepted = true
                    }
                }

                ToolTip.visible: pointer.containsMouse
                ToolTip.delay: 550
                ToolTip.text: modelData.tooltipTitle || modelData.title
            }
        }
    }
}
