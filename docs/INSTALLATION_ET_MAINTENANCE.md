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

#### A. Chromium (compte Unix dédié `chromium`)
Chromium tourne sous le compte système **`chromium`** : son profil (cookies, sessions, extensions comme Proton Pass, historique) est dans `/var/lib/chromium-sbx` (`0700`), illisible par les programmes de la session. Principe, architecture et tests : `SECURITE_ET_ARCHITECTURE.md` §7 et `system/chromium-sbx/README.md`.

- **Lancement** : `~/.local/share/applications/chromium.desktop` (ou `chromium [URL...]` dans zsh, alias de `chromium-sbx` ; `/usr/bin/chromium` lancé en direct ouvrirait un profil lisible par la session dans `~/.config/chromium`) lance `~/.local/bin/chromium-sbx`. Ce script démarre les sockets de passage dans `/run/chromium-sbx` (services systemd utilisateur `chromium-sbx-wayland`, `chromium-sbx-dbus`, `chromium-sbx-dbus-relay`), puis `sudo -n -u chromium /usr/local/bin/chromium-sbx-inner`, sans mot de passe pour cette seule commande. Le lanceur interne refuse toute option et lance Chromium dans Bubblewrap.
- **Flags** : `/var/lib/chromium-sbx/.config/chromium-flags.conf` (écrit par `install.sh`, appartient au compte `chromium`) force `--password-store=gnome-libsecret`. Les cookies sont chiffrés avec la clé `Chromium Safe Storage` rangée dans KeePassXC (§4). `~/.config/chromium-flags.conf` n'existe plus.
- **Installation** (après `chezmoi apply`, qui déploie les fichiers de session : lanceur, relais `dbus-uid-relay`, trois services, config PipeWire) :
  ```bash
  cd ~/.local/share/chezmoi/system/chromium-sbx
  ./build.sh                                     # compile wayland-sandbox-socket (sans sudo)
  sudo ./install.sh                              # compte, lanceur interne, sudoers, /run/chromium-sbx, /srv/chromium-sbx/Downloads
  systemctl --user daemon-reload && systemctl --user restart pipewire-pulse
  keepass-tokens set-account chromium            # mot de passe du compte, rangé dans KeePassXC « Comptes sandbox »
  ./test.sh                                      # test complet (ouvre un Chromium de test)
  ```
  `install.sh` s'exécute en root depuis un dossier modifiable par ton compte : relis-le avant de le lancer.
- **Migrer un profil existant** : fermer tous les Chromium, puis :
  ```bash
  sudo rsync -a --delete --exclude='Singleton*' <ancien profil>/ /var/lib/chromium-sbx/.config/chromium/
  sudo chown -R chromium:chromium /var/lib/chromium-sbx/.config/chromium
  ```
  Vérifier ensuite onglets, connexions et Proton Pass, puis **supprimer l'ancienne copie**, sinon elle reste lisible par la session. Les cookies suivent, car le compte `chromium` récupère la même clé dans KeePassXC.
- **Administration du compte** : `keepass-tokens sudo chromium <commande>`. Le mot de passe du compte est lu dans le groupe KeePassXC « Comptes sandbox », avec une fenêtre de mot de passe maître **à chaque fois**. `sudo` n'accepte que ce mot de passe pour agir en tant que `chromium` (`Defaults>chromium targetpw, timestamp_timeout=0`).
- **Fichiers** : Chromium ne voit plus ton home. Téléchargements et envois passent par `/srv/chromium-sbx/Downloads`, ouvert à la session par ACL.
- **OpenSnitch** : les connexions de Chromium viennent d'un nouveau compte, il faut les autoriser à nouveau.
- **Maintenance** : les mises à jour de Chromium (`pacman`) ne demandent rien. Après une modification de `chromium-sbx-inner`, `sudoers-chromium-sbx` ou `tmpfiles-chromium-sbx.conf`, relancer `sudo ./install.sh`, puis `./test.sh` pour revérifier. Après une modification des services ou du relais : `chezmoi apply` puis `systemctl --user daemon-reload`. Pour les agents (`agy`, `claude` dans `bwrap-agent`), `chezmoi`, `~/.config` et `sudo` sont inaccessibles : faire ces opérations depuis un terminal normal (ou `command claude`).

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

Le système utilise l'API standard Linux `org.freedesktop.secrets` (Secret Service), fournie par KeePassXC. Activer le service ne suffit pas : **une base ouverte doit exposer un groupe**. Sinon, chaque client (Chromium, `secret-tool`…) déclenche soit une fenêtre de déverrouillage sans base cible (erreur *« Aucun chemin de fichier n'a été indiqué »*), soit l'assistant « Créer une nouvelle base de données ».

