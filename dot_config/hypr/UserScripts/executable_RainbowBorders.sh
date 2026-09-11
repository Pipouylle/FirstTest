#!/bin/bash
# Bordure active en dégradé aléatoire animé (animation borderangle en boucle).
random_hex() { echo "rgb($(openssl rand -hex 3))"; }
colors=""
for _ in $(seq 1 10); do colors="$colors\"$(random_hex)\", "; done
hyprctl eval "hl.config({ general = { col = { active_border = { colors = { ${colors%, } }, angle = 270 } } } })"
