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
    easyeffects \
    kitty \
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
* `easyeffects` : Égaliseur et traitement du son (avec tes préréglages).
* `kitty` : Le terminal par défaut.
* `wl-clipboard`, `cliphist` : Gestionnaire de presse-papiers sous Wayland.
* `jq`, `bc` : Utilitaires système requis par les scripts de fond d'écran et de météo.
* `ffmpeg`, `imagemagick` : Requis par le script de fond d'écran pour générer les aperçus vidéo et GIF dans Rofi.

---

### B. Paquets AUR (via un helper comme `yay` ou `paru`)
Installez-les depuis l'AUR :

```bash
yay -S --needed \
    quickshell-git \
    swww \
    linux-wallpaperengine-git \
    waypaper \
    wallust
```

*Description rapide :*
* `quickshell-git` : Requis pour faire tourner l'interface et la barre supérieure **Caelestia-Shell**.
* `swww` : Moteur de gestion des fonds d'écran (images et transitions fluides).
* `linux-wallpaperengine-git` : Moteur pour lire les fonds d'écran du Steam Workshop (Wallpaper Engine).
* `waypaper` : L'interface graphique pour choisir et appliquer facilement vos fonds d'écran.
* `wallust` : Générateur automatique de schémas de couleurs basé sur votre fond d'écran.

---

## 3. Post-installation & Premier démarrage

1. Assurez-vous que le service de presse-papiers démarre bien (il est configuré dans `Startup_Apps.conf`).
2. Pour lancer les fonds d'écran interactifs :
   * Ouvrez Steam et téléchargez vos fonds d'écran dans Wallpaper Engine.
   * Lancez `waypaper`, choisissez `linux-wallpaperengine` comme backend, et sélectionnez votre fond d'écran.
3. Pour EasyEffects, ouvrez l'application une première fois afin qu'elle charge tes configurations de filtres et d'égaliseur depuis `~/.config/easyeffects/db/`.
