pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// EasyEffects 8.x integration.
// `easyeffects --bypass 3` prints "1" when the global bypass is ON (effects off)
// and "2" when effects are active. Calling the CLI while no instance is running
// would spawn a full instance, so the state is only queried when a process exists.
Singleton {
    id: root

    // true when an easyeffects process is alive
    property bool running: false
    // true when the global bypass is enabled (effects are NOT applied)
    property bool bypassed: false
    // effects are actually processing audio
    readonly property bool active: running && !bypassed
    property bool busy: false

    function refresh(): void {
        if (Date.now() < suppressUntil)
            return;
        if (!stateProc.running)
            stateProc.running = true;
    }

    function setEnabled(enabled: bool): void {
        busy = true;
        if (enabled) {
            if (running) {
                Quickshell.execDetached(["easyeffects", "--bypass", "2"]);
            } else {
                // Start in service mode (no window), then disable bypass once it is up
                Quickshell.execDetached(["sh", "-c", "setsid easyeffects --hide-window >/dev/null 2>&1 & sleep 1.5; easyeffects --bypass 2"]);
            }
        } else {
            if (running)
                Quickshell.execDetached(["easyeffects", "--bypass", "1"]);
        }
        settleTimer.restart();
    }

    function toggle(): void {
        setEnabled(!active);
    }

    // Instant (ms) avant lequel aucune lecture d'etat ne doit avoir lieu. Couvre le delai
    // entre le lancement d'EasyEffects et l'apparition reelle de sa fenetre dans hyprctl.
    property double suppressUntil: 0

    function openWindow(): void {
        suppressUntil = Date.now() + 8000;
        Quickshell.execDetached(["easyeffects"]);
    }

    function quit(): void {
        if (running)
            Quickshell.execDetached(["easyeffects", "--quit"]);
        settleTimer.restart();
    }

    Process {
        id: stateProc

        // ATTENTION : `easyeffects --bypass 3` parle a l'instance en cours et, ce faisant,
        // MASQUE sa fenetre (journal systeme : easyeffects[...]: hidden "Easy Effects").
        // Sonder toutes les 5 s rendait donc l'application impossible a ouvrir : la fenetre
        // etait escamotee dans la seconde. On saute la lecture d'etat tant qu'une fenetre
        // est ouverte ; "skip" laisse l'etat connu inchange.
        command: ["sh", "-c", "if ! pgrep -x easyeffects >/dev/null; then echo off; elif hyprctl -j clients 2>/dev/null | grep -q com.github.wwmm.easyeffects; then echo skip; else easyeffects --bypass 3; fi"]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = text.trim();
                if (out === "skip") {
                    // Fenetre ouverte : on ne touche a rien pour ne pas la masquer.
                    root.busy = false;
                    return;
                }
                if (out === "off") {
                    root.running = false;
                    root.bypassed = false;
                } else {
                    root.running = true;
                    root.bypassed = out === "1";
                }
                root.busy = false;
            }
        }
    }

    // Re-read state shortly after an action (easyeffects needs a moment to apply)
    Timer {
        id: settleTimer

        interval: 2000
        onTriggered: root.refresh()
    }

    // Periodic sync in case the state is changed from the EasyEffects window
    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }
}
