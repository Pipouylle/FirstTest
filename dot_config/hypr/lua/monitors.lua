-- Écrans et workspaces : lit monitors.conf et workspaces.conf (hyprlang, écrits par
-- nwg-displays et le sélecteur de profils), pour que ces outils continuent de marcher.
local home = os.getenv("HOME")
local MON = home .. "/.config/hypr/monitors.conf"
local WS = home .. "/.config/hypr/workspaces.conf"

local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

local function lines(path)
  local out, f = {}, io.open(path, "r")
  if not f then return out end
  for raw in f:lines() do
    local l = trim((raw:gsub("#.*$", "")))
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
for _, l in ipairs(lines(MON)) do
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
for _, l in ipairs(lines(WS)) do
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
