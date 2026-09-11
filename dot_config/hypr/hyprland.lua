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
