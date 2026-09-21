#!/usr/bin/env bash
# ==============================================================================
# test.sh : vérifie l'installation de chromium-sbx. À lancer dans le terminal de session,
# PAS depuis un agent sandboxé (bwrap-agent bloque sudo et systemd).
# Ouvre deux fenêtres de mot de passe KeePassXC (accès au compte chromium) et lance
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
  stat -c "  info   profil : %A %U:%G %n" /var/lib/chromium-sbx /var/lib/chromium-sbx/.config/chromium 2>/dev/null; true
' || ko "vérification en tant que chromium impossible (mot de passe annulé ?)"

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

echo "=== 6. Sélecteur de fichiers ==="
R=/srv/chromium-sbx
attendu_r="root:root 755"
if [[ $(stat -c '%U:%G %a' "$R" 2>/dev/null) == "$attendu_r" ]]; then ok "$R : $attendu_r"; else ko "$R : $(stat -c '%U:%G %a' "$R" 2>&1) (attendu : $attendu_r)"; fi
E=/srv/chromium-sbx/Envois
attendu="$(id -un):chromium 2750"
if [[ $(stat -c '%U:%G %a' "$E" 2>/dev/null) == "$attendu" ]]; then ok "$E : $attendu"; else ko "$E : $(stat -c '%U:%G %a' "$E" 2>&1) (attendu : $attendu)"; fi
if grep -qF -- '--ro-bind "$ENVOIS" "$ENVOIS"' /usr/local/bin/chromium-sbx-inner; then ok "lanceur interne installé : Envois monté en lecture seule"; else ko "lanceur interne installé sans Envois : relancer sudo ./install.sh"; fi
# Le relais qui tourne, pas l'unité : un relais démarré avant la mise à jour n'a pas l'option
pid=$(systemctl --user show -p MainPID --value chromium-sbx-dbus-relay 2>/dev/null)
if [[ ${pid:-0} -le 0 ]]; then
    ko "relais arrêté : impossible de vérifier --filechooser (systemctl --user start chromium-sbx-dbus-relay)"
elif tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null | grep -q -- --filechooser; then
    ok "relais lancé avec --filechooser (pid $pid)"
else
    ko "relais sans --filechooser : systemctl --user daemon-reload && systemctl --user restart chromium-sbx-dbus-relay"
fi
t=$(mktemp -d)
mkdir -p "$t/dossier/sous-dossier"
echo "test chromium-sbx" > "$t/dossier/sous-dossier/essai.txt"
if u=$(chromium-sbx-fichiers copier "$t/dossier"); then
    f=${u#file://}/sous-dossier/essai.txt
    id=${u#file://$E/}
    id=${id%%/*}
    ok "copie préparée : ${u#file://}"
    keepass-tokens sudo chromium sh -c "
      if [ \"\$(cat '$f' 2>/dev/null)\" = 'test chromium-sbx' ]; then echo '  OK     le compte chromium lit la copie (sous-dossier compris)'; else echo '  ÉCHEC  le compte chromium ne lit pas $f'; fi
      if [ ! -f '$f' ]; then echo '  ÉCHEC  copie absente : $f'; elif ( echo x >> '$f' ) 2>/dev/null; then echo '  ÉCHEC  le compte chromium peut modifier la copie'; else echo '  OK     copie en lecture seule pour le compte chromium'; fi
    " || ko "vérification en tant que chromium impossible (mot de passe annulé ?)"
    chromium-sbx-fichiers supprimer "$id"
else
    ko "chromium-sbx-fichiers copier a échoué"
fi
rm -rf "$t"
if [[ -s ~/.config/keepass-tokens/phrase ]]; then
    if bwrap-agent claude -- true >/dev/null 2>&1; then
        if bwrap-agent claude -- test -e ~/.config/keepass-tokens/phrase >/dev/null 2>&1; then ko "phrase anti-hameçonnage lisible depuis bwrap-agent"; else ok "phrase anti-hameçonnage invisible depuis bwrap-agent"; fi
    else
        ko "bwrap-agent inutilisable : impossible de vérifier la phrase anti-hameçonnage"
    fi
else
    ko "pas de phrase anti-hameçonnage : crée ~/.config/keepass-tokens/phrase"
fi

echo "=== 7. À vérifier à la main dans Chromium ==="
cat <<'TXT'
  - Gmail : joindre un fichier (fenêtre de mot de passe avec ta phrase, puis sélection)
  - joindre plusieurs fichiers ; envoyer un dossier (ex. Proton Drive)
  - annuler au mot de passe, puis à la sélection : rien n'est joint
  - choisir un fichier de ~/.ssh : envoi refusé, avec la raison
  - Ctrl+S sur une page : fichier dans /srv/chromium-sbx/Downloads
  - joindre un fichier déjà téléchargé par Chromium (Downloads) : envoyé sans copie dans Envois
  - 2e pièce jointe dans les 10 min : pas de mot de passe
  - toujours bon : thème sombre, connexions aux sites, KeePassXC sollicité au lancement
TXT
