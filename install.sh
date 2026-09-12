#!/usr/bin/env bash
# Installation complète sur une Arch vierge : paquets (pacman + AUR), oh-my-zsh,
# dotfiles (chezmoi), puis réglages système (system/install.sh via sudo).
#   bash install.sh        # en utilisateur ; sudo est demandé quand il faut
# Idempotent : relançable (--needed partout, clones sautés s'ils existent).
# Justification des paquets : README.md §1.
set -euo pipefail
[[ $EUID -ne 0 ]] || { echo "À lancer en utilisateur (pas root ni sudo)."; exit 1; }
here=$(cd "$(dirname "$0")" && pwd)
REPO=${REPO:-$(git -C "$here" remote get-url origin 2>/dev/null || echo https://github.com/Pipouylle/FirstTest.git)}
step() { printf '\n\e[1m== %s ==\e[0m\n' "$*"; }

PACMAN=(
  # Hyprland, session, portails
  hyprland hypridle hyprlock hyprpolkitagent xdg-desktop-portal-hyprland xdg-desktop-portal-gtk
  xdg-utils xdg-user-dirs qt6-wayland qt6ct nwg-look sddm
  # audio, réseau, bluetooth
  pipewire pipewire-pulse wireplumber pavucontrol easyeffects
  networkmanager network-manager-applet dnsmasq wpa_supplicant iw bluez bluez-utils blueman
  # shell et outils terminal
  kitty zsh lsd fastfetch fzf tree bc jq go-yq nvm btop cava
  yazi glow micro 7zip zip unzip zed wtype
  # fonds d'écran, écrans, aperçus
  awww nwg-displays imagemagick ffmpeg
  # menus, notifications, presse-papiers, captures, touches média (scripts JaKooLit)
  rofi yad libnotify wl-clipboard cliphist grim slurp swappy brightnessctl playerctl pamixer
  # polices, apps
  ttf-jetbrains-mono-nerd noto-fonts noto-fonts-emoji nautilus firefox
  # système (README §4) et outillage
  zram-generator earlyoom power-profiles-daemon python-gobject git base-devel chezmoi
)
AUR=(
  # caelestia : le shell tourne depuis ~/.config/quickshell/caelestia (chezmoi), mais
  # `import Caelestia` a besoin du plugin QML compilé que seul le paquet caelestia-shell
  # fournit. Ses QML vont dans /etc/xdg/quickshell/caelestia : la copie utilisateur les masque.
  quickshell-git caelestia-shell caelestia-cli app2unit
  vicinae-bin                              # lanceur (SUPER+D)
  wallust waypaper mpvpaper wlogout        # couleurs, choix des fonds, fonds vidéo, menu déconnexion
  linux-wallpaperengine-git                # fonds Steam Workshop (backend waypaper ; build long)
  simple-sddm-theme-2-git                  # thème SDDM (system/etc/sddm.conf)
  ttf-victor-mono bibata-cursor-theme-bin  # police hyprlock, curseur (lua/env.lua)
)

step "paquets officiels"
sudo pacman -Syu --needed --noconfirm "${PACMAN[@]}"

step "yay"
if ! command -v yay >/dev/null; then
  tmp=$(mktemp -d)
  git clone --depth 1 https://aur.archlinux.org/yay-bin.git "$tmp/yay-bin"
  (cd "$tmp/yay-bin" && makepkg -si --noconfirm)
  rm -rf "$tmp"
fi

step "paquets AUR"
yay -S --needed --noconfirm "${AUR[@]}"

step "contrôle de version caelestia-shell"
want=$(cat "$(chezmoi source-path)/dot_config/quickshell/caelestia/dot_upstream-version" 2>/dev/null || echo inconnu)
have=$(pacman -Q caelestia-shell 2>/dev/null | awk '{print $2}' | cut -d- -f1)
[[ $want == "$have" ]] || cat <<MSG
ATTENTION : le fork QML de ~/.config/quickshell/caelestia vise caelestia-shell $want,
mais $have est installé. Le shell risque de ne pas démarrer (API du plugin).
Voir docs/superpowers/plans/ pour la procédure de portage.
MSG

step "oh-my-zsh + plugins"
[[ -d ~/.oh-my-zsh ]] || sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended --keep-zshrc
plugins=${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins
clone() { [[ -d $2 ]] || git clone --depth 1 "$1" "$2"; }
clone https://github.com/zsh-users/zsh-syntax-highlighting.git "$plugins/zsh-syntax-highlighting"
clone https://github.com/zsh-users/zsh-autosuggestions "$plugins/zsh-autosuggestions"
clone https://github.com/enrico9034/watch-plugin-zsh.git "$plugins/watch"
[[ $SHELL == */zsh ]] || chsh -s "$(command -v zsh)"

step "dotfiles (chezmoi)"
if [[ -d ~/.local/share/chezmoi/.git ]]; then chezmoi apply; else chezmoi init --apply "$REPO"; fi
mkdir -p ~/Pictures/wallpapers   # lu par UserScripts/WallpaperSelect.sh et WallpaperRandom.sh
LC_ALL=C xdg-user-dirs-update --force   # cree ~/Documents, ~/Music, ~/Videos, etc. (noms anglais : ~/Pictures et ~/Downloads sont codes en dur dans les dotfiles)

step "système : /etc, swap, services (sudo)"
sudo bash "$(chezmoi source-path)/system/install.sh"

cat <<'MSG'

Terminé. Redémarrer (sudo reboot), puis :
  - SDDM → session Hyprland ; caelestia démarre via lua/autostart.lua
  - zramctl ; swapon --show          (zram + /swapfile)
  - facultatif : cp avatar.jpg ~/.face ; tailscale set --accept-dns=false
MSG
