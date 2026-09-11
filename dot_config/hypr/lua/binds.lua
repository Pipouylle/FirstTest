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
-- SUPER+M (splitratio 0.3) : pas d'équivalent dans l'API Lua de Hyprland 0.56, retiré.

-- Fenêtres
hl.bind("SUPER + SHIFT + F", hl.dsp.window.fullscreen({ mode = "fullscreen" }))
hl.bind("SUPER + CTRL + F", hl.dsp.window.fullscreen({ mode = "maximized" }))
hl.bind("SUPER + SPACE", hl.dsp.window.float({ action = "toggle" }))
-- SUPER+ALT+SPACE (workspaceopt allfloat) : dispatcher supprimé par Hyprland, retiré.
hl.bind("SUPER + G", hl.dsp.group.toggle())
hl.bind("SUPER + CTRL + tab", hl.dsp.group.next())
hl.bind("ALT + tab", function()
  hl.dispatch(hl.dsp.window.cycle_next())
  hl.dispatch(hl.dsp.window.bring_to_top())
end)

for _, dir in ipairs({ "left", "right", "up", "down" }) do
  hl.bind("SUPER + CTRL + " .. dir, hl.dsp.window.move({ direction = dir }))
  hl.bind("SUPER + ALT + " .. dir, hl.dsp.window.swap({ direction = dir }))
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
