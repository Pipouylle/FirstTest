#!/bin/bash
# Mode jeu : coupe animations, ombres, flou, gaps, arrondis ; fenêtres opaques.
notif="$HOME/.config/swaync/images/ja.png"
SCRIPTSDIR="$HOME/.config/hypr/scripts"
HYPRGAMEMODE=$(hyprctl -j getoption animations:enabled | jq -r '.set // .int // .bool' 2>/dev/null)

if [ "$HYPRGAMEMODE" = "true" ] || [ "$HYPRGAMEMODE" = "1" ]; then
	hyprctl eval '
		hl.config({
			animations = { enabled = false },
			decoration = { shadow = { enabled = false }, blur = { enabled = false }, rounding = 0 },
			general = { gaps_in = 0, gaps_out = 0, border_size = 1 },
		})
		if GAMEMODE_RULE then GAMEMODE_RULE:set_enabled(true) else
			GAMEMODE_RULE = hl.window_rule({ name = "gamemode-opaque", match = { class = ".*" }, opacity = "1 override 1 override 1 override" })
		end'
	awww kill
	notify-send -e -u low -i "$notif" " Gamemode:" " enabled"
else
	hyprctl eval 'if GAMEMODE_RULE then GAMEMODE_RULE:set_enabled(false) end'
	awww-daemon --format xrgb && awww img "$HOME/.config/rofi/.current_wallpaper" &
	sleep 0.1
	"${SCRIPTSDIR}/WallustSwww.sh"
	sleep 0.5
	"${SCRIPTSDIR}/Refresh.sh"   # hyprctl reload : rétablit les valeurs de la config
	notify-send -e -u normal -i "$notif" " Gamemode:" " disabled"
fi
