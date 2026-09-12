pragma ComponentBehavior: Bound

import QtQuick
import M3Shapes
import Caelestia.Config
import qs.components
import qs.components.effects
import qs.components.images
import qs.services
import qs.utils

// Deliberately mirrors the surface of components/widgets/CoverArt.qml — size it,
// and reach its outline through `shape` — so the two are interchangeable inside
// the lock ring's centre.
Item {
    id: root

    property real implicitSize
    property string source: `${Paths.home}/.face`
    readonly property alias shape: shape
    readonly property color bgColour: Colours.tPalette.m3surfaceContainerHighest

    implicitWidth: implicitSize
    implicitHeight: implicitSize

    MaterialShape {
        id: shape

        anchors.centerIn: parent
        implicitSize: Math.min(root.width, root.height)

        shape: MaterialShape.Circle
        color: Qt.alpha(root.bgColour, 1)
        opacity: root.bgColour.a
        layer.enabled: true
    }

    MaterialIcon {
        anchors.centerIn: parent

        text: "person"
        color: Colours.palette.m3onSurfaceVariant
        // Same ratio CoverArt gives its own fallback glyph, so the two centres
        // read at the same weight when neither has an image.
        fontStyle: Tokens.font.icon.size((root.width * 0.35) || 1).build()
        visible: pfp.status !== Image.Ready
    }

    CachingImage {
        id: pfp

        anchors.fill: shape
        path: root.source

        layer.enabled: true
        layer.effect: Mask {
            maskSource: shape
        }
    }
}
