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
                        
                        color: isActive ? Colours.tPalette.m3surfaceContainerHighest : Colours.tPalette.m3surfaceContainer
                        radius: Tokens.rounding.large
                        border.width: isActive ? 2 : 1
                        border.color: isActive ? Colours.palette.m3primary : Colours.layer(Colours.palette.m3outlineVariant, 2)
                        
                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: Tokens.padding.large
                            spacing: Tokens.spacing.medium
                            
                            // Workspace Header
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Tokens.spacing.small
                                
                                StyledText {
                                    text: qsTr("Workspace %1").arg(wsCard.modelData.name)
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
                            StyledFlickable {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                clip: true
                                contentWidth: width
                                contentHeight: windowsGrid.implicitHeight
                                
                                GridLayout {
                                    id: windowsGrid
                                    width: parent.width
                                    columns: 2
                                    rowSpacing: Tokens.spacing.small
                                    columnSpacing: Tokens.spacing.small
                                    
                                    Repeater {
                                        model: ScriptModel {
                                            values: Hypr.toplevels.values.filter(t => t.workspace?.id === wsCard.modelData.id)
                                        }
                                        
                                        delegate: StyledRect {
                                            id: windowCard
                                            
                                            required property var modelData // HyprlandToplevel
                                            
                                            Layout.fillWidth: true
                                            implicitHeight: 110
                                            
                                            color: Colours.tPalette.m3surface
                                            radius: Tokens.rounding.medium
                                            border.width: mouseArea.containsMouse ? 1.5 : 1
                                            border.color: mouseArea.containsMouse ? Colours.palette.m3primary : Colours.layer(Colours.palette.m3outlineVariant, 2)
                                            
                                            scale: mouseArea.containsMouse ? 1.02 : 1.0
                                            
                                            Behavior on scale {
                                                Anim { duration: 150 }
                                            }
                                            
                                            Behavior on border.color {
                                                CAnim { duration: 150 }
                                            }

                                            MouseArea {
                                                id: mouseArea
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                
                                                onClicked: {
                                                    // Focus the selected window
                                                    Hypr.dispatch("focuswindow address:0x" + windowCard.modelData.address);
                                                    // If on a different workspace, switch to it
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
                                                
                                                // Window App Icon & Title
                                                RowLayout {
                                                    Layout.fillWidth: true
                                                    spacing: Tokens.spacing.extraSmall
                                                    
                                                    IconImage {
                                                        asynchronous: true
                                                        implicitSize: 18
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
                                                    
                                                    // Close window button
                                                    Item {
                                                        implicitWidth: 22
                                                        implicitHeight: 22
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
                                                
                                                // Live Window Preview
                                                StyledClippingRect {
                                                    Layout.fillWidth: true
                                                    Layout.fillHeight: true
                                                    color: Colours.tPalette.m3surfaceContainer
                                                    radius: Tokens.rounding.small
                                                    
                                                    ScreencopyView {
                                                        anchors.fill: parent
                                                        captureSource: windowCard.modelData.wayland ?? null
                                                        live: root.active && windowCard.visible
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
