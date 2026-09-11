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
