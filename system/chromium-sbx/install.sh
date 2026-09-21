#!/usr/bin/env bash
# ==============================================================================
# install.sh : partie système (root) du compte dédié « chromium ».
# Idempotent. Après ./build.sh :   sudo ./install.sh
#
# - compte système chromium, home /var/lib/chromium-sbx (0700), sans shell ni mot de
#   passe (verrouillé ; « keepass-tokens set-account chromium » lui en donne un, rangé
#   dans KeePassXC)
# - /usr/local/bin/{wayland-sandbox-socket,chromium-sbx-inner}, appartenant à root
# - /run/chromium-sbx (tmpfiles) : dossier de passage des sockets, setgid chromium
# - /srv/chromium-sbx (root:root, 0755) : traversée seulement, pour qu'aucun des deux comptes
#   ne puisse renommer ou remplacer les sous-dossiers ci-dessous
# - /srv/chromium-sbx/Downloads : téléchargements, partagés avec la session par ACL
#   (la session n'obtient AUCUN autre droit sur le compte chromium)
# - /srv/chromium-sbx/Envois (2750, session:chromium) : copies des fichiers envoyés à
#   Chromium par le sélecteur de fichiers ; la session écrit, Chromium lit
# - /etc/sudoers.d/chromium-sbx : lancer Chromium sans mot de passe, le reste avec le
#   mot de passe du compte chromium
# ==============================================================================
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "à lancer avec sudo : sudo $0" >&2
    exit 1
fi
SESSION_USER=${SUDO_USER:-}
if [[ -z $SESSION_USER || $SESSION_USER == root ]]; then
    echo "à lancer avec sudo depuis ta session (SUDO_USER inconnu)" >&2
    exit 1
fi
cd "$(dirname "$0")"
if [[ ! -x wayland-sandbox-socket ]]; then
    echo "lancer d'abord ./build.sh (sans sudo)" >&2
    exit 1
fi

echo "==> compte chromium"
if ! id chromium &>/dev/null; then
    useradd --system --user-group --home-dir /var/lib/chromium-sbx --create-home \
        --shell /usr/bin/nologin --comment "Chromium isolé (chromium-sbx)" chromium
fi
chmod 700 /var/lib/chromium-sbx

echo "==> programmes système (root, non modifiables par la session)"
install -o root -g root -m 755 wayland-sandbox-socket /usr/local/bin/wayland-sandbox-socket
install -o root -g root -m 755 chromium-sbx-inner /usr/local/bin/chromium-sbx-inner

echo "==> dossier de passage /run/chromium-sbx"
sed "s/ timothe / $SESSION_USER /" tmpfiles-chromium-sbx.conf > /etc/tmpfiles.d/chromium-sbx.conf
chmod 644 /etc/tmpfiles.d/chromium-sbx.conf
systemd-tmpfiles --create /etc/tmpfiles.d/chromium-sbx.conf

echo "==> téléchargements partagés /srv/chromium-sbx/Downloads"
# root:root 755 : traversée pour la session et pour chromium, sans droit d'écriture pour aucun
# des deux ; le compte chromium ne peut donc ni renommer ni remplacer Downloads ou Envois. Les
# deux sous-dossiers gardent leurs propres propriétaires et modes : Downloads 2770 chromium:chromium
# avec ses ACL, Envois 2750 session:chromium (voir plus bas).
install -d -o root -g root -m 755 /srv/chromium-sbx
install -d -o chromium -g chromium -m 2770 /srv/chromium-sbx/Downloads
setfacl -m "u:$SESSION_USER:rwx,d:u:$SESSION_USER:rwx,d:u:chromium:rwx,d:g:chromium:rwx" /srv/chromium-sbx/Downloads

echo "==> copies envoyées à Chromium /srv/chromium-sbx/Envois"
# Bit setgid : ce que la session y crée prend le groupe chromium. Pas d'ACL par défaut, pour
# que Chromium n'y ait jamais plus que la lecture.
install -d -o "$SESSION_USER" -g chromium -m 2750 /srv/chromium-sbx/Envois

echo "==> flags Chromium du compte (chiffrement via KeePassXC)"
install -d -o chromium -g chromium -m 700 /var/lib/chromium-sbx/.config
printf '%s\n' '--password-store=gnome-libsecret' > /var/lib/chromium-sbx/.config/chromium-flags.conf
chown chromium:chromium /var/lib/chromium-sbx/.config/chromium-flags.conf
chmod 600 /var/lib/chromium-sbx/.config/chromium-flags.conf

echo "==> règle sudo"
tmp=$(mktemp)
sed "s/^timothe /$SESSION_USER /" sudoers-chromium-sbx > "$tmp"
if visudo -cf "$tmp" >/dev/null; then
    install -o root -g root -m 440 "$tmp" /etc/sudoers.d/chromium-sbx
    rm -f "$tmp"
else
    rm -f "$tmp"
    echo "règle sudo invalide : non installée" >&2
    exit 1
fi

echo
echo "Partie système installée. La suite (services de session, son, test, migration du"
echo "profil) se fait sans sudo."
