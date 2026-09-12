import QtQuick
import Quickshell
import Caelestia.Config
import qs.components
import qs.modules.bar.popouts // Need to import this module so the Wrapper type is the same as others

Item {
    id: root

    required property ShellScreen screen
    required property real borderThickness

    readonly property bool isCalendar: content.currentName === "calendar"
    readonly property alias content: content
    property real offsetScale: (isCalendar ? (y > 0) : (x > 0)) || content.hasCurrent ? 0 : 1

    visible: width > 0 && height > 0
    clip: true

    implicitWidth: isCalendar ? content.implicitWidth : (content.implicitWidth * (1 - offsetScale))
    implicitHeight: isCalendar ? (content.implicitHeight * (1 - offsetScale)) : content.implicitHeight

    x: {
        if (content.isDetached)
            return (parent.width - content.nonAnimWidth) / 2;
        if (isCalendar)
            return (parent.width - content.nonAnimWidth) / 2;
        return 0;
    }
    y: {
        if (content.isDetached)
            return (parent.height - content.nonAnimHeight) / 2;
        if (isCalendar)
            return Tokens.sizes.bar.innerWidth + Tokens.padding.large * 2;

        const off = content.currentCenter - borderThickness - content.nonAnimHeight / 2;
        const diff = parent.height - Math.floor(off + content.nonAnimHeight);
        if (diff < 0)
            return off + diff;
        return Math.max(off, 0);
    }

    Behavior on offsetScale {
        Anim {}
    }

    Behavior on x {
        Anim {
            duration: content.animLength
            easing: content.animCurve
        }
    }

    Behavior on y {
        enabled: root.offsetScale < 1

        Anim {
            duration: content.animLength
            easing: content.animCurve
        }
    }

    Wrapper {
        id: content

        screen: root.screen
        offsetScale: root.offsetScale

        anchors.verticalCenter: isCalendar ? undefined : parent.verticalCenter
        anchors.horizontalCenter: isCalendar ? parent.horizontalCenter : undefined
        anchors.left: isCalendar ? undefined : parent.left
        anchors.top: isCalendar ? parent.top : undefined

        anchors.leftMargin: isCalendar ? 0 : ((-implicitWidth - 5) * root.offsetScale)
        anchors.topMargin: isCalendar ? ((-implicitHeight - 5) * root.offsetScale) : 0
    }
}
