#!/bin/bash
# /* ---- 💫 https://github.com/JaKooLit 💫 ---- */  ##
# searchable enabled keybinds using rofi

# kill yad to not interfere with this binds
pkill yad || true

# check if rofi is already running
if pidof rofi > /dev/null; then
  pkill rofi
fi

# define the config files
lua_dir="$HOME/.config/hypr/lua"
rofi_theme="$HOME/.config/rofi/config-keybinds.rasi"
msg='Keybinds (config Lua : lua/binds*.lua, lua/laptop.lua)'

# Extrait les hl.bind("touches", ...) des modules Lua
keybinds=$(grep -hE '^\s*hl\.bind\(' "$lua_dir/binds.lua" "$lua_dir/binds-caelestia.lua" "$lua_dir/laptop.lua" \
  | sed -E 's/^\s*hl\.bind\("([^"]+)",\s*(.*)\)\s*(--.*)?$/\1  →  \2  \3/')

display_keybinds="$keybinds"

# use rofi to display the keybinds with the modified content
echo "$display_keybinds" | rofi -dmenu -i -config "$rofi_theme" -mesg "$msg"