pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.services

StyledRect {
    id: root

    property var bar: null

    readonly property color colour: Colours.palette.m3tertiary
    readonly property int padding: Config.bar.clock.background ? Tokens.padding.medium : Tokens.padding.extraSmall
    readonly property var font: Tokens.font.body.builders.small.scale(1.1)

    // Expand width dynamically to fit seconds and full French date string
    implicitWidth: layout.implicitWidth + Tokens.padding.medium * 2
    implicitHeight: Tokens.sizes.bar.innerWidth

    color: "transparent"
    radius: Tokens.rounding.full

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            if (!root.bar) return;
            const popouts = root.bar.popouts;
            if (popouts.hasCurrent && popouts.currentName === "calendar") {
                popouts.hasCurrent = false;
            } else {
                popouts.currentName = "calendar";
                popouts.hasCurrent = true;
            }
        }
    }

    RowLayout {
        id: layout
        spacing: Tokens.spacing.small
        anchors.centerIn: parent

        Loader {
            Layout.alignment: Qt.AlignVCenter
            asynchronous: true
            active: Config.bar.clock.showIcon
            visible: active

            sourceComponent: MaterialIcon {
                text: "calendar_month"
                color: root.colour
            }
        }

        StyledText {
            text: {
                const timePart = Time.format(GlobalConfig.services.useTwelveHourClock ? "hh:mm:ss AP" : "hh:mm:ss");
                const rawDate = Time.format("dddd d MMMM yyyy");
                const datePart = rawDate.charAt(0).toUpperCase() + rawDate.slice(1);
                return `${timePart}   •   ${datePart}`;
            }
            font: root.font.build()
            color: root.colour
            Layout.alignment: Qt.AlignVCenter
        }
    }
}
