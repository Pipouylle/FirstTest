"""Tests de dbus-uid-relay : bus D-Bus privé, faux portail, client dbus-python (libdbus, comme Chromium).

Programme testé : $CHROMIUM_FICHIERS_BIN/dbus-uid-relay (par défaut ~/.local/bin).
"""
import os
import socket
import subprocess
import sys
import tempfile
import time
import unittest
import uuid
from pathlib import Path

import dbus
import dbus.bus
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib
from jeepney import DBusAddress, HeaderFields, new_method_call
from jeepney.bus_messages import message_bus
from jeepney.low_level import Parser

ICI = Path(__file__).resolve().parent
BIN = Path(os.environ.get("CHROMIUM_FICHIERS_BIN", Path.home() / ".local/bin"))
RELAIS = BIN / "dbus-uid-relay"
FAUX_PORTAIL = ICI / "faux_portail.py"
PORTAIL = "org.freedesktop.portal.Desktop"
CHEMIN_PORTAIL = "/org/freedesktop/portal/desktop"

CONFIG_BUS = """<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>
  <type>session</type>
  <listen>unix:path={socket}</listen>
  <auth>EXTERNAL</auth>
  <policy context="default">
    <allow send_destination="*" eavesdrop="true"/>
    <allow eavesdrop="true"/>
    <allow own="*"/>
  </policy>
</busconfig>
"""

# Faux programme de sélection : note ses arguments et son pid, puis suit le fichier « mode »
FAUX_SELECTEUR = """#!/usr/bin/env bash
d=$(dirname "$0")
printf '%s\\n' "$@" > "$d/args"
echo $$ > "$d/pid"
case $(cat "$d/mode" 2>/dev/null) in
    ok)     printf '%s\\n' 'file:///srv/chromium-sbx/Envois/abc/1/%C3%A9t%C3%A9%20100%25.pdf' \\
                           'file:///srv/chromium-sbx/Envois/abc/2/b.txt'
            exit 0 ;;
    annule) exit 1 ;;
    erreur) exit 3 ;;
    dort)   exec sleep 60 ;;
esac
exit 2
"""


def attendre(condition, delai=10.0):
    """Fait tourner la boucle GLib (signaux dbus-python) jusqu'à condition() ou la fin du délai."""
    contexte = GLib.MainContext.default()
    fin = time.monotonic() + delai
    while not condition():
        if time.monotonic() > fin:
            return False
        while contexte.pending():
            contexte.iteration(False)
        time.sleep(0.01)
    return True


def connexion_brute(chemin):
    """Socket authentifié auprès du relais, sans bibliothèque D-Bus."""
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(10)
    s.connect(str(chemin))
    s.sendall(b"\0AUTH EXTERNAL " + str(os.getuid()).encode().hex().encode() + b"\r\n")
    if not s.recv(4096).startswith(b"OK "):
        raise AssertionError("authentification refusée par le relais")
    s.sendall(b"BEGIN\r\n")
    return s


class BaseRelais(unittest.TestCase):
    """Bus privé et faux portail pour toute la classe ; un relais neuf par test."""

    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory(dir="/tmp", prefix="relais-")
        cls.dossier = Path(cls.tmp.name)
        socket_bus = cls.dossier / "bus"
        (cls.dossier / "bus.conf").write_text(CONFIG_BUS.format(socket=socket_bus))
        cls.bus = subprocess.Popen(["dbus-daemon", "--config-file", str(cls.dossier / "bus.conf"), "--nofork"])
        for _ in range(100):
            if socket_bus.exists():
                break
            time.sleep(0.05)
        cls.env = dict(os.environ, DBUS_SESSION_BUS_ADDRESS="unix:path=%s" % socket_bus)
        cls.portail = subprocess.Popen([sys.executable, str(FAUX_PORTAIL)], env=cls.env,
                                       stdout=subprocess.PIPE, text=True)
        cls.nom_portail = cls.portail.stdout.readline().strip()
        cls.selecteur = cls.dossier / "selecteur"
        cls.selecteur.write_text(FAUX_SELECTEUR)
        cls.selecteur.chmod(0o755)

    @classmethod
    def tearDownClass(cls):
        cls.portail.kill()
        cls.portail.wait()
        cls.portail.stdout.close()
        cls.bus.kill()
        cls.bus.wait()
        cls.tmp.cleanup()

    def options(self):
        return []

    def setUp(self):
        self.socket_relais = self.dossier / ("r-%s" % uuid.uuid4().hex[:8])
        self.journal_relais = self.dossier / ("%s.log" % self.socket_relais.name)
        with open(self.journal_relais, "w") as journal:
            self.relais = subprocess.Popen(
                [sys.executable, str(RELAIS), *self.options(), str(self.socket_relais), str(self.dossier / "bus")],
                env=self.env, stdout=subprocess.PIPE, stderr=journal, text=True)
        ligne = self.relais.stdout.readline()
        self.assertTrue(ligne.startswith("prêt"), "relais non démarré : %r\n%s" % (ligne, self.journal_relais.read_text()))
        self.connexions = []

    def tearDown(self):
        for connexion in self.connexions:
            connexion.close()
        self.relais.terminate()
        self.relais.communicate(timeout=5)

    def client(self):
        connexion = dbus.bus.BusConnection("unix:path=%s" % self.socket_relais, mainloop=DBusGMainLoop())
        self.connexions.append(connexion)
        return connexion

    def methode(self, connexion, chemin, interface, nom, destination=PORTAIL):
        return connexion.get_object(destination, chemin, introspect=False).get_dbus_method(nom, interface)


