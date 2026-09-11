#!/bin/bash
# Bascule Master / Dwindle à la volée et adapte SUPER+J/K/O (config Lua : hyprctl eval).
notif="$HOME/.config/swaync/images/ja.png"
LAYOUT=$(hyprctl -j getoption general:layout | jq -r '.str')

case $LAYOUT in
"master")
	hyprctl eval '
		hl.config({ general = { layout = "dwindle" } })
		hl.unbind("SUPER + J"); hl.unbind("SUPER + K")
		hl.bind("SUPER + J", hl.dsp.window.cycle_next())
		hl.bind("SUPER + K", hl.dsp.window.cycle_next({ prev = true }))
		hl.bind("SUPER + O", hl.dsp.layout("togglesplit"))'
	notify-send -e -u low -i "$notif" " Dwindle Layout"
	;;
"dwindle")
	hyprctl eval '
		hl.config({ general = { layout = "master" } })
		hl.unbind("SUPER + J"); hl.unbind("SUPER + K"); hl.unbind("SUPER + O")
		hl.bind("SUPER + J", hl.dsp.layout("cyclenext"))
		hl.bind("SUPER + K", hl.dsp.layout("cycleprev"))'
	notify-send -e -u low -i "$notif" " Master Layout"
	;;
*) ;;
esac
