pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.Services
import Caelestia.Internal
import qs.components
import qs.components.controls
import qs.components.misc
import qs.services

StyledRect {
    id: root

    required property DrawerVisibilities visibilities
    property string section: "all" // "all", "left", "right"

    readonly property color cpuColor: Colours.palette.m3primary
    readonly property color gpuColor: Colours.palette.m3error
    readonly property color ramColor: Colours.palette.m3tertiary
    readonly property color storageColor: Colours.palette.m3secondary
    readonly property color netColor: Colours.palette.m3primary

    implicitWidth: layout.implicitWidth + Tokens.padding.medium * 2
    implicitHeight: Tokens.sizes.bar.innerWidth

    color: "transparent"

    ServiceRef {
        service: Cpu
    }

    ServiceRef {
        service: Memory
    }

    ServiceRef {
        service: Storage
    }

    ServiceRef {
        service: Gpu
    }

    Ref {
        service: NetworkUsage
    }

    RowLayout {
        id: layout

        anchors.centerIn: parent
        spacing: Tokens.spacing.large

        // CPU Metric (Usage + Temp)
        RowLayout {
            visible: root.section === "all" || root.section === "left"
            spacing: Tokens.spacing.small
            Layout.alignment: Qt.AlignVCenter

            CircularProgress {
                implicitSize: 26
                strokeWidth: 3
                value: Cpu.percentage
                fgColour: root.cpuColor
                bgColour: Qt.alpha(root.cpuColor, 0.15)

                MaterialIcon {
                    anchors.centerIn: parent
                    text: "memory"
                    fontStyle: Tokens.font.icon.builders.small.scale(0.85).build()
                    color: root.cpuColor
                }
            }

            StyledText {
                text: `${Math.round(Cpu.percentage * 100)}% (${Math.round(Cpu.temperature)}°C)`
                font: Tokens.font.body.builders.small.weight(Font.Medium).build()
                color: Colours.palette.m3onSurface
            }
        }

        // GPU Metric (Usage + Temp)
        RowLayout {
            visible: (root.section === "all" || root.section === "left") && Gpu.type !== Gpu.None
            spacing: Tokens.spacing.small
            Layout.alignment: Qt.AlignVCenter

            CircularProgress {
                implicitSize: 26
                strokeWidth: 3
                value: Gpu.percentage
                fgColour: root.gpuColor
                bgColour: Qt.alpha(root.gpuColor, 0.15)

                MaterialIcon {
                    anchors.centerIn: parent
                    text: "developer_board"
                    fontStyle: Tokens.font.icon.builders.small.scale(0.85).build()
                    color: root.gpuColor
                }
            }

            StyledText {
                text: `${Math.round(Gpu.percentage * 100)}% (${Math.round(Gpu.temperature)}°C)`
                font: Tokens.font.body.builders.small.weight(Font.Medium).build()
                color: Colours.palette.m3onSurface
            }
        }

        // RAM Metric
        RowLayout {
            visible: root.section === "all" || root.section === "right"
            spacing: Tokens.spacing.small
            Layout.alignment: Qt.AlignVCenter

            CircularProgress {
                implicitSize: 26
                strokeWidth: 3
                value: Memory.percentage
                fgColour: root.ramColor
                bgColour: Qt.alpha(root.ramColor, 0.15)

                MaterialIcon {
                    anchors.centerIn: parent
                    text: "memory_alt"
                    fontStyle: Tokens.font.icon.builders.small.scale(0.85).build()
                    color: root.ramColor
                }
            }

            StyledText {
                text: `${Math.round(Memory.percentage * 100)}%`
                font: Tokens.font.body.builders.small.weight(Font.Medium).build()
                color: Colours.palette.m3onSurface
            }
        }

        // Storage/Storage Metric
        RowLayout {
            visible: root.section === "all" || root.section === "right"
            spacing: Tokens.spacing.small
            Layout.alignment: Qt.AlignVCenter

            CircularProgress {
                implicitSize: 26
                strokeWidth: 3
                value: Storage.percentage
                fgColour: root.storageColor
                bgColour: Qt.alpha(root.storageColor, 0.15)

                MaterialIcon {
                    anchors.centerIn: parent
                    text: "hard_disk"
                    fontStyle: Tokens.font.icon.builders.small.scale(0.85).build()
                    color: root.storageColor
                }
            }

            StyledText {
                text: `${Math.round(Storage.percentage * 100)}%`
                font: Tokens.font.body.builders.small.weight(Font.Medium).build()
                color: Colours.palette.m3onSurface
            }
        }

        // Network Metric (Upload + Download speed)
        RowLayout {
            visible: root.section === "all" || root.section === "right"
            spacing: Tokens.spacing.small
            Layout.alignment: Qt.AlignVCenter

            StyledRect {
                implicitWidth: 26
                implicitHeight: 26
                radius: Tokens.rounding.full
                color: Qt.alpha(root.netColor, 0.15)

                MaterialIcon {
                    anchors.centerIn: parent
                    text: "swap_vert"
                    fontStyle: Tokens.font.icon.builders.small.scale(0.95).build()
                    color: root.netColor
                }
            }

            RowLayout {
                spacing: Tokens.spacing.medium
                Layout.alignment: Qt.AlignVCenter

                RowLayout {
                    spacing: 2
                    MaterialIcon {
                        text: "arrow_downward"
                        fontStyle: Tokens.font.icon.builders.small.scale(0.65).build()
                        color: Colours.palette.m3onSurfaceVariant
                    }
                    StyledText {
                        text: {
                            const fmt = NetworkUsage.formatBytes(NetworkUsage.downloadSpeed ?? 0);
                            return fmt ? `${fmt.value.toFixed(0)} ${fmt.unit}` : "0 B/s";
                        }
                        font: Tokens.font.body.builders.small.scale(0.85).weight(Font.Medium).build()
                        color: Colours.palette.m3onSurface
                    }
                }

                RowLayout {
                    spacing: 2
                    MaterialIcon {
                        text: "arrow_upward"
                        fontStyle: Tokens.font.icon.builders.small.scale(0.65).build()
                        color: Colours.palette.m3onSurfaceVariant
                    }
                    StyledText {
                        text: {
                            const fmt = NetworkUsage.formatBytes(NetworkUsage.uploadSpeed ?? 0);
                            return fmt ? `${fmt.value.toFixed(0)} ${fmt.unit}` : "0 B/s";
                        }
                        font: Tokens.font.body.builders.small.scale(0.85).weight(Font.Medium).build()
                        color: Colours.palette.m3onSurface
                    }
                }
            }
        }
    }
}
