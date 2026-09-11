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
| `install.sh` (racine, non déployé) | installation complète : paquets, oh-my-zsh, chezmoi, système (§1) |
| `system/` (non déployé par chezmoi) | copies des fichiers `/etc` + `install.sh` (sudo, appelé par le script racine) |

---

## 1. Restauration sur une Arch vierge

```bash
git clone https://github.com/Pipouylle/FirstTest.git && bash FirstTest/install.sh   # sudo demandé au besoin
sudo reboot
```

`install.sh` est idempotent (relançable) et enchaîne : paquets officiels → `yay` → paquets AUR →
oh-my-zsh + plugins → `chezmoi init --apply` → `system/install.sh` (sudo : /etc, swap, services, fond SDDM ; §3-4).
Les listes de paquets sont dans le script (`PACMAN=`, `AUR=`) ; `REPO=…` pour viser un fork.

Après redémarrage, en utilisateur :

```bash
tailscale set --accept-dns=false     # si Tailscale est utilisé, voir §4
powerprofilesctl get                 # doit répondre sans traceback
zramctl ; swapon --show              # zram0 3,5 Go prio 100 + /swapfile 4 Go
```

### Pourquoi ces paquets

* `hyprland` 0.56+ (config Lua), `hypridle`/`hyprlock` (installés mais **non lancés** : caelestia gère l'inactivité et le verrouillage), `hyprpolkitagent` (agent polkit, lancé par `scripts/Polkit.sh`).
* `sddm` + `simple-sddm-theme-2-git` (AUR) : écran de connexion et son thème (voir §3).
* `networkmanager` + `wpa_supplicant` + `dnsmasq` : Wi‑Fi et DNS local. **Ne pas installer/activer `iwd`** (doublon, il crée et supprime lui‑même `wlan0`).
* `quickshell-git` + `caelestia-shell` + `caelestia-cli` + `app2unit` (AUR) : le shell tourne depuis la copie gérée `~/.config/quickshell/caelestia/` (patch `Hypr.qml`), mais ses QML font `import Caelestia`, plugin compilé que seul le paquet `caelestia-shell` fournit. Le paquet installe ses QML dans `/etc/xdg/quickshell/caelestia`, que la copie utilisateur masque : il n'écrase rien. Recompiler `quickshell-git` après une mise à jour de Qt.
* `vicinae-bin` (AUR) : lanceur, `vicinae server` au démarrage.
* `awww` : remplaçant de `swww` (renommé upstream) ; `waypaper` (AUR) : sélection des fonds ; `wallust` (AUR) : couleurs depuis le fond d'écran, lues par `lua/colors.lua` et hyprlock ; `nwg-displays` : écrit `monitors.conf`/`workspaces.conf`, que `lua/monitors.lua` relit.
* `linux-wallpaperengine-git` (AUR) : fonds Steam Workshop (lanceur dans `~/.local/bin`, backend de `waypaper/config.ini`) ; `mpvpaper` (AUR) : fonds vidéo (`live_wallpaper` dans `lua/autostart.lua`).
* `rofi`, `yad`, `wlogout` (AUR), `libnotify` : menus et notifications des scripts JaKooLit (SUPER+SHIFT+E, SUPER+H, CTRL+ALT+P, fonds d'écran). Les thèmes rofi (`~/.config/rofi/*.rasi`) ne sont pas dans le dépôt.
* `yazi` + `glow` (aperçu Markdown), `jq`/`go-yq` (aperçus JSON/YAML), `7zip`/`zip`/`unzip` (raccourcis `C`/`U`), `micro` (édition dans le terminal).
* `zed` : le binaire est `zeditor` (alias `zed` dans `.zshrc`) ; `wtype` envoie `ctrl-alt-v` pour ouvrir l'aperçu Markdown côte à côte.
* `wl-clipboard`/`cliphist` : presse‑papiers ; `grim`/`slurp`/`swappy` : captures ; `brightnessctl`/`playerctl`/`pamixer` : touches média ; `xdg-user-dirs` : dossier des captures.
* `ttf-jetbrains-mono-nerd`, `ttf-victor-mono` (AUR) : polices kitty/hyprlock ; `bibata-cursor-theme-bin` (AUR) : curseur de `lua/env.lua` ; `qt6ct`/`nwg-look` : thèmes Qt/GTK (`QT_QPA_PLATFORMTHEME=qt6ct`).
* `nvm` : sourcé sans garde par `.zshrc` (`/usr/share/nvm/init-nvm.sh`).
* `zram-generator`, `earlyoom`, `iw`, `power-profiles-daemon`, `python-gobject` : voir §4 « Réglages système ».
* `ffmpeg`/`imagemagick`/`bc`/`jq` : scripts JaKooLit (aperçus vidéo, météo).

### Hors script (à la main, facultatif)

* **Anaconda** dans `~/anaconda3`. `~/.condarc` désactive l'activation automatique : sinon `~/anaconda3/bin` passe devant `/usr/bin` et casse `jq`, `python3`, `powerprofilesctl`.
* Outils perso référencés par `.zshrc`/`.zprofile` sans en dépendre : SDKMAN, JetBrains Toolbox, Antigravity, `claude`, `gemini`, Docker/kubectl (plugins oh-my-zsh seulement).
* Avatar du tableau de bord caelestia : `cp avatar.jpg ~/.face`.

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

`/etc/sddm.conf` (dans `system/`) sélectionne le thème `simple_sddm_2`. Le fond de l'écran de connexion
suit le fond d'écran courant : `system/install.sh` crée `/var/lib/sddm_wallpaper.jpg` (propriété de
l'utilisateur) et y fait pointer `/usr/share/sddm/themes/simple_sddm_2/Backgrounds/default` ;
`UserScripts/WallpaperSelect.sh` y copie ensuite le fond choisi.

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
Sauvegarde du fichier d'origine : `Hypr.qml.bak-2026-09-11`. Le paquet AUR `caelestia-shell` installe
ses QML dans `/etc/xdg/quickshell/caelestia` (masqués par cette copie) et fournit le plugin compilé
`Caelestia` : il est requis, et n'écrase pas ce fichier.

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
