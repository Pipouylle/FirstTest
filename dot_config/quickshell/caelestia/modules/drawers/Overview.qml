pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Widgets
import Caelestia
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.components.controls
import qs.services
import qs.utils

Item {
    id: root

    required property ShellScreen screen
    required property DrawerVisibilities visibilities

    readonly property bool active: visibilities.overview
    property real offsetScale: active ? 0 : 1

    visible: offsetScale < 1
    opacity: 1 - offsetScale

    Behavior on offsetScale {
        Anim {
            type: Anim.SlowEffects
        }
    }

    onActiveChanged: {
        if (active) {
            root.forceActiveFocus();
        }
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) {
            visibilities.overview = false;
            event.accepted = true;
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: visibilities.overview = false
    }

    Connections {
        target: Hypr
        function onActiveWsIdChanged() {
            if (root.active) {
                root.visibilities.overview = false;
            }
        }
    }

    // Main layout
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Tokens.padding.extraLargeIncreased
        spacing: Tokens.spacing.extraLarge

        // Header Title
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.medium

            MaterialIcon {
                text: "grid_view"
                color: Colours.palette.m3primary
                fontStyle: Tokens.font.icon.builders.extraLarge.scale(1.5).build()
            }

            StyledText {
                text: qsTr("Task View")
                font: Tokens.font.body.builders.large.size(32).weight(Font.Bold).build()
                color: Colours.palette.m3onSurface
            }
        }

        // Workspaces and Windows Grid
        StyledFlickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            
            contentWidth: width
            contentHeight: workspacesFlow.implicitHeight

            Flow {
                id: workspacesFlow
                width: parent.width
                spacing: Tokens.spacing.extraLarge
                
                Repeater {
                    // Get all active (occupied) workspaces, sorted by ID
                    model: ScriptModel {
                        values: Hypr.workspaces.values
                            .filter(w => w.id > 0 && w.lastIpcObject.windows > 0)
                            .sort((a, b) => a.id - b.id)
                    }
                    
                    delegate: StyledRect {
                        id: wsCard
                        
                        required property var modelData // HyprlandWorkspace
                        
                        readonly property bool isActive: Hypr.activeWsId === modelData.id
                        
                        implicitWidth: Math.max(300, (workspacesFlow.width - Tokens.spacing.extraLarge * 2) / 3)
                        implicitHeight: 320
                        
                        color: isActive ? Colours.tPalette.m3surfaceContainerHighest : (wsMouseArea.containsMouse ? Colours.tPalette.m3surfaceContainerHigh : Colours.tPalette.m3surfaceContainer)
                        radius: Tokens.rounding.large
                        border.width: isActive || wsMouseArea.containsMouse ? 2 : 1
                        border.color: isActive ? Colours.palette.m3primary : (wsMouseArea.containsMouse ? Colours.palette.m3secondary : Colours.layer(Colours.palette.m3outlineVariant, 2))

                        Behavior on color { CAnim { duration: 150 } }
                        Behavior on border.color { CAnim { duration: 150 } }

                        // Declare avant le ColumnLayout : les vignettes de fenetres
                        // sont donc testees en premier et gardent la priorite.
                        MouseArea {
                            id: wsMouseArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                Hypr.dispatch("workspace " + wsCard.modelData.id);
                                root.visibilities.overview = false;
                            }
                        }
                        
                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: Tokens.padding.large
                            spacing: Tokens.spacing.medium
                            
                            // Workspace Header
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Tokens.spacing.small
                                
                                StyledText {
                                    text: wsCard.modelData.monitor ? qsTr("Workspace %1 (%2)").arg(wsCard.modelData.name).arg(wsCard.modelData.monitor.name) : qsTr("Workspace %1").arg(wsCard.modelData.name)
                                    font: Tokens.font.body.builders.large.weight(Font.Bold).build()
                                    color: wsCard.isActive ? Colours.palette.m3primary : Colours.palette.m3onSurface
                                    Layout.fillWidth: true
                                }
                                
                                MaterialIcon {
                                    text: "visibility"
                                    color: Colours.palette.m3primary
                                    visible: wsCard.isActive
                                    fontStyle: Tokens.font.icon.medium
                                }
                            }
                            
                            // Windows Flow inside Workspace
                            Item {
                                id: workspaceWindowsArea
                                Layout.fillWidth: true
                                Layout.fillHeight: true

                                readonly property real monitorWidth: wsCard.modelData.monitor ? wsCard.modelData.monitor.lastIpcObject.width : 1920
                                readonly property real monitorHeight: wsCard.modelData.monitor ? wsCard.modelData.monitor.lastIpcObject.height : 1080
                                readonly property real monitorAspect: monitorWidth / monitorHeight

                                Item {
                                    id: screenContainer
                                    anchors.centerIn: parent
                                    
                                    width: (parent.width / parent.height > workspaceWindowsArea.monitorAspect) ? (parent.height * workspaceWindowsArea.monitorAspect) : parent.width
                                    height: (parent.width / parent.height > workspaceWindowsArea.monitorAspect) ? parent.height : (parent.width / workspaceWindowsArea.monitorAspect)

                                    Repeater {
                                        model: ScriptModel {
                                            values: Hypr.toplevels.values.filter(t => t.workspace?.id === wsCard.modelData.id)
                                        }
                                        
                                        delegate: StyledRect {
                                            id: windowCard
                                            required property var modelData // HyprlandToplevel
                                            
                                            readonly property real relX: modelData.lastIpcObject.at[0] - (wsCard.modelData.monitor ? wsCard.modelData.monitor.lastIpcObject.x : 0)
                                            readonly property real relY: modelData.lastIpcObject.at[1] - (wsCard.modelData.monitor ? wsCard.modelData.monitor.lastIpcObject.y : 0)
                                            readonly property real winW: modelData.lastIpcObject.size[0]
                                            readonly property real winH: modelData.lastIpcObject.size[1]

                                            x: relX * screenContainer.width / workspaceWindowsArea.monitorWidth
                                            y: relY * screenContainer.height / workspaceWindowsArea.monitorHeight
                                            width: winW * screenContainer.width / workspaceWindowsArea.monitorWidth
                                            height: winH * screenContainer.height / workspaceWindowsArea.monitorHeight

                                            color: Colours.tPalette.m3surface
                                            radius: Tokens.rounding.medium
                                            border.width: mouseArea.containsMouse ? 1.5 : 1
                                            border.color: mouseArea.containsMouse ? Colours.palette.m3primary : Colours.layer(Colours.palette.m3outlineVariant, 2)
                                            scale: mouseArea.containsMouse ? 1.02 : 1.0

                                            Behavior on scale { Anim { duration: 150 } }
                                            Behavior on border.color { CAnim { duration: 150 } }

                                            MouseArea {
                                                id: mouseArea
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                onClicked: {
                                                    Hypr.dispatch("focuswindow address:0x" + windowCard.modelData.address);
                                                    if (windowCard.modelData.workspace.id !== Hypr.activeWsId) {
                                                        Hypr.dispatch("workspace " + windowCard.modelData.workspace.id);
                                                    }
                                                    root.visibilities.overview = false;
                                                }
                                            }

                                            ColumnLayout {
                                                anchors.fill: parent
                                                anchors.margins: Tokens.padding.small
                                                spacing: Tokens.spacing.extraSmall

                                                RowLayout {
                                                    Layout.fillWidth: true
                                                    spacing: Tokens.spacing.extraSmall
                                                    
                                                    IconImage {
                                                        asynchronous: true
                                                        implicitSize: 14
                                                        source: Icons.getAppIcon(windowCard.modelData.lastIpcObject.class, "image-missing")
                                                        Layout.alignment: Qt.AlignVCenter
                                                    }
                                                    
                                                    StyledText {
                                                        text: windowCard.modelData.title
                                                        font: Tokens.font.body.small
                                                        color: Colours.palette.m3onSurface
                                                        elide: Text.ElideRight
                                                        Layout.fillWidth: true
                                                        Layout.alignment: Qt.AlignVCenter
                                                    }
                                                    
                                                    Item {
                                                        implicitWidth: 16
                                                        implicitHeight: 16
                                                        Layout.alignment: Qt.AlignVCenter

                                                        StateLayer {
                                                            radius: Tokens.rounding.full
                                                            color: Colours.palette.m3error
                                                            onClicked: {
                                                                Hypr.dispatch("killwindow address:0x" + windowCard.modelData.address);
                                                            }
                                                        }

                                                        MaterialIcon {
                                                            text: "close"
                                                            color: Colours.palette.m3onError
                                                            fontStyle: Tokens.font.icon.small
                                                            anchors.centerIn: parent
                                                        }
                                                    }
                                                }
                                                
                                                StyledClippingRect {
                                                    Layout.fillWidth: true
                                                    Layout.fillHeight: true
                                                    color: Colours.tPalette.m3surfaceContainer
                                                    radius: Tokens.rounding.small
                                                    
                                                    ScreencopyView {
                                                        id: windowPreview
                                                        anchors.centerIn: parent
                                                        captureSource: windowCard.modelData.wayland ?? null
                                                        live: root.active && windowCard.visible

                                                        readonly property real w: windowCard.modelData.lastIpcObject.size[0]
                                                        readonly property real h: windowCard.modelData.lastIpcObject.size[1]
                                                        readonly property real aspect: (w > 0 && h > 0) ? (w / h) : 1.6

                                                        constraintSize.width: (parent.width / parent.height > aspect) ? (parent.height * aspect) : parent.width
                                                        constraintSize.height: (parent.width / parent.height > aspect) ? parent.height : (parent.width / aspect)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
