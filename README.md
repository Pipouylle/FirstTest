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
    easyeffects \
    rofi \
    kitty \
    zsh \
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
* `easyeffects` : Égaliseur et traitement du son (avec tes préréglages).
* `rofi` : Le menu de sélection de fonds d'écran et lanceur d'applications.
* `kitty` : Le terminal par défaut.
* `zsh` : Le shell alternatif interactif utilisé par défaut.
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
    vicinae
```

*Description rapide :*
* `quickshell-git` : Requis pour faire tourner l'interface et la barre supérieure **Caelestia-Shell**.
* `swww` : Moteur de gestion des fonds d'écran (images et transitions fluides).
* `linux-wallpaperengine-git` : Moteur pour lire les fonds d'écran du Steam Workshop (Wallpaper Engine).
* `waypaper` : L'interface graphique pour choisir et appliquer facilement vos fonds d'écran.
* `wallust` : Générateur automatique de schémas de couleurs basé sur votre fond d'écran.
* `vicinae` : Le lanceur d'applications rapide (style Raycast) lancé en arrière-plan.

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
