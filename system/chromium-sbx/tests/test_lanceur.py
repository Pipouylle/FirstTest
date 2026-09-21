"""Tests de ~/.local/bin/chromium-sbx (lanceur de session).

Le dossier de passage /run/chromium-sbx est remplacé par un dossier temporaire grâce à un
Bubblewrap imbriqué, et systemctl/sudo par de faux programmes : rien n'est démarré ni lancé.

Programme testé : $CHROMIUM_FICHIERS_BIN/chromium-sbx (par défaut ~/.local/bin).
"""
import os
import socket
import subprocess
import tempfile
import unittest
from pathlib import Path

BIN = Path(os.environ.get("CHROMIUM_FICHIERS_BIN", Path.home() / ".local/bin"))
SCRIPT = BIN / "chromium-sbx"

FAUX_SYSTEMCTL = """#!/usr/bin/env bash
printf '%s\\n' "$*" >> "$FAUX/systemctl.log"
"""
FAUX_SUDO = """#!/usr/bin/env bash
printf '%s\\n' "$*" >> "$FAUX/sudo.log"
"""


class Lanceur(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(dir="/tmp", prefix="lanceur-")
        t = Path(self.tmp.name)
        self.run, self.faux = t / "run", t / "faux"
        self.run.mkdir()
        self.faux.mkdir()
        for nom, contenu in (("systemctl", FAUX_SYSTEMCTL), ("sudo", FAUX_SUDO)):
            (self.faux / nom).write_text(contenu)
            (self.faux / nom).chmod(0o755)

    def tearDown(self):
        self.tmp.cleanup()

    def socket_factice(self, nom):
        s = socket.socket(socket.AF_UNIX)
        s.bind(str(self.run / nom))
        self.addCleanup(s.close)

    def lancer(self):
        """Lance chromium-sbx avec /run/chromium-sbx remplacé ; renvoie le processus terminé."""
        commande = ["bwrap", "--dev-bind", "/", "/", "--bind", str(self.run), "/run/chromium-sbx",
                    "--", "bash", str(SCRIPT), "about:blank"]
        env = dict(os.environ, FAUX=str(self.faux), PATH="%s:%s" % (self.faux, os.environ["PATH"]))
        return subprocess.run(commande, env=env, capture_output=True, encoding="utf-8",
                              errors="replace", timeout=60)

    def journal(self, nom):
        f = self.faux / nom
        return f.read_text(encoding="utf-8") if f.exists() else ""

    def test_demarre_le_son_et_previent_quand_il_manque(self):
        # Sans socket son, Chromium démarrerait muet jusqu'à sa fermeture complète :
        # le lanceur doit demander le service et le dire quand il n'arrive pas.
        self.socket_factice("wayland")
        self.socket_factice("bus")
        r = self.lancer()
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("pipewire-pulse", self.journal("systemctl.log"))
        self.assertIn("sans son", r.stderr)
        self.assertIn("chromium-sbx-inner", self.journal("sudo.log"))

    def test_rien_a_signaler_quand_le_son_est_la(self):
        for nom in ("wayland", "bus", "pulse"):
            self.socket_factice(nom)
        r = self.lancer()
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("pipewire-pulse", self.journal("systemctl.log"))
        self.assertNotIn("sans son", r.stderr)
        self.assertIn("chromium-sbx-inner", self.journal("sudo.log"))

    def test_demarre_toujours_les_services_de_passage(self):
        for nom in ("wayland", "bus", "pulse"):
            self.socket_factice(nom)
        self.lancer()
        journal = self.journal("systemctl.log")
        self.assertIn("chromium-sbx-wayland.service", journal)
        self.assertIn("chromium-sbx-dbus-relay.service", journal)
