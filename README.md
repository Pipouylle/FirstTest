# Setup des Dotfiles (Arch Linux + Hyprland + Caelestia)

Ce dépôt contient les fichiers de configuration de votre environnement de travail (dotfiles), gérés avec [chezmoi](https://www.chezmoi.io/).

---

## 1. Restauration des configurations (sur une Arch vierge)

Une fois que votre nouveau système Arch Linux est installé et que vous avez accès à internet :

```bash
# 1. Initialiser chezmoi avec votre dépôt
chezmoi init https://github.com/Pipouylle/FirstTest.git

# 2. Appliquer les configurations sur votre machine
chezmoi apply
```

Toutes vos configurations (`hypr`, `quickshell/caelestia`, `easyeffects`) seront automatiquement placées dans leurs dossiers respectifs (`~/.config/`).

---

## 2. Paquets requis à installer

Pour que l'ensemble de l'environnement fonctionne correctement (raccourcis, barre d'état, effets audio, fonds d'écran animés, utilitaires), vous devez installer les paquets suivants.

### A. Paquets système (depuis les dépôts officiels Arch)
Installez-les via `pacman` :

```bash
sudo pacman -S --needed \
    hyprland \
    hypridle \
    hyprlock \
    hyprpolkitagent \
    sddm \
    easyeffects \
    rofi \
    kitty \
    zsh \
    lsd \
    fastfetch \
    fzf \
    wl-clipboard \
    cliphist \
    jq \
    bc \
    ffmpeg \
    imagemagick \
    git \
    xdg-desktop-portal-hyprland
```

*Description rapide :*
* `hyprland`, `hypridle`, `hyprlock` : Le compositeur de fenêtres, le gestionnaire d'inactivité et l'écran de verrouillage.
* `hyprpolkitagent` : L'agent Polkit pour gérer l'authentification et les droits système en mode graphique.
* `sddm` : Le gestionnaire de connexion graphique (Display Manager) pour démarrer la session.
* `easyeffects` : Égaliseur et traitement du son (avec tes préréglages).
* `rofi` : Le menu de sélection de fonds d'écran et lanceur d'applications.
* `kitty` : Le terminal par défaut.
* `zsh` : Le shell alternatif interactif utilisé par défaut.
* `lsd` : Une alternative moderne à `ls` avec des couleurs et des icônes (utilisée dans les alias de `.zshrc`).
* `fastfetch` : Affiche les informations système au démarrage du terminal.
* `fzf` : Le moteur de recherche floue (Fuzzy Finder) utilisé pour la recherche d'historique dans le terminal.
* `wl-clipboard`, `cliphist` : Gestionnaire de presse-papiers sous Wayland.
* `jq`, `bc` : Utilitaires système requis par les scripts de fond d'écran et de météo.
* `ffmpeg`, `imagemagick` : Requis par le script de fond d'écran pour générer les aperçus vidéo et GIF dans Rofi.

---

### B. Outils de compilation (Requis pour compiler les paquets AUR)
Avant d'installer les paquets de l'AUR, installez les outils de compilation essentiels :

```bash
sudo pacman -S --needed base-devel cmake meson ninja git
```

---

### C. Paquets AUR (via un helper comme `yay` ou `paru`)
Installez-les depuis l'AUR :

```bash
yay -S --needed \
    quickshell-git \
    swww \
    linux-wallpaperengine-git \
    waypaper \
    wallust \
    vicinae \
    caelestia-cli \
    caelestia-shell \
    simple-sddm-theme-2-git
```

*Description rapide :*
* `quickshell-git` : Requis pour faire tourner l'interface et la barre supérieure **Caelestia-Shell**.
* `swww` : Moteur de gestion des fonds d'écran (images et transitions fluides).
* `linux-wallpaperengine-git` : Moteur pour lire les fonds d'écran du Steam Workshop (Wallpaper Engine).
* `waypaper` : L'interface graphique pour choisir et appliquer facilement vos fonds d'écran.
* `wallust` : Générateur automatique de schémas de couleurs basé sur votre fond d'écran.
* `vicinae` : Le lanceur d'applications rapide (style Raycast) lancé en arrière-plan.
* `caelestia-cli` : L'outil en ligne de commande principal (CLI) pour gérer les dotfiles de Caelestia.
* `caelestia-shell` : Le paquet de l'interface qui compile les composants QML et les plugins système pour le shell.
* `simple-sddm-theme-2-git` : Le thème minimaliste et personnalisable pour l'écran de connexion SDDM.

---

## 3. Post-installation & Premier démarrage

1. Assurez-vous que le service de presse-papiers démarre bien (il est configuré dans `Startup_Apps.conf`).
2. Pour lancer les fonds d'écran interactifs :
   * Ouvrez Steam et téléchargez vos fonds d'écran dans Wallpaper Engine.
   * Lancez `waypaper`, choisissez `linux-wallpaperengine` comme backend, et sélectionnez votre fond d'écran.
3. Pour EasyEffects, ouvrez l'application une première fois afin qu'elle charge tes configurations de filtres et d'égaliseur depuis `~/.config/easyeffects/db/`.
4. **Configuration de Zsh & Oh My Zsh** :
   * Installez Oh My Zsh :
     ```bash
     sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
     ```
   * Installez les deux plugins de complétion et coloration syntaxique :
     ```bash
     # zsh-syntax-highlighting
     git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
     
     # zsh-autosuggestions
     git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
     ```
   * Ré-appliquez chezmoi pour restaurer le fichier `.zshrc` configuré :
     ```bash
     chezmoi apply
     ```

---

## 4. Configuration de Quickshell et Caelestia-Shell

Caelestia-Shell est une configuration unifiée écrite en QML pour le gestionnaire d'interface **Quickshell**. Il n'y a pas besoin de compiler l'interface manuellement car c'est un langage interprété (QML/Qt6).

### A. Structure des dossiers
Quickshell cherche ses configurations sous `~/.config/quickshell/<nom-de-la-config>/shell.qml`.
Chezmoi va automatiquement restaurer le dossier Caelestia à cet emplacement :
`~/.config/quickshell/caelestia/`

### B. Tester et lancer Caelestia-Shell
Pour lancer Caelestia en arrière-plan (mode daemon) :
```bash
# Lancer Caelestia-Shell
qs -c caelestia -d
```

Si vous modifiez les fichiers QML et voulez recharger l'interface à la volée :
```bash
# Tuer l'instance active et redémarrer
qs kill -c caelestia && qs -c caelestia -d
```

### C. Lancement automatique au démarrage d'Hyprland
Le lancement automatique est configuré dans votre fichier `~/.config/hypr/UserConfigs/Startup_Apps.conf` via la ligne :
```ini
exec-once = qs -c caelestia -d
```
Cela remplace automatiquement Waybar et SwayNC d'origine au chargement d'Hyprland.

---

## 5. Démarrage automatique sur Hyprland (Boot automatique)

Pour que l'ordinateur démarre automatiquement sur Hyprland à l'allumage, vous avez deux approches :

### Méthode 1 : Avec écran de connexion SDDM (Recommandé)
1. **Activer le service SDDM** pour qu'il se lance au démarrage :
   ```bash
   sudo systemctl enable sddm
   ```
2. **Configurer le thème SDDM et la synchronisation du fond d'écran** :
   * Installez le thème `simple-sddm-theme-2-git` depuis l'AUR.
   * Créez ou modifiez `/etc/sddm.conf.d/theme.conf` avec root :
     ```ini
     [Theme]
     Current=simple-sddm-2
     ```
   * Pour que le fond d'écran de l'écran de connexion se synchronise automatiquement et sans mot de passe avec votre fond d'écran actif :
     ```bash
     # 1. Créer le fichier de destination et donner les droits à votre utilisateur
     sudo touch /var/lib/sddm_wallpaper.jpg
     sudo chown timothe:timothe /var/lib/sddm_wallpaper.jpg

     # 2. Créer le lien symbolique du thème vers ce fichier
     sudo rm -f /usr/share/sddm/themes/simple-sddm-2/Backgrounds/default
     sudo ln -sf /var/lib/sddm_wallpaper.jpg /usr/share/sddm/themes/simple-sddm-2/Backgrounds/default
     ```
     Le script `set_wallpaper.py` copiera automatiquement le fond d'écran actuel (ou son aperçu haute résolution si c'est un fond animé) dans `/var/lib/sddm_wallpaper.jpg`.
