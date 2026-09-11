# Hyprland : nettoyage de la config hyprlang puis migration vers Lua

Date : 2026-09-11. Validé en discussion (approche « nettoyage puis migration », TV à gauche).

## Contexte

- Hyprland 0.56.2 (Arch), config héritée des dotfiles JaKooLit, complétée par une
  intégration caelestia-shell (barre, notifications, verrouillage, OSD).
- Depuis Hyprland 0.55 le format documenté est `hyprland.lua`. Les fichiers `.conf`
  (hyprlang) passent par le chargeur « legacy », toujours supporté, sans date de retrait,
  mais plus documenté. `hyprctl reload full-reset` permet de basculer entre les deux.
- État actuel : `hyprctl configerrors` vide ; ~600 lignes utiles réparties sur 14 fichiers,
  ~40 % de commentaires (bannières, liens wiki, blocs NVIDIA, alternatives commentées).
- Outils tiers qui produisent ou lisent du hyprlang : wallust (couleurs →
  `wallust/wallust-hyprland.conf`, aussi lu par hyprlock), nwg-displays et hyprmon
  (`monitors.conf`, `workspaces.conf`), cinq scripts JaKooLit
  (`TouchPad.sh`, `SwitchKeyboardLayout.sh`, `KeyBinds.sh`, `Kool_Quick_Settings.sh`,
  `WallpaperSelect.sh`).

## Objectifs

