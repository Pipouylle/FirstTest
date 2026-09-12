import "center"
import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.services

ColumnLayout {
    id: root

    required property var lock
    readonly property real centerScale: Math.min(1, (lock.screen?.height ?? 1440) / 1440)
    readonly property int centerWidth: Tokens.sizes.lock.centerWidth * centerScale

    Layout.preferredWidth: centerWidth
    Layout.fillWidth: false
    Layout.fillHeight: true

    spacing: Tokens.spacing.largeIncreased

    Clock {
        Layout.alignment: Qt.AlignHCenter
        Layout.topMargin: Tokens.padding.large
        centerScale: root.centerScale
    }

    StyledText {
        Layout.alignment: Qt.AlignHCenter

        text: Time.format("dddd • d MMM").toUpperCase()
        color: Colours.palette.m3onSurface
        font: Tokens.font.title.builders.medium.weight(Font.DemiBold).build()
    }

    // The profile picture used to sit here; it now lives inside the ring. These
    // two spacers take the height it freed and centre the ring / state message
    // pair in what is left under the clock and date, instead of letting the
    // whole column bunch up at the top. They collapse first on short screens.
    Item {
        Layout.fillHeight: true
    }

    SegmentedRing {
        Layout.alignment: Qt.AlignHCenter
        centerScale: Math.max(0.8, root.centerScale)
        centerWidth: root.centerWidth
        lock: root.lock
    }

    StateMessage {
        Layout.fillWidth: true
        pam: root.lock.pam
    }

    Item {
        Layout.fillHeight: true
    }
}