3. **(Optionnel) Activer la connexion automatique** (sans avoir à taper votre mot de passe) :
   Créez ou modifiez le fichier `/etc/sddm.conf.d/autologin.conf` :
   ```ini
   [Autologin]
   User=timothe
   Session=hyprland
   ```

### Méthode 2 : Sans gestionnaire graphique (Lancement direct depuis le TTY)
Si vous ne souhaitez pas installer de gestionnaire de connexion (pas de SDDM), vous pouvez utiliser le fichier de profil utilisateur **`.zprofile`** (géré par chezmoi) :
1. Ouvrez `~/.zprofile` (qui a été restauré par chezmoi).
2. Décommentez les lignes suivantes au début du fichier :
   ```bash
   if [ -z "${DISPLAY}" ] && [ "${XDG_VTNR}" -eq 1 ]; then
          exec Hyprland
   fi
   ```
   *Note : la commande `exec` est importante car elle remplace le processus du shell de connexion par Hyprland, ce qui sécurise le TTY sous-jacent.*

---

## 6. Synchronisation et Mises à jour (Récupérer les changements distants)

Si vous apportez des modifications à vos configurations depuis un autre PC et les poussez sur GitHub, vous pouvez les récupérer et les appliquer sur votre machine locale de deux façons :

### Option A : Tout faire en une seule commande (Recommandé)
```bash
chezmoi update
```
*Cette commande télécharge les modifications depuis GitHub (via un `git pull` interne) et les applique directement sur vos fichiers locaux.*

### Option B : Étape par étape (Sécurisé, pour valider les changements)
1. **Télécharger les nouveautés** depuis GitHub sans les appliquer immédiatement :
   ```bash
   chezmoi git pull
   ```
2. **Vérifier les différences** (voir ce qui va changer sur votre machine) :
   ```bash
   chezmoi diff
   ```
3. **Appliquer les nouveautés** sur votre système réel :
   ```bash
   chezmoi apply
   ```

---

## 7. Partage d'écran sous Wayland (WebRTC / Discord / Meet)

Pour partager votre écran entier ou d'autres applications sous Wayland/Hyprland (et pas seulement un onglet du navigateur), le système utilise **PipeWire** et **xdg-desktop-portal-hyprland**.

### A. Démarrage des portails
Assurez-vous que le script de portails est activé au démarrage dans votre fichier `~/.config/hypr/UserConfigs/Startup_Apps.conf` :
```ini
exec-once = $scriptsDir/PortalHyprland.sh
```

Pour les démarrer manuellement sans redémarrer votre session :
```bash
~/.config/hypr/scripts/PortalHyprland.sh
```

### B. Configuration du navigateur (Chromium, Brave, Chrome)
Pour que le navigateur puisse interagir avec le portail de capture de Wayland :
1. Ouvrez `chrome://flags` dans votre navigateur.
2. Recherchez **Preferred Ozone platform**.
3. Remplacez **Default** par **Auto** (ou **Wayland**).
4. Relancez le navigateur.

