"""Tests de chromium-sbx-fichiers, sans session graphique (faux zenity, keepass-tokens, systemd-run).

Programme testé : $CHROMIUM_FICHIERS_BIN/chromium-sbx-fichiers (par défaut ~/.local/bin).
"""
import os
import socket
import stat
import subprocess
import tempfile
import time
import unittest
from pathlib import Path

BIN = Path(os.environ.get("CHROMIUM_FICHIERS_BIN", Path.home() / ".local/bin"))
SCRIPT = BIN / "chromium-sbx-fichiers"

FAUX_ZENITY = """#!/usr/bin/env bash
printf '%s\\n' "$*" >> "$FAUX/zenity.log"
case $1 in
    --file-selection) [[ -f $FAUX/choix ]] || exit 1; cat "$FAUX/choix" ;;
    --question) exit "$(cat "$FAUX/question.rc" 2>/dev/null || echo 0)" ;;
esac
exit 0
"""
FAUX_KEEPASS = """#!/usr/bin/env bash
printf '%s\\n' "$*" >> "$FAUX/keepass.log"
exit "$(cat "$FAUX/keepass.rc" 2>/dev/null || echo 0)"
"""
FAUX_SYSTEMD_RUN = """#!/usr/bin/env bash
printf '%s\\n' "$*" >> "$FAUX/systemd-run.log"
"""


