# chromium-sbx : Chromium sous un compte Unix dédié

Objectif : aucun programme lancé dans la session (malware compris) ne peut lire le profil
Chromium (cookies, sessions, Proton Pass, historique) ni inspecter ses processus.

Un sandbox Bubblewrap seul ne suffit pas : il empêche l'application de **sortir**, pas les
programmes du même compte d'**entrer** (`/proc/<pid>/root`, `/proc/<pid>/environ`, fichiers du
profil sur disque ; vérifié le 16/09/2026). Seul un autre compte Unix l'empêche.
Explication détaillée et tests : `docs/SECURITE_ET_ARCHITECTURE.md` §6 et §7.

```
SESSION (timothe)                                         COMPTE chromium (uid système)
chromium.desktop -> ~/.local/bin/chromium-sbx
  | démarre des services systemd utilisateur ; sockets dans /run/chromium-sbx (2750, setgid chromium) :
  |   wayland : wayland-sandbox-socket, contexte de sécurité Hyprland (71 -> 40 protocoles :
  |             ni capture d'écran, ni clavier/souris virtuels, ni presse-papiers global...)
  |   bus     : dbus-uid-relay -> xdg-dbus-proxy (socket privé %t/chromium-sbx-dbus)
  |             KeePassXC, notifications, MPRIS, portails Réglages et Partage d'écran seulement
  |   pulse   : adresse pipewire-pulse supplémentaire, client.access = restricted
  +-- sudo -n -u chromium /usr/local/bin/chromium-sbx-inner --------->  bwrap -> Chromium
       (NOPASSWD limité à ce fichier root, qui refuse toute option)     profil : /var/lib/chromium-sbx (0700)
                                                                        téléchargements : /srv/chromium-sbx/Downloads
```

## Fichiers

Partie root, dans ce dossier (non déployé par chezmoi), installée par `install.sh` :

| Fichier | Installé dans | Rôle |
|---|---|---|
| `wayland-sandbox-socket.c`, `build.sh` | `/usr/local/bin/wayland-sandbox-socket` | socket Wayland déclaré par `wp_security_context_v1` (moteur `chromium-sbx`, app-id `chromium`) |
| `chromium-sbx-inner` | `/usr/local/bin/` (root, 755) | lanceur exécuté en tant que chromium : refuse les options (dont `--renderer-cmd-prefix`, `--gpu-launcher`), lance `/usr/bin/chromium` dans bwrap |
| `sudoers-chromium-sbx` | `/etc/sudoers.d/chromium-sbx` | lanceur interne sans mot de passe ; toute autre commande en tant que chromium exige le mot de passe **du compte chromium** (`targetpw`, `timestamp_timeout=0`) |
| `tmpfiles-chromium-sbx.conf` | `/etc/tmpfiles.d/chromium-sbx.conf` | `/run/chromium-sbx` : propriétaire session, groupe chromium, setgid. La session n'est **pas** membre du groupe |
| `install.sh` | | compte `chromium`, programmes, dossiers, ACL de `/srv/chromium-sbx/Downloads`, flags Chromium du compte, règle sudo (validée par `visudo`). Idempotent |
| `test.sh` | | vérification complète (sudo, sockets, D-Bus depuis le compte chromium, lancement, isolation) |

Partie session, **gérée par chezmoi** comme dotfiles :

| Fichier | Rôle |
|---|---|
| `~/.local/bin/chromium-sbx` | lanceur : démarre les services, puis `sudo -n -u chromium chromium-sbx-inner` |
| `~/.local/bin/dbus-uid-relay` | relais D-Bus : Chromium (libdbus) s'annonce avec l'uid de chromium, refusé à travers xdg-dbus-proxy ; le relais règle l'authentification et relaie les descripteurs de fichiers |
| `~/.config/systemd/user/chromium-sbx-wayland.service` | socket Wayland sandboxé |
| `~/.config/systemd/user/chromium-sbx-dbus.service` | xdg-dbus-proxy filtré, socket privé |
| `~/.config/systemd/user/chromium-sbx-dbus-relay.service` | relais, socket `/run/chromium-sbx/bus` (0660, groupe chromium) |
| `~/.config/pipewire/pipewire-pulse.conf.d/chromium-sbx.conf` | socket son `/run/chromium-sbx/pulse` en accès restreint (WirePlumber : lecture + exécution seulement) |
| `~/.local/share/applications/chromium.desktop` | raccourci -> `chromium-sbx` |

