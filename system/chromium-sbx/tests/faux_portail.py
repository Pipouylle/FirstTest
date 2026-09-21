#!/usr/bin/env python3
"""Faux org.freedesktop.portal.Desktop pour les tests de dbus-uid-relay (bus D-Bus privé).

Écrit son nom unique sur la sortie standard, puis répond :
- Properties.Get(org.freedesktop.portal.FileChooser, version) -> 4 ;
- org.example.Test.Echo(s) -> s, org.example.Test.EchoFd(h) -> h ;
- org.freedesktop.portal.FileChooser.<méthode> -> chemin /faux/portail/<méthode>
  (prouve qu'un appel est arrivé jusqu'au bus au lieu d'être intercepté).
"""
from jeepney import HeaderFields, MessageType, new_error, new_method_return
from jeepney.bus_messages import message_bus
from jeepney.io.blocking import open_dbus_connection

connexion = open_dbus_connection(bus="SESSION", enable_fds=True)
connexion.send_and_get_reply(message_bus.RequestName("org.freedesktop.portal.Desktop"))
print(connexion.unique_name, flush=True)

while True:
    appel = connexion.receive()
    if appel.header.message_type != MessageType.method_call:
        continue
    interface = appel.header.fields.get(HeaderFields.interface)
    membre = appel.header.fields.get(HeaderFields.member)
    if (interface, membre) == ("org.freedesktop.DBus.Properties", "Get") \
            and appel.body == ("org.freedesktop.portal.FileChooser", "version"):
        reponse = new_method_return(appel, "v", (("u", 4),))
    elif (interface, membre) == ("org.example.Test", "Echo"):
        reponse = new_method_return(appel, "s", appel.body)
    elif (interface, membre) == ("org.example.Test", "EchoFd"):
        reponse = new_method_return(appel, "h", appel.body)
    elif interface == "org.freedesktop.portal.FileChooser":
        reponse = new_method_return(appel, "o", ("/faux/portail/" + membre,))
    else:
        reponse = new_error(appel, "org.freedesktop.DBus.Error.UnknownMethod", "s", ("inconnu",))
    connexion.send(reponse)
    if (interface, membre) == ("org.example.Test", "EchoFd"):
        appel.body[0].close()