class TestsTransmission:
    """Ce qui n'est pas destiné au relais passe sans modification (avec ou sans --filechooser)."""

    def test_appel_et_propriete(self):
        c = self.client()
        get = self.methode(c, CHEMIN_PORTAIL, "org.freedesktop.DBus.Properties", "Get")
        self.assertEqual(get("org.freedesktop.portal.FileChooser", "version"), 4)
        self.assertEqual(self.methode(c, "/test", "org.example.Test", "Echo")("bonjour é"), "bonjour é")

    def test_gros_message_et_plusieurs_messages_d_un_coup(self):
        s = connexion_brute(self.socket_relais)
        gros = "x" * 200_000
        cible = DBusAddress("/test", bus_name=PORTAIL, interface="org.example.Test")
        donnees = (message_bus.Hello().serialise(serial=1)
                   + new_method_call(cible, "Echo", "s", (gros,)).serialise(serial=2)
                   + new_method_call(cible, "Echo", "s", ("petit",)).serialise(serial=3))
        s.sendall(donnees[:7])          # coupe au milieu de l'en-tête
        time.sleep(0.1)
        s.sendall(donnees[7:])
        parser, reponses = Parser(), {}
        while len(reponses) < 3:
            morceau = s.recv(65536)
            self.assertTrue(morceau, "connexion fermée par le relais")
            parser.add_data(morceau)
            while (message := parser.get_next_message()) is not None:
                serie = message.header.fields.get(HeaderFields.reply_serial)
                if serie:
                    reponses[serie] = message
        s.close()
        self.assertTrue(reponses[1].body[0].startswith(":"))
        self.assertEqual(reponses[2].body, (gros,))
        self.assertEqual(reponses[3].body, ("petit",))

    def test_descripteur_de_fichier(self):
        c = self.client()
        lecture, ecriture = os.pipe()
        recu = self.methode(c, "/test", "org.example.Test", "EchoFd")(dbus.types.UnixFd(lecture)).take()
        os.write(ecriture, b"par le relais")
        self.assertEqual(os.read(recu, 100), b"par le relais")
        for fd in (lecture, ecriture, recu):
            os.close(fd)

    def test_en_tete_invalide(self):
        s = connexion_brute(self.socket_relais)
        s.sendall(b"x" * 16)
        self.assertEqual(s.recv(4096), b"")
        s.close()
        c = self.client()   # le relais sert toujours les autres clients
        self.assertEqual(self.methode(c, "/test", "org.example.Test", "Echo")("encore"), "encore")


class TransmissionSansSelecteur(TestsTransmission, BaseRelais):
    def test_selecteur_transmis_au_bus(self):
        c = self.client()
        open_file = self.methode(c, CHEMIN_PORTAIL, "org.freedesktop.portal.FileChooser", "OpenFile")
        self.assertEqual(open_file("", "Titre", {"handle_token": "T1"}, signature="ssa{sv}"), "/faux/portail/OpenFile")


class TransmissionAvecSelecteur(TestsTransmission, BaseRelais):
    def options(self):
        return ["--filechooser", str(self.selecteur)]


def demander(test, connexion, methode, options, jeton):
    """Appelle FileChooser.<methode> ; renvoie (chemin renvoyé, chemin attendu, Response reçus)."""
    attendu = "%s/request/%s/%s" % (CHEMIN_PORTAIL, connexion.get_unique_name()[1:].replace(".", "_"), jeton)
    reponses = []
    connexion.add_signal_receiver(
        lambda code, resultats, emetteur=None: reponses.append((code, resultats, emetteur)),
        "Response", "org.freedesktop.portal.Request", PORTAIL, attendu, sender_keyword="emetteur")
    connexion.get_name_owner(PORTAIL)   # le filtre d'émetteur de dbus-python connaît le portail avant la réponse
    appel = test.methode(connexion, CHEMIN_PORTAIL, "org.freedesktop.portal.FileChooser", methode)
    chemin = appel("", "Titre imposé", dict(options, handle_token=jeton), signature="ssa{sv}")
    return chemin, attendu, reponses


