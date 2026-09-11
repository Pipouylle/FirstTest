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
