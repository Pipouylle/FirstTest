# Hyprland : nettoyage hyprlang puis migration Lua — plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Supprimer les fichiers morts et commentaires hérités de la config Hyprland, puis la migrer vers `hyprland.lua` sans changer le comportement et sans casser wallust, nwg-displays ni les scripts JaKooLit.

**Architecture:** Phase 1 nettoie les `.conf` en place (suppressions et édits ciblés, `hyprctl reload` après chaque étape). Phase 2 crée `hyprland.lua` + `lua/*.lua` (un module par responsabilité) ; les couleurs wallust et les écrans nwg-displays restent en hyprlang et sont lus par deux petits parseurs Lua. Les modules sont testés hors Hyprland avec un stub `hl` (compte les appels), puis la bascule se fait par `hyprctl reload full-reset` avec comparaison à la ligne de base.

**Tech Stack:** Hyprland 0.56.2 (API Lua `hl.*`, stubs `/usr/share/hypr/stubs/hl.meta.lua`), Lua 5.4 (`/usr/bin/lua5.4`, `luac5.4`), hyprctl, bash.

**Spec:** `~/.config/hypr/docs/superpowers/specs/2026-09-11-hyprland-config-cleanup-and-lua-migration-design.md`

## Global Constraints

- Session Hyprland vivante : chaque tâche finit par `hyprctl reload` (ou `full-reset`) puis `hyprctl configerrors` vide.
- Sauvegarde complète : `~/.config/hypr.bak-2026-09-11.tar.gz` (déjà faite). Ligne de base dans le scratchpad `baseline/` : 148 binds (`hyprctl binds | grep -c key:`), options listées dans `baseline/options.txt`, kitty taggé `terminal*`.
- Aucun changement de raccourci, règle ou valeur hors ceux listés : QT_QPA_PLATFORMTHEME garde seulement `qt6ct` (dernier gagnant en hyprlang), binds JaKooLit déjà annulés par caelestia non recréés, doublons `CTRL SUPER SHIFT R` et `SUPER SHIFT N` gardés en version caelestia (dernier gagnant).
- Disposition écrans : TV (`desc:LG Electronics LG TV 0x01010101`) à `0x0`, `eDP-1` à `1920x0`.
- Commentaires : français, une ligne d'en-tête par fichier, pas de bannière ni lien wiki.
- Pas de git dans `~/.config/hypr` : pas de commit ; la sauvegarde tar tient lieu de point de retour.
- Retour arrière phase 2 : `mv ~/.config/hypr/hyprland.lua{,.off} && hyprctl reload full-reset`.

---

## Phase 1 — nettoyage hyprlang

### Task 1 : fichiers morts, sources, écrans

**Files:**
- Delete: `hyprland.conf.bak.1780911312`, `.1780911313`, `.1780911314`, `monitors.conf.bak`, `UserConfigs/Laptops.conf.bak`, `UserConfigs/WindowRules-old.conf`, `UserConfigs/LaptopDisplay.conf`, `v2.3.15`, `UserConfigs/00-Readme`, `initial-boot.sh`
- Modify: `hyprland.conf` (réécrit), `monitors.conf`

- [ ] **Step 1 : vérifier que rien ne référence les fichiers à supprimer**

Run: `cd ~/.config/hypr && grep -rnE 'LaptopDisplay|WindowRules-old|initial-boot|00-Readme|v2\.3\.15' --exclude-dir=docs . | grep -vE '^\./(hyprland\.conf|UserConfigs/Laptops\.conf):'`
Expected: aucune ligne (seuls hyprland.conf et Laptops.conf les citent, et ils sont édités ci-dessous).

- [ ] **Step 2 : supprimer**

```bash
cd ~/.config/hypr && rm -f hyprland.conf.bak.1780911312 hyprland.conf.bak.1780911313 hyprland.conf.bak.1780911314 monitors.conf.bak UserConfigs/Laptops.conf.bak UserConfigs/WindowRules-old.conf UserConfigs/LaptopDisplay.conf v2.3.15 UserConfigs/00-Readme initial-boot.sh
```

- [ ] **Step 3 : réécrire `hyprland.conf`**

```conf
# Hyprland — point d'entrée. Les réglages sont dans configs/ et UserConfigs/.
$configs = $HOME/.config/hypr/configs
$UserConfigs = $HOME/.config/hypr/UserConfigs

source = $configs/Keybinds.conf              # raccourcis de base
source = $UserConfigs/Startup_Apps.conf      # démarrage
source = $UserConfigs/ENVariables.conf       # variables d'environnement
source = $UserConfigs/Laptops.conf           # portable : touches Fn, pavé, capot
source = $UserConfigs/WindowRules.conf       # règles fenêtres et layers
source = $UserConfigs/UserDecorations.conf   # bordures, ombres, flou (couleurs wallust)
source = $UserConfigs/UserAnimations.conf    # animations
source = $UserConfigs/UserKeybinds.conf      # raccourcis perso
source = $UserConfigs/UserSettings.conf      # réglages généraux
source = $UserConfigs/01-UserDefaults.conf   # apps par défaut
source = $HOME/.config/hypr/monitors.conf    # écrans (écrit par nwg-displays)
source = $HOME/.config/hypr/workspaces.conf  # workspaces (écrit par nwg-displays)
source = $UserConfigs/CaelestiaKeybinds.conf # overrides caelestia (en dernier)
```

- [ ] **Step 4 : réécrire `monitors.conf` (TV à gauche)**

```conf
# Écrans — généré par nwg-displays / hyprmon, réécrit à chaque « Apply ».
monitor=desc:LG Electronics LG TV 0x01010101,1920x1080@60.00,0x0,1
monitor=eDP-1,1920x1080@60.00,1920x0,1
monitor=,preferred,auto,1
```

- [ ] **Step 5 : vérifier**

Run: `hyprctl reload && sleep 1 && echo "err='$(hyprctl configerrors)'" && hyprctl binds | grep -c key: && hyprctl -j monitors | grep -E '"name"|"x"|"y"' | head -4`
Expected: `err=''`, `148`, eDP-1 en `x: 1920, y: 0`.

### Task 2 : élaguer les commentaires des `.conf` chargés

**Files:**
- Modify: `configs/Keybinds.conf`, `UserConfigs/{UserKeybinds,CaelestiaKeybinds,ENVariables,Startup_Apps,Laptops,UserSettings,UserDecorations,UserAnimations,WindowRules,01-UserDefaults}.conf`, `workspaces.conf`, `hypridle.conf`

Règle : on supprime les lignes de commentaire qui sont des bannières JaKooLit (`# /* ---- 💫`), des liens wiki, des `#bind`/`#exec-once`/`#env` morts, les blocs NVIDIA/VM/Aquamarine, les séparateurs `# ────…`. On garde les commentaires qui expliquent un choix (caelestia, capot, vicinae, keycodes). Les valeurs ne bougent pas.

- [ ] **Step 1 : script d'élagage**

```bash
cd ~/.config/hypr && for f in configs/Keybinds.conf UserConfigs/UserKeybinds.conf UserConfigs/CaelestiaKeybinds.conf UserConfigs/ENVariables.conf UserConfigs/Startup_Apps.conf UserConfigs/Laptops.conf UserConfigs/UserSettings.conf UserConfigs/UserDecorations.conf UserConfigs/UserAnimations.conf UserConfigs/WindowRules.conf UserConfigs/01-UserDefaults.conf workspaces.conf hypridle.conf; do
  sed -i -E \
    -e '/^# \/\* ---- /d' \
    -e '/https?:\/\/(wiki\.hyprland\.org|wiki\.hypr\.land|github\.com\/JaKooLit|www\.electronjs\.org|github\.com\/elFarto)/d' \
    -e '/^#\s*(bind|bindl|binde|bindel|bindm|exec-once|env|source|submap|monitor|workspace)\s*=/d' \
    -e '/^#\s*(NVIDIA|FOR VM|nvidia|additional ENV|LIBGL|#### )/d' \
    -e '/^# ─+/d' \
    "$f"
  cat -s "$f" > "$f.tmp" && mv "$f.tmp" "$f"
done
```

