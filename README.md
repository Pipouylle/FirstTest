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
| `~/.config/yazi/` | gestionnaire de fichiers : ouvreurs Zed/micro, zip/unzip, aperçus glow/jq/yq, et **bac à sable Firejail (touche `O`)** |
| `~/.config/zed/` | keymap (aperçu Markdown `ctrl-alt-v`), settings, thème caelestia |
| `~/.config/kitty/` | terminal + thèmes |
| `~/.config/easyeffects/`, `waypaper/`, `fastfetch/`, `vicinae/` | audio, fonds d'écran, fetch, lanceur |
| `~/.local/bin/bwrap-app` | sandbox Bubblewrap durci pour une appli quelconque : `$HOME` vide, bus D-Bus filtré (`xdg-dbus-proxy`), seuls Wayland/PipeWire/Pulse montés, `/tmp` partagé entre lancements, GPU |
| `~/.local/share/applications/chromium.desktop`, `~/.local/bin/chromium-sbx`, `~/.local/bin/dbus-uid-relay`, `~/.local/bin/chromium-sbx-fichiers`, `~/.config/systemd/user/chromium-sbx-{wayland,dbus,dbus-relay}.service`, `~/.config/pipewire/pipewire-pulse.conf.d/chromium-sbx.conf` | partie session de **Chromium sous le compte dédié `chromium`** : le raccourci lance `chromium-sbx`, qui démarre les sockets de passage dans `/run/chromium-sbx` (Wayland en contexte de sécurité Hyprland, bus D-Bus filtré + relais d'authentification, son PipeWire restreint) puis le lanceur interne root via sudo. Le profil (`/var/lib/chromium-sbx`) est illisible par la session. Sélecteur de fichiers : le relais répond aux demandes de Chromium avec `chromium-sbx-fichiers` (mot de passe KeePassXC valable 10 min, fenêtre de la session, copie dans `/srv/chromium-sbx/Envois` supprimée au bout d'1 h) |
| `~/.local/bin/keepass-tokens` | tokens d'`agy` et de `claude` dans le groupe « Tokens CLI » de la base KeePassXC principale (groupe non exposé au Secret Service) : mot de passe maître demandé par application dans une fenêtre `pinentry-gtk` (flottante via `lua/rules.lua`), valable 10 min après sa dernière utilisation. Chaque demande affiche la phrase anti-hameçonnage de `~/.config/keepass-tokens/phrase` (hors chezmoi). Sous-commandes `set-claude`, `lock` et `verifier <appli>` (mot de passe maître seul, pour le sélecteur de fichiers de Chromium), et pour les comptes dédiés (`system/chromium-sbx`) `set-account <compte>` et `sudo <compte> <commande>`, avec le mot de passe du compte lu dans KeePassXC à chaque fois |
| `~/.local/bin/bwrap-agent` | sandbox Bubblewrap d'`agy` et de `claude`, lancé par `keepass-tokens`. Il garde l'accès au reste du PC, mais aucun agent ne voit le token, la config ou les processus de l'autre. Secrets masqués (SSH, GPG, fichier clé et config KeePassXC, phrase anti-hameçonnage, profils de navigateurs et de messageries), fichiers de démarrage en lecture seule, ni IPC Hyprland, ni systemd, ni bus système, `/tmp` privé |
| `~/.zshrc`, `~/.zprofile`, `~/.condarc` | shell (oh-my-zsh), fonctions `agy` et `claude` (passent par `keepass-tokens` ; `command claude` les contourne), alias `chromium` → `chromium-sbx`, conda **sans** activation auto de `base` |
| `~/.local/bin/linux-wallpaperengine` | lanceur Wallpaper Engine |
| `install.sh` (racine, non déployé) | installation complète : paquets (dont Timeshift, KeePassXC, OpenSnitch, Firejail), oh-my-zsh, chezmoi, système |
| `system/` (non déployé par chezmoi) | copies des fichiers `/etc` (zram, earlyoom, timeshift) + `install.sh` (sudo, appelé par le script racine) |
| `system/chromium-sbx/` (non déployé par chezmoi) | partie root de Chromium sous compte dédié : `wayland-sandbox-socket.c` + `build.sh`, `chromium-sbx-inner`, `sudoers-chromium-sbx`, `tmpfiles-chromium-sbx.conf`, `install.sh` (sudo), `test.sh` (test complet), `tests/` (tests automatiques du relais et du sélecteur de fichiers), `README.md` |
| `docs/` | **Guides spécialisés détaillés** (installation, maintenance, architecture technique de sécurité) |

---

## 📚 Guides et Documentation Dédiée