#### Cas A : Vous possédez déjà une base KeePassXC existante (Restauration)
1. Récupérez votre fichier `.kdbx` (et son fichier clé s'il en a un) depuis une clé USB, une sauvegarde chiffrée, etc., et placez-le dans votre dossier personnel.
2. Lancez KeePassXC et ouvrez votre base avec votre mot de passe maître (et le fichier clé).
3. Activez le service **globalement** : **Outils** > **Paramètres** > **Intégration Secret Service** :
   - Cochez **Activer l'intégration Secret Service**.
   - Laissez cochée **Confirmer quand des mots de passe sont récupérés par des clients**.
4. Exposez la base (réglage **par base**) : **Base de données** > **Paramètres de la base de données** > **Intégration Secret Service** > exposez un **groupe dédié** (ex : un groupe `Secret Service` créé pour l'occasion), **pas toute la base**. Enregistrez (`Ctrl + S`).
5. Fermez complètement Chromium puis relancez-le (`chromium-sbx`) : il enregistre sa clé de chiffrement (`Chromium Safe Storage`) dans ce groupe. Chromium tourne sous le compte `chromium`, mais sa demande passe par le relais et le bus filtré de ta session (§3.A) : KeePassXC la voit venant de `xdg-dbus-proxy`, et c'est la même clé qui sert après une migration du profil.

> ⚠️ Si Chromium (ou une autre application) ouvre l'assistant **« Créer une nouvelle base de données »**, ne le suivez pas : cela signifie qu'aucun groupe n'est exposé. Annulez et faites l'étape 4.

> ♻️ Après toute modification de `chromium-sbx-inner`, des services de passage ou de `/var/lib/chromium-sbx/.config/chromium-flags.conf`, fermez **complètement** Chromium et relancez-le : l'instance déjà ouverte garde l'ancien sandbox et les anciens flags.

> 🔐 **Groupe « Comptes sandbox »** (non exposé au Secret Service) : mots de passe des comptes Unix dédiés, par exemple `chromium`. Ils sont créés par `keepass-tokens set-account <compte>` et lus par `keepass-tokens sudo <compte> <commande>` (§3.A).

#### Cas B : Nouvelle installation vierge (Créer un nouveau trousseau KeePassXC)
1. Lancez **KeePassXC**.
2. Cliquez sur **Créer une nouvelle base de données** (ex: `~/MotsDePasse.kdbx`).
3. Définissez un mot de passe maître solide.
4. Suivez les étapes 3 à 5 du Cas A.
5. **Importer vos mots de passe depuis Chromium** :
   - Dans Chromium : `chrome://password-manager/settings` > Exporter les mots de passe (CSV).
   - Dans KeePassXC : **Base de données** > **Importer** > **Fichier CSV Chromium/Chrome**.
   - Supprimez immédiatement le CSV temporaire : `rm ~/Downloads/mots_de_passe.csv`.

**Tokens Claude Code / Antigravity** : ils vont dans le groupe « Tokens CLI » de la base KeePassXC principale, lu par `keepass-tokens`. Le mot de passe maître est demandé par application, dans une fenêtre `pinentry-gtk` (paquet `pinentry`), et reste valable 10 min après sa dernière utilisation ; voir `SECURITE_ET_ARCHITECTURE.md` §5. Sur une nouvelle machine, vérifier d'abord `DB` et `KEY_FILE` en tête du script. Première mise en place, dans un terminal :
```bash
agy                              # 1re connexion agy : le token est enregistré dans la base à la sortie
command claude setup-token       # token Claude longue durée (contourne la fonction claude du .zshrc)
keepass-tokens set-claude        # colle ce token : il est enregistré dans la base
```
`keepass-tokens lock` reverrouille tout de suite. `command agy` / `command claude` lancent les outils sans la base (connexion classique).

#### Cas C : Utilisation de GNOME Keyring au lieu de KeePassXC
Le paquet `gnome-keyring` n'est plus installé, et ses unités systemd utilisateur sont masquées (`~/.config/systemd/user/gnome-keyring-daemon.service` et `.socket` pointent vers `/dev/null`). Un seul programme peut détenir `org.freedesktop.secrets` : pour revenir à GNOME Keyring, désactivez d'abord l'intégration Secret Service de KeePassXC, réinstallez `gnome-keyring`, puis démasquez les unités (`systemctl --user unmask gnome-keyring-daemon.service gnome-keyring-daemon.socket`).

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
