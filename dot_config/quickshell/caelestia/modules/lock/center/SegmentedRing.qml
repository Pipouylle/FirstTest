pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import M3Shapes
import Caelestia.Config
import qs.components
import qs.components.widgets
import qs.services
import qs.modules.lock

Item {
    id: root

    required property real centerScale
    required property int centerWidth
    required property var lock

    // ─────────────────────────────────────────────────────────────────────
    //  The four constants that define the crown. Everything else is derived.
    // ─────────────────────────────────────────────────────────────────────
    //  N — how many arc pieces the crown is split into.
    property int segments: 7
    //  Radius of an arc piece at rest…
    readonly property real restRadius: activeRadius - travel
    //  …and once a keystroke has pushed it out.
    readonly property real activeRadius: ringSize / 2 - arcStroke / 2
    //  Distance kept between two neighbouring pieces, in PIXELS, not degrees.
    //  It is the same whatever the radius, which is exactly what forces a
    //  piece to grow as it slides outwards:
    //      arc length = 2*PI*r/N - gap
    //      angular opening = 2*PI/N - gap/r
    readonly property real gap: Math.max(Tokens.spacing.extraSmall, Math.round(ringSize / 18))

    // The angular opening of `gap` for a piece sitting at radius r, in degrees.
    // The round caps stick out by half a stroke at each end, so the stroke is
    // folded in here and `gap` stays the gap the eye actually measures.
    function gapDegrees(r: real): real {
        return ((gap + arcStroke) / (r || 1)) * (180 / Math.PI);
    }

    // No idle token exists for the lock, so it lives here as a tweakable knob.
    property int idleTimeout: 5000

    // Cover art in the middle while a player is around, the user's profile
    // picture otherwise. Overridable so the centre can be driven without a
    // player.
    property bool showCover: !!Players.active

    // Every length below is a fraction of ringSize, so growing the ring grows the
    // whole drawing at the proportions that were validated at the smaller size,
    // instead of leaving thin strokes on a big circle. The Tokens floors only
    // ever bite on very short screens.
    // Diameter as a fraction of the centre column. 0.70 is the measured ceiling
    // that still leaves 54 px of slack at 1080p with a two-line error message
    // (the worst real case, and the one that dimensions the column); it is also
    // exactly the footprint the profile picture used to take in the column
    // before it moved inside the ring.
    property real sizeFactor: 0.70
    readonly property real ringSize: Math.round(centerWidth * sizeFactor)
    readonly property real arcStroke: Math.max(Tokens.padding.extraSmall, Math.round(ringSize / 18))
    readonly property real travel: Math.max(Tokens.spacing.small, Math.round(ringSize / 11))
    readonly property real segmentAngle: 360 / segments

    // The thick circle the crown revolves around, and the room left inside it
    // for the cover art / profile picture.
    readonly property real centreStroke: Math.max(Tokens.padding.small, Math.round(ringSize / 11))
    readonly property real centreGap: Math.max(Tokens.spacing.extraSmall, Math.round(ringSize / 18))
    readonly property real centreRadius: restRadius - arcStroke / 2 - centreGap - centreStroke / 2
    readonly property real centreInner: (centreRadius - centreStroke / 2) * 2

    // Single source of truth: which pieces are out is derived from the pam
    // buffer, never from a counter of our own. With `segments` = 7 a new turn
    // therefore starts on the 8th character.
    readonly property int bufLen: lock.pam.buffer.length
    readonly property int turn: bufLen === 0 ? 0 : Math.floor((bufLen - 1) / segments)
    readonly property int outCount: bufLen === 0 ? 0 : ((bufLen - 1) % segments) + 1

    // The random draw *is* memorised: `order` is only rebuilt when a new turn
    // starts, so a repaint never reshuffles the pieces.
    property var order: []
    readonly property var outMask: {
        const mask = new Array(segments).fill(false);
        for (let i = 0; i < outCount && i < order.length; i++)
            mask[order[i]] = true;
        return mask;
    }

    property bool errorFlash
    readonly property bool succeeded: lock.unlocking

    // Read here rather than inside ShakeStep: Tokens is an attached property and
    // only resolves its screen on an Item, not on a NumberAnimation.
    readonly property real shakeWide: Math.round(Tokens.spacing.medium * centerScale)
    readonly property real shakeNarrow: Math.round(Tokens.spacing.extraSmall * centerScale)

    // Movement says "a key was struck"; colour is kept for the two outcomes.
    readonly property color arcColour: {
        if (succeeded)
            return Colours.palette.m3success;
        if (errorFlash)
            return Colours.palette.m3error;
        return Colours.palette.m3primary;
    }

    function shuffle(): void {
        const o = [];
        for (let i = 0; i < segments; i++)
            o.push(i);
        for (let i = o.length - 1; i > 0; i--) {
            const j = Math.floor(Math.random() * (i + 1));
            [o[i], o[j]] = [o[j], o[i]];
        }
        order = o;
    }

    function clearError(): void {
        failAnim.stop();
        errorFlash = false;
        shake.x = 0;
    }

    function reset(): void {
        lock.pam.buffer = "";
    }

    Component.onCompleted: shuffle()
    onSegmentsChanged: shuffle()
    onTurnChanged: shuffle()
    onBufLenChanged: {
        if (bufLen === 0) {
            idleReset.stop();
            shuffle();
        } else {
            clearError();
            idleReset.restart();
        }
    }

    implicitWidth: ringSize
    implicitHeight: ringSize

    // Focus contract, kept as-is from center/PasswordInput.qml: this item owns
    // the keyboard and grabs it back if anything steals it.
    focus: true
    onActiveFocusChanged: {
        if (!activeFocus)
            forceActiveFocus();
    }

    Keys.onPressed: event => {
        if (root.lock.unlocking)
            return;

        // handleKey drops control characters, so Ctrl+C has to be caught here.
        if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_C) {
            root.reset();
            root.clearError();
            event.accepted = true;
            return;
        }

        idleReset.restart();
        root.lock.pam.handleKey(event);
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.forceActiveFocus()
    }

    Timer {
        id: idleReset

        interval: root.idleTimeout
        onTriggered: {
            if (!root.lock.unlocking)
                root.reset();
        }
    }

    Connections {
        function onStateChanged(): void {
            const s = root.lock.pam.state;
            if (s === Pam.Error || s === Pam.Failed || s === Pam.MaxTries)
                failAnim.restart();
        }

        target: root.lock.pam
    }

    // Everything that shakes together lives in here. Extra decoration around
    // the crown goes in as a sibling of `crown` / `centre`.
    Item {
        id: ring

        anchors.centerIn: parent
        implicitWidth: root.ringSize
        implicitHeight: root.ringSize

        transform: Translate {
            id: shake
        }

        // The thick circle the crown sits around.
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            asynchronous: true

            ShapePath {
                fillColor: "transparent"
                strokeColor: Colours.palette.m3outlineVariant
                strokeWidth: root.centreStroke
                capStyle: ShapePath.FlatCap

                PathAngleArc {
                    radiusX: root.centreRadius
                    radiusY: root.centreRadius
                    centerX: root.ringSize / 2
                    centerY: root.ringSize / 2
                    startAngle: -90
                    sweepAngle: 360
                }

                Behavior on strokeColor {
                    CAnim {}
                }
            }
        }

        Repeater {
            id: crown

            model: root.segments

            Shape {
                id: seg

                required property int index
                readonly property bool out: root.succeeded || root.errorFlash || (root.outMask[index] ?? false)

                // The only thing a keystroke animates: how far the piece sits
                // from the centre. Its angular opening follows from the radius,
                // which is what keeps the pixel gap constant.
                property real radius: out ? root.activeRadius : root.restRadius
                readonly property real gapAngle: root.gapDegrees(radius)

                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                asynchronous: true

                Behavior on radius {
                    Anim {
                        type: Anim.FastSpatial
                    }
                }

                ShapePath {
                    fillColor: "transparent"
                    strokeColor: root.arcColour
                    strokeWidth: root.arcStroke
                    capStyle: ShapePath.RoundCap

                    PathAngleArc {
                        radiusX: seg.radius
                        radiusY: seg.radius
                        centerX: root.ringSize / 2
                        centerY: root.ringSize / 2
                        // Piece 0 starts half a gap clockwise of 12 o'clock, so
                        // the crown is mirror symmetric about the vertical axis
                        // and the wrap-around gap is as wide as all the others.
                        startAngle: -90 + seg.gapAngle / 2 + seg.index * root.segmentAngle
                        sweepAngle: root.segmentAngle - seg.gapAngle
                    }

                    Behavior on strokeColor {
                        CAnim {}
                    }
                }
            }
        }

        // Cover art while something is playing, profile picture otherwise.
        AnimLoader {
            id: centre

            anchors.centerIn: parent
            sourceComp: root.showCover ? coverComp : pfpComp
        }
    }

    Component {
        id: coverComp

        CoverArt {
            implicitWidth: root.centreInner
            implicitHeight: root.centreInner
            shape.shape: MaterialShape.Circle
        }
    }

    Component {
        id: pfpComp

        ProfilePic {
            implicitSize: root.centreInner
            shape.shape: MaterialShape.Circle
        }
    }

    SequentialAnimation {
        id: failAnim

        PropertyAction {
            target: root
            property: "errorFlash"
            value: true
        }
        ShakeStep {
            to: root.shakeWide
        }
        ShakeStep {
            to: -root.shakeWide
        }
        ShakeStep {
            to: root.shakeNarrow
        }
        ShakeStep {
            to: -root.shakeNarrow
        }
        ShakeStep {
            to: 0
        }
        PauseAnimation {
            duration: Tokens.anim.durations.large
        }
        PropertyAction {
            target: root
            property: "errorFlash"
            value: false
        }
    }

    component ShakeStep: Anim {
        target: shake
        property: "x"
        duration: Tokens.anim.durations.small / 3
        easing: Tokens.anim.standard
    }
}
