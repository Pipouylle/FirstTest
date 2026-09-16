# Tutoriel : Isoler n'importe quelle Application avec Bubblewrap (Mount Namespace)

Ce tutoriel vous explique comment isoler n'importe quelle application Linux (Chromium, Discord, Spotify, Steam, etc.) dans son propre **Mount Namespace privé** grâce à **Bubblewrap (`bwrap`)**.

---

## 🎯 Pourquoi utiliser Bubblewrap plutôt qu'un lancement classique ?

Dans un système Linux standard :
- Toutes les applications lancées par votre utilisateur partagent le même espace de noms et le même dossier personnel (`/home/timothe`).
- Si vous lancez une application vérolée ou un script suspect, il a un accès direct en lecture à vos clés SSH (`~/.ssh`), vos tokens (`~/.claude`), vos cookies de navigateur et votre session Discord.

Avec **Bubblewrap et les Mount Namespaces** :
1. **L'application est enfermée dans un faux `$HOME` en RAM (tmpfs)** : Elle ne peut voir ni vos clés SSH, ni vos documents, ni vos tokens cachés.
2. **Son profil est rangé à part** : il vit dans `~/.local/share/secure-profiles/<app>/` et n'apparaît sur `~/.config/<app>` qu'à l'intérieur du bac à sable. Attention : ce dossier reste lisible sur l'hôte par tout programme de votre compte ; le bac à sable protège vos fichiers **de l'application**, pas l'inverse.
3. **Zéro privilège root requis** : Bubblewrap s'exécute directement en utilisateur simple via les namespaces non privilégiés du noyau Linux.

> ⚠️ **Bubblewrap est à sens unique.** Il empêche l'application de **sortir** (lire vos fichiers, joindre vos sockets), mais pas un programme lancé sous le même compte d'**entrer** : le compte qui crée le namespace en est propriétaire, donc `/proc/<pid>/root` (les fichiers vus par l'appli, tmpfs compris) et `/proc/<pid>/environ` (ses variables d'environnement) restent lisibles depuis votre session (vérifié le 16/09/2026). Pour protéger les **données de l'application** contre les autres programmes de votre compte, il faut la faire tourner sous un **compte Unix dédié** : c'est ce que fait `system/chromium-sbx` pour Chromium (voir `SECURITE_ET_ARCHITECTURE.md` §7).

---

## 🚀 Méthode 1 : Utiliser l'outil universel automatique (`bwrap-app`)

Nous avons créé un utilitaire universel dans votre PATH : [`~/.local/bin/bwrap-app`](file:///home/timothe/.local/bin/bwrap-app).

### Utilisation :
Il vous suffit de préfixer la commande de votre application par `bwrap-app` :

```bash
# Lancer Discord de manière isolée
bwrap-app discord

# Lancer Spotify
bwrap-app spotify

# Lancer VLC pour ouvrir une vidéo
bwrap-app vlc ma_video.mp4
```

### Ce que fait `bwrap-app` automatiquement :
- Il crée un profil de données étanche dans `~/.local/share/secure-profiles/<nom_application>/` (avec permissions `700`).
- Il monte ce dossier sur `~/.config/<nom_application>` à l'intérieur du bac à sable.
- Il monte votre dossier `~/Downloads` pour pouvoir échanger des fichiers.
- De `$XDG_RUNTIME_DIR`, il ne monte que l'affichage (socket Wayland), le son (`pipewire-0`, `pulse/native`) et un **bus D-Bus filtré** par `xdg-dbus-proxy` : `org.freedesktop.secrets`, `org.freedesktop.portal.*`, `org.freedesktop.Notifications`, `org.freedesktop.ScreenSaver`, et la possession des noms MPRIS de l'appli (`org.mpris.MediaPlayer2.<app>`, `org.mpris.MediaPlayer2.chromium.*` pour Electron). L'IPC Hyprland, `systemd --user` et les agents SSH/GPG restent hors d'atteinte.
- Il donne à l'appli un `/tmp` **commun à tous ses lancements** (`$XDG_RUNTIME_DIR/bwrap-app/<app>/tmp`, invisible de l'hôte) : un 2e lancement est transmis à l'instance ouverte au lieu d'ouvrir le même profil une seconde fois.
- Il fournit l'accélération graphique (`/dev/dri`).
- **Tout le reste de votre `$HOME` est masqué et inaccessible.**

---

## 🛠️ Méthode 2 : Créer un wrapper sur-mesure pour une application

Si vous voulez personnaliser précisément les autorisations d'une application (par exemple, donner accès à un dossier précis ou couper Internet), voici comment fabriquer votre propre script de confinement.