class Fichiers(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(dir="/tmp", prefix="fichiers-")
        t = Path(self.tmp.name)
        self.home, self.run, self.envois, self.dl, self.faux = (
            t / "home", t / "run", t / "envois", t / "dl", t / "faux")
        for dossier in (self.home, self.run, self.envois, self.dl, self.faux):
            dossier.mkdir()
        for nom, contenu in (("zenity", FAUX_ZENITY), ("keepass-tokens", FAUX_KEEPASS),
                             ("systemd-run", FAUX_SYSTEMD_RUN)):
            (self.faux / nom).write_text(contenu)
            (self.faux / nom).chmod(0o755)
        self.fichier(".ssh/id_ed25519", "clé privée")
        # WAYLAND_DISPLAY : le service relais en a un ; sans lui, « ouvrir » refuse de commencer
        self.env = dict(os.environ, HOME=str(self.home), XDG_RUNTIME_DIR=str(self.run), FAUX=str(self.faux),
                        WAYLAND_DISPLAY="wayland-test",
                        CSF_ENVOIS=str(self.envois), CSF_DOWNLOADS=str(self.dl),
                        CSF_KEEPASS_TOKENS=str(self.faux / "keepass-tokens"),
                        CSF_ZENITY=str(self.faux / "zenity"), CSF_SYSTEMD_RUN=str(self.faux / "systemd-run"))

    def tearDown(self):
        self.tmp.cleanup()

    def fichier(self, relatif, contenu="contenu"):
        f = self.home / relatif
        f.parent.mkdir(parents=True, exist_ok=True)
        f.write_text(contenu, encoding="utf-8")
        return f

    def lancer(self, *args, choix=None, cwd=None, env=None):
        if choix is not None:
            (self.faux / "choix").write_text("".join("%s\n" % c for c in choix), encoding="utf-8")
        return subprocess.run(["bash", str(SCRIPT), *args], env=env or self.env, cwd=cwd, capture_output=True,
                              encoding="utf-8", errors="replace", timeout=30)

    def journal(self, nom):
        f = self.faux / nom
        return f.read_text(encoding="utf-8") if f.exists() else ""

    def copies(self):
        return sorted(p.name for p in self.envois.iterdir())

    def test_fichier_simple(self):
        f = self.fichier("Documents/facture.pdf", "PDF")
        r = self.lancer("ouvrir", choix=[f])
        self.assertEqual(r.returncode, 0, r.stderr)
        [ident] = self.copies()
        self.assertRegex(ident, r"^[0-9a-f]{32}$")
        copie = self.envois / ident / "1" / "facture.pdf"
        self.assertEqual(r.stdout, "file://%s\n" % copie)
        self.assertEqual(copie.read_text(), "PDF")
        self.assertEqual(stat.S_IMODE((self.envois / ident).stat().st_mode), 0o750)
        self.assertEqual(stat.S_IMODE(copie.stat().st_mode), 0o640)
        self.assertEqual(self.journal("keepass.log"), "verifier chromium\n")
        zenity = self.journal("zenity.log")
        self.assertIn("--file-selection", zenity)
        self.assertIn("--timeout=600", zenity)
        self.assertNotIn("--multiple", zenity)
        self.assertIn("--on-active=3600", self.journal("systemd-run.log"))
        self.assertIn("supprimer %s" % ident, self.journal("systemd-run.log"))
        self.assertEqual((self.run / "chromium-sbx-fichiers/dernier-dossier").read_text().strip(), str(f.parent))

    def test_plusieurs_fichiers_de_meme_nom(self):
        a = self.fichier("a/x.txt", "A")
        b = self.fichier("b/x.txt", "B")
        r = self.lancer("ouvrir", "--multiple", choix=[a, b])
        self.assertEqual(r.returncode, 0, r.stderr)
        [ident] = self.copies()
        base = self.envois / ident
        self.assertEqual(r.stdout.splitlines(), ["file://%s/1/x.txt" % base, "file://%s/2/x.txt" % base])
        self.assertEqual((base / "1/x.txt").read_text(), "A")
        self.assertEqual((base / "2/x.txt").read_text(), "B")
        self.assertIn("--multiple", self.journal("zenity.log"))

    def test_mode_simple_refuse_plusieurs_chemins(self):
        # Sans --multiple, zenity ne devrait rendre qu'un chemin ; s'il en rend plusieurs
        # (nom avec saut de ligne ?), toute la sélection est refusée avant résolution.
        a = self.fichier("a/x.txt", "A")
        b = self.fichier("b/x.txt", "B")
        r = self.lancer("ouvrir", choix=[a, b])
        self.assertEqual(r.returncode, 1, r.stderr)
        self.assertEqual(self.copies(), [])
        self.assertIn("sélection inattendue", r.stderr)
        self.assertIn("--error", self.journal("zenity.log"))

    def test_dossier_et_liens(self):
        self.fichier("Projet/notes.txt", "notes")
        self.fichier("Projet/sous/plan.txt", "plan")
        (self.home / "Projet/cle").symlink_to(self.home / ".ssh/id_ed25519")
        r = self.lancer("ouvrir", "--dossier", choix=[self.home / "Projet"])
        self.assertEqual(r.returncode, 0, r.stderr)
        [ident] = self.copies()
        copie = self.envois / ident / "1" / "Projet"
        self.assertEqual(r.stdout, "file://%s\n" % copie)
        self.assertEqual((copie / "sous/plan.txt").read_text(), "plan")
        self.assertTrue((copie / "cle").is_symlink())
        self.assertEqual(os.readlink(copie / "cle"), str(self.home / ".ssh/id_ed25519"))
        self.assertIn("--directory", self.journal("zenity.log"))
        for chemin in copie.rglob("*"):
            if not chemin.is_symlink():
                attendu = 0o050 if chemin.is_dir() else 0o040
                self.assertEqual(stat.S_IMODE(chemin.stat().st_mode) & 0o077, attendu, chemin)

    def test_refus(self):
        (self.home / "raccourci").symlink_to(self.home / ".ssh/id_ed25519")
        base_kdbx = self.fichier("Docs/base.kdbx")
        self.fichier("Sauvegardes/vieille.KDBX")
        dossier_socket = self.home / "Sockets"
        dossier_socket.mkdir()
        s = socket.socket(socket.AF_UNIX)
        s.bind(str(dossier_socket / "s"))
        self.addCleanup(s.close)
        jeton = self.run / "jeton"
        jeton.write_text("secret")
        (self.home / "a\nb.txt").write_text("x")
        cas = {
            "clé ssh": [self.home / ".ssh/id_ed25519"],
            "lien vers la clé": [self.home / "raccourci"],
            "home entier": [self.home],
            "base kdbx": [base_kdbx],
            "dossier avec kdbx": [self.home / "Sauvegardes"],
            "dossier avec socket": [dossier_socket],
            "runtime": [jeton],
            "introuvable": [self.home / "absent.txt"],
            "saut de ligne": [self.home / "a\nb.txt"],
            "un bon et un mauvais": [self.fichier("ok.txt"), self.home / ".ssh"],
            "historique du shell": [self.fichier(".zsh_history", "commandes")],
            "identifiants git": [self.fichier(".git-credentials", "https://x:y@z")],
            "config gh": [self.fichier(".config/gh/hosts.yml", "oauth_token: x")],
            "netrc": [self.fichier(".netrc", "machine x password y")],
        }
        for nom, choix in cas.items():
            with self.subTest(nom):
                (self.faux / "zenity.log").unlink(missing_ok=True)
                r = self.lancer("ouvrir", "--multiple", choix=choix)
                self.assertEqual(r.returncode, 1, r.stderr)
                self.assertEqual(self.copies(), [])
                self.assertIn("--error", self.journal("zenity.log"))

    # Les téléchargements de Chromium sont une zone hostile : il y écrit ce qu'il veut, liens
    # symboliques compris. Rien de ce qui en vient n'est copié, et rien n'en sort.
    def test_telechargements_lien_qui_sort_refuse(self):
        cible = self.fichier("Documents/public.txt", "rien de secret")
        (self.dl / "facture.pdf").symlink_to(cible)
        r = self.lancer("ouvrir", choix=[self.dl / "facture.pdf"])
        self.assertEqual(r.returncode, 1, r.stderr)
        self.assertEqual(self.copies(), [])
        self.assertIn("lien qui sort des téléchargements", r.stderr)
        self.assertIn("--error", self.journal("zenity.log"))

    def test_telechargements_fichier_rendu_en_place(self):
        (self.dl / "reçu.pdf").write_text("PDF", encoding="utf-8")
        r = self.lancer("ouvrir", choix=[self.dl / "reçu.pdf"])
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(r.stdout, "file:///var/lib/chromium-sbx/Downloads/re%C3%A7u.pdf\n")
        self.assertEqual(self.copies(), [])                    # Chromium le lit déjà lui-même
        self.assertEqual(self.journal("systemd-run.log"), "")

    def test_telechargements_selection_mixte(self):
        (self.dl / "reçu.pdf").write_text("PDF", encoding="utf-8")
        f = self.fichier("Documents/note.txt", "N")
        r = self.lancer("ouvrir", "--multiple", choix=[self.dl / "reçu.pdf", f])
        self.assertEqual(r.returncode, 0, r.stderr)
        [ident] = self.copies()
        self.assertEqual(r.stdout.splitlines(), [                     # même ordre que les choix
            "file:///var/lib/chromium-sbx/Downloads/re%C3%A7u.pdf",
            "file://%s/1/note.txt" % (self.envois / ident)])
        self.assertEqual((self.envois / ident / "1/note.txt").read_text(), "N")
        self.assertEqual([p.name for p in (self.envois / ident).iterdir()], ["1"])

    # $DOWNLOADS est modifiable par Chromium : le sélecteur ne doit jamais s'y rouvrir par défaut.
    def test_dernier_dossier_jamais_dans_downloads(self):
        (self.dl / "reçu.pdf").write_text("PDF", encoding="utf-8")
        r = self.lancer("ouvrir", choix=[self.dl / "reçu.pdf"])
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertFalse((self.run / "chromium-sbx-fichiers/dernier-dossier").exists())

    def test_dernier_dossier_selection_mixte_retient_le_home(self):
        (self.dl / "reçu.pdf").write_text("PDF", encoding="utf-8")
        f = self.fichier("Documents/note.txt", "N")
        r = self.lancer("ouvrir", "--multiple", choix=[self.dl / "reçu.pdf", f])
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual((self.run / "chromium-sbx-fichiers/dernier-dossier").read_text().strip(), str(f.parent))

    def test_lien_vers_les_telechargements_refuse(self):
        (self.dl / "reçu.pdf").write_text("PDF", encoding="utf-8")
        (self.home / "raccourci.pdf").symlink_to(self.dl / "reçu.pdf")
        r = self.lancer("ouvrir", choix=[self.home / "raccourci.pdf"])
        self.assertEqual(r.returncode, 1, r.stderr)
        self.assertEqual(self.copies(), [])
        self.assertIn("lien vers les téléchargements", r.stderr)
        self.assertIn("--error", self.journal("zenity.log"))

    def test_fragment_relatif_refuse(self):
        # Un nom qui contient un saut de ligne coupe la sortie de zenity en deux ; le second
        # morceau est relatif et serait résolu depuis le dossier courant du service ($HOME).
        self.fichier("a", "premier")
        self.fichier("b.txt", "à ne pas copier")
        r = self.lancer("ouvrir", "--multiple", choix=[self.home / "a", "b.txt"], cwd=str(self.home))
        self.assertEqual(r.returncode, 1, r.stderr)
        self.assertEqual(self.copies(), [])
        self.assertIn("chemin relatif inattendu", r.stderr)
        self.assertIn("--error", self.journal("zenity.log"))

    def test_selecteur_indisponible(self):
        f = self.fichier("doc.txt")
        with self.subTest("sans session graphique"):
            r = self.lancer("ouvrir", choix=[f], env=dict(self.env, WAYLAND_DISPLAY="", DISPLAY=""))
            self.assertEqual(r.returncode, 2, r.stderr)
            self.assertIn("sélecteur indisponible", r.stderr)
            self.assertIn("journalctl", r.stderr)
        with self.subTest("zenity introuvable"):
            r = self.lancer("ouvrir", choix=[f], env=dict(self.env, CSF_ZENITY=str(self.faux / "absent")))
            self.assertEqual(r.returncode, 2, r.stderr)
            self.assertIn("sélecteur indisponible", r.stderr)
        self.assertEqual(self.copies(), [])
        self.assertEqual(self.journal("keepass.log"), "")

    def test_annulations(self):
        f = self.fichier("doc.txt", "x" * 100)
        with self.subTest("mot de passe refusé"):
            (self.faux / "keepass.rc").write_text("1")
            r = self.lancer("ouvrir", choix=[f])
            self.assertEqual(r.returncode, 1)
            self.assertNotIn("--file-selection", self.journal("zenity.log"))
            (self.faux / "keepass.rc").unlink()
        with self.subTest("sélection annulée"):
            (self.faux / "choix").unlink(missing_ok=True)
            self.assertEqual(self.lancer("ouvrir").returncode, 1)
        with self.subTest("taille refusée"):
            self.env["CSF_CONFIRM_BYTES"] = "10"
            (self.faux / "question.rc").write_text("1")
            r = self.lancer("ouvrir", choix=[f])
            self.assertEqual(r.returncode, 1)
            self.assertIn("--question", self.journal("zenity.log"))
        self.assertEqual(self.copies(), [])
        with self.subTest("taille acceptée"):
            (self.faux / "question.rc").write_text("0")
            r = self.lancer("ouvrir", choix=[f])
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertEqual(len(self.copies()), 1)

    def test_enregistrer(self):
        prefixe = "file:///var/lib/chromium-sbx/Downloads/"

        def nom(propose):
            r = self.lancer("enregistrer", propose)
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertTrue(r.stdout.startswith(prefixe), r.stdout)
            return r.stdout[len(prefixe):].rstrip("\n")

        self.assertEqual(nom("rapport.pdf"), "rapport.pdf")
        (self.dl / "rapport.pdf").write_text("x")
        self.assertEqual(nom("rapport.pdf"), "rapport%20%281%29.pdf")
        (self.dl / "rapport (1).pdf").write_text("x")
        self.assertEqual(nom("rapport.pdf"), "rapport%20%282%29.pdf")
        self.assertEqual(nom("../../etc/passwd"), "passwd")
        self.assertEqual(nom(""), "t%C3%A9l%C3%A9chargement")
        self.assertEqual(nom(".."), "t%C3%A9l%C3%A9chargement")
        self.assertEqual(nom("a\x01b.txt"), "ab.txt")
        (self.dl / ".bashrc").write_text("x")
        self.assertEqual(nom(".bashrc"), ".bashrc%20%281%29")
        self.assertEqual(self.journal("zenity.log"), "")
        self.assertEqual(self.journal("keepass.log"), "")

    def test_encodage(self):
        f = self.fichier("été à 100%#?.txt")
        r = self.lancer("ouvrir", choix=[f])
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertTrue(r.stdout.rstrip("\n").endswith("/1/%C3%A9t%C3%A9%20%C3%A0%20100%25%23%3F.txt"), r.stdout)

    def test_purger_et_supprimer(self):
        vieux, recent = "a" * 32, "b" * 32
        for nom in (vieux, recent, "autre"):
            (self.envois / nom).mkdir()
        il_y_a_2h = time.time() - 7200
        for nom in (vieux, "autre"):
            os.utime(self.envois / nom, (il_y_a_2h, il_y_a_2h))
        self.assertEqual(self.lancer("purger").returncode, 0)
        self.assertEqual(self.copies(), ["autre", recent])
        # minuteur réarmé pour ce qui survit (il est perdu à chaque redémarrage)
        self.assertIn("supprimer %s" % recent, self.journal("systemd-run.log"))
        self.assertNotIn("supprimer autre", self.journal("systemd-run.log"))
        self.assertEqual(self.lancer("supprimer", "../x").returncode, 2)
        self.assertEqual(self.lancer("supprimer", recent).returncode, 0)
        self.assertEqual(self.copies(), ["autre"])

    def test_copier(self):
        f = self.fichier("note.txt", "n")
        r = self.lancer("copier", str(f))
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(len(self.copies()), 1)
        r = self.lancer("copier", str(self.home / ".ssh"))
        self.assertEqual(r.returncode, 1)
        self.assertIn("chemin sensible", r.stderr)
        self.assertEqual(self.journal("zenity.log"), "")
        self.assertEqual(self.journal("keepass.log"), "")