- [ ] **Step 2 : en-têtes d'une ligne (remplacer la première ligne de chaque fichier si elle est vide ou un ancien titre)**

Pour chaque fichier, insérer en ligne 1 :
`Keybinds.conf` → `# Raccourcis de base (JaKooLit). Les touches média sont reprises par CaelestiaKeybinds.conf.`
`UserKeybinds.conf` → `# Raccourcis perso.`
`CaelestiaKeybinds.conf` → `# Overrides caelestia-shell : chargé en dernier, remplace les binds média/overview de JaKooLit.`
`ENVariables.conf` → `# Variables d'environnement.`
`Startup_Apps.conf` → `# Programmes lancés au démarrage.`
`Laptops.conf` → `# Portable : touches Fn, pavé tactile, capot.`
`UserSettings.conf` → `# Réglages généraux : layouts, clavier, souris, divers.`
`UserDecorations.conf` → `# Bordures, ombres, flou. Couleurs générées par wallust.`
`UserAnimations.conf` → `# Animations.`
`WindowRules.conf` → `# Règles fenêtres (tags, flottant, opacité, workspaces) et layers.`
`01-UserDefaults.conf` → `# Apps par défaut.`
`workspaces.conf` → `# Workspaces — écrit par nwg-displays.`
`hypridle.conf` → `# hypridle — non lancé : inactivité et verrouillage gérés par caelestia (shell.json general.idle).`

- [ ] **Step 3 : relecture manuelle rapide**

Run: `cd ~/.config/hypr && grep -cE '^\s*#' configs/Keybinds.conf UserConfigs/*.conf workspaces.conf hypridle.conf`
Expected: nettement moins de commentaires qu'avant (ENVariables ≤ 15, Startup_Apps ≤ 12, WindowRules ≤ 30). Ouvrir chaque fichier et retirer à la main les commentaires restants qui ne servent à rien (alternatives, notes JaKooLit « note for ja »).

- [ ] **Step 4 : vérifier**

Run: `hyprctl reload && sleep 1 && echo "err='$(hyprctl configerrors)'" && hyprctl binds | grep -c key:`
Expected: `err=''`, `148`.

---

## Phase 2 — migration Lua

### Task 3 : stub de test, `lua/colors.lua`, `lua/monitors.lua`

**Files:**
- Create: `<scratchpad>/hlstub.lua` (harnais de test hors Hyprland), `lua/colors.lua`, `lua/monitors.lua`

**Interfaces:**
- Produces: `require("lua.colors")` → table `{ background, foreground, color0…color15 }` de chaînes `rgb(HEX)`, avec repli `rgb(888888)` pour toute clé absente.
- Produces: `require("lua.monitors")` → appelle `hl.monitor` et `hl.workspace_rule` ; ne retourne rien.

- [ ] **Step 1 : écrire le stub `hl`**

```lua
-- hlstub.lua : imite l'API hl.* et compte les appels. Usage :
--   cd ~/.config/hypr && lua5.4 -e 'dofile("<scratchpad>/hlstub.lua")' -e 'require("lua.binds")' -e 'STUB.report()'
STUB = { calls = {} }
local function rec(name) return function(...) STUB.calls[name] = (STUB.calls[name] or 0) + 1; return { __dsp = name, args = { ... } } end end
local function ns(prefix, names) local t = {}; for _, n in ipairs(names) do t[n] = rec(prefix .. n) end; return t end
hl = {
  config = rec("config"), env = rec("env"), on = rec("on"), exec_cmd = rec("exec_cmd"),
  bind = rec("bind"), unbind = rec("unbind"), device = rec("device"), gesture = rec("gesture"),
  monitor = rec("monitor"), workspace_rule = rec("workspace_rule"), window_rule = rec("window_rule"),
  layer_rule = rec("layer_rule"), animation = rec("animation"), curve = rec("curve"),
  dispatch = rec("dispatch"), get_config = function() return 1 end, focus = rec("dsp.focus"),
  dsp = {
    exec_cmd = rec("dsp.exec_cmd"), exit = rec("dsp.exit"), global = rec("dsp.global"), layout = rec("dsp.layout"),
    focus = rec("dsp.focus"), submap = rec("dsp.submap"),
    window = ns("dsp.window.", { "close", "kill", "float", "fullscreen", "pseudo", "move", "swap", "cycle_next", "bring_to_top", "drag", "resize", "pin", "center", "set_prop" }),
    workspace = ns("dsp.workspace.", { "toggle_special", "move" }),
    group = ns("dsp.group.", { "toggle", "next", "prev" }),
  },
}
function STUB.report() local ks = {}; for k in pairs(STUB.calls) do ks[#ks + 1] = k end; table.sort(ks); for _, k in ipairs(ks) do print(k, STUB.calls[k]) end end
package.path = os.getenv("HOME") .. "/.config/hypr/?.lua;" .. package.path
```

- [ ] **Step 2 : `lua/colors.lua`**

```lua
-- Couleurs wallust : lit wallust/wallust-hyprland.conf (lignes « $nom = rgb(HEX) »).
-- Le fichier reste en hyprlang car hyprlock le lit aussi.
local M = {}
local f = io.open(os.getenv("HOME") .. "/.config/hypr/wallust/wallust-hyprland.conf", "r")
if f then
  for line in f:lines() do
    local name, value = line:match("^%$([%w_]+)%s*=%s*(%S.-)%s*$")
    if name then M[name] = value end
  end
  f:close()
end
-- Repli si wallust n'a pas encore généré le fichier.
return setmetatable(M, { __index = function() return "rgb(888888)" end })
```

- [ ] **Step 3 : tester colors**

Run: `cd ~/.config/hypr && lua5.4 -e 'dofile("<scratchpad>/hlstub.lua")' -e 'local c = require("lua.colors"); print(c.color12, c.background, c.absent)'`
Expected: `rgb(398797)	rgb(151719)	rgb(888888)` (valeurs actuelles du fichier wallust).

- [ ] **Step 4 : `lua/monitors.lua`**

