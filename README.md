# Dotfiles — Arch Linux + Hyprland (Lua) + caelestia-shell

Gérés avec [chezmoi](https://www.chezmoi.io/). Dernière remise à plat : 2026-09-11
(migration Hyprland en Lua, Yazi/Zed/Kitty ajoutés, réglages de performance).
Machine de référence : Lenovo IdeaPad Slim 3 15AMN8, Ryzen 3 7320U, 8 Go, Radeon 610M.

Contenu géré :

| Cible | Rôle |
|---|---|
| `~/.config/hypr/` | Hyprland en **Lua** (`hyprland.lua` + `lua/`), scripts, hyprlock, hypridle, profils d'écran, `legacy/` (ancienne config hyprlang, non chargée) |
| `~/.config/quickshell/caelestia/` | caelestia-shell (barre, notifications, verrouillage, OSD), avec le patch `services/Hypr.qml` pour l'API Lua |
| `~/.config/caelestia/` | réglages caelestia (`shell.json`) |
| `~/.config/yazi/` | gestionnaire de fichiers : ouvreurs Zed/micro, zip/unzip, aperçus glow/jq/yq (plugins inclus, déjà patchés pour Yazi 26.x) |
| `~/.config/zed/` | keymap (aperçu Markdown `ctrl-alt-v`), settings, thème caelestia |
| `~/.config/kitty/` | terminal + thèmes |
| `~/.config/easyeffects/`, `waypaper/`, `fastfetch/`, `vicinae/` | audio, fonds d'écran, fetch, lanceur |
| `~/.zshrc`, `~/.zprofile`, `~/.condarc` | shell (oh-my-zsh), conda **sans** activation auto de `base` |
| `~/.local/bin/linux-wallpaperengine` | lanceur Wallpaper Engine |
| `system/` (non déployé par chezmoi) | copies des fichiers `/etc` + `install.sh` |

---

## 1. Restauration sur une Arch vierge

Ordre à respecter : paquets → oh-my-zsh → chezmoi → script système → redémarrage.

### A. Paquets des dépôts officiels

```bash
sudo pacman -S --needed \
  hyprland hypridle hyprlock hyprpolkitagent xdg-desktop-portal-hyprland xdg-desktop-portal-gtk \
  qt6-wayland sddm pipewire wireplumber \
  networkmanager network-manager-applet dnsmasq wpa_supplicant bluez bluez-utils blueman \
  kitty zsh lsd fastfetch fzf tree bc jq go-yq \
  yazi glow micro 7zip zip unzip \
  zed wtype \
  awww waypaper wallust nwg-displays \
  wl-clipboard cliphist grim slurp swappy \
  brightnessctl playerctl pamixer easyeffects cava btop \
  ffmpeg imagemagick git base-devel cmake meson ninja \
  ttf-jetbrains-mono-nerd noto-fonts-emoji \
  nautilus firefox \
  zram-generator earlyoom iw power-profiles-daemon python-gobject \
  chezmoi
```

Pourquoi ces paquets :

* `hyprland` 0.56+ (config Lua), `hypridle`/`hyprlock` (installés mais **non lancés** : caelestia gère l'inactivité et le verrouillage), `hyprpolkitagent` (agent polkit, lancé par `scripts/Polkit.sh`).
* `sddm` : écran de connexion, thème `simple_sddm_2` (voir §3).
* `networkmanager` + `wpa_supplicant` + `dnsmasq` : Wi‑Fi et DNS local. **Ne pas installer/activer `iwd`** (doublon, il crée et supprime lui‑même `wlan0`).
* `awww` : remplaçant de `swww` (renommé upstream) ; `waypaper` : sélection des fonds ; `wallust` : couleurs depuis le fond d'écran, lues par `lua/colors.lua` et hyprlock ; `nwg-displays` : écrit `monitors.conf`/`workspaces.conf`, que `lua/monitors.lua` relit.
* `yazi` + `glow` (aperçu Markdown), `jq`/`go-yq` (aperçus JSON/YAML), `7zip`/`zip`/`unzip` (raccourcis `C`/`U`), `micro` (édition dans le terminal).
* `zed` : le binaire est `zeditor` (alias `zed` dans `.zshrc`) ; `wtype` envoie `ctrl-alt-v` pour ouvrir l'aperçu Markdown côte à côte.
* `wl-clipboard`/`cliphist` : presse‑papiers ; `grim`/`slurp`/`swappy` : captures ; `brightnessctl`/`playerctl`/`pamixer` : touches média.
* `zram-generator`, `earlyoom`, `iw`, `power-profiles-daemon`, `python-gobject` : voir §4 « Réglages système ».
* `ffmpeg`/`imagemagick`/`bc`/`jq` : scripts JaKooLit (aperçus vidéo, météo).

### B. Paquets AUR (`yay -S --needed …`)

```bash
yay -S --needed quickshell-git caelestia-cli linux-wallpaperengine-git mpvpaper simple-sddm-theme-2-git
```

* `quickshell-git` : moteur de caelestia-shell. À recompiler (`yay -S quickshell-git`) après une mise à jour de Qt.
* `caelestia-cli` : commande `caelestia` (schémas, fonds). **Ne pas installer `caelestia-shell`** : le shell tourne depuis la copie gérée `~/.config/quickshell/caelestia/`, qui contient le patch `Hypr.qml` (traduction des dispatchers legacy vers l'API Lua).
* `linux-wallpaperengine-git` : fonds Steam Workshop (lanceur dans `~/.local/bin`).
* `mpvpaper` : fonds vidéo (`live_wallpaper` dans `lua/autostart.lua`). Pas installé sur la machine de référence au 2026‑09‑11 : à installer si les fonds vidéo sont utilisés.
* `simple-sddm-theme-2-git` : thème SDDM (le dossier `/usr/share/sddm/themes/simple_sddm_2` existe sur la machine de référence sans paquet pacman ; réinstaller via l'AUR ou recopier le dossier).

### C. Installés à la main (hors pacman)

* **vicinae** (lanceur, `vicinae server` au démarrage) : AppImage des releases GitHub (<https://github.com/vicinaehq/vicinae>) décompressée dans `/usr/local/lib/vicinae`, lien `/usr/local/bin/vicinae` vers `usr/bin/vicinae`, fichiers `.desktop` dans `/usr/local/share/applications`. Refaire pareil ou utiliser le paquet AUR `vicinae-bin` s'il existe.
* **Anaconda** dans `~/anaconda3` (facultatif). `~/.condarc` désactive l'activation automatique : sinon `~/anaconda3/bin` passe devant `/usr/bin` et casse `jq`, `python3`, `powerprofilesctl`.
* **oh-my-zsh** + plugins, avant `chezmoi apply` :

```bash
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
git clone https://github.com/enrico9034/watch-plugin-zsh.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/watch
```

### D. Déployer les dotfiles puis le système

```bash
chezmoi init --apply git@github.com:Pipouylle/FirstTest.git   # ou l'URL https
sudo bash ~/.local/share/chezmoi/system/install.sh            # /etc, swap, services (§4)
sudo reboot
```

Après redémarrage, en utilisateur :

```bash
tailscale set --accept-dns=false     # si Tailscale est utilisé, voir §4
powerprofilesctl get                 # doit répondre sans traceback
zramctl ; swapon --show              # zram0 3,5 Go prio 100 + /swapfile 4 Go
```

---

## 2. Hyprland en Lua

Point d'entrée `~/.config/hypr/hyprland.lua`, modules dans `lua/` (monitors, env, settings,
decorations, animations, rules, binds, laptop, binds-caelestia, autostart). Détails, différences et
retour arrière dans `~/.config/hypr/README.md`. À retenir :

* Sous le gestionnaire Lua, `hyprctl keyword`, `hyprctl setprop` et l'ancienne syntaxe
  `hyprctl dispatch <nom>` sont refusés. Tout passe par `hyprctl eval 'hl....'`
  (ex. `hyprctl dispatch 'hl.dsp.focus({ workspace = "3" })'`). Tous les scripts de `scripts/` et
  `UserScripts/` sont déjà adaptés ; `UserScripts/hypr-window hide|show|focus` gère une fenêtre par pid.
* **Ne jamais lancer `hyprctl reload full-reset`** (retour à chaud vers hyprlang) : plante Hyprland 0.56.2.
* Le démarrage automatique est dans `lua/autostart.lua` (awww ou mpvpaper, caelestia `qs -c caelestia -d`,
  vicinae, cliphist, easyeffects, portails). Un marqueur dans `$XDG_RUNTIME_DIR` évite de relancer à chaque reload.
* Les couleurs wallust sont lues au chargement : les scripts font `hyprctl reload` après `wallust run`.
* Capot : `UserScripts/lid-switch` ne coupe l'écran interne que si un autre écran est actif et que la
  session n'est pas verrouillée (sinon crash screencopy caelestia).
* Écrans : TV `desc:LG Electronics LG TV 0x01010101` à gauche (0x0), `eDP-1` à 1920x0, dans `monitors.conf`.
* Raccourcis retirés faute d'équivalent Lua : SUPER+M (`splitratio`), SUPER+ALT+SPACE (`workspaceopt`).

## 3. SDDM

`/etc/sddm.conf` (dans `system/`) sélectionne le thème `simple_sddm_2`. Pour synchroniser le fond de
l'écran de connexion avec le fond d'écran courant (fait par `UserScripts/WallpaperSelect.sh`) :

```bash
sudo touch /var/lib/sddm_wallpaper.jpg && sudo chown $USER:$USER /var/lib/sddm_wallpaper.jpg
sudo ln -sf /var/lib/sddm_wallpaper.jpg /usr/share/sddm/themes/simple_sddm_2/Backgrounds/default
```

Connexion automatique (facultatif) : `/etc/sddm.conf.d/autologin.conf` avec `[Autologin] User=timothe Session=hyprland`.
Sans SDDM : décommenter le bloc `exec Hyprland` dans `~/.zprofile`.

## 4. Réglages système (`system/install.sh`)

Copies dans `system/etc/`, appliquées par le script. Justification (mesures du 2026‑09‑11, 8 Go de RAM,
SSD sans DRAM, dizaines d'OOM kills dans le journal avant) :

| Fichier / action | Effet |
|---|---|
| `systemd/zram-generator.conf` | zram0 = RAM/2 en zstd, priorité 100 |
| `tmpfiles.d/disable-zswap.conf` | coupe zswap (ne pas cumuler avec zram) |
| `sysctl.d/99-zram.conf` | swappiness 180, page-cluster 0 (valeurs wiki Arch pour zram) |
| `/swapfile` 4 Go, priorité -1 | filet derrière la zram (32 Go avant) ; hibernation non gérée |
| `default/earlyoom` | tue processus par processus (Firefox d'abord) sous 5 % RAM et 50 % swap libres ; protège Hyprland, qs, pipewire, sddm |
| `NetworkManager/NetworkManager.conf` | `dns=dnsmasq` |
| services | active NetworkManager, earlyoom, sddm, bluetooth, `docker.socket` (à la demande) ; désactive iwd, netbird, rustdesk, `docker.service` |
| `tailscale set --accept-dns=false` | DNS système indépendant de tailscaled (les noms MagicDNS ne se résolvent plus, les IP 100.x oui) |

Autres choix de performance déjà dans les dotfiles : flou Hyprland `size = 4, passes = 1`
(`lua/decorations.lua`) ; `ALT+O` (`scripts/ChangeBlur.sh`) bascule encore entre 5/2 et 2/1.
`power-profiles-daemon` est en `performance` sur secteur et `low-power` sur batterie ; forcer avec
`powerprofilesctl set performance`.

## 5. caelestia-shell

Lancé par `lua/autostart.lua` (`qs -c caelestia -d`). Recharger à la main :

```bash
qs kill -c caelestia && qs -c caelestia -d
```

`services/Hypr.qml` sonde le gestionnaire de config (`hyprctl keyword zz_probe 1`) et traduit
`workspace N`, `togglespecialworkspace`, `focuswindow`, `movetoworkspace`, `dpms …` en API Lua.
Sauvegarde du fichier d'origine : `Hypr.qml.bak-2026-09-11`. Ne pas écraser ce fichier avec
`caelestia-shell` du paquet AUR.

## 6. Yazi, Zed, Kitty

* Yazi : `Entrée`/`O` sur un fichier → Zed dans la fenêtre courante, ou en cachant/remplaçant le terminal
  (`UserScripts/yazi-zed-swap`) ; `.md` → Zed avec aperçu côte à côte (`UserScripts/zed-md-preview`) ;
  `micro` dans le même terminal ; `C` = zip, `U` = unzip ; dossiers → Zed. Kitty exporte `KITTY_PID`,
  utilisé pour retrouver la fenêtre.
* Zed : `~/.config/zed/keymap.json` lie `ctrl-alt-v` à `markdown::OpenPreviewToTheSide`
  (le keymap JetBrains masque `ctrl-k`). Le thème caelestia est dans `themes/`.
* Kitty : le thème vient de `~/.zshrc` (`cat ~/.local/state/caelestia/sequences.txt`), donc les terminaux
  relancés par script le sont en `zsh -ic`.

## 7. Partage d'écran (PipeWire + xdg-desktop-portal-hyprland)

Les portails sont lancés par `scripts/PortalHyprland.sh` depuis `lua/autostart.lua`. Dans Chromium/Brave :
`chrome://flags` → *Preferred Ozone platform* → **Wayland**.

## 8. Synchroniser

```bash
chezmoi update                 # pull + apply
chezmoi git pull && chezmoi diff && chezmoi apply   # pas à pas
chezmoi re-add && chezmoi git -- add -A && chezmoi git -- commit -m "…" && chezmoi git -- push
```

Le dossier `system/` n'est pas déployé par chezmoi (`.chezmoiignore`) : après avoir modifié un fichier
dans `/etc`, le recopier à la main dans `system/etc/`.
