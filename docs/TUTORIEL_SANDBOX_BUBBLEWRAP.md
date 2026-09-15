# Tutoriel : Isoler n'importe quelle Application avec Bubblewrap (Mount Namespace)

Ce tutoriel vous explique comment isoler n'importe quelle application Linux (Chromium, Discord, Spotify, Steam, etc.) dans son propre **Mount Namespace privé** grâce à **Bubblewrap (`bwrap`)**.

---

## 🎯 Pourquoi utiliser Bubblewrap plutôt qu'un lancement classique ?

Dans un système Linux standard :
- Toutes les applications lancées par votre utilisateur partagent le même espace de noms et le même dossier personnel (`/home/timothe`).
- Si vous lancez une application vérolée ou un script suspect, il a un accès direct en lecture à vos clés SSH (`~/.ssh`), vos tokens (`~/.claude`), vos cookies de navigateur et votre session Discord.

Avec **Bubblewrap et les Mount Namespaces** :
1. **L'application est enfermée dans un faux `$HOME` en RAM (tmpfs)** : Elle ne peut voir ni vos clés SSH, ni vos documents, ni vos tokens cachés.
2. **Pour le reste de votre ordinateur, son profil est invisible** : Même pendant que l'application tourne, les autres programmes de votre PC ne voient qu'un dossier vide sur le système hôte.
3. **Zéro privilège root requis** : Bubblewrap s'exécute directement en utilisateur simple via les namespaces non privilégiés du noyau Linux.

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
- Il fournit le son (PipeWire), l'affichage (Wayland/X11) et l'accélération graphique (GPU).
- **Tout le reste de votre `$HOME` est masqué et inaccessible.**

---

## 🛠️ Méthode 2 : Créer un wrapper sur-mesure pour une application

Si vous voulez personnaliser précisément les autorisations d'une application (par exemple, donner accès à un dossier précis ou couper Internet), voici comment fabriquer votre propre script de confinement.

### Anatomie d'un bac à sable Bubblewrap

Voici le squelette standard d'une commande `bwrap` :

```bash
bwrap \
    # 1. Système de fichiers de base de Linux (en lecture seule)
    --ro-bind /usr /usr \
    --ro-bind /lib /lib \
    --ro-bind /lib64 /lib64 \
    --ro-bind /bin /bin \
    --ro-bind /etc /etc \
    --ro-bind-try /opt /opt \
    --ro-bind-try /run/dbus /run/dbus \
    # 2. Périphériques matériels et kernel
    --dev /dev \
    --proc /proc \
    --tmpfs /tmp \
    # 3. Audio (PipeWire), Affichage (Wayland) et D-Bus
    --bind "$XDG_RUNTIME_DIR" "$XDG_RUNTIME_DIR" \
    # 4. Le faux dossier personnel en RAM (étanche)
    --tmpfs "$HOME" \
    # 5. Les dossiers que vous autorisez spécifiquement
    --bind "$HOME/.local/share/secure-profiles/mon_app" "$HOME/.config/mon_app" \
    --bind "$HOME/Downloads" "$HOME/Downloads" \
    # 6. Polices et thèmes pour un rendu graphique propre
    --ro-bind-try "$HOME/.icons" "$HOME/.icons" \
    --ro-bind-try "$HOME/.local/share/fonts" "$HOME/.local/share/fonts" \
    --ro-bind-try "$HOME/.config/fontconfig" "$HOME/.config/fontconfig" \
    # 7. La commande à exécuter
    /usr/bin/mon_application "$@"
```

---

## 📱 Exemple concret : Isoler Discord à 100 % (Anti-Token Grabber)

Pour empêcher tout script d'accéder aux tokens de Discord et empêcher Discord de fouiller sur votre PC :

### Étape 1 : Créer le script `~/.local/bin/bwrap-discord`

```bash
cat <<'EOF' > ~/.local/bin/bwrap-discord
#!/usr/bin/env bash
set -euo pipefail

SECURE_DIR="$HOME/.local/share/secure-profiles/discord"
mkdir -p "$SECURE_DIR" "$HOME/Downloads"
chmod 700 "$SECURE_DIR"

exec bwrap \
    --ro-bind /usr /usr \
    --ro-bind /lib /lib \
    --ro-bind /lib64 /lib64 \
    --ro-bind /bin /bin \
    --ro-bind /etc /etc \
    --ro-bind-try /opt /opt \
    --ro-bind-try /run/dbus /run/dbus \
    --dev /dev \
    --proc /proc \
    --tmpfs /tmp \
    --bind "$XDG_RUNTIME_DIR" "$XDG_RUNTIME_DIR" \
    --tmpfs "$HOME" \
    --bind "$SECURE_DIR" "$HOME/.config/discord" \
    --bind "$HOME/Downloads" "$HOME/Downloads" \
    --ro-bind-try "$HOME/.icons" "$HOME/.icons" \
    --ro-bind-try "$HOME/.local/share/fonts" "$HOME/.local/share/fonts" \
    --ro-bind-try "$HOME/.config/fontconfig" "$HOME/.config/fontconfig" \
    /usr/bin/discord "$@"
EOF

chmod +x ~/.local/bin/bwrap-discord
```

### Étape 2 : Créer le raccourci d'application graphique
Pour que votre lanceur (Vicinae, Rofi, etc.) utilise ce bac à sable automatiquement :

Créez le fichier `~/.local/share/applications/discord.desktop` :
```ini
[Desktop Entry]
Name=Discord (Sécurisé)
StartupWMClass=discord
Comment=Client de messagerie Discord isolé dans un Mount Namespace Bubblewrap
GenericName=Internet Messenger
Exec=/home/timothe/.local/bin/bwrap-discord %U
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

Ouvrez un terminal pendant que votre application tourne dans `bwrap` :

1. Regardez le dossier standard de l'application sur votre système hôte :
   ```bash
   ls -la ~/.config/chromium
   # OU
   ls -la ~/.config/discord
   ```
   **Résultat** : Le dossier est vide sur votre système hôte ! Le profil actif n'existe que dans le namespace privé de l'application.

2. Même si un malware tente d'exécuter :
   ```bash
   cat ~/.config/discord/Local\ Storage/leveldb/*.ldb
   ```
   Il recevra une erreur *« Fichier ou dossier introuvable »*.
