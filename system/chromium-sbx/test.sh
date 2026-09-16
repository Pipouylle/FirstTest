#!/usr/bin/env bash
# ==============================================================================
# test.sh : vérifie l'installation de chromium-sbx. À lancer dans le terminal de session,
# PAS depuis un agent sandboxé (bwrap-agent bloque sudo et systemd).
# Ouvre une fenêtre de mot de passe KeePassXC (accès au compte chromium) et lance
# Chromium sur about:blank (nouvel onglet si Chromium est déjà ouvert).
# ==============================================================================
set -u
ok() { echo "  OK     $*"; }
ko() { echo "  ÉCHEC  $*"; }

echo "=== 1. Règle sudo ==="
out=$(sudo -n -u chromium /usr/local/bin/chromium-sbx-inner --option-de-test 2>&1); rc=$?
if [[ $rc -eq 2 && $out == *"option refusée"* ]]; then ok "lanceur interne sans mot de passe, options refusées"; else ko "lanceur interne : code=$rc [$out]"; fi
if sudo -n -u chromium /usr/bin/true 2>/dev/null; then ko "une commande quelconque passe sans mot de passe"; else ok "toute autre commande en tant que chromium exige un mot de passe"; fi

echo "=== 2. Services et sockets de passage ==="
systemctl --user start chromium-sbx-wayland.service chromium-sbx-dbus-relay.service
sleep 1
for u in chromium-sbx-wayland chromium-sbx-dbus chromium-sbx-dbus-relay pipewire-pulse; do
    if [[ $(systemctl --user is-active "$u") == active ]]; then ok "$u actif"; else ko "$u inactif"; fi
done
for s in wayland bus pulse; do
    if [[ -S /run/chromium-sbx/$s ]]; then ok "socket /run/chromium-sbx/$s ($(stat -c '%A %G' /run/chromium-sbx/$s))"; else ko "socket $s absent"; fi
done
p=$XDG_RUNTIME_DIR/chromium-sbx-dbus
[[ $(stat -c '%a' "$p" 2>/dev/null) == 700 ]] && ok "proxy D-Bus sur socket privé" || ko "socket du proxy absent ou pas privé : $p"

echo "=== 3. En tant que chromium : D-Bus comme Chromium (libdbus, dans Bubblewrap) ==="
keepass-tokens sudo chromium sh -c '
  bwrap --ro-bind / / --dev /dev --proc /proc --tmpfs /run --dir /run/chromium \
    --ro-bind /run/chromium-sbx/bus /run/chromium/bus --setenv DBUS_SESSION_BUS_ADDRESS unix:path=/run/chromium/bus sh -c "
      t=\$(dbus-send --session --print-reply --dest=org.freedesktop.portal.Desktop /org/freedesktop/portal/desktop org.freedesktop.portal.Settings.ReadOne string:org.freedesktop.appearance string:color-scheme 2>&1 | tail -1)
      case \"\$t\" in *uint32*) echo \"  OK     portail Réglages (color-scheme : \${t##* })\";; *) echo \"  ÉCHEC  portail Réglages : \$t\";; esac
      k=\$(dbus-send --session --print-reply --dest=org.freedesktop.secrets /org/freedesktop/secrets org.freedesktop.DBus.Properties.Get string:org.freedesktop.Secret.Service string:Collections 2>&1)
      case \"\$k\" in *collection/*) echo \"  OK     KeePassXC joignable (Secret Service)\";; *) echo \"  ÉCHEC  KeePassXC : \$k\";; esac
      f=\$(dbus-send --session --print-reply --dest=org.freedesktop.portal.Desktop /org/freedesktop/portal/desktop org.freedesktop.portal.OpenURI.OpenURI string: string:x 2>&1)
      case \"\$f\" in *ccess*denied*|*AccessDenied*) echo \"  OK     portail OpenURI refusé\";; *) echo \"  ÉCHEC  OpenURI non refusé : \$f\";; esac
    "
  stat -c "  info   profil : %A %U:%G %n" /var/lib/chromium-sbx /var/lib/chromium-sbx/.config/chromium 2>/dev/null
'

echo "=== 4. Lancement de Chromium ==="
chromium-sbx about:blank >/dev/null 2>&1 &
sleep 10
P=$(pgrep -u chromium -o -f '^/usr/lib/chromium/chromium' || true)
if [[ -z $P ]]; then
    ko "Chromium ne tourne pas sous le compte chromium"
else
    ok "Chromium tourne sous le compte $(ps -o user= -p "$P") (pid $P)"
    g=$(pgrep -u chromium -f -- '--type=gpu-process' | head -1)
    if [[ -n $g ]] && ! tr '\0' ' ' </proc/$g/cmdline | grep -q -- '--use-gl=disabled'; then ok "GPU actif"; else ko "GPU désactivé ou processus GPU absent"; fi
    found=0
    while IFS='|' read -r pid class xw; do
        [[ $(ps -o user= -p "$pid" 2>/dev/null) == chromium ]] || continue
        found=1
        [[ $class == chromium && $xw == false ]] && ok "fenêtre Hyprland : classe chromium, Wayland natif" || ko "fenêtre : classe=[$class] xwayland=$xw"
    done < <(hyprctl clients -j | jq -r '.[] | "\(.pid)|\(.class)|\(.xwayland)"')
    [[ $found == 1 ]] || ko "aucune fenêtre Hyprland du compte chromium"
    echo "=== 5. Isolation vue depuis la session ==="
    if ls /var/lib/chromium-sbx >/dev/null 2>&1; then ko "home de chromium lisible"; else ok "home de chromium illisible"; fi
    if cat /proc/$P/environ >/dev/null 2>&1; then ko "environnement de Chromium lisible"; else ok "/proc/$P/environ refusé"; fi
    if ls /proc/$P/root/ >/dev/null 2>&1; then ko "/proc/$P/root accessible"; else ok "/proc/$P/root refusé"; fi
    if kill -0 "$P" 2>/dev/null; then ko "la session peut signaler Chromium"; else ok "la session ne peut pas signaler Chromium"; fi
fi
if [[ -d ~/.local/share/secure-profiles/chromium || -d ~/.config/chromium ]]; then
    ko "une ancienne copie du profil traîne dans ton home (~/.local/share/secure-profiles/chromium ou ~/.config/chromium)"
else
    ok "aucune ancienne copie du profil dans ton home"
fi
