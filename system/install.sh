#!/usr/bin/env bash
# Réglages système hors $HOME (fichiers /etc + services), à lancer APRÈS `chezmoi apply` :
#   sudo bash ~/.local/share/chezmoi/system/install.sh
# Idempotent. Détail et justification dans README.md, section « Réglages système ».
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
[[ $EUID -eq 0 ]] || { echo "À lancer avec sudo."; exit 1; }

echo "== paquets =="
pacman -S --needed --noconfirm zram-generator earlyoom iw dnsmasq networkmanager wpa_supplicant sddm

echo "== fichiers /etc =="
install -Dm644 "$here/etc/systemd/zram-generator.conf"  /etc/systemd/zram-generator.conf
install -Dm644 "$here/etc/tmpfiles.d/disable-zswap.conf" /etc/tmpfiles.d/disable-zswap.conf
install -Dm644 "$here/etc/sysctl.d/99-zram.conf"        /etc/sysctl.d/99-zram.conf
install -Dm644 "$here/etc/default/earlyoom"             /etc/default/earlyoom
install -Dm644 "$here/etc/NetworkManager/NetworkManager.conf" /etc/NetworkManager/NetworkManager.conf
install -Dm644 "$here/etc/sddm.conf"                    /etc/sddm.conf
systemd-tmpfiles --create /etc/tmpfiles.d/disable-zswap.conf
sysctl --system >/dev/null
systemctl daemon-reload

echo "== swapfile 4 Go (filet derrière la zram) =="
if [[ ! -e /swapfile ]]; then
  mkswap -U clear -s 4G -F /swapfile >/dev/null
  chmod 600 /swapfile
  swapon /swapfile
fi
grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap defaults 0 0' >> /etc/fstab

echo "== services =="
systemctl enable --now NetworkManager earlyoom
systemctl enable sddm bluetooth
# iwd crée/supprime lui-même wlan0 et fait doublon avec wpa_supplicant : jamais actif ici.
for s in iwd netbird rustdesk docker.service; do systemctl disable --now "$s" 2>/dev/null || true; done
systemctl enable docker.socket 2>/dev/null || true   # docker à la demande, si installé

cat <<'MSG'

Terminé. Reste à faire :
  - redémarrer (zram active au boot, zswap coupé) puis vérifier : zramctl ; swapon --show
  - en utilisateur, si Tailscale est utilisé : tailscale set --accept-dns=false
MSG
