-- Overrides caelestia-shell (ex UserConfigs/CaelestiaKeybinds.conf).
-- Ces touches ne sont volontairement pas déclarées dans binds.lua : caelestia affiche
-- déjà son OSD, les scripts JaKooLit faisaient doublon (notification + OSD).
local g = hl.dsp.global

-- Redémarrer le shell. `qs kill` passe par l'IPC de l'instance ; si elle ne répond pas
-- (cas probable pendant le chargement de la config, ~27 s au boot le 15/09/2026, où deux
-- instances ont tourné), `pkill -x qs` sert de repli (-x compare le nom du processus, pas la
-- ligne de commande, donc le bind ne se tue pas lui-même comme `pkill -f quickshell`).
-- `-n` refuse de lancer un doublon.
hl.bind("CTRL + SUPER + SHIFT + R", hl.dsp.exec_cmd("qs kill -c caelestia; sleep 0.5; pkill -x qs; sleep 0.5; qs -c caelestia -n -d"))

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
