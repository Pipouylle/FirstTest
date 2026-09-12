pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Caelestia.Config
import qs.modules.bar as Bar

Region {
    id: root

    required property Bar.BarWrapper bar
    required property Panels panels
    required property var win

    readonly property real borderThickness: win.contentItem.Config.border.thickness
    readonly property real clampedThickness: win.contentItem.Config.border.clampedThickness

    x: bar.clampedWidth + win.dragMaskPadding
    y: (bar.screenState.barIsTop ? 60 : clampedThickness) + win.dragMaskPadding
    width: win.width - bar.clampedWidth - clampedThickness - win.dragMaskPadding * 2
    height: win.height - (bar.screenState.barIsTop ? (60 + clampedThickness) : clampedThickness * 2) - win.dragMaskPadding * 2
    intersection: Intersection.Xor

    R {
        panel: root.panels.dashboard
        y: 0
        height: panel.height * (1 - root.panels.dashboard.offsetScale) + root.borderThickness
    }

    R {
        panel: root.panels.launcher
        y: root.win.height - height
        height: panel.height * (1 - root.panels.launcher.offsetScale) + root.borderThickness
    }

    R {
        id: sessionRegion

        panel: root.panels.sessionWrapper
        x: root.win.width - width
        width: panel.width * (1 - root.panels.session.offsetScale) + root.borderThickness + sidebarRegion.width
    }

    R {
        id: sidebarRegion

        panel: root.panels.sidebar
        x: root.win.width - width
        width: panel.width * (1 - root.panels.sidebar.offsetScale) + root.borderThickness
    }

    R {
        panel: root.panels.osdWrapper
        x: root.win.width - width
        width: panel.width * (1 - root.panels.osd.offsetScale) + root.borderThickness + sessionRegion.width
    }

    R {
        panel: root.panels.notifications
        y: 0
        height: panel.height + root.borderThickness
    }

    R {
        panel: root.panels.utilities
        y: root.win.height - height
        height: panel.height * (1 - root.panels.utilities.offsetScale) + root.borderThickness
    }

    R {
        panel: root.panels.popoutsWrapper
        width: panel.width * (1 - root.panels.popoutsWrapper.offsetScale)
    }

    // L'overview (SUPER+Tab) remplit tout le content area. Sans cette region il
    // n'est pas soustrait du masque d'input de la fenetre, donc les clics le
    // traversent et vont sur les fenetres derriere. Les autres panneaux se
    // replient a une taille nulle via offsetScale, l'overview lui garde sa
    // taille et joue seulement sur l'opacite : on gate donc sur visible.
    R {
        panel: root.panels.overview
        width: panel.visible ? panel.width : 0
        height: panel.visible ? panel.height : 0
    }

    component R: Region {
        required property Item panel

        x: panel.x + root.bar.implicitWidth
        y: panel.y + (root.bar.screenState.barIsTop ? 60 : root.borderThickness)
        width: panel.width
        height: panel.height
        intersection: Intersection.Subtract
    }
}