```lua
-- Écrans et workspaces : lit monitors.conf et workspaces.conf (hyprlang, écrits par
-- nwg-displays et le sélecteur de profils), pour que ces outils continuent de marcher.
local home = os.getenv("HOME")

local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

local function lines(path)
  local out, f = {}, io.open(path, "r")
  if not f then return out end
  for l in f:lines() do
    l = trim((l:gsub("#.*$", "")))
    if l ~= "" then out[#out + 1] = l end
  end
  f:close()
  return out
end

local function split(s)
  local t = {}
  for part in (s .. ","):gmatch("(.-),") do t[#t + 1] = trim(part) end
  return t
end

-- monitor=name,mode,pos,scale[,mirror,x][,transform,n][,bitdepth,n]  |  monitor=name,disable
for _, l in ipairs(lines(home .. "/.config/hypr/monitors.conf")) do
  local rhs = l:match("^monitor%s*=%s*(.*)$")
  if rhs then
    local f = split(rhs)
    if f[2] == "disable" then
      hl.monitor({ output = f[1], disabled = true })
    else
      local spec = { output = f[1], mode = f[2] or "preferred", position = f[3] or "auto", scale = tonumber(f[4]) or f[4] or 1 }
      for i = 5, #f, 2 do
        if f[i] == "mirror" then spec.mirror = f[i + 1]
        elseif f[i] == "transform" then spec.transform = tonumber(f[i + 1])
        elseif f[i] == "bitdepth" then spec.bitdepth = tonumber(f[i + 1])
        elseif f[i] == "vrr" then spec.vrr = tonumber(f[i + 1]) end
      end
      hl.monitor(spec)
    end
  end
end

-- workspace = sel, clé:valeur, ...
local ws_keys = {
  monitor = "monitor", default = "default", persistent = "persistent", layout = "layout",
  gapsin = "gaps_in", gapsout = "gaps_out", bordersize = "border_size", decorate = "decorate",
  ["on-created-empty"] = "on_created_empty", ["default-name"] = "default_name", animation = "animation",
}
local function val(v)
  if v == "true" then return true elseif v == "false" then return false end
  return tonumber(v) or v
end
for _, l in ipairs(lines(home .. "/.config/hypr/workspaces.conf")) do
  local rhs = l:match("^workspace%s*=%s*(.*)$")
  if rhs then
    local f = split(rhs)
    local spec = { workspace = f[1] }
    for i = 2, #f do
      local k, v = f[i]:match("^([%w%-]+):(.*)$")
      if k == "border" then spec.no_border = (v == "false")
      elseif k == "rounding" then spec.no_rounding = (v == "false")
      elseif k == "shadow" then spec.no_shadow = (v == "false")
      elseif k and ws_keys[k] then spec[ws_keys[k]] = val(v) end
    end
    hl.workspace_rule(spec)
  end
end
```

- [ ] **Step 5 : tester monitors**

