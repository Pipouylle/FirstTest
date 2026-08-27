pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Services.Pipewire
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

Item {
    id: root

    required property PopoutState popouts

    implicitWidth: layout.implicitWidth + Tokens.padding.medium * 2
    implicitHeight: layout.implicitHeight + Tokens.padding.medium * 2

    Component.onCompleted: EasyEffects.refresh()

    ButtonGroup {
        id: sinks
    }

    ButtonGroup {
        id: sources
    }

    ColumnLayout {
        id: layout

        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: Tokens.spacing.medium

        StyledText {
            text: qsTr("EasyEffects")
            font: Tokens.font.body.builders.medium.weight(Font.Medium).build()
        }

        SwitchRow {
            Layout.minimumWidth: 260
            label: qsTr("Effets audio")
            checked: EasyEffects.active
            enabled: !EasyEffects.busy
            onToggled: checked => EasyEffects.setEnabled(checked)
        }

        StyledText {
            text: {
                if (!EasyEffects.running)
                    return qsTr("EasyEffects n'est pas lancé");
                return EasyEffects.bypassed ? qsTr("Bypass actif — son non traité") : qsTr("Effets appliqués");
            }
            color: Colours.palette.m3outline
            font: Tokens.font.body.small
        }

        StyledText {
            Layout.topMargin: Tokens.spacing.medium
            text: qsTr("Sortie audio")
            font: Tokens.font.body.builders.medium.weight(Font.Medium).build()
        }

        Repeater {
            model: Audio.sinks

            StyledRadioButton {
                required property PwNode modelData

                ButtonGroup.group: sinks
                checked: Audio.sink?.id === modelData.id
                onClicked: Audio.setAudioSink(modelData)
                text: modelData.description
            }
        }

        StyledText {
            Layout.topMargin: Tokens.spacing.medium
            text: qsTr("Entrée audio")
            font: Tokens.font.body.builders.medium.weight(Font.Medium).build()
        }

        Repeater {
            model: Audio.sources

            StyledRadioButton {
                required property PwNode modelData

                ButtonGroup.group: sources
                checked: Audio.source?.id === modelData.id
                onClicked: Audio.setAudioSource(modelData)
                text: modelData.description
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.medium
            spacing: Tokens.spacing.small

            IconTextButton {
                Layout.fillWidth: true
                inactiveColour: Colours.palette.m3primaryContainer
                inactiveOnColour: Colours.palette.m3onPrimaryContainer
                verticalPadding: Tokens.padding.extraSmall
                text: qsTr("Ouvrir EasyEffects")
                icon: "graphic_eq"

                onClicked: EasyEffects.openWindow()
            }

            IconTextButton {
                Layout.fillWidth: true
                inactiveColour: Colours.palette.m3secondaryContainer
                inactiveOnColour: Colours.palette.m3onSecondaryContainer
                verticalPadding: Tokens.padding.extraSmall
                text: qsTr("Mixer")
                icon: "tune"

                onClicked: root.popouts.detachRequested("audio")
            }
        }
    }
}