1. Config lisible, sans fichiers morts ni commentaires hérités, commentée en français court.
2. Config au format Lua, modulaire, sans perte de comportement.
3. Les outils tiers continuent de fonctionner (wallust, nwg-displays, profils d'écran,
   menu Réglages, pavé tactile, disposition clavier, fond d'écran vidéo).
4. Retour arrière possible à tout moment.

## Hors périmètre

- hyprlock.conf, hyprlock-2k.conf, hypridle.conf restent en hyprlang (programmes séparés).
  hypridle.conf reçoit seulement un allègement de commentaires.
- Aucun changement de raccourci, de règle ou de valeur, sauf ceux listés ci-dessous.
- Les dossiers `animations/`, `wallpaper_effects/`, `scheme/`, `scripts/`, `UserScripts/`
  ne sont pas restructurés.

## Phase 1 : nettoyage hyprlang

Chaque étape est suivie de `hyprctl reload` puis `hyprctl configerrors`.

Supprimer :
- `hyprland.conf.bak.1780911312`, `.1780911313`, `.1780911314`, `monitors.conf.bak`,
  `UserConfigs/Laptops.conf.bak`
- `UserConfigs/WindowRules-old.conf` (non chargé, syntaxe `windowrulev2` refusée)
- `UserConfigs/LaptopDisplay.conf` (vide) et sa ligne `source`
- `v2.3.15`, `UserConfigs/00-Readme`
- `initial-boot.sh` et sa ligne `exec-once` (marqueur `.initial_startup_done` présent,
  le script ne s'exécute plus jamais)

Modifier :
- `hyprland.conf` : retirer les `source` commentés (Monitors.conf, WorkspaceRules.conf) et
  les deux lignes `monitor=` finales ; reporter la disposition « TV à gauche » dans
  `monitors.conf` (TV `desc:LG Electronics LG TV 0x01010101` à `0x0`, `eDP-1` à `1920x0`).
- Tous les `.conf` chargés : réécrire les commentaires (en-tête d'une ligne par fichier,
  sections courtes en français), supprimer bannières, liens wiki, blocs NVIDIA/VM,
  binds et exec commentés depuis longtemps. Conserver les notes qui expliquent un choix
  (unbind des touches média pour caelestia, capot, `stay_focused` vicinae).
- `Laptops.conf` : retirer le bloc « WARNING » et les binds commentés vers LaptopDisplay.

Conserver tels quels : `Monitor_Profiles/`, `monitors.json`, `workspaces.conf`,
`application-style.conf`, `wallust/`, `scheme/`.

Vérification de fin de phase : `hyprctl configerrors` vide, même nombre de binds
(`hyprctl binds | grep -c key:`), mêmes écrans (`hyprctl monitors`), session intacte.

## Phase 2 : migration vers `hyprland.lua`

### Structure

```
~/.config/hypr/
  hyprland.lua          -- point d'entrée : require des modules dans l'ordre
  lua/
    colors.lua          -- lit wallust/wallust-hyprland.conf → table {color0.., background, foreground}
    monitors.lua        -- lit monitors.conf et workspaces.conf (hyprlang) → hl.monitor / hl.workspace_rule
    env.lua             -- hl.env(...)
    autostart.lua       -- hl.on("hyprland.start", ...) : mêmes commandes que Startup_Apps.conf
    settings.lua        -- hl.config{ general, input, misc, binds, xwayland, render, cursor, dwindle, master }, hl.gesture
    decorations.lua     -- hl.config{ general.col, decoration, group } avec les couleurs wallust
    animations.lua      -- hl.curve + hl.animation (mêmes courbes et vitesses)
    binds.lua           -- raccourcis JaKooLit (configs/Keybinds.conf + UserKeybinds.conf), variables term/files/editor
    binds-caelestia.lua -- overrides caelestia (remplace les unbind + rebind)
    laptop.lua          -- hl.device pavé tactile, touches ASUS, F6, capot (switch:on/off)
    rules.lua           -- hl.window_rule / hl.layer_rule (tags, float, opacité, workspaces)
```

### Correspondances

- `bind` → `hl.bind("SUPER + X", dispatcher)` ; `bindl` → `{ locked = true }` ;
  `bindel` → `{ locked = true, repeating = true }` ; `binde` → `{ repeating = true }` ;
  `bindln` → `{ locked = true, non_consuming = true }` ; `bindm` → `{ mouse = true }` avec
  `hl.dsp.window.drag()` / `hl.dsp.window.resize()`.
- `[float; move 15% 5%; size 70% 60%] $term` → `hl.dsp.exec_cmd(term, { float = true,
  move = {"15%","5%"}, size = {"70%","60%"} })`.
- `unbind` + rebind caelestia → les binds caelestia sont simplement définis après, dans
  `binds-caelestia.lua`, et les binds JaKooLit correspondants ne sont pas déclarés.
- `windowrule = effet, match:clé regex` → `hl.window_rule({ match = { clé = "regex" },
  effet = valeur })` ; `negative:` conservé tel quel dans la chaîne.
- `layerrule` → `hl.layer_rule({ match = { namespace = "..." }, blur = true, ignore_alpha = x })`.
- `$color12` etc. → `colors.color12` (chaîne `rgb(HEX)`).
- `$TOUCHPAD_ENABLED` → `hl.device({ name = ..., enabled = true })` ; `TouchPad.sh` bascule
  via `hyprctl eval`.
- `monitor=...` et `workspace=...` restent produits par nwg-displays en hyprlang ;
  `monitors.lua` les parse (nom, mode, position, échelle, `disable`, `mirror`).

### Scripts adaptés (changements minimaux)

- `scripts/TouchPad.sh` : `hyprctl keyword '$TOUCHPAD_ENABLED'` → `hyprctl eval
  'hl.device({ name = "...", enabled = true|false })'`.
- `scripts/SwitchKeyboardLayout.sh` : lecture de `kb_layout` via `hyprctl getoption
  input:kb_layout` au lieu de grep dans UserSettings.conf.
- `scripts/KeyBinds.sh` : extraction des `hl.bind(` dans `lua/binds*.lua` et `lua/laptop.lua`.
- `scripts/Kool_Quick_Settings.sh` : entrées « view/edit … » pointent vers les modules Lua.
- `UserScripts/WallpaperSelect.sh` : le sed qui commente `exec-once = awww-daemon` vise la
  ligne équivalente dans `lua/autostart.lua`.
- Après changement de couleurs wallust : `hyprctl reload` est déjà appelé par les scripts
  JaKooLit (`Refresh.sh`) ; vérifier, sinon l'ajouter.

### Bascule et retour arrière

- Tant que `hyprland.lua` n'existe pas, Hyprland charge `hyprland.conf`.
- Bascule : créer `hyprland.lua`, puis `hyprctl reload full-reset`.
- Retour arrière : `mv hyprland.lua hyprland.lua.off && hyprctl reload full-reset`.
- `hyprland.conf` et les `.conf` nettoyés sont conservés jusqu'à validation par l'utilisateur,
  puis archivés dans `legacy/` (non chargé).

### Vérification de fin de phase

- `luac -p` sur chaque module.
- `hyprctl reload full-reset` puis `hyprctl configerrors` vide.
- Comparaison avant/après : nombre de binds (`hyprctl binds`), écrans (`hyprctl monitors`),
  options clés (`hyprctl getoption general:gaps_out`, `input:kb_layout`,
  `decoration:rounding`, `general:layout`), couleur de bordure active
  (`hyprctl getoption general:col.active_border`).
- Règles : `hyprctl clients` sur une fenêtre kitty (tag `terminal*`, opacité 0.9/0.7).
- Test manuel demandé à l'utilisateur : capot, pavé tactile (Fn), SUPER+Return, SUPER+D,
  SUPER+L, changement de fond d'écran.

## Risques

- Une option renommée entre hyprlang et Lua qui passe inaperçue : couvert par
  `hyprctl configerrors` et la comparaison `getoption`.
- Le parseur `monitors.lua` ne couvre pas une syntaxe exotique produite par nwg-displays :
  limité aux formes `name,mode,pos,scale[,mirror,x]`, `name,disable`, `,preferred,auto,1`.
- `hyprland.start` et reload : les commandes d'autostart ne doivent pas être relancées à
  chaque `hyprctl reload` ; à vérifier sur la session, sinon garder un garde-fou (fichier
  marqueur dans `$XDG_RUNTIME_DIR`).

## Écarts constatés à l'exécution (2026-09-11)

- Sous le gestionnaire Lua, `hyprctl keyword`, `hyprctl setprop` et l'ancienne syntaxe de
  `hyprctl dispatch` sont refusés. Tous les scripts (TouchPad, ChangeBlur, ChangeLayout, GameMode,
  RainbowBorders, lid-switch, hypridle, ouvreurs Yazi via `UserScripts/hypr-window`) ont été
  réécrits avec `hyprctl eval`. caelestia-shell (`~/.config/quickshell/caelestia/services/Hypr.qml`)
  a reçu un traducteur legacy → Lua activé par sonde, compatible hyprlang.
- `hyprctl reload full-reset` Lua → hyprlang plante Hyprland 0.56.2 (assertion dans
  `CConfigValueBase::flushCaches`). Retour arrière = renommage + déconnexion.
- Le Lua embarqué traite la variable de boucle `for` comme constante ; `borderangle` est plafonné à
  une vitesse de 100 (180 avant).
- Raccourcis sans équivalent Lua retirés : SUPER+M (`splitratio`), SUPER+ALT+SPACE (`workspaceopt`,
  déjà supprimé par Hyprland). Doublons hyprlang fusionnés : ALT+Tab, CTRL+SUPER+SHIFT+R, SUPER+SHIFT+N.
- Les couleurs wallust sont lues au chargement : `WallustSwww.sh` et `WallpaperEffects.sh` font
  `wait; hyprctl reload`.
- Phase 1 : les commentaires ont été élagués (bannières, liens, blocs morts) mais la réécriture en
  français a été faite directement dans les modules Lua, les `.conf` étant archivés juste après.