## Installation (nouvelle machine)

```bash
chezmoi apply                                  # fichiers de session
cd ~/.local/share/chezmoi/system/chromium-sbx
./build.sh                                     # sans sudo
sudo ./install.sh                              # relire le script avant : il s'exécute en root
systemctl --user daemon-reload
systemctl --user restart pipewire-pulse        # coupe le son une seconde
keepass-tokens set-account chromium            # mot de passe du compte, rangé dans KeePassXC « Comptes sandbox »
./test.sh
```

Migration d'un profil existant (Chromium fermé) :

```bash
sudo rsync -a --delete --exclude='Singleton*' <ancien profil>/ /var/lib/chromium-sbx/.config/chromium/
sudo chown -R chromium:chromium /var/lib/chromium-sbx/.config/chromium
```
Vérifier onglets, connexions et Proton Pass, puis **supprimer l'ancienne copie** : sinon elle reste
lisible par la session et la protection ne sert à rien. Les cookies chiffrés restent lisibles :
le compte chromium récupère la même clé « Chromium Safe Storage » dans KeePassXC.

## Utilisation et administration

- Lancer Chromium : le raccourci, ou `chromium-sbx [URL...]`, sans mot de passe.
- Agir en tant que chromium : `keepass-tokens sudo chromium <commande>`. Le mot de passe du compte est lu
  dans KeePassXC, avec une fenêtre de déverrouillage à chaque fois.
- Envoyer ou récupérer des fichiers : `/srv/chromium-sbx/Downloads` (ACL pour la session).
  Chromium ne voit pas le home de la session.
- Après modification de `chromium-sbx-inner`, des sudoers ou de tmpfiles : `sudo ./install.sh`, puis
  `./test.sh`. Mise à jour de Chromium par pacman : rien à faire.
- À faire hors d'un agent sandboxé : `bwrap-agent` bloque sudo, systemd et l'écriture dans chezmoi.

## Historique des problèmes rencontrés

- **`runaspw` au lieu de `targetpw`** (16/09/2026) : `runaspw` demande le mot de passe de
  `runas_default`, donc root, et aucun mot de passe ne passait. `targetpw` demande celui du compte `-u`.
- **Bus D-Bus injoignable depuis Chromium** (16/09/2026) : xdg-dbus-proxy transmet l'authentification
  du client telle quelle. libdbus annonce l'uid 963, que le bus refuse, puisque la connexion vient du
  proxy (compte de session). `busctl` (sd-bus) n'annonce pas d'uid et passait, ce qui masquait le
  problème. Symptômes : cookies en `v10` (clé fixe), pas de thème sombre. Corrigé par `dbus-uid-relay`.

## Limites

- root lit tout. Aujourd'hui, `sudo -i` avec le mot de passe de la session donne root, puis le compte
  chromium. Le fermer demanderait `Defaults rootpw` (mot de passe root rangé dans KeePassXC).
- Une session compromise contrôle les sockets de passage. Elle peut s'interposer sur l'affichage et le
  son pendant l'utilisation, et demander à KeePassXC la clé des cookies. Mais elle ne lit ni le profil
  au repos ni la mémoire de Chromium.
- Les applications de la session peuvent toujours capturer l'écran, donc la fenêtre de Chromium.
- Le bus système n'est pas exposé : erreurs UPower dans le journal de Chromium, sans conséquence.
- Les extensions à hôte natif (vicinae, KeePassXC-Browser) ne fonctionnent pas. Proton Pass fonctionne.
- OpenSnitch voit un nouveau compte : les autorisations sont à redonner.