### Anatomie d'un bac à sable Bubblewrap

Voici le squelette repris de `bwrap-app`, `bwrap-agent` et `chromium-sbx-inner` (le plus simple est de copier `bwrap-app` ; il gère en plus un `WAYLAND_DISPLAY` absolu, l'absence de `DBUS_SESSION_BUS_ADDRESS` et le nettoyage des vieux sockets) :

```bash
RUNTIME_DIR="$XDG_RUNTIME_DIR"
STATE_DIR="$RUNTIME_DIR/bwrap-app/mon_app"
mkdir -p -m 700 "$RUNTIME_DIR/bwrap-app" "$STATE_DIR" "$STATE_DIR/tmp"

# Bus D-Bus filtré : un proxy par lancement, qui s'arrête quand bwrap se termine
BUS_SOCKET="$STATE_DIR/bus-$$"
exec {proxy_fd}< <(exec xdg-dbus-proxy "$DBUS_SESSION_BUS_ADDRESS" "$BUS_SOCKET" --fd=1 --filter \
    --talk='org.freedesktop.portal.*' \
    --talk=org.freedesktop.Notifications)
read -r -N 1 -u "$proxy_fd" _ready

exec bwrap \
    --new-session \
    --sync-fd "$proxy_fd" \
    --ro-bind /usr /usr \
    --ro-bind /lib /lib \
    --ro-bind /lib64 /lib64 \
    --ro-bind /bin /bin \
    --ro-bind /etc /etc \
    --ro-bind-try /opt /opt \
    --ro-bind-try /run/dbus /run/dbus \
    --dev /dev \
    --dev-bind-try /dev/dri /dev/dri \
    --ro-bind-try /sys/dev /sys/dev \
    --ro-bind-try /sys/devices /sys/devices \
    --ro-bind-try /sys/bus /sys/bus \
    --ro-bind-try /sys/class /sys/class \
    --proc /proc \
    --bind "$STATE_DIR/tmp" /tmp \
    --perms 0700 --dir "$RUNTIME_DIR" \
    --ro-bind "$RUNTIME_DIR/$WAYLAND_DISPLAY" "$RUNTIME_DIR/$WAYLAND_DISPLAY" \
    --ro-bind-try "$RUNTIME_DIR/pipewire-0" "$RUNTIME_DIR/pipewire-0" \
    --ro-bind-try "$RUNTIME_DIR/pulse/native" "$RUNTIME_DIR/pulse/native" \
    --ro-bind "$BUS_SOCKET" "$RUNTIME_DIR/bus" \
    --setenv DBUS_SESSION_BUS_ADDRESS "unix:path=$RUNTIME_DIR/bus" \
    --tmpfs "$HOME" \
    --bind "$HOME/.local/share/secure-profiles/mon_app" "$HOME/.config/mon_app" \
    --bind "$HOME/Downloads" "$HOME/Downloads" \
    --ro-bind-try "$HOME/.icons" "$HOME/.icons" \
    --ro-bind-try "$HOME/.local/share/fonts" "$HOME/.local/share/fonts" \
    --ro-bind-try "$HOME/.config/fontconfig" "$HOME/.config/fontconfig" \
    /usr/bin/mon_application "$@"
```

| Bloc | Rôle |
|---|---|
| `xdg-dbus-proxy` + `--sync-fd` | bus de session filtré : l'appli ne voit que les noms autorisés (`--talk`, `--own`). Sans filtre, `systemd --user` est joignable et permet de lancer n'importe quelle commande hors du bac à sable |
| `/usr`, `/lib`, `/bin`, `/etc`, `/opt` | système de base en lecture seule |
| `--dev`, `/dev/dri`, `/sys/…` | périphériques minimaux et GPU (sans `/dev/dri`, rendu logiciel) |
| `--bind "$STATE_DIR/tmp" /tmp` | `/tmp` propre à l'appli mais **commun à ses lancements** : les verrous « instance unique » (Chromium, Electron) y placent leur socket. Avec `--tmpfs /tmp`, un 2e lancement ouvre le même profil une seconde fois |
| `--dir "$RUNTIME_DIR"` + sockets | seuls Wayland, PipeWire, Pulse et le bus filtré. **Ne jamais monter `$XDG_RUNTIME_DIR` entier** : il contient l'IPC Hyprland (`hyprctl dispatch exec`), les agents SSH/GPG et le vrai bus de session |
| `--tmpfs "$HOME"` + binds | faux dossier personnel en RAM, avec seulement le profil de l'appli et `~/Downloads` |
| `--new-session` | détache l'appli du terminal qui l'a lancée |

> ⚠️ Les chemins de sockets UNIX sont limités à **108 caractères**. Si vous placez `STATE_DIR` dans un chemin long, le socket du proxy n'est pas créé au chemin attendu et `bwrap` échoue avec *« Can't find source path …/bus-NNNN »*. Gardez `STATE_DIR` sous `$XDG_RUNTIME_DIR`.

---

## 📱 Exemple concret : Isoler Discord à 100 % (Anti-Token Grabber)

Pour empêcher Discord de fouiller sur votre PC, inutile d'écrire un script dédié : `bwrap-app` applique déjà tout le cloisonnement ci-dessus.

### Étape 1 : Tester le lancement isolé

```bash
bwrap-app discord
```

Le profil isolé est créé vide dans `~/.local/share/secure-profiles/discord/` : il faut se reconnecter une fois (l'ancien `~/.config/discord` n'est pas migré). Un 2e `bwrap-app discord` est transmis à l'instance ouverte au lieu d'ouvrir le profil une seconde fois (mécanisme « instance unique » de Chromium, qu'Electron réutilise ; vérifié avec Chromium).

### Étape 2 : Créer le raccourci d'application graphique
Pour que votre lanceur (Vicinae, Rofi, etc.) utilise ce bac à sable automatiquement :

Créez le fichier `~/.local/share/applications/discord.desktop` :
```ini
[Desktop Entry]
Name=Discord (Sécurisé)
StartupWMClass=discord
Comment=Client de messagerie Discord isolé dans un Mount Namespace Bubblewrap
GenericName=Internet Messenger
Exec=/home/timothe/.local/bin/bwrap-app discord %U
Icon=discord
Type=Application
Categories=Network;InstantMessaging;
```

---

## 🎛️ Options avancées pour vos besoins spécifiques

### 1. Couper totalement l'accès à Internet pour l'application
Ajoutez simplement le drapeau :
```bash
--unshare-net \
```
L'application n'aura accès à aucune carte réseau physique.

### 2. Donner accès à un dossier supplémentaire (ex: Musique ou Images)
Pour autoriser une application multimédia (comme un lecteur de musique ou de vidéo) à lire un dossier :
```bash
--ro-bind "$HOME/Music" "$HOME/Music" \
```
*(Utilisez `--ro-bind` pour un accès en lecture seule sécurisé, ou `--bind` pour lecture/écriture)*.

### 3. Masquer complètement un fichier précis
Si vous partagez un dossier mais voulez masquer un fichier ultra-sensible à l'intérieur :
```bash
--tmpfs "$HOME/Documents/secret.txt" \
```
Le fichier devient un fichier vide de 0 octet dans le bac à sable.

---

## 🔍 Comment vérifier que l'isolation fonctionne ?

1. **Le profil actif n'est pas dans `~/.config/<app>` sur l'hôte** :
   ```bash
   ls -la ~/.config/discord
   ```
   Le profil vit dans `~/.local/share/secure-profiles/<app>/`. Si `~/.config/<app>` contient des données sur l'hôte, elles viennent d'un lancement **hors** bac à sable (application lancée en direct, sans `bwrap-app`) : à examiner puis supprimer une fois l'application fermée, sinon ces données restent lisibles par toute la session.

2. **Depuis l'intérieur, seul l'autorisé est visible** (lance un shell dans le même bac à sable ; crée au passage un profil `secure-profiles/bash` inutile, supprimable ensuite) :
   ```bash
   bwrap-app bash -c '
     ls -A "$XDG_RUNTIME_DIR"
     busctl --user list --no-legend | awk "{print \$1}" | grep -v "^:"
     busctl --user status org.freedesktop.systemd1 >/dev/null 2>&1 && echo "systemd JOIGNABLE" || echo "systemd bloqué"
     hyprctl version >/dev/null 2>&1 && echo "Hyprland JOIGNABLE" || echo "Hyprland bloqué"
     ls ~/.ssh
   '
   ```
   **Résultat attendu** : `bus pipewire-0 pulse wayland-1` ; uniquement `org.freedesktop.DBus`, `org.freedesktop.Notifications`, des `org.freedesktop.portal.*` et `org.freedesktop.secrets` ; `systemd bloqué` ; `Hyprland bloqué` (`hyprctl version` doit échouer) ; `~/.ssh` introuvable.

3. **Un 2e lancement ne double pas l'appli** : relancer la même commande pendant que l'appli tourne doit la réutiliser (pour Chromium : message *« Ouverture dans une session de navigateur existante »*).
