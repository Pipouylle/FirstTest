-- Programmes lancés au démarrage (ex UserConfigs/Startup_Apps.conf).
-- Garde-fou : « hyprland.start » ne doit lancer ces commandes qu'une fois par session,
-- même si l'événement est rejoué à un reload.
local home = os.getenv("HOME")
local scripts = home .. "/.config/hypr/scripts"
local user_scripts = home .. "/.config/hypr/UserScripts"
local marker = (os.getenv("XDG_RUNTIME_DIR") or "/tmp") .. "/hypr-autostart-" .. (os.getenv("HYPRLAND_INSTANCE_SIGNATURE") or "nosig")
local live_wallpaper = ""  -- chemin d'une vidéo (mis à jour par UserScripts/WallpaperSelect.sh) ; vide = image

hl.on("hyprland.start", function()
  local f = io.open(marker, "r")
  if f then f:close(); return end
  f = io.open(marker, "w"); if f then f:close() end

  -- fond d'écran : image (awww) ou vidéo (mpvpaper)
  if live_wallpaper ~= "" then
    hl.exec_cmd("mpvpaper '*' -o \"load-scripts=no no-audio --loop\" '" .. live_wallpaper .. "'")
  else
    hl.exec_cmd("awww-daemon --format xrgb")
    hl.exec_cmd("waypaper --restore")
  end

  hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP")
  hl.exec_cmd("systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP")
  hl.exec_cmd(scripts .. "/Polkit.sh")

  -- nm-applet et blueman-applet ne servaient qu'a poser une icone dans le tray, en
  -- doublon des indicateurs reseau et bluetooth natifs de la barre caelestia (qui gere
  -- aussi la saisie du mot de passe wifi et l'appairage). Ils ne sont plus lances.
  hl.exec_cmd("qs -c caelestia -d")   -- barre, notifications, verrouillage
  hl.exec_cmd("vicinae server")       -- lanceur

  hl.exec_cmd("wl-paste --type text --watch cliphist store")
  hl.exec_cmd("wl-paste --type image --watch cliphist store")

  hl.exec_cmd(user_scripts .. "/RainbowBorders.sh")
  hl.exec_cmd("easyeffects --hide-window")  -- `--service-mode` etait la CLI d'EasyEffects 7
  hl.exec_cmd(scripts .. "/PortalHyprland.sh")
end)
