# Architecture de Sécurité & Guide des Technologies

Ce document détaille le fonctionnement technique interne de chaque composant de sécurité mis en place sur le système, pourquoi ces choix ont été faits, et comment ils vous protègent en profondeur contre les malwares, les vols de tokens et les pannes système.

---

## Sommaire

1. [Sauvegarde d'état incrémentale : Timeshift RSYNC](#1-sauvegarde-détat-incrémentale--timeshift-rsync)
2. [Trousseau d'authentification : KeePassXC & Secret Service](#2-trousseau-dauthentification--keepassxc--secret-service)
3. [Isolation « à la Android » : Firejail & Namespaces Linux](#3-isolation--à-la-android---firejail--namespaces-linux)
4. [Pare-feu Applicatif Sortant : OpenSnitch](#4-pare-feu-applicatif-sortant--opensnitch)
5. [Coffre-fort Volatile de Tokens en RAM : keyring-vault](#5-coffre-fort-volatile-de-tokens-en-ram--keyring-vault)
6. [Protection contre les écoutes réseau & Wi-Fi](#6-protection-contre-les-écoutes-réseau--wi-fi)

---

## 1. Sauvegarde d'état incrémentale : Timeshift RSYNC

### Le défi sur un système de fichiers ext4
Contrairement à Btrfs ou ZFS qui intègrent nativement des snapshots instantanés au niveau des blocs, **ext4** ne gère pas de snapshots intégrés.  
Cependant, Timeshift résout élégamment ce problème grâce aux **liens physiques matériels (*hard links*)** de `rsync`.

### Fonctionnement sous le capot (`rsync --link-dest`)
1. **Premier snapshot (Référence)** :
   Timeshift effectue une copie complète des fichiers système dans `/timeshift/snapshots/<date>/localhost/`. Cela prend l'espace réel de l'OS (environ 32 Go sur votre machine).
2. **Snapshots suivants (À chaque démarrage)** :
   Timeshift utilise l'option `--link-dest` en pointant vers l'instantané précédent :
   - Si un fichier **n'a pas été modifié**, aucun octet n'est copié sur le disque ! Timeshift crée simplement un *hard link* pointant vers le même *inode* physique sur le disque NVMe. **Espace disque supplémentaire consommé : 0 octet**.
   - Si un fichier a été modifié, supprimé ou créé (par exemple suite à une mise à jour ou un téléchargement), seul le fichier modifié est physiquement écrit sur le disque.
3. **Suppression propre des anciens instantanés** :
   Grâce au fonctionnement d'ext4, supprimer un ancien instantané ne casse pas les autres : un fichier n'est physiquement effacé du disque que lorsque le dernier hard link pointant vers son inode est supprimé.

### Optimisation du démarrage sans ralentissement (`timeshift-boot.service`)
Pour éviter que la sauvegarde ne ralentisse l'ouverture de votre session Hyprland, le service systemd est configuré avec deux directives de priorité basse :
```ini
Nice=19
IOSchedulingClass=idle
```
- **`Nice=19`** : La priorité CPU la plus basse possible. Le processeur n'alloue des cycles à Timeshift que lorsqu'aucun autre processus utilisateur n'en a besoin.
- **`IOSchedulingClass=idle`** : L'accès au disque NVMe est prioritaire pour votre session et vos applications. Timeshift n'accède au disque que lors des micro-pauses d'I/O.

---

## 2. Trousseau d'authentification : KeePassXC & Secret Service

### Le protocole D-Bus `org.freedesktop.secrets`
Sur le bureau Linux moderne, les applications ne stockent pas directement les mots de passe dans des fichiers de configuration. Elles interrogent le bus D-Bus sur le nom standardisé `org.freedesktop.secrets` (géré par la bibliothèque `libsecret`).

```
[ Chromium / Scripts CLI / Applications ]
                    │
                    ▼ (Requête D-Bus : org.freedesktop.secrets)
            [ KeePassXC ]
                    │
        ┌───────────┴───────────┐
        ▼                       ▼
[ Base chiffrée .kdbx ]    [ Fenêtre Popup d'Autorisation (ACL) ]
```

### Pourquoi KeePassXC est supérieur à GNOME Keyring pour la sécurité
- **La faiblesse de GNOME Keyring** : Une fois le trousseau déverrouillé avec votre mot de passe maître au boot, **n'importe quel processus** tournant sous votre UID peut interroger le Secret Service en arrière-plan sans qu'aucune alerte ne soit levée. Un malware lancé dans votre session peut siphonner vos clés discrètement.
- **La force de KeePassXC (Access Control List)** :
  KeePassXC conserve une liste blanche d'applications autorisées. Dès qu'un binaire inconnu (ex: un script Python ou un binaire malveillant) demande un secret, **KeePassXC stoppe la requête et affiche une boîte de dialogue d'alerte** :
  > *« L'application `/tmp/programme_inconnu` demande l'accès à `Token Discord`. Autoriser / Refuser ? »*
  Si vous n'êtes pas à l'origine de cette demande, vous cliquez sur **Refuser**.

### Chiffrement militaire de la base
Votre fichier `.kdbx` est chiffré de bout en bout avec :
- Algorithme de chiffrement : **AES-256** ou **ChaCha20**.
- Fonction de dérivation de clé (KDF) : **Argon2d** (résistant aux attaques par GPU et FPGA grâce à une consommation contrôlée de mémoire RAM lors du déchiffrement).

---

## 3. Isolation « à la Android » : Firejail & Namespaces Linux

### Le principe d'isolation Android sous Linux
Sur Android, chaque application s'exécute sous un UID distinct et dispose de son propre répertoire privé (`/data/data/<package>`). Elle n'a aucun accès aux fichiers des autres applications.

Sous Linux standard, tous vos programmes s'exécutent sous le même utilisateur (`timothe`) et ont donc accès en lecture à l'ensemble de votre `$HOME` (y compris vos photos, vos clés SSH, et la session de Discord).

### Comment Firejail recrée ce confinement
Firejail exploite les **Namespaces du noyau Linux** (les mêmes briques de base que Docker et Bubblewrap) :

1. **Mount Namespace (`--private`)** :
   Firejail crée une table de montage isolée. Il monte un système de fichiers virtuel en mémoire vive (`tmpfs`) par-dessus votre dossier personnel.
   - Le programme croit être dans un vrai `/home/timothe`, mais ce dossier est **vide et temporaire**.
   - Vos vrais fichiers (`.ssh`, `.config/discord`, `Documents`, etc.) sont **physiquement invisibles et inaccessibles**.
   - À la fermeture du programme, la mémoire vive est libérée et toutes les traces créées par le programme s'évaporent.
2. **Network Namespace (`--net=none`)** :
   Firejail détache le programme de la pile réseau de l'hôte.
   - La seule interface réseau visible dans le conteneur est `lo` (127.0.0.1).
   - Les cartes Wi-Fi et Ethernet n'existent pas pour le processus. Même si un voleur de token s'exécute, il ne peut envoyer aucun paquet vers Internet.
3. **PID Namespace** :
   Le programme ne peut pas voir ni interagir avec les autres processus de votre session (empêchant l'espionnage de mémoire vive).

### Intégration ergonomique dans Yazi
Grâce au script [`~/.config/hypr/UserScripts/yazi-firejail`](file:///home/timothe/.config/hypr/UserScripts/yazi-firejail) lié au menu **`O`** de Yazi :
- Un dossier éphémère est créé dans `/tmp/yazi-firejail.XXXXXX`.
- Le fichier ciblé y est injecté.
- Firejail exécute le programme dans son bac à sable étanche.
- Le terminal attend une touche avant de fermer, vous permettant d'inspecter les sorties console.

---

## 4. Pare-feu Applicatif Sortant : OpenSnitch

### La faille des pare-feux traditionnels
Les pare-feux classiques sous Linux (UFW, iptables, nftables) sont conçus pour filtrer le trafic **entrant** (bloquer les attaques venant d'Internet vers votre PC).  
Or, un malware (Trojan, Stealer de token, reverse-shell) fonctionne à l'inverse : il effectue une connexion **sortante** (du PC vers un serveur pirate ou un Webhook Discord). Par défaut, tous les pare-feux laissent sortir 100 % du trafic.

### Fonctionnement d'OpenSnitch
OpenSnitch est inspiré du célèbre *Little Snitch* sous macOS :
1. **Interception noyau (NFQUEUE / eBPF)** :
   Le démon système `opensnitchd` surveille chaque tentative d'ouverture de socket réseau (`connect()`).
2. **Association Processus ↔ Connexion** :
   OpenSnitch identifie avec exactitude :
   - Le chemin du binaire exécuté (ex: `/home/timothe/Downloads/test.sh`).
   - L'adresse IP et le nom de domaine cibles (ex: `discordapp.com/api/webhooks/...`).
   - Le port utilisé (ex: 443 HTTPS).
3. **Alerte interactive en temps réel (`opensnitch-ui`)** :
   La connexion est mise en pause dans le noyau pendant qu'une fenêtre surgit sur votre bureau. Vous pouvez bloquer la tentative d'exfiltration en un clic.

---

## 5. Coffre-fort Volatile de Tokens en RAM : keyring-vault

### La vulnérabilité des fichiers `.credentials.json`
Par défaut :
- Claude Code stocke ses jetons OAuth dans `~/.claude/.credentials.json`.
- Antigravity / Agy stocke ses jetons dans `~/.gemini/antigravity-cli/antigravity-oauth-token`.

Ces fichiers texte restent en clair sur le disque dur, accessibles à n'importe quel binaire lancé sous votre compte.

### L'architecture `keyring-vault`

```
[ Disque dur / Timeshift ]
  ~/.claude/.credentials.json ────────┐ (Lien symbolique)
  ~/.gemini/.../antigravity-token ────┤
                                      ▼
                        [ /run/user/1000/secrets/ ] (RAM / tmpfs)
                                      ▲
                                      │ (Extraction sécurisée via mot de passe)
                           [ KeePassXC / Keyring ]
```

1. **Stockage sécurisé permanent** : Les tokens réels sont injectés dans la base chiffrée via `secret-tool store`.
2. **Stockage d'exécution volatil** :
   Le répertoire `/run/user/1000/` est un point de montage en mémoire vive géré par `systemd` (`tmpfs`).
   - Lorsque vous lancez `claude` ou `agy`, la fonction du shell (`~/.zshrc`) appelle `keyring-vault unlock`.
   - Si la mémoire vive ne contient pas les tokens, KeePassXC demande la confirmation par popup, extrait les tokens et les écrit dans `/run/user/1000/secrets/` avec des permissions `0600`.
3. **Disparition totale à l'extinction** :
   Dès que le PC s'éteint ou redémarre, la RAM est coupée. Les tokens en clair **disparaissent complètement**. Sur le disque dur, il ne reste que des liens symboliques pointant vers du vide.

---

## 6. Protection contre les écoutes réseau & Wi-Fi

### Randomisation de l'adresse MAC (Anti-traçage)
L'adresse MAC physique est l'empreinte unique de votre carte réseau. Sur un réseau public (université, hôtel, gare), les bornes Wi-Fi enregistrent cette adresse pour pister vos allées et venues.  
Dans `/etc/NetworkManager/conf.d/00-mac-randomization.conf` :
- `wifi.scan-rand-mac-address=yes` : Fausse adresse MAC générée lors de la recherche des réseaux.
- `wifi.cloned-mac-address=random` : Nouvelle adresse MAC aléatoire générée à chaque association avec une borne Wi-Fi.

### Chiffrement des requêtes DNS (DNS-over-TLS - DoT)
- **Problème** : En DNS classique (port 53 UDP), chaque nom de domaine auquel vous accédez (`banque.com`, `discord.com`) est transmis en texte brut non chiffré. N'importe qui analysant le réseau Wi-Fi local ou votre FAI peut dresser l'historique complet de votre navigation.
- **Solution** : En activant `DNSOverTLS=yes` dans `systemd-resolved` avec Quad9 (`9.9.9.9`), chaque requête DNS est encapsulée dans un tunnel chiffré TLS sur le port 853. Le contenu des requêtes devient totalement illisible pour les espions sur le réseau local.
