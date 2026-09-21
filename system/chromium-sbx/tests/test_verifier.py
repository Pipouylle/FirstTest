"""Tests de keepass-tokens verifier et de la phrase anti-hameçonnage.

Copie du script avec une base de test (sans fichier clé) et saisie dans le terminal
(PINENTRY vide), dans un terminal simulé par script(1). systemd-run est remplacé.
Programme testé : $CHROMIUM_FICHIERS_BIN/keepass-tokens (par défaut ~/.local/bin).
"""
import os
import re
import shlex
import subprocess
import tempfile
import time
import unittest
from pathlib import Path

BIN = Path(os.environ.get("CHROMIUM_FICHIERS_BIN", Path.home() / ".local/bin"))
SCRIPT = BIN / "keepass-tokens"
MOT_DE_PASSE = "correct cheval pile agrafe"
FAUX_SYSTEMD_RUN = """#!/usr/bin/env bash
printf '%s\\n' "$*" >> "$(dirname "$0")/systemd-run.log"
"""


class Verifier(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory(dir="/tmp", prefix="verifier-")
        t = Path(cls.tmp.name)
        cls.base = t / "test.kdbx"
        subprocess.run(["keepassxc-cli", "db-create", "-p", "-t", "100", str(cls.base)],
                       input="%s\n%s\n" % (MOT_DE_PASSE, MOT_DE_PASSE), text=True, capture_output=True,
                       check=True, env=dict(os.environ, LC_ALL="C.UTF-8"))
        script = SCRIPT.read_text()
        for motif, remplacement in ((r"^DB=.*$", 'DB="%s"' % cls.base),
                                    (r"^KEY_FILE=.*$", 'KEY_FILE=""'),
                                    (r"^PINENTRY=.*$", 'PINENTRY=""')):
            script, n = re.subn(motif, remplacement, script, count=1, flags=re.M)
            assert n == 1, motif
        cls.copie = t / "keepass-tokens"
        cls.copie.write_text(script)
        cls.copie.chmod(0o755)
        cls.faux = t / "faux"
        cls.faux.mkdir()
        (cls.faux / "systemd-run").write_text(FAUX_SYSTEMD_RUN)
        (cls.faux / "systemd-run").chmod(0o755)

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def setUp(self):
        self.home = Path(tempfile.mkdtemp(dir=self.tmp.name))
        self.run = self.home / "run"
        self.run.mkdir()
        self.env = dict(os.environ, HOME=str(self.home), XDG_RUNTIME_DIR=str(self.run), SHELL="/bin/bash",
                        PATH="%s:%s" % (self.faux, os.environ["PATH"]))
        self.env.pop("WAYLAND_DISPLAY", None)
        self.env.pop("DISPLAY", None)

    def lancer(self, *args, saisie=""):
        """Lance la copie dans un terminal simulé ; renvoie (code, tout ce qui s'est affiché)."""
        commande = " ".join(shlex.quote(a) for a in (str(self.copie), *args))
        r = subprocess.run(["script", "-qec", commande, "/dev/null"], input=saisie, env=self.env,
                           capture_output=True, encoding="utf-8", errors="replace", timeout=60)
        return r.returncode, r.stdout + r.stderr

    def expiration(self):
        f = self.run / "secrets/chromium/expires"
        return int(f.read_text()) if f.exists() else None

    def test_bon_mot_de_passe_puis_delai(self):
        code, sortie = self.lancer("verifier", "chromium", saisie=MOT_DE_PASSE + "\n")
        self.assertEqual(code, 0, sortie)
        self.assertIn("Chromium demande un fichier", sortie)
        self.assertGreater(self.expiration(), time.time() + 500)
        code, sortie = self.lancer("verifier", "chromium")
        self.assertEqual(code, 0, sortie)
        self.assertNotIn("Mot de passe maître", sortie)

    def test_delai_expire(self):
        (self.run / "secrets/chromium").mkdir(parents=True)
        (self.run / "secrets/chromium/expires").write_text("0")
        code, sortie = self.lancer("verifier", "chromium", saisie=MOT_DE_PASSE + "\n")
        self.assertEqual(code, 0, sortie)
        self.assertIn("Mot de passe maître", sortie)

    def test_trois_mauvais_mots_de_passe(self):
        code, sortie = self.lancer("verifier", "chromium", saisie="faux1\nfaux2\nfaux3\n")
        self.assertEqual(code, 1, sortie)
        self.assertEqual(sortie.count("mot de passe incorrect"), 3, sortie)
        self.assertIsNone(self.expiration())

    def test_phrase(self):
        (self.home / ".config/keepass-tokens").mkdir(parents=True)
        (self.home / ".config/keepass-tokens/phrase").write_text("girafe violette 42\n")
        code, sortie = self.lancer("verifier", "chromium", saisie=MOT_DE_PASSE + "\n")
        self.assertEqual(code, 0, sortie)
        self.assertIn("Ta phrase : « girafe violette 42 »", sortie)

    def test_sans_phrase(self):
        code, sortie = self.lancer("verifier", "chromium", saisie=MOT_DE_PASSE + "\n")
        self.assertEqual(code, 0, sortie)
        self.assertIn("pas de phrase anti-hameçonnage", sortie)

    def test_noms_refuses(self):
        for nom in ("agy", "claude", "../x", "Chromium"):
            with self.subTest(nom=nom):
                code, sortie = self.lancer("verifier", nom)
                self.assertEqual(code, 1, sortie)
                self.assertIn("nom d'appli invalide", sortie)