def processus_vivant(pid):
    try:
        etat = Path("/proc/%d/stat" % pid).read_text().rsplit(")", 1)[1].split()[0]
    except (OSError, IndexError):
        return False
    return etat != "Z"


class SelecteurDeFichiers(BaseRelais):
    """Appels FileChooser traités par le relais (--filechooser)."""

    def options(self):
        return ["--filechooser", str(self.selecteur)]

    def mode(self, mode):
        (self.dossier / "mode").write_text(mode)
        for nom in ("args", "pid"):
            (self.dossier / nom).unlink(missing_ok=True)

    def test_ouvrir_reussi(self):
        self.mode("ok")
        c = self.client()
        chemin, attendu, reponses = demander(self, c, "OpenFile", {"multiple": True, "directory": False}, "JETON1")
        self.assertEqual(chemin, attendu)
        self.assertTrue(attendre(lambda: reponses), self.journal_relais.read_text())
        code, resultats, emetteur = reponses[0]
        self.assertEqual(code, 0)
        self.assertEqual(list(resultats["uris"]), [
            "file:///srv/chromium-sbx/Envois/abc/1/%C3%A9t%C3%A9%20100%25.pdf",
            "file:///srv/chromium-sbx/Envois/abc/2/b.txt"])
        self.assertEqual(emetteur, self.nom_portail)
        self.assertEqual((self.dossier / "args").read_text(), "ouvrir\n--multiple\n")

    def test_dossier(self):
        self.mode("ok")
        c = self.client()
        _, _, reponses = demander(self, c, "OpenFile", {"directory": True}, "JETON2")
        self.assertTrue(attendre(lambda: reponses))
        self.assertEqual((self.dossier / "args").read_text(), "ouvrir\n--dossier\n")

    def test_annule_et_erreur(self):
        for mode, code in (("annule", 1), ("erreur", 2)):
            with self.subTest(mode=mode):
                self.mode(mode)
                c = self.client()
                _, _, reponses = demander(self, c, "OpenFile", {}, "J" + mode)
                self.assertTrue(attendre(lambda: reponses))
                self.assertEqual(reponses[0][0], code)
                self.assertEqual(dict(reponses[0][1]), {})

    def test_enregistrer(self):
        self.mode("ok")
        c = self.client()
        _, _, reponses = demander(self, c, "SaveFile", {"current_name": "rapport final.pdf"}, "JETON3")
        self.assertTrue(attendre(lambda: reponses))
        self.assertEqual(reponses[0][0], 0)
        self.assertEqual((self.dossier / "args").read_text(), "enregistrer\nrapport final.pdf\n")

    def test_enregistrer_plusieurs_refuse(self):
        c = self.client()
        _, _, reponses = demander(self, c, "SaveFiles", {}, "JETON4")
        self.assertTrue(attendre(lambda: reponses))
        self.assertEqual(reponses[0][0], 1)

    def test_trop_de_demandes_en_cours(self):
        """Au-delà de deux sélections ouvertes, la demande est refusée tout de suite (code 2)."""
        self.mode("dort")
        c = self.client()
        chemin1, _, reponses1 = demander(self, c, "OpenFile", {}, "JETONA")
        chemin2, _, reponses2 = demander(self, c, "OpenFile", {}, "JETONB")
        chemin3, attendu3, reponses3 = demander(self, c, "OpenFile", {}, "JETONC")
        self.assertEqual(chemin3, attendu3)          # le chemin de requête est quand même renvoyé
        self.assertTrue(attendre(lambda: reponses3, 5), self.journal_relais.read_text())
        self.assertEqual(reponses3[0][0], 2)
        self.assertEqual((reponses1, reponses2), ([], []))   # les deux premières tournent toujours
        self.assertIn("trop de demandes en cours", self.journal_relais.read_text())
        for chemin in (chemin1, chemin2):
            self.methode(c, chemin, "org.freedesktop.portal.Request", "Close")()

    def test_close_arrete_la_selection(self):
        self.mode("dort")
        c = self.client()
        chemin, _, reponses = demander(self, c, "OpenFile", {}, "JETON5")
        fichier_pid = self.dossier / "pid"
        self.assertTrue(attendre(lambda: fichier_pid.exists() and fichier_pid.read_text().strip()))
        pid = int(fichier_pid.read_text())
        self.methode(c, chemin, "org.freedesktop.portal.Request", "Close")()
        self.assertTrue(attendre(lambda: not processus_vivant(pid), 5))
        attendre(lambda: reponses, 1)
        self.assertEqual(reponses, [])


class SelecteurAbsent(BaseRelais):
    def options(self):
        return ["--filechooser", str(self.dossier / "absent")]

    def test_programme_absent(self):
        c = self.client()
        _, _, reponses = demander(self, c, "OpenFile", {}, "JETON6")
        self.assertTrue(attendre(lambda: reponses))
        self.assertEqual(reponses[0][0], 2)
