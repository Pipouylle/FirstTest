# Config Hyprland (Lua)

Migrée le 2026-09-11 depuis les dotfiles JaKooLit (hyprlang). Hyprland 0.56.2.

## Structure

```
hyprland.lua          point d'entrée : charge les modules dans l'ordre
lua/
  monitors.lua        lit monitors.conf et workspaces.conf (hyprlang, écrits par nwg-displays)
  env.lua             variables d'environnement
  settings.lua        layouts, clavier, souris, divers
  decorations.lua     bordures, ombres, flou (couleurs wallust via colors.lua)
  colors.lua          lit wallust/wallust-hyprland.conf
  animations.lua      courbes et animations
  rules.lua           règles fenêtres (tags, flottant, opacité, workspaces) et layers
  binds.lua           raccourcis ; retourne term/files/editor/scripts
  laptop.lua          pavé tactile, touches Fn/ASUS, capot
  binds-caelestia.lua overrides caelestia (média, luminosité, overview, lock), chargé en dernier
  autostart.lua       programmes au démarrage (garde-fou : une fois par session)
monitors.conf, workspaces.conf   restent en hyprlang (outils tiers)
hyprlock.conf, hypridle.conf     programmes séparés, hyprlang
legacy/                          ancienne config, plus chargée
scripts/, UserScripts/           scripts JaKooLit + perso, adaptés à l'API Lua
```

## Ce qui change avec le gestionnaire Lua

- `hyprctl keyword`, `hyprctl setprop` et l'ancienne syntaxe de `hyprctl dispatch` sont refusés.
  Tout passe par `hyprctl eval 'hl....'`. Exemples :
  - option : `hyprctl eval 'hl.config({ decoration = { blur = { size = 2 } } })'`
  - dispatcher : `hyprctl dispatch 'hl.dsp.focus({ workspace = "3" })'`
  - fenêtre par pid : `UserScripts/hypr-window hide|show|focus`
- caelestia-shell (`~/.config/quickshell/caelestia/services/Hypr.qml`) traduit lui-même ses commandes
  (`workspace 3`, `togglespecialworkspace`, `dpms off`, …) quand Hyprland est en Lua.
- Les couleurs wallust sont lues au chargement : `WallustSwww.sh` et `WallpaperEffects.sh` font
  `hyprctl reload` après `wallust run`.
- Hyprland embarque un Lua où la variable d'une boucle `for` est constante : ne pas la réassigner.

## Raccourcis retirés (sans équivalent Lua dans 0.56.2)

- SUPER+M (`splitratio 0.3`)
- SUPER+ALT+SPACE (`workspaceopt allfloat`, déjà supprimé par Hyprland)

## Retour arrière

Le reload à chaud Lua → hyprlang plante Hyprland 0.56.2. Il faut se déconnecter :

```
mv ~/.config/hypr/hyprland.lua ~/.config/hypr/hyprland.lua.off
mv ~/.config/hypr/legacy/{hyprland.conf,configs,UserConfigs} ~/.config/hypr/
```

puis déconnexion / reconnexion. Sauvegarde complète d'avant migration :
`~/.config/hypr.bak-2026-09-11.tar.gz` (scripts d'origine inclus).