Pour aller plus loin et gérer l'ensemble des cas d'usage, deux guides complets sont disponibles dans `docs/` :

* 🛠️ **[Guide d'Installation, Déploiement et Maintenance](docs/INSTALLATION_ET_MAINTENANCE.md)** :  
  Procédure pas à pas d'installation complète d'Arch Linux, choix et gestion du trousseau KeePassXC (restaurer une base existante vs en créer une nouvelle), configuration des applications (Chromium, Discord, Firejail), politique d'entretien du système et **procédures de restauration (rollback) de l'OS avec Timeshift** (en mode graphique, en console TTY ou depuis une clé Live USB).

* 🛡️ **[Architecture de Sécurité & Fonctionnement des Technologies](docs/SECURITE_ET_ARCHITECTURE.md)** :  
  Explication technique approfondie du fonctionnement sous le capot : comment Timeshift gère les instantanés incrémentaux par *hard links* sur ext4 sans ralentir le boot (`Nice=19`, `idle`), fonctionnement du protocole Secret Service et des popups d'autorisation ACL dans KeePassXC, isolation d'applications dans des namespaces Linux en RAM par Firejail, blocage des exfiltrations de données par le pare-feu sortant OpenSnitch, stockage des tokens CLI, sandbox Bubblewrap de Chromium (failles de la première version), Chromium sous un compte Unix dédié (`chromium-sbx`) et sandbox des agents CLI (`bwrap-agent`).

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
* `yazi` + `glow` (aperçu Markdown), `jq`/`go-yq` (aperçus JSON/YAML), `7zip`/`zip`/`unzip` (raccourcis `Z`/`U` ; `C` lance Claude Code dans le dossier affiché), `micro` (édition dans le terminal).
* `zed` : le binaire est `zeditor` (alias `zed` dans `.zshrc`) ; `wtype` envoie `ctrl-alt-v` pour ouvrir l'aperçu Markdown côte à côte.
* `wl-clipboard`/`cliphist` : presse‑papiers ; `grim`/`slurp`/`swappy` : captures ; `brightnessctl`/`playerctl`/`pamixer` : touches média ; `xdg-user-dirs` : dossier des captures.
* `ttf-jetbrains-mono-nerd`, `ttf-victor-mono` (AUR) : polices kitty/hyprlock ; `bibata-cursor-theme-bin` (AUR) : curseur de `lua/env.lua` ; `qt6ct`/`nwg-look` : thèmes Qt/GTK (`QT_QPA_PLATFORMTHEME=qt6ct`).
* `nvm` : sourcé sans garde par `.zshrc` (`/usr/share/nvm/init-nvm.sh`).
* `zram-generator`, `earlyoom`, `iw`, `power-profiles-daemon`, `python-gobject` : voir §4 « Réglages système ».
* `ffmpeg`/`imagemagick`/`bc`/`jq` : scripts JaKooLit (aperçus vidéo, météo).
* `timeshift` : instantanés incrémentaux automatiques de l'OS au boot (`timeshift-boot.service`, conservation des 5 derniers démarrages).
* `keepassxc` : gestionnaire de coffre-fort et fournisseur Secret Service avec popups d'autorisation ACL par application.
* `opensnitch` : pare-feu applicatif sortant pour bloquer les fuites et exfiltrations de données ou tokens.
* `firejail` : bac à sable isolant les programmes dans un dossier éphémère en RAM (accessible depuis Yazi avec la touche `O`).
* `chromium` + `discord` : navigateur principal (chiffré via Secret Service, lancé sous le compte dédié `chromium` : voir `system/chromium-sbx/`) et messagerie. `xdg-dbus-proxy`, `bubblewrap`, `pinentry` : sandboxes et saisie des mots de passe. `python-jeepney`, `zenity` : sélecteur de fichiers de Chromium (relais D-Bus, fenêtre de sélection).

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
* Le démarrage automatique est dans `lua/autostart.lua` (awww ou mpvpaper, caelestia `qs -c caelestia -n -d`,
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

Lancé par `lua/autostart.lua` (`qs -c caelestia -n -d`). Recharger à la main (ou CTRL+SUPER+SHIFT+R) :

```bash
qs kill -c caelestia; sleep 0.5; pkill -x qs; sleep 0.5; qs -c caelestia -n -d
```

`-n` (`--no-duplicate`) refuse de lancer une 2e instance. Le 15/09/2026, deux instances ont tourné après
le boot, où le chargement de la config a pris ~27 s (cause non identifiée) ; origine probable : un redémarrage
pendant ce chargement, quand `qs kill` (IPC) ne peut pas encore répondre. `pkill -x qs` sert de repli ;
`-x` compare le nom du processus, donc la commande ne se tue pas elle-même.

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
  **Touche `O` sur n'importe quel fichier** : propose désormais également l'exécution isolée en bac à sable
  **`Firejail (Private, Pas d'Internet)`** et **`Firejail (Private, Internet Actif)`** (`UserScripts/yazi-firejail`).
* Zed : `~/.config/zed/keymap.json` lie `ctrl-alt-v` à `markdown::OpenPreviewToTheSide`
  (le keymap JetBrains masque `ctrl-k`). Le thème caelestia est dans `themes/`.
* Kitty : le thème vient de `~/.zshrc` (`cat ~/.local/state/caelestia/sequences.txt`), donc les terminaux
  relancés par script le sont en `zsh -ic`.

## 7. Partage d'écran (PipeWire + xdg-desktop-portal-hyprland)

Les portails sont lancés par `scripts/PortalHyprland.sh` depuis `lua/autostart.lua`. Chromium (compte dédié) : Wayland est forcé par `chromium-sbx-inner`, et le partage d'écran passe par
le portail ScreenCast, autorisé par son bus filtré. Brave : `chrome://flags` → *Preferred Ozone platform* → **Wayland**.

## 8. Sécurité et Restauration Système (Rollback)

* **Timeshift au boot** : un instantané incrémental par liens physiques est créé à chaque démarrage via `timeshift-boot.service` (conserve les 5 derniers démarrages).
  - Restauration graphique : `sudo timeshift-gtk`.
  - Restauration d'urgence en TTY (si le bureau plante) : `sudo timeshift --restore`.
* **KeePassXC (Secret Service)** : lancé minimisé au démarrage (`lua/autostart.lua`). Répond aux demandes de secrets pour le **groupe exposé** de la base (à configurer par base, sinon popups de déverrouillage sans base) et peut demander confirmation avant de livrer un secret.
* **OpenSnitch** : pare-feu applicatif actif au démarrage (`opensnitch-ui`), surveille et bloque les connexions sortantes suspectes.
* **Chromium sous le compte dédié `chromium` (`chromium-sbx`)** : profil dans `/var/lib/chromium-sbx` (0700), illisible par les programmes de la session, qui ne peuvent pas non plus inspecter ni signaler les processus de Chromium. Lancé sans mot de passe par une règle sudo limitée au lanceur interne root, qui refuse toute option. Chromium reste dans Bubblewrap ; son socket Wayland est un contexte de sécurité Hyprland (ni capture d'écran, ni clavier virtuel), son bus D-Bus est filtré, son son passe par PipeWire en accès restreint. Administration : `keepass-tokens sudo chromium <commande>`. Téléchargements : `/srv/chromium-sbx/Downloads`. Envois : fenêtre de sélection de la session, avec le mot de passe KeePassXC (valable 10 min) ; Chromium reçoit une copie, supprimée au bout d'1 h. Voir `system/chromium-sbx/README.md` et `docs/SECURITE_ET_ARCHITECTURE.md` §7.
* **Tokens CLI (Claude, Agy)** : dans le groupe « Tokens CLI » de la base KeePassXC principale (groupe non exposé au Secret Service), lu par `keepass-tokens`. Le mot de passe maître est demandé par application et reste valable 10 min après sa dernière utilisation ; pendant ce temps, le token est en RAM. Invisibles depuis Chromium (autre compte Unix) et d'un agent à l'autre (`bwrap-agent`, `docs/SECURITE_ET_ARCHITECTURE.md` §8). Première installation : `command claude setup-token`, puis `keepass-tokens set-claude`. `keyring-vault` a été retiré (voir `docs/SECURITE_ET_ARCHITECTURE.md` §5). **Disque non chiffré** : sans LUKS, `~/.claude/.credentials.json`, s'il existe encore, est lisible par qui accède au disque.
* *Pour la documentation exhaustive et tous les cas de figure : voir `docs/INSTALLATION_ET_MAINTENANCE.md` et `docs/SECURITE_ET_ARCHITECTURE.md`.*

## 9. Synchroniser

```bash
chezmoi update                 # pull + apply
chezmoi git pull && chezmoi diff && chezmoi apply   # pas à pas
chezmoi re-add && chezmoi git -- add -A && chezmoi git -- commit -m "…" && chezmoi git -- push
```

Le dossier `system/` n'est pas déployé par chezmoi (`.chezmoiignore`) : après avoir modifié un fichier
dans `/etc`, le recopier à la main dans `system/etc/`.
