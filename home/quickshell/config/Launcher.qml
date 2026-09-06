pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Widgets
import "Theme.js" as Theme

PopupWindow {
    id: root

    required property var barWindow
    required property var shellState

    readonly property var monitor: Hyprland.monitorFor(screen)
    readonly property bool screenFocused: monitor !== null && monitor.focused
    property int selectedIndex: 0
    property alias query: searchField.text

    function appText(entry) {
        return (entry.name + " " + entry.genericName + " " + entry.comment + " "
            + entry.keywords.join(" ")).toLowerCase()
    }

    function rank(entry, queryText) {
        const name = entry.name.toLowerCase()
        const genericName = entry.genericName.toLowerCase()
        if (name === queryText)
            return 0
        if (name.startsWith(queryText))
            return 10 + name.length
        if (genericName.startsWith(queryText))
            return 50 + genericName.length
        const nameIndex = name.indexOf(queryText)
        if (nameIndex >= 0)
            return 100 + nameIndex
        return 300 + appText(entry).indexOf(queryText)
    }

    function filteredApplications() {
        const queryText = query.trim().toLowerCase()
        const words = queryText.split(/\s+/).filter(word => word !== "")
        const entries = [...DesktopEntries.applications.values]
            .filter(entry => words.every(word => appText(entry).includes(word)))

        entries.sort((left, right) => {
            if (queryText !== "") {
                const difference = rank(left, queryText) - rank(right, queryText)
                if (difference !== 0)
                    return difference
            }
            return left.name.localeCompare(right.name)
        })
        return entries
    }

    function moveSelection(delta) {
        if (results.count === 0)
            return
        selectedIndex = (selectedIndex + delta + results.count) % results.count
        results.positionViewAtIndex(selectedIndex, ListView.Contain)
    }

    function launch(entry) {
        if (!entry)
            return

        shellState.launcherOpen = false
        if (entry.runInTerminal) {
            const command = ["alacritty", "-e"]
            for (const argument of entry.command)
                command.push(argument)
            Quickshell.execDetached({
                command: command,
                workingDirectory: entry.workingDirectory
            })
        } else {
            entry.execute()
        }
    }

    function launchSelected() {
        if (selectedIndex >= 0 && selectedIndex < appModel.values.length)
            launch(appModel.values[selectedIndex])
    }

    anchor.window: barWindow
    anchor.rect.x: Math.round((barWindow.width - implicitWidth) / 2)
    anchor.rect.y: Theme.barHeight + 4

    implicitWidth: Math.min(660, screen.width - 32)
    implicitHeight: Math.min(510, screen.height - Theme.barHeight - 32)
    color: "transparent"
    grabFocus: false
    visible: shellState.launcherOpen && screenFocused

    onVisibleChanged: {
        if (visible) {
            query = ""
            selectedIndex = 0
            Qt.callLater(() => searchField.forceActiveFocus())
        } else if (shellState.launcherOpen && screenFocused) {
            shellState.launcherOpen = false
        }
    }

    HyprlandFocusGrab {
        windows: [root]
        active: root.visible
        onCleared: {
            if (root.visible)
                root.shellState.launcherOpen = false
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radius + 2
        color: Theme.background
        border.width: 1
        border.color: Theme.activeBorder

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Text {
                    text: "󰍜"
                    color: Theme.accent
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.largeFontSize
                }

                TextField {
                    id: searchField

                    Layout.fillWidth: true
                    Layout.preferredHeight: 40
                    leftPadding: 12
                    rightPadding: 12
                    placeholderText: "Search applications"
                    placeholderTextColor: Theme.muted
                    color: Theme.emphasized
                    selectionColor: Theme.accentSurface
                    selectedTextColor: Theme.accent
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    selectByMouse: true

                    background: Rectangle {
                        radius: Theme.smallRadius
                        color: Theme.panel
                        border.width: searchField.activeFocus ? 1 : 0
                        border.color: Theme.accent
                    }

                    onTextChanged: {
                        root.selectedIndex = 0
                        results.positionViewAtBeginning()
                    }

                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Down) {
                            root.moveSelection(1)
                            event.accepted = true
                        } else if (event.key === Qt.Key_Up) {
                            root.moveSelection(-1)
                            event.accepted = true
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            root.launchSelected()
                            event.accepted = true
                        } else if (event.key === Qt.Key_Escape) {
                            root.shellState.launcherOpen = false
                            event.accepted = true
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: Theme.smallRadius
                color: Theme.panel

                ScriptModel {
                    id: appModel
                    values: root.filteredApplications()
                }

                ListView {
                    id: results
                    anchors.fill: parent
                    anchors.margins: 6
                    spacing: 3
                    clip: true
                    model: appModel
                    boundsBehavior: Flickable.StopAtBounds
                    highlightMoveDuration: 90

                    delegate: Rectangle {
                        id: appRow

                        required property var modelData
                        required property int index
                        readonly property bool selected: index === root.selectedIndex

                        width: results.width
                        height: 50
                        radius: Theme.smallRadius
                        color: selected ? Theme.accentSurface : (rowPointer.containsMouse ? Theme.elevated : "transparent")
                        border.width: selected ? 1 : 0
                        border.color: Theme.accent

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 11

                            IconImage {
                                Layout.preferredWidth: 32
                                Layout.preferredHeight: 32
                                source: Quickshell.iconPath(appRow.modelData.icon, "application-x-executable")
                                implicitSize: 32
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1

                                Text {
                                    Layout.fillWidth: true
                                    text: appRow.modelData.name
                                    color: appRow.selected ? Theme.accent : Theme.emphasized
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize
                                    font.weight: appRow.selected ? Font.DemiBold : Font.Normal
                                    elide: Text.ElideRight
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: appRow.modelData.genericName || appRow.modelData.comment
                                    visible: text !== ""
                                    color: Theme.muted
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.smallFontSize
                                    elide: Text.ElideRight
                                }
                            }
                        }

                        MouseArea {
                            id: rowPointer
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: root.selectedIndex = appRow.index
                            onClicked: root.launch(appRow.modelData)
                        }

                        Behavior on color {
                            ColorAnimation { duration: 90 }
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: results.count === 0
                        text: "No matching applications"
                        color: Theme.muted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true

                Text {
                    text: results.count + (results.count === 1 ? " application" : " applications")
                    color: Theme.muted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.smallFontSize
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: "↑↓ navigate   ↵ launch   esc close"
                    color: Theme.dim
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.smallFontSize
                }
            }
        }
    }
}