Run: `cd ~/.config/hypr && lua5.4 -e 'dofile("<scratchpad>/hlstub.lua")' -e 'require("lua.monitors")' -e 'STUB.report()'`
Expected: `monitor	3` (TV, eDP-1, fallback) et pas de `workspace_rule` (workspaces.conf n'a que des commentaires).

Puis un test de parseur avec un fichier temporaire : écrire dans le scratchpad `ws.conf` contenant `workspace = 1, monitor:eDP-1, default:true` et `monitor=HDMI-A-1,disable`, et vérifier via une copie du module pointant sur ce fichier (`sed "s#/.config/hypr/monitors.conf#<scratchpad>/ws.conf#; s#/.config/hypr/workspaces.conf#<scratchpad>/ws.conf#" lua/monitors.lua > <scratchpad>/mon_test.lua`) que `hl.monitor` reçoit `{ output = "HDMI-A-1", disabled = true }` et `hl.workspace_rule` reçoit `{ workspace = "1", monitor = "eDP-1", default = true }` (imprimer `STUB.calls` et les args).

### Task 4 : `env`, `autostart`, `settings`, `decorations`, `animations`

**Files:**
- Create: `lua/env.lua`, `lua/autostart.lua`, `lua/settings.lua`, `lua/decorations.lua`, `lua/animations.lua`

**Interfaces:**
- Consumes: `require("lua.colors")` (Task 3).
- Produces: rien d'exporté ; effets via `hl.*`.

- [ ] **Step 1 : `lua/env.lua`**

```lua
-- Variables d'environnement (ex UserConfigs/ENVariables.conf).
hl.env("GDK_BACKEND", "wayland,x11,*")
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("CLUTTER_BACKEND", "wayland")

hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_TYPE", "wayland")

hl.env("QT_AUTO_SCREEN_SCALE_FACTOR", "1")
hl.env("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1")
hl.env("QT_QPA_PLATFORMTHEME", "qt6ct")
hl.env("QT_QUICK_CONTROLS_STYLE", "org.hyprland.style")

-- Mise à l'échelle XWayland : garder la même valeur que l'échelle des écrans.
hl.env("GDK_SCALE", "1")
hl.env("QT_SCALE_FACTOR", "1")

hl.env("HYPRCURSOR_THEME", "Bibata-Modern-Ice")
hl.env("HYPRCURSOR_SIZE", "24")

hl.env("MOZ_ENABLE_WAYLAND", "1")
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")
```

- [ ] **Step 2 : `lua/autostart.lua`**

```lua
-- Programmes lancés au démarrage (ex UserConfigs/Startup_Apps.conf).
-- Garde-fou : « hyprland.start » ne doit lancer ces commandes qu'une fois par session,
-- même si l'événement est rejoué à un reload.
local home = os.getenv("HOME")
local scripts = home .. "/.config/hypr/scripts"
local user_scripts = home .. "/.config/hypr/UserScripts"
local marker = (os.getenv("XDG_RUNTIME_DIR") or "/tmp") .. "/hypr-autostart-" .. (os.getenv("HYPRLAND_INSTANCE_SIGNATURE") or "nosig")

hl.on("hyprland.start", function()
  local f = io.open(marker, "r")
  if f then f:close(); return end
  f = io.open(marker, "w"); if f then f:close() end

  -- fond d'écran (WallpaperSelect.sh commente la ligne awww pour un fond vidéo)
  hl.exec_cmd("awww-daemon --format xrgb")
  hl.exec_cmd("waypaper --restore")

  hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP")
  hl.exec_cmd("systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP")
  hl.exec_cmd(scripts .. "/Polkit.sh")

  hl.exec_cmd("nm-applet --indicator")
  hl.exec_cmd("blueman-applet")
  hl.exec_cmd("qs -c caelestia -d")   -- barre, notifications, verrouillage
  hl.exec_cmd("vicinae server")       -- lanceur

  hl.exec_cmd("wl-paste --type text --watch cliphist store")
  hl.exec_cmd("wl-paste --type image --watch cliphist store")

  hl.exec_cmd(user_scripts .. "/RainbowBorders.sh")
  hl.exec_cmd("easyeffects --service-mode")
  hl.exec_cmd(scripts .. "/PortalHyprland.sh")
end)
```

- [ ] **Step 3 : `lua/settings.lua`**

```lua
-- Réglages généraux (ex UserConfigs/UserSettings.conf).
hl.config({
  general = { layout = "dwindle", resize_on_border = true },
  dwindle = { preserve_split = true, special_scale_factor = 0.8 },
  master = { new_status = "master", new_on_top = true, mfact = 0.5 },

  input = {
    kb_layout = "fr", kb_variant = "", kb_model = "", kb_options = "", kb_rules = "",
    repeat_rate = 50, repeat_delay = 300,
    sensitivity = 0, numlock_by_default = true, left_handed = false,
    follow_mouse = 1, float_switch_override_focus = 0,
    touchpad = {
      disable_while_typing = true, natural_scroll = true, clickfinger_behavior = false,
      middle_button_emulation = true, tap_to_click = true, drag_lock = false,
    },
    touchdevice = { enabled = true },
    tablet = { transform = 0, left_handed = false },
  },

  misc = {
    disable_hyprland_logo = true, disable_splash_rendering = true,
    vrr = 2, mouse_move_enables_dpms = true,
    enable_swallow = false, swallow_regex = "^(kitty)$",
    focus_on_activate = false, initial_workspace_tracking = 0, middle_click_paste = false,
  },

  binds = { workspace_back_and_forth = true, allow_workspace_cycles = true, pass_mouse_when_bound = false },
  xwayland = { enabled = true, force_zero_scaling = true },
  render = { direct_scanout = 0 },
  cursor = {
    sync_gsettings_theme = true, no_hardware_cursors = 2, enable_hyprcursor = true,
    warp_on_change_workspace = 2, no_warps = true,
  },
})

hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })
```

- [ ] **Step 4 : `lua/decorations.lua`**

```lua
-- Bordures, ombres, flou (ex UserConfigs/UserDecorations.conf). Couleurs wallust.
local c = require("lua.colors")

hl.config({
  general = {
    border_size = 2, gaps_in = 2, gaps_out = 4,
    col = { active_border = c.color12, inactive_border = c.color10 },
  },
  decoration = {
    rounding = 10,
    active_opacity = 1.0, inactive_opacity = 0.9, fullscreen_opacity = 1.0,
    dim_inactive = true, dim_strength = 0.1, dim_special = 0.8,
    shadow = { enabled = true, range = 3, render_power = 1, color = c.color12, color_inactive = c.color10 },
    blur = { enabled = true, size = 6, passes = 2, ignore_opacity = true, new_optimizations = true, special = true, popups = true },
  },
  group = {
    col = { border_active = c.color15 },
    groupbar = { col = { active = c.color0 } },
  },
})
```

- [ ] **Step 5 : `lua/animations.lua`**

```lua
-- Animations (ex UserConfigs/UserAnimations.conf).
hl.config({ animations = { enabled = true } })

hl.curve("wind",      { type = "bezier", points = { { 0.05, 0.9 }, { 0.1, 1.05 } } })
hl.curve("winIn",     { type = "bezier", points = { { 0.1, 1.1 }, { 0.1, 1.1 } } })
hl.curve("winOut",    { type = "bezier", points = { { 0.3, -0.3 }, { 0, 1 } } })
hl.curve("liner",     { type = "bezier", points = { { 1, 1 }, { 1, 1 } } })
hl.curve("overshot",  { type = "bezier", points = { { 0.05, 0.9 }, { 0.1, 1.05 } } })
hl.curve("smoothOut", { type = "bezier", points = { { 0.5, 0 }, { 0.99, 0.99 } } })
hl.curve("smoothIn",  { type = "bezier", points = { { 0.5, -0.5 }, { 0.68, 1.5 } } })

hl.animation({ leaf = "windows",       enabled = true, speed = 6,   bezier = "wind",      style = "slide" })
hl.animation({ leaf = "windowsIn",     enabled = true, speed = 5,   bezier = "winIn",     style = "slide" })
hl.animation({ leaf = "windowsOut",    enabled = true, speed = 3,   bezier = "smoothOut", style = "slide" })
hl.animation({ leaf = "windowsMove",   enabled = true, speed = 5,   bezier = "wind",      style = "slide" })
hl.animation({ leaf = "border",        enabled = true, speed = 1,   bezier = "liner" })
hl.animation({ leaf = "borderangle",   enabled = true, speed = 180, bezier = "liner",     style = "loop" }) -- RainbowBorders.sh
hl.animation({ leaf = "fade",          enabled = true, speed = 3,   bezier = "smoothOut" })
hl.animation({ leaf = "workspaces",    enabled = true, speed = 5,   bezier = "overshot" })
hl.animation({ leaf = "workspacesIn",  enabled = true, speed = 5,   bezier = "winIn",     style = "slide" })
hl.animation({ leaf = "workspacesOut", enabled = true, speed = 5,   bezier = "winOut",    style = "slide" })
```

- [ ] **Step 6 : tester**

Run: `cd ~/.config/hypr && for m in env autostart settings decorations animations; do luac5.4 -p lua/$m.lua && echo "$m: syntaxe OK"; done && lua5.4 -e 'dofile("<scratchpad>/hlstub.lua")' -e 'for _, m in ipairs{"env","autostart","settings","decorations","animations"} do require("lua."..m) end' -e 'STUB.report()'`
Expected : 5 × « syntaxe OK », puis `animation 10`, `config 4` (settings 1, decorations 1, animations 1... plus autostart 0), `curve 7`, `env 15`, `gesture 1`, `on 1`.

Vérifier aussi que `middle_click_paste` existe dans les stubs : `grep -c 'middle_click_paste' /usr/share/hypr/stubs/hl.meta.lua` ≥ 1 (sinon retirer la clé).

### Task 5 : `binds`, `binds-caelestia`, `laptop`

**Files:**
- Create: `lua/binds.lua`, `lua/binds-caelestia.lua`, `lua/laptop.lua`

**Interfaces:**
- Produces: `lua/binds.lua` retourne `{ term = "kitty", files = "nautilus", editor = "zeditor", scripts = <path>, user_scripts = <path> }` pour les autres modules.

- [ ] **Step 1 : `lua/binds.lua`**

```lua
-- Raccourcis de base et perso (ex configs/Keybinds.conf + UserConfigs/UserKeybinds.conf).
-- Les touches média/luminosité et SUPER+Tab sont dans binds-caelestia.lua.
local home = os.getenv("HOME")
local M = {
  term = "kitty", files = "nautilus", editor = "zeditor",
  scripts = home .. "/.config/hypr/scripts",
  user_scripts = home .. "/.config/hypr/UserScripts",
}
local S, U = M.scripts, M.user_scripts
local function run(cmd) return hl.dsp.exec_cmd(cmd) end

-- Système
hl.bind("CTRL + ALT + Delete", hl.dsp.exit())
hl.bind("SUPER + Q", hl.dsp.window.close())
hl.bind("SUPER + SHIFT + Q", run(S .. "/KillActiveProcess.sh"))
hl.bind("CTRL + ALT + L", run(S .. "/LockScreen.sh"))
hl.bind("CTRL + ALT + P", run(S .. "/Wlogout.sh"))
hl.bind("SUPER + SHIFT + E", run(S .. "/Kool_Quick_Settings.sh"))

-- Apps
hl.bind("SUPER + D", run("vicinae toggle"))
hl.bind("SUPER + B", run('xdg-open "https://"'))
hl.bind("SUPER + Return", run(M.term))
hl.bind("SUPER + E", run(M.files))
hl.bind("Print", run(U .. "/ScreenShotMenu.sh"))
hl.bind("SUPER + V", run("vicinae vicinae://launch/clipboard/history"))
hl.bind("SUPER + SHIFT + Return", hl.dsp.exec_cmd(M.term, { float = true, move = { "15%", "5%" }, size = { "70%", "60%" } })) -- terminal flottant

-- Extras
hl.bind("SUPER + H", run(S .. "/KeyHints.sh"))
hl.bind("SUPER + ALT + R", run(S .. "/Refresh.sh"))
hl.bind("SUPER + ALT + O", run(S .. "/ChangeBlur.sh"))
hl.bind("SUPER + SHIFT + G", run(S .. "/GameMode.sh"))
hl.bind("SUPER + ALT + L", run(S .. "/ChangeLayout.sh"))
hl.bind("SUPER + W", run("caelestia shell nexus open"))
hl.bind("SUPER + SHIFT + W", run(U .. "/WallpaperEffects.sh"))
hl.bind("CTRL + ALT + W", run(U .. "/WallpaperRandom.sh"))
hl.bind("SUPER + CTRL + O", hl.dsp.window.set_prop({ prop = "opaque", value = "toggle" }))
hl.bind("SUPER + SHIFT + O", run(U .. "/ZshChangeTheme.sh"))
hl.bind("Alt_L + Shift_L", run(S .. "/SwitchKeyboardLayout.sh"), { locked = true, non_consuming = true })

-- Layouts
hl.bind("SUPER + CTRL + D", hl.dsp.layout("removemaster"))
hl.bind("SUPER + I", hl.dsp.layout("addmaster"))
hl.bind("SUPER + J", hl.dsp.layout("cyclenext"))
hl.bind("SUPER + K", hl.dsp.layout("cycleprev"))
hl.bind("SUPER + CTRL + Return", hl.dsp.layout("swapwithmaster"))
hl.bind("SUPER + SHIFT + I", hl.dsp.layout("togglesplit")) -- dwindle
hl.bind("SUPER + P", hl.dsp.window.pseudo())
hl.bind("SUPER + M", run("hyprctl dispatch splitratio 0.3"))

-- Fenêtres
hl.bind("SUPER + SHIFT + F", hl.dsp.window.fullscreen({ mode = "fullscreen" }))
hl.bind("SUPER + CTRL + F", hl.dsp.window.fullscreen({ mode = "maximized" }))
hl.bind("SUPER + SPACE", hl.dsp.window.float({ action = "toggle" }))
hl.bind("SUPER + ALT + SPACE", run("hyprctl dispatch workspaceopt allfloat"))
hl.bind("SUPER + G", hl.dsp.group.toggle())
hl.bind("SUPER + CTRL + tab", hl.dsp.group.next())
hl.bind("ALT + tab", function()
  hl.dispatch(hl.dsp.window.cycle_next())
  hl.dispatch(hl.dsp.window.bring_to_top())
end)

for key, dir in pairs({ left = "left", right = "right", up = "up", down = "down" }) do
  hl.bind("SUPER + CTRL + " .. key, hl.dsp.window.move({ direction = dir }))
  hl.bind("SUPER + ALT + " .. key, hl.dsp.window.swap({ direction = dir }))
end
hl.bind("SUPER + SHIFT + left",  hl.dsp.window.resize({ x = -50, y = 0, relative = true }), { repeating = true })
hl.bind("SUPER + SHIFT + right", hl.dsp.window.resize({ x = 50, y = 0, relative = true }),  { repeating = true })
hl.bind("SUPER + SHIFT + up",    hl.dsp.window.resize({ x = 0, y = -50, relative = true }), { repeating = true })
hl.bind("SUPER + SHIFT + down",  hl.dsp.window.resize({ x = 0, y = 50, relative = true }),  { repeating = true })
hl.bind("SUPER + up",   hl.dsp.focus({ direction = "up" }))
hl.bind("SUPER + down", hl.dsp.focus({ direction = "down" }))

-- Workspaces
hl.bind("SUPER + left",  hl.dsp.focus({ workspace = "e-1" }))
hl.bind("SUPER + right", hl.dsp.focus({ workspace = "e+1" }))
hl.bind("SUPER + SHIFT + left",  hl.dsp.window.move({ workspace = "-1", follow = true }))
hl.bind("SUPER + SHIFT + right", hl.dsp.window.move({ workspace = "+1", follow = true }))
hl.bind("SUPER + CTRL + left",   hl.dsp.window.move({ workspace = "-1", follow = false }))
hl.bind("SUPER + CTRL + right",  hl.dsp.window.move({ workspace = "+1", follow = false }))
hl.bind("SUPER + SHIFT + U", hl.dsp.window.move({ workspace = "special", follow = true }))
hl.bind("SUPER + U", hl.dsp.workspace.toggle_special())
-- code:10..19 = touches 1..0 (indépendant de la disposition clavier)
for i = 1, 10 do
  local code = "code:" .. (9 + i)
  hl.bind("SUPER + " .. code, hl.dsp.focus({ workspace = tostring(i) }))
  hl.bind("SUPER + SHIFT + " .. code, hl.dsp.window.move({ workspace = tostring(i), follow = true }))
  hl.bind("SUPER + CTRL + " .. code, hl.dsp.window.move({ workspace = tostring(i), follow = false }))
end
hl.bind("SUPER + SHIFT + bracketleft",  hl.dsp.window.move({ workspace = "-1", follow = true }))
hl.bind("SUPER + SHIFT + bracketright", hl.dsp.window.move({ workspace = "+1", follow = true }))
hl.bind("SUPER + CTRL + bracketleft",   hl.dsp.window.move({ workspace = "-1", follow = false }))
hl.bind("SUPER + CTRL + bracketright",  hl.dsp.window.move({ workspace = "+1", follow = false }))
hl.bind("SUPER + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind("SUPER + mouse_up",   hl.dsp.focus({ workspace = "e-1" }))
hl.bind("SUPER + period", hl.dsp.focus({ workspace = "e+1" }))
hl.bind("SUPER + comma",  hl.dsp.focus({ workspace = "e-1" }))

-- Souris
hl.bind("SUPER + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind("SUPER + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Loupe (zoom curseur)
local function zoom(factor)
  return function()
    local z = tonumber(hl.get_config("cursor.zoom_factor")) or 1
    if z < 1 then z = 1 end
    hl.config({ cursor = { zoom_factor = z * factor } })
  end
end
hl.bind("SUPER + ALT + mouse_down", zoom(2))
hl.bind("SUPER + ALT + mouse_up",   zoom(0.5))

-- Captures d'écran
hl.bind("SUPER + Print", run(S .. "/ScreenShot.sh --now"))
hl.bind("SUPER + SHIFT + Print", run(S .. "/ScreenShot.sh --area"))
hl.bind("SUPER + CTRL + Print", run(S .. "/ScreenShot.sh --in5"))
hl.bind("SUPER + CTRL + SHIFT + Print", run(S .. "/ScreenShot.sh --in10"))
hl.bind("ALT + Print", run(S .. "/ScreenShot.sh --active"))
hl.bind("SUPER + SHIFT + S", run(S .. "/ScreenShot.sh --swappy"))

-- Touches spéciales restantes (les touches audio/luminosité sont dans binds-caelestia.lua)
hl.bind("XF86Sleep",  run("systemctl suspend"), { locked = true })
hl.bind("XF86RFKill", run(S .. "/AirplaneMode.sh"), { locked = true })

return M
```

- [ ] **Step 2 : `lua/binds-caelestia.lua`**

```lua
-- Overrides caelestia-shell (ex UserConfigs/CaelestiaKeybinds.conf).
-- Ces touches ne sont volontairement pas déclarées dans binds.lua : caelestia affiche
-- déjà son OSD, les scripts JaKooLit faisaient doublon (notification + OSD).
local g = hl.dsp.global

-- Redémarrer le shell. `qs kill` passe par le registre d'instances de quickshell ;
-- un `pkill -f quickshell` se tuait lui-même (le mot est dans la ligne de commande du bind).
hl.bind("CTRL + SUPER + SHIFT + R", hl.dsp.exec_cmd("qs kill -c caelestia; sleep 0.3; qs -c caelestia -d"))

hl.bind("SUPER + tab",         g("caelestia:overview"))
hl.bind("SUPER + SHIFT + tab", g("caelestia:sidebar"))
hl.bind("SUPER + SHIFT + N",   g("caelestia:clearNotifs"))
hl.bind("SUPER + L",           g("caelestia:lock"))

-- Média
hl.bind("CTRL + SUPER + Space", g("caelestia:mediaToggle"), { locked = true })
hl.bind("CTRL + SUPER + Equal", g("caelestia:mediaNext"),   { locked = true })
hl.bind("CTRL + SUPER + Minus", g("caelestia:mediaPrev"),   { locked = true })
hl.bind("XF86AudioPlay",  g("caelestia:mediaToggle"), { locked = true })
hl.bind("XF86AudioPause", g("caelestia:mediaToggle"), { locked = true })
hl.bind("XF86AudioNext",  g("caelestia:mediaNext"),   { locked = true })
hl.bind("XF86AudioPrev",  g("caelestia:mediaPrev"),   { locked = true })
hl.bind("XF86AudioStop",  g("caelestia:mediaStop"),   { locked = true })

-- Luminosité et volume
hl.bind("XF86MonBrightnessUp",   g("caelestia:brightnessUp"),   { locked = true })
hl.bind("XF86MonBrightnessDown", g("caelestia:brightnessDown"), { locked = true })
hl.bind("XF86AudioRaiseVolume",  g("caelestia:volumeUp"),   { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume",  g("caelestia:volumeDown"), { locked = true, repeating = true })
hl.bind("XF86AudioMute",         g("caelestia:volumeMute"), { locked = true })
-- Pas de global caelestia pour le micro : wpctl, l'OSD suit le nœud PipeWire.
hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), { locked = true })
```

- [ ] **Step 3 : `lua/laptop.lua`**

```lua
-- Portable : pavé tactile, touches ASUS/Fn, capot (ex UserConfigs/Laptops.conf).
local B = require("lua.binds")
local S = B.scripts
local run = hl.dsp.exec_cmd

-- Pavé tactile (basculé par scripts/TouchPad.sh via hyprctl eval). `hyprctl devices` donne le nom.
hl.device({ name = "asue1209:00-04f3:319f-touchpad", enabled = true })

hl.bind("XF86KbdBrightnessDown", run(S .. "/BrightnessKbd.sh --dec"), { repeating = true })
hl.bind("XF86KbdBrightnessUp",   run(S .. "/BrightnessKbd.sh --inc"), { repeating = true })
hl.bind("XF86Launch1", run("rog-control-center"))     -- bouton Armoury Crate
hl.bind("XF86Launch3", run("asusctl led-mode -n"))    -- Fn+F4 : profil RGB clavier
hl.bind("XF86Launch4", run("asusctl profile -n"))     -- Fn+F5 : profil ventilation
hl.bind("XF86TouchpadToggle", run(S .. "/TouchPad.sh"))

-- Captures sans touche Impr
hl.bind("SUPER + F6", run(S .. "/ScreenShot.sh --now"))
hl.bind("SUPER + SHIFT + F6", run(S .. "/ScreenShot.sh --area"))
hl.bind("SUPER + CTRL + F6", run(S .. "/ScreenShot.sh --in5"))
hl.bind("SUPER + ALT + F6", run(S .. "/ScreenShot.sh --in10"))
hl.bind("ALT + F6", run(S .. "/ScreenShot.sh --active"))

-- Capot : lid-switch ne désactive eDP-1 que si un autre écran est actif et la session
-- n'est pas verrouillée (sinon Hyprland plantait au réveil, cf. UserScripts/lid-switch).
local lid = os.getenv("HOME") .. "/.config/hypr/UserScripts/lid-switch"
hl.bind("switch:off:Lid Switch", run(lid .. " off"), { locked = true })
hl.bind("switch:on:Lid Switch",  run(lid .. " on"),  { locked = true })
```

- [ ] **Step 4 : tester**

Run: `cd ~/.config/hypr && for m in binds binds-caelestia laptop; do luac5.4 -p lua/$m.lua && echo "$m: syntaxe OK"; done && lua5.4 -e 'dofile("<scratchpad>/hlstub.lua")' -e 'require("lua.binds"); require("lua.binds-caelestia"); require("lua.laptop")' -e 'STUB.report()'`
Expected : 3 × « syntaxe OK », `bind 148` (= ligne de base), `device 1`.
Si le compte diffère, lister les clés : ajouter au stub `print(name, args[1])` dans `rec` pour `bind`, comparer avec `grep -E '^\s*bind' ` des `.conf` après retrait des lignes annulées par `unbind`.

### Task 6 : `rules.lua`

**Files:**
- Create: `lua/rules.lua`

- [ ] **Step 1 : écrire le module**

```lua
-- Règles fenêtres et layers (ex UserConfigs/WindowRules.conf).
local W, L = hl.window_rule, hl.layer_rule
local function tag(name, key, pat) W({ match = { [key] = pat }, tag = "+" .. name }) end

-- Tags
tag("browser", "class", "^([Ff]irefox|org.mozilla.firefox|[Ff]irefox-esr|[Ff]irefox-bin)$")
tag("browser", "class", "^([Gg]oogle-chrome(-beta|-dev|-unstable)?)$")
tag("browser", "class", "^(chrome-.+-Default)$")
tag("browser", "class", "^([Cc]hromium)$")
tag("browser", "class", "^([Mm]icrosoft-edge(-stable|-beta|-dev|-unstable))$")
tag("browser", "class", "^(Brave-browser(-beta|-dev|-unstable)?)$")
tag("browser", "class", "^([Tt]horium-browser|[Cc]achy-browser)$")
tag("browser", "class", "^(zen-alpha|zen)$")
tag("notif", "class", "^(swaync-control-center|swaync-notification-window|swaync-client|class)$")
tag("KooL_Cheat", "title", "^(KooL Quick Cheat Sheet)$")
tag("KooL_Settings", "title", "^(KooL Hyprland Settings)$")
tag("KooL-Settings", "class", "^(nwg-displays|nwg-look)$")
tag("terminal", "class", "^(Alacritty|kitty|kitty-dropterm)$")
tag("email", "class", "^([Tt]hunderbird|org.gnome.Evolution)$")
tag("email", "class", "^(eu.betterbird.Betterbird)$")
tag("projects", "class", "^(codium|codium-url-handler|VSCodium)$")
tag("projects", "class", "^(VSCode|code|code-url-handler)$")
tag("projects", "class", "^(jetbrains-.+)$")
tag("screenshare", "class", "^(com.obsproject.Studio)$")
tag("im", "class", "^([Dd]iscord|[Ww]ebCord|[Vv]esktop)$")
tag("im", "class", "^([Ff]erdium)$")
tag("im", "class", "^([Ww]hatsapp-for-linux)$")
tag("im", "class", "^(ZapZap|com.rtosta.zapzap)$")
tag("im", "class", "^(org.telegram.desktop|io.github.tdesktop_x64.TDesktop)$")
tag("im", "class", "^(teams-for-linux)$")
tag("im", "class", "^(im.riot.Riot|Element)$")
tag("games", "class", "^(gamescope)$")
tag("games", "class", "^(steam_app_\\d+)$")
tag("gamestore", "class", "^([Ss]team)$")
tag("gamestore", "title", "^([Ll]utris)$")
tag("gamestore", "class", "^(com.heroicgameslauncher.hgl)$")
tag("file-manager", "class", "^([Tt]hunar|org.gnome.Nautilus|[Pp]cmanfm-qt)$")
tag("file-manager", "class", "^(app.drey.Warp)$")
tag("wallpaper", "class", "^([Ww]aytrogen)$")
tag("multimedia", "class", "^([Aa]udacious)$")
tag("multimedia_video", "class", "^([Mm]pv|vlc)$")
tag("settings", "title", "^(ROG Control)$")
tag("settings", "class", "^(wihotspot(-gui)?)$")
tag("settings", "class", "^([Bb]aobab|org.gnome.[Bb]aobab)$")
tag("settings", "class", "^(gnome-disks|wihotspot(-gui)?)$")
tag("settings", "title", "(Kvantum Manager)")
tag("settings", "class", "^(file-roller|org.gnome.FileRoller)$")
tag("settings", "class", "^(nm-applet|nm-connection-editor|blueman-manager)$")
tag("settings", "class", "^(pavucontrol|org.pulseaudio.pavucontrol|com.saivert.pwvucontrol)$")
tag("settings", "class", "^(qt5ct|qt6ct|[Yy]ad)$")
tag("settings", "class", "(xdg-desktop-portal-gtk)")
tag("settings", "class", "^(org.kde.polkit-kde-authentication-agent-1)$")
tag("settings", "class", "^([Rr]ofi)$")
tag("viewer", "class", "^(gnome-system-monitor|org.gnome.SystemMonitor|io.missioncenter.MissionCenter)$")
tag("viewer", "class", "^(evince)$")
tag("viewer", "class", "^(eog|org.gnome.Loupe)$")

-- Vidéo : pas de flou, opaque
W({ match = { tag = "multimedia_video*" }, no_blur = true })
W({ match = { tag = "multimedia_video*" }, opacity = "1.0" })

-- Position
W({ match = { tag = "KooL_Cheat*" }, center = true })
W({ match = { class = "^([Tt]hunar)$", title = "negative:(.*[Tt]hunar.*)" }, center = true })
W({ match = { title = "^(ROG Control)$" }, center = true })
W({ match = { tag = "KooL-Settings*" }, center = true })
W({ match = { title = "^(Keybindings)$" }, center = true })
W({ match = { class = "^(pavucontrol|org.pulseaudio.pavucontrol|com.saivert.pwvucontrol)$" }, center = true })
W({ match = { class = "^([Ww]hatsapp-for-linux|ZapZap|com.rtosta.zapzap)$" }, center = true })
W({ match = { class = "^([Ff]erdium)$" }, center = true })
W({ match = { title = "^(Picture-in-Picture)$" }, move = { "72%", "7%" } })

-- Pas de mise en veille en plein écran
W({ match = { fullscreen = true }, idle_inhibit = "fullscreen" })

-- Workspaces
W({ match = { tag = "email*" }, workspace = "1" })
W({ match = { tag = "browser*" }, workspace = "2" })
W({ match = { tag = "gamestore*" }, workspace = "5" })
W({ match = { tag = "im*" }, workspace = "7" })
W({ match = { tag = "games*" }, workspace = "8" })
W({ match = { tag = "screenshare*" }, workspace = "4 silent" })
W({ match = { class = "^(virt-manager)$" }, workspace = "6 silent" })
W({ match = { class = "^(.virt-manager-wrapped)$" }, workspace = "6 silent" })
W({ match = { tag = "multimedia*" }, workspace = "9 silent" })

-- Flottant
for _, t in ipairs({ "KooL_Cheat*", "wallpaper*", "settings*", "viewer*", "KooL-Settings*" }) do W({ match = { tag = t }, float = true }) end
W({ match = { class = "^([Zz]oom|onedriver|onedriver-launcher)$" }, float = true })
W({ match = { class = "^(org.gnome.Calculator)$" }, float = true })
W({ match = { class = "^(mpv|com.github.rafostar.Clapper)$" }, float = true })
W({ match = { class = "^([Qq]alculate-gtk)$" }, float = true })
W({ match = { class = "^([Ff]erdium)$" }, float = true })
W({ match = { title = "^(Picture-in-Picture)$" }, float = true })

-- Popups et dialogues
W({ match = { title = "^(Authentication Required)$" }, float = true })
W({ match = { title = "^(Authentication Required)$" }, center = true })
W({ match = { class = "^(codium|codium-url-handler|VSCodium)$", title = "negative:(.*codium.*|.*VSCodium.*)" }, float = true })
W({ match = { class = "^(com.heroicgameslauncher.hgl)$", title = "negative:(Heroic Games Launcher)" }, float = true })
W({ match = { class = "^([Ss]team)$", title = "negative:^([Ss]team)$" }, float = true })
W({ match = { class = "^([Tt]hunar)$", title = "negative:(.*[Tt]hunar.*)" }, float = true })
for _, t in ipairs({ "^(Add Folder to Workspace)$", "^(Save As)$" }) do
  W({ match = { title = t }, float = true })
  W({ match = { title = t }, size = { "70%", "60%" } })
  W({ match = { title = t }, center = true })
end
W({ match = { initial_title = "^(Open Files)$" }, float = true })
W({ match = { initial_title = "^(Open Files)$" }, size = { "70%", "60%" } })
W({ match = { title = "^(SDDM Background)$" }, float = true })
W({ match = { title = "^(SDDM Background)$" }, center = true })
W({ match = { title = "^(SDDM Background)$" }, size = { "16%", "12%" } })

-- Opacité (active inactive)
W({ match = { tag = "browser*" }, opacity = "0.95 0.7" })
W({ match = { tag = "projects*" }, opacity = "0.9 0.8" })
W({ match = { tag = "im*" }, opacity = "0.94 0.86" })
W({ match = { tag = "multimedia*" }, opacity = "0.94 0.86" })
W({ match = { tag = "file-manager*" }, opacity = "0.9 0.8" })
W({ match = { tag = "terminal*" }, opacity = "0.9 0.7" })
W({ match = { tag = "settings*" }, opacity = "0.8 0.7" })
W({ match = { tag = "viewer*" }, opacity = "0.82 0.75" })
W({ match = { tag = "wallpaper*" }, opacity = "0.9 0.7" })
W({ match = { class = "^(gedit|org.gnome.TextEditor|mousepad)$" }, opacity = "0.8 0.7" })
W({ match = { class = "^(deluge)$" }, opacity = "0.9 0.8" })
W({ match = { class = "^(im.riot.Riot)$" }, opacity = "0.9 0.8" })
W({ match = { class = "^(seahorse)$" }, opacity = "0.9 0.8" })
W({ match = { title = "^(Picture-in-Picture)$" }, opacity = "0.95 0.75" })
W({ match = { class = "^(jetbrains-.*)$" }, opacity = "1 0.95" })

-- Taille
W({ match = { tag = "KooL_Cheat*" }, size = { "65%", "90%" } })
W({ match = { tag = "wallpaper*" }, size = { "70%", "70%" } })
W({ match = { tag = "settings*" }, size = { "70%", "70%" } })
W({ match = { class = "^([Ww]hatsapp-for-linux|ZapZap|com.rtosta.zapzap)$" }, size = { "60%", "70%" } })
W({ match = { class = "^([Ff]erdium)$" }, size = { "60%", "70%" } })

-- Divers
W({ match = { title = "^(Picture-in-Picture)$" }, pin = true })
W({ match = { title = "^(Picture-in-Picture)$" }, keep_aspect_ratio = true })
W({ match = { tag = "games*" }, no_blur = true })
W({ match = { tag = "games*" }, fullscreen = true })
W({ match = { class = "^(jetbrains-.*)$" }, no_initial_focus = true }) -- tooltips JetBrains
W({ match = { title = "^(win.*)$" }, no_initial_focus = true })

-- Vicinae : flottant en bas, épinglé, garde le focus clavier tant qu'il est ouvert
W({ match = { class = "^(vicinae)$" }, float = true })
W({ match = { class = "^(vicinae)$" }, move = { 575, 550 } })
W({ match = { class = "^(vicinae)$" }, pin = true })
W({ match = { class = "^(vicinae)$" }, stay_focused = true })

-- Layers
L({ match = { namespace = "^rofi$" }, blur = true })
L({ match = { namespace = "^rofi$" }, ignore_alpha = 0 })
L({ match = { namespace = "^notifications$" }, blur = true })
L({ match = { namespace = "^notifications$" }, ignore_alpha = 0 })
L({ match = { namespace = "^quickshell:overview$" }, blur = true })
L({ match = { namespace = "^quickshell:overview$" }, ignore_alpha = 0.5 })
```

- [ ] **Step 2 : tester**

Run: `cd ~/.config/hypr && luac5.4 -p lua/rules.lua && lua5.4 -e 'dofile("<scratchpad>/hlstub.lua")' -e 'require("lua.rules")' -e 'STUB.report()' && echo "attendu : $(grep -cE '^\s*windowrule' UserConfigs/WindowRules.conf) windowrule, $(grep -cE '^\s*layerrule' UserConfigs/WindowRules.conf) layerrule"`
Expected : `window_rule` = nombre de lignes `windowrule` du `.conf`, `layer_rule 6`.

### Task 7 : `hyprland.lua` et bascule

**Files:**
- Create: `hyprland.lua`

- [ ] **Step 1 : écrire le point d'entrée**

```lua
-- Hyprland — point d'entrée Lua. Un module par sujet dans lua/.
-- Retour à l'ancienne config : mv hyprland.lua hyprland.lua.off && hyprctl reload full-reset
require("lua.monitors")        -- écrans (monitors.conf / workspaces.conf via nwg-displays)
require("lua.env")             -- variables d'environnement
require("lua.settings")        -- layouts, clavier, souris, divers
require("lua.decorations")     -- bordures, ombres, flou (couleurs wallust)
require("lua.animations")      -- animations
require("lua.rules")           -- règles fenêtres et layers
require("lua.binds")           -- raccourcis
require("lua.laptop")          -- pavé tactile, touches Fn, capot
require("lua.binds-caelestia") -- overrides caelestia, en dernier
require("lua.autostart")       -- démarrage
```

- [ ] **Step 2 : test complet hors Hyprland**

Run: `cd ~/.config/hypr && luac5.4 -p hyprland.lua && lua5.4 -e 'dofile("<scratchpad>/hlstub.lua")' -e 'dofile("hyprland.lua")' -e 'STUB.report()'`
Expected : `bind 148`, `monitor 3`, `device 1`, `layer_rule 6`, pas d'erreur.

- [ ] **Step 3 : bascule**

Run: `hyprctl reload full-reset; sleep 2; echo "err='$(hyprctl configerrors)'"; hyprctl version | head -2`
Expected : `err=''`. Si erreur : la lire, corriger le module, `hyprctl reload`. Si la session devient inutilisable : `mv ~/.config/hypr/hyprland.lua{,.off} && hyprctl reload full-reset`.

- [ ] **Step 4 : comparer à la ligne de base**

```bash
S=<scratchpad>; hyprctl binds | grep -c key:; hyprctl -j monitors | grep -E '"name"|"x"|"y"' | head -4
for o in general:gaps_out general:gaps_in general:border_size general:layout general:col.inactive_border decoration:rounding decoration:inactive_opacity decoration:blur:size input:kb_layout input:repeat_rate misc:vrr cursor:no_hardware_cursors dwindle:preserve_split master:new_status binds:workspace_back_and_forth xwayland:force_zero_scaling; do printf '%s => ' "$o"; hyprctl getoption "$o" | head -1; done | diff - <(grep -v active_border $S/baseline/options.txt) && echo "options identiques"
hyprctl -j clients | python3 -c 'import json,sys; print([(c["class"],c["tags"]) for c in json.load(sys.stdin) if c["class"]=="kitty"][:1])'
hyprctl binds | grep -B4 'toggle_special\|togglespecial' | head -8
```
Expected : `148`, eDP-1 à 1920x0, « options identiques » (`col.active_border` exclu : RainbowBorders.sh l'anime), kitty taggé `terminal*`, bind SUPER+U présent.

### Task 8 : adapter les scripts

**Files:**
- Modify: `scripts/TouchPad.sh:15,21`, `scripts/SwitchKeyboardLayout.sh:21,32`, `scripts/KeyBinds.sh:14-25`, `scripts/Kool_Quick_Settings.sh:56-65`, `UserScripts/WallpaperSelect.sh:135-175`

- [ ] **Step 1 : TouchPad.sh** — remplacer les deux `hyprctl keyword '$TOUCHPAD_ENABLED' "true|false" -r` par :

```bash
hyprctl eval 'hl.device({ name = "asue1209:00-04f3:319f-touchpad", enabled = true })'
hyprctl eval 'hl.device({ name = "asue1209:00-04f3:319f-touchpad", enabled = false })'
```
Test : `hyprctl eval 'hl.device({ name = "asue1209:00-04f3:319f-touchpad", enabled = true })'` → `ok`.

- [ ] **Step 2 : SwitchKeyboardLayout.sh** — remplacer les deux `grep 'kb_layout = ' "$settings_file" | cut -d '=' -f 2` par `hyprctl getoption input:kb_layout | awk 'NR==1 {print $2}'`. Test : la commande renvoie `fr`.

- [ ] **Step 3 : KeyBinds.sh** — pointer sur les modules Lua :

```bash
keybinds=$(grep -hE '^\s*hl\.bind\(' "$HOME/.config/hypr/lua/binds.lua" "$HOME/.config/hypr/lua/binds-caelestia.lua" "$HOME/.config/hypr/lua/laptop.lua" | sed -E 's/^\s*hl\.bind\("([^"]+)",\s*(.*)\)\s*(--.*)?$/\1 → \2 \3/')
```
et supprimer le bloc `laptop_binds` devenu inutile. Test : `bash -n` puis lancer `KeyBinds.sh` (rofi affiche la liste).

- [ ] **Step 4 : Kool_Quick_Settings.sh** — remplacer les cibles « view/edit … » :

| Entrée | Fichier |
|---|---|
| User Defaults | `lua/binds.lua` |
| ENV variables | `lua/env.lua` |
| Window Rules | `lua/rules.lua` |
| User Keybinds | `lua/binds.lua` |
| User Settings | `lua/settings.lua` |
| Startup Apps | `lua/autostart.lua` |
| Decorations | `lua/decorations.lua` |
| Animations | `lua/animations.lua` |
| Laptop Keybinds | `lua/laptop.lua` |
| Default Keybinds | `lua/binds.lua` |

Test : `bash -n scripts/Kool_Quick_Settings.sh`.

- [ ] **Step 5 : WallpaperSelect.sh** — lire `modify_startup_config` en entier, puis remplacer les `sed` qui commentent/décommentent `exec-once = awww-daemon …` et `mpvpaper` dans `Startup_Apps.conf` par les mêmes opérations sur `lua/autostart.lua` (lignes `hl.exec_cmd("awww-daemon --format xrgb")` et `hl.exec_cmd("mpvpaper …")`). Test : `bash -n`, puis simuler sur une copie du module dans le scratchpad et vérifier que la ligne est commentée (`-- hl.exec_cmd("awww…`).

- [ ] **Step 6 : `Refresh.sh` recharge-t-il Hyprland après wallust ?** `grep -n 'hyprctl reload' UserScripts/WallpaperSelect.sh scripts/Refresh.sh UserScripts/WallpaperRandom.sh`. Si absent dans le chemin wallust → ajouter `hyprctl reload` après l'appel wallust. Test : changer le fond d'écran (SUPER+W) et vérifier que `hyprctl getoption general:col.inactive_border` change.

### Task 9 : archiver l'ancienne config, finir

**Files:**
- Move: `hyprland.conf`, `configs/`, `UserConfigs/*.conf` → `legacy/`
- Keep: `monitors.conf`, `workspaces.conf`, `hyprlock*.conf`, `hypridle.conf`, `application-style.conf`, `wallust/`, `scheme/`, `Monitor_Profiles/`, `scripts/`, `UserScripts/`

- [ ] **Step 1 : vérifier que plus rien ne lit les `.conf` déplacés**

Run: `cd ~/.config/hypr && grep -rnE 'UserConfigs/[A-Za-z_0-9-]+\.conf|configs/Keybinds\.conf|hypr/hyprland\.conf' scripts UserScripts lua hyprland.lua ../wallust ../caelestia 2>/dev/null | grep -v legacy`
Expected : aucune ligne (sinon corriger le script concerné).

- [ ] **Step 2 : déplacer**

```bash
cd ~/.config/hypr && mkdir -p legacy && mv hyprland.conf configs UserConfigs legacy/ && echo "# Ancienne config hyprlang, plus chargée. Retour : mv legacy/hyprland.conf legacy/configs legacy/UserConfigs . ; mv hyprland.lua hyprland.lua.off ; hyprctl reload full-reset" > legacy/README
```

- [ ] **Step 3 : dernier reload et rapport**

Run: `hyprctl reload full-reset; sleep 2; echo "err='$(hyprctl configerrors)'"; hyprctl binds | grep -c key:`
Expected : `err=''`, `148`. Lister à l'utilisateur les tests manuels : capot, Fn pavé tactile, SUPER+Return, SUPER+D, SUPER+L, SUPER+W (fond d'écran + couleurs), Alt+Shift (disposition clavier).
