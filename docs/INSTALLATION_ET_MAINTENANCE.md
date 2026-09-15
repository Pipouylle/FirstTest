# Guide d'Installation, Déploiement et Maintenance du Système

Ce guide documente l'installation complète d'Arch Linux, le déploiement des dotfiles via **chezmoi**, la configuration des applications et des trousseaux de sécurité, ainsi que les procédures complètes pour **prendre soin de son système et restaurer l'état de l'OS** en cas de problème.

---

## Sommaire

- [Partie 1 : Installation et Déploiement](#partie-1--installation-et-déploiement)
  - [1. Installation d'Arch Linux de base](#1-installation-darch-linux-de-base)
  - [2. Déploiement automatique des dotfiles et paquets](#2-déploiement-automatique-des-dotfiles-et-paquets)
  - [3. Configuration des Applications (Chromium, Discord, Firejail)](#3-configuration-des-applications)
  - [4. Gestion du Trousseau / Keyring (Tous les cas de figure)](#4-gestion-du-trousseau--keyring-tous-les-cas-de-figure)
- [Partie 2 : Prendre Soin de son OS & Restauration (Rollback)](#partie-2--prendre-soin-de-son-os--restauration-rollback)
  - [1. Procédures de Restauration avec Timeshift](#1-procédures-de-restauration-avec-timeshift)
  - [2. Gestion et Politique des Instantanés](#2-gestion-et-politique-des-instantanés)
  - [3. Entretien régulier et Santé d'Arch Linux](#3-entretien-régulier-et-santé-darch-linux)

---

## Partie 1 : Installation et Déploiement

### 1. Installation d'Arch Linux de base

Sur une machine UEFI vierge (ex: NVMe) :
1. **Partitionnement type** (exemple sur `/dev/nvme0n1`) :
   - `/dev/nvme0n1p1` : 1 Go, type `EFI System` (FAT32), monté sur `/boot`
   - `/dev/nvme0n1p2` : reste du disque, type `Linux filesystem` (ext4), monté sur `/`
2. **Installation minimale** :
   ```bash
   pacstrap -K /mnt base base-devel linux linux-firmware git sudo nano networkmanager
   genfstab -U /mnt >> /mnt/etc/fstab
   arch-chroot /mnt
   ```
3. **Configuration utilisateur** :
   - Créer l'utilisateur (ex: `timothe`), l'ajouter au groupe `wheel` et configurer `sudoers` (`%wheel ALL=(ALL:ALL) ALL`).
   - Configurer le bootloader (`systemd-boot` via `bootctl install` ou `grub`).

---

### 2. Déploiement automatique des dotfiles et paquets

Une fois connecté sur votre nouvel utilisateur :

```bash
git clone https://github.com/Pipouylle/FirstTest.git
cd FirstTest
bash install.sh
```

Le script `install.sh` est **idempotent** (relançable sans risque) et réalise les opérations suivantes :
- Installe tous les paquets officiels : Hyprland (Lua), Caelestia, Yazi, Zed, Kitty, Chromium, Discord, Timeshift, KeePassXC, OpenSnitch, Firejail, etc.
- Compile et installe `yay` si absent, puis déploie les paquets AUR requis.
- Installe Oh-My-Zsh et ses plugins (`syntax-highlighting`, `autosuggestions`, `watch`).
- Initialise et applique les dotfiles avec `chezmoi`.
- Applique les réglages système via `system/install.sh` (swap, zram, earlyoom, service Timeshift au boot, pare-feu OpenSnitch).

---

### 3. Configuration des Applications

#### A. Chromium
- **Flags de sécurité** : Chromium lit automatiquement `~/.config/chromium-flags.conf`.
- Le fichier force `--password-store=gnome-libsecret` afin que toutes les données sensibles (cookies, sessions, mots de passe) soient chiffrées via l'API Secret Service (gérée par KeePassXC).

#### B. Discord
- Installé nativement (`/usr/bin/discord`).
- **Attention sécurité** : Par défaut, Discord stocke sa session dans `~/.config/discord/Local Storage/leveldb/`. Pour tester des fichiers douteux, lancez-les impérativement via Firejail (voir ci-dessous) afin qu'ils ne puissent pas accéder à ce dossier.

#### C. Firejail & Intégration Yazi
- Firejail est prêt à l'emploi.
- Dans le gestionnaire de fichiers `yazi`, appuyez sur **`O`** (Shift+o) sur n'importe quel script, binaire ou fichier :
  - **`Firejail (Private, Pas d'Internet)`** : sandbox éphémère en RAM sans accès réseau.
  - **`Firejail (Private, Internet Actif)`** : sandbox éphémère en RAM avec accès réseau.

#### D. Pare-feu applicatif OpenSnitch
- Le service démarre au boot : `sudo systemctl enable --now opensnitchd`.
- L'interface graphique `opensnitch-ui` démarre automatiquement avec Hyprland (`lua/autostart.lua`).
- Dès qu'un processus tente une connexion sortante suspecte, une alerte interactive surgit à l'écran.

---

### 4. Gestion du Trousseau / Keyring (Tous les cas de figure)

Le système utilise l'API standard Linux `org.freedesktop.secrets` (Secret Service). Selon votre situation, voici la marche à suivre :

#### Cas A : Vous possédez déjà une base KeePassXC existante (Restauration)
1. Récupérez votre fichier `MotsDePasse.kdbx` (clé USB, sauvegarde chiffrée, etc.) et placez-le dans votre dossier personnel (ex: `~/MotsDePasse.kdbx`).
2. Lancez KeePassXC et ouvrez votre base avec votre mot de passe maître.
3. Allez dans **Outils** > **Paramètres** > **Intégration Secret Service** :
   - Cochez **Activer l'intégration Secret Service**.
   - Sélectionnez votre base `MotsDePasse.kdbx`.
4. Lancez `keyring-vault unlock` : vos tokens Claude et Antigravity sont immédiatement restaurés en mémoire vive (`/run/user/1000/secrets/`).

#### Cas B : Nouvelle installation vierge (Créer un nouveau trousseau KeePassXC)
1. Lancez **KeePassXC**.
2. Cliquez sur **Créer une nouvelle base de données** (ex: `~/MotsDePasse.kdbx`).
3. Définissez un mot de passe maître solide.
4. Activez le Secret Service : **Outils** > **Paramètres** > **Intégration Secret Service** > Cocher l'activation.
5. **Importer vos mots de passe depuis Chromium** :
   - Dans Chromium : `chrome://password-manager/settings` > Exporter les mots de passe (CSV).
   - Dans KeePassXC : **Base de données** > **Importer** > **Fichier CSV Chromium/Chrome**.
   - Supprimez immédiatement le CSV temporaire : `rm ~/Downloads/mots_de_passe.csv`.
6. **Enregistrer les tokens Claude et Agy dans KeePassXC** :
   - Dans votre terminal, lancez :
     ```bash
     keyring-vault init
     ```
   - KeePassXC affichera une alerte demandant d'autoriser la création des entrées. Cliquez sur **Autoriser**.
   - Les fichiers réels sur le disque sont remplacés par des liens vers la RAM.

#### Cas C : Utilisation de GNOME Keyring au lieu de KeePassXC
Si vous préférez le trousseau classique GNOME Keyring (déverrouillage global de session sans popups par application) :
1. Dans `~/.config/hypr/lua/autostart.lua`, activez :
   ```lua
   hl.exec_cmd("gnome-keyring-daemon --start --components=secrets,pkcs11")
   ```
2. Au premier lancement d'une application sensible, saisissez votre mot de passe maître pour initialiser le trousseau `login`.
3. Lancez `keyring-vault init` pour migrer les tokens dans GNOME Keyring.

---

## Partie 2 : Prendre Soin de son OS & Restauration (Rollback)

Grâce au setup mis en place, votre système prend un instantané incrémental complet de l'OS **à chaque démarrage** via Timeshift.

### 1. Procédures de Restauration avec Timeshift

En cas d'infection, de fausse manipulation ou de mise à jour qui casse le système :

#### Méthode 1 : Restauration graphique (Votre session démarre encore)
1. Ouvrez un terminal ou le lanceur d'applications et lancez :
   ```bash
   sudo timeshift-gtk
   ```
2. La liste des snapshots apparaît (identifiés par date et type `[B]` pour boot).
3. Cliquez sur l'instantané de votre choix (par exemple celui de ce matin ou d'hier).
4. Cliquez sur **Restaurer** en haut, validez les disques cibles (par défaut `/`), puis confirmez.
5. Le système réapplique l'état exact antérieur en quelques secondes et redémarre.

#### Méthode 2 : Restauration en console TTY (Si Hyprland ne démarre plus)
Si l'interface graphique plante au boot :
1. Sur l'écran noir ou bloqué, appuyez sur **`Ctrl + Alt + F3`** pour ouvrir un TTY.
2. Connectez-vous avec votre identifiant et mot de passe.
3. Lancez la restauration en ligne de commande :
   ```bash
   sudo timeshift --restore
   ```
4. Timeshift liste vos instantanés avec un numéro (0, 1, 2...).
5. Tapez le numéro du snapshot souhaité, validez avec Entrée (options par défaut recommandées), puis confirmez avec `y`.
6. Une fois terminé, redémarrez :
   ```bash
   sudo reboot
   ```

#### Méthode 3 : Restauration critique depuis une clé USB Live Arch (Si le PC ne boot plus du tout)
Si le noyau ou le bootloader est détruit :
1. Démarrez sur une clé USB d'installation Arch Linux standard.
2. Installez et lancez Timeshift en mémoire vive sur la clé :
   ```bash
   pacman -Sy timeshift
   timeshift --restore
   ```
3. Timeshift détectera votre partition NVMe (`/dev/nvme0n1p2`) et ses snapshots stockés dans `/timeshift/snapshots/`.
4. Sélectionnez le snapshot sain et restaurez. Retirez la clé et redémarrez : votre OS est ressuscité.

---

### 2. Gestion et Politique des Instantanés

- **Politique de rétention** : Configuré dans `/etc/timeshift/timeshift.json` pour conserver automatiquement les **5 derniers démarrages** (`count_boot: 5`). Les plus anciens sont automatiquement purgés pour ne pas saturer le disque.
- **Prendre un instantané manuel avant une manipulation dangereuse** :
  Avant de tester un script inconnu ou de faire une grosse manipulation système :
  ```bash
  sudo timeshift --create --comments "Avant test risqué"
  ```
- **Lister les instantanés existants** :
  ```bash
  sudo timeshift --list
  ```
- **Supprimer un instantané spécifique** :
  ```bash
  sudo timeshift --delete --snapshot '2026-09-14_20-38-29'
  ```

---

### 3. Entretien régulier et Santé d'Arch Linux

Pour conserver un système rapide, stable et propre :

1. **Mises à jour recommandées** :
   Effectuez une mise à jour régulière (ex: une fois par semaine) :
   ```bash
   sudo pacman -Syu
   yay -Sua
   ```
   *(Un instantané Timeshift aura de toute façon été pris au démarrage précédent en cas de régression)*.

2. **Nettoyage du cache pacman (Libérer de l'espace disque)** :
   Pacman conserve tous les paquets téléchargés dans `/var/cache/pacman/pkg/`.
   Pour ne conserver que les 2 dernières versions de chaque paquet :
   ```bash
   sudo paccache -rk2
   ```
   Pour supprimer le cache des paquets désinstallés :
   ```bash
   sudo paccache -ruk0
   ```

3. **Supprimer les paquets orphelins (dépendances inutilisées)** :
   ```bash
   pacman -Qtdq | sudo pacman -Rns - 2>/dev/null || echo "Aucun paquet orphelin."
   ```

4. **Vérifier les erreurs du journal système** :
   ```bash
   journalctl -p 3 -xb
   ```
   Affiche uniquement les erreurs critiques survenues depuis le dernier démarrage.
