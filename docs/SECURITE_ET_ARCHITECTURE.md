# Architecture de Sécurité & Guide des Technologies

Ce document détaille le fonctionnement technique interne de chaque composant de sécurité mis en place sur le système, pourquoi ces choix ont été faits, et comment ils vous protègent en profondeur contre les malwares, les vols de tokens et les pannes système.

---

## Sommaire

1. [Sauvegarde d'état incrémentale : Timeshift RSYNC](#1-sauvegarde-détat-incrémentale--timeshift-rsync)
2. [Trousseau d'authentification : KeePassXC & Secret Service](#2-trousseau-dauthentification--keepassxc--secret-service)
3. [Isolation « à la Android » : Firejail & Namespaces Linux](#3-isolation--à-la-android---firejail--namespaces-linux)
4. [Pare-feu Applicatif Sortant : OpenSnitch](#4-pare-feu-applicatif-sortant--opensnitch)
5. [Tokens CLI (Claude, Antigravity)](#5-tokens-cli-claude-antigravity)
6. [Sandbox Bubblewrap : principe, limites et première version pour Chromium](#6-sandbox-bubblewrap--principe-limites-et-première-version-pour-chromium)
7. [Chromium sous un compte Unix dédié (chromium-sbx)](#7-chromium-sous-un-compte-unix-dédié-chromium-sbx)
8. [Sandbox des agents CLI (bwrap-agent)](#8-sandbox-des-agents-cli-bwrap-agent)
9. [Protection contre les écoutes réseau & Wi-Fi](#9-protection-contre-les-écoutes-réseau--wi-fi)

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
- **Ce qu'apporte KeePassXC** :
  - Seul le groupe **exposé** par une base (Base de données > Paramètres de la base de données > Intégration Secret Service) est visible des clients ; le reste de la base ne l'est pas.
  - Avec **Confirmer quand des mots de passe sont récupérés par des clients**, KeePassXC affiche une boîte de dialogue avant de livrer un secret, en nommant le client :
    > *« L'application `/tmp/programme_inconnu` demande l'accès à `Token Discord`. Autoriser / Refuser ? »*
    Si vous n'êtes pas à l'origine de cette demande, vous cliquez sur **Refuser**.
- **Limites à connaître** :
  - Le client est identifié par le PID et l'exécutable de la connexion D-Bus. C'est un garde-fou, **pas une frontière forte** contre un malware tournant sous le même UID que vos applications légitimes.
  - Pour Chromium (compte dédié, §7), le client D-Bus que voit KeePassXC est `xdg-dbus-proxy`, qui tourne sous le compte de session, et non Chromium lui-même.
  - Sans groupe exposé, KeePassXC répond à toute recherche par une fenêtre de déverrouillage sans base cible (*« Aucun chemin de fichier n'a été indiqué »*), ou par l'assistant de création de base quand un client demande une collection.

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

## 5. Tokens CLI (Claude, Antigravity)

### Où sont les tokens
- **Claude Code et Antigravity (agy)** : dans le groupe **« Tokens CLI »** de la base KeePassXC principale (`~/Mots de passe.kdbx`, mot de passe maître et fichier clé). Ce groupe n'est **pas** celui exposé au Secret Service. Il est lu avec `keepassxc-cli` par `~/.local/bin/keepass-tokens`, qu'appellent les fonctions `agy()` et `claude()` du `.zshrc`. Le groupe et ses entrées sont créés au premier enregistrement.
  - agy : pièce jointe `antigravity-oauth-token` de l'entrée `Tokens CLI/agy`. Le chemin `~/.gemini/antigravity-cli/antigravity-oauth-token` n'existe que pendant l'exécution d'agy, sous forme de lien vers une copie en RAM.
  - Claude : champ mot de passe de l'entrée `Tokens CLI/claude`. C'est un token longue durée créé par `claude setup-token` (valable 1 an, facturé sur l'abonnement), transmis à Claude Code dans `CLAUDE_CODE_OAUTH_TOKEN`, qui passe avant la connexion `/login`. Il est limité à l'inférence : pas de Remote Control, pas de connecteurs claude.ai.
- `~/.claude/.credentials.json` (connexion `/login`, en clair, `0600`) n'est plus utilisé par la fonction `claude`. On peut le supprimer une fois `keepass-tokens claude` validé ; `command claude` demandera alors une nouvelle connexion.

### Modèle d'accès : un mot de passe par application, valable 10 min
Le Secret Service de KeePassXC ne sait pas redemander un mot de passe à chaque accès. Une fois la base déverrouillée, il livre les secrets du groupe exposé à tout client, au mieux après une confirmation Autoriser/Refuser. D'où la lecture du groupe « Tokens CLI » par `keepassxc-cli`, qui ouvre lui-même le fichier de la base et exige le mot de passe maître (et le fichier clé) à chaque fois, que KeePassXC soit ouvert ou non :
- **Chaque application se déverrouille séparément.** Le mot de passe est demandé au lancement d'`agy` ou de `claude`, dans une fenêtre `pinentry-gtk`. Une règle Hyprland l'affiche flottante et centrée, et elle se ferme d'office au bout de 120 s (`timeout`, car `pinentry-gtk` ignore `SETTIMEOUT`). Hors session graphique, la saisie se fait dans le terminal. `pinentry-qt` n'est pas utilisé : il lui manque `libKF6WindowSystem`, fournie par le paquet `kwindowsystem`. L'application se relance ensuite sans le redemander jusqu'à **10 min après sa dernière utilisation** (`UNLOCK_SECONDS`), pendant que l'autre reste verrouillée.
- **Pendant cette période**, le token de l'application est en clair dans `$XDG_RUNTIME_DIR/secrets/<appli>/` (RAM, `0600`). À l'expiration, un minuteur `systemd-run --user` l'efface. `keepass-tokens lock` reverrouille tout de suite.
- **Rafraîchissement d'agy.** agy renouvelle son jeton d'accès toutes les heures, en réécrivant son fichier sur place (vérifié) : le lien est suivi et le token reste en RAM. Seul un **nouveau jeton de rafraîchissement** est réenregistré dans la base, avec une nouvelle demande de mot de passe à la sortie. Si cet enregistrement échoue, le token est gardé en RAM et marqué « à enregistrer » : le minuteur ne l'efface pas, et l'enregistrement est retenté au lancement suivant.
- **Token laissé en clair.** Un token agy trouvé en clair sur le disque (connexion faite hors du script, arrêt brutal) est enregistré dans la base, puis retiré du disque.
- **Écritures dans la base.** Le premier enregistrement, un nouveau jeton de rafraîchissement d'agy et `set-claude` modifient le fichier de la base. KeePassXC le recharge, et propose de fusionner s'il a des modifications non enregistrées.
- **Tests.** Le script a été testé avec de faux `agy` et `claude` dans un pseudo-terminal, sur une base protégée par mot de passe et fichier clé qui contenait déjà un groupe `Secret Service`. 15 scénarios : période de 10 min, isolation entre applications, mauvais mots de passe, nouveau jeton de rafraîchissement, échec d'enregistrement, token en clair, deux agy simultanés, `lock`, création du groupe et remplacement du token Claude.
- **Limites** :
  - le mot de passe maître tapé pour `agy` ou `claude` ouvre toute la base : s'il est capturé dans le terminal, tous les mots de passe sont exposés, pas seulement les tokens ;
  - seuls `agy` et `claude` lancés depuis zsh passent par le script ;
  - `agy` et `claude` tournent chacun dans le sandbox `bwrap-agent` (§8) : aucun des deux ne voit le token, la config ou les processus de l'autre (vérifié). En revanche, un programme lancé **hors** sandbox sous votre compte peut lire la copie en RAM et `CLAUDE_CODE_OAUTH_TOKEN` via `/proc/<pid>/environ` : Bubblewrap empêche de sortir, pas d'entrer (vérifié : le propriétaire d'un namespace a tous les droits dessus) ;
  - la RAM peut être écrite dans `/swapfile` sous forte pression mémoire ;
  - s'il est volé, le token Claude reste valable jusqu'à 1 an.

### Pourquoi `keyring-vault` a été retiré (15/09/2026)
L'ancien script copiait les tokens dans le trousseau et remplaçait les fichiers par des liens vers `/run/user/1000/secrets/` (RAM), appelé par des fonctions `claude()` / `agy()` du `.zshrc`. En pratique :
- **Copies en clair sur le disque** : `init` et `unlock` laissaient des `.bak` des tokens à côté des originaux (ex : `antigravity-oauth-token.bak`).
- **Déconnexions** : les CLI rafraîchissent leurs tokens OAuth dans le fichier en RAM, mais rien ne les réécrivait dans le trousseau (`sync` et `lock` n'étaient jamais appelés) : au redémarrage, le token restauré était périmé.
- **Popup KeePassXC à chaque `claude` / `agy`** : `unlock` lançait deux `secret-tool lookup` ; sans groupe exposé, KeePassXC ouvrait à chaque fois une fenêtre de déverrouillage sans base (*« Aucun chemin de fichier n'a été indiqué »*).
- **Risque d'écrasement** : dès qu'une recherche aurait réussi, le script aurait remplacé les identifiants neufs (obtenus par `claude /login`) par un lien vers l'ancien token en RAM.
- **Dépendance GNOME** : `secret-tool lock --collection=login` ne vise que la collection de GNOME Keyring.

### Historique : `agy-keepass` (15/09/2026, remplacé le même jour)
Première correction de `keyring-vault`. Le token agy était rangé dans le groupe Secret Service de la base principale, avec une copie en RAM pendant l'exécution et un réenregistrement à la sortie. Il a été remplacé par `keepass-tokens`, car il ne demandait aucun mot de passe tant que la base principale était déverrouillée. `secret-tool clear` échoue contre KeePassXC : l'ancienne entrée « Antigravity OAuth Token » est à supprimer dans l'interface.

### Ce qui protège aujourd'hui
- Au repos, les tokens agy et Claude n'existent que chiffrés dans la base KeePassXC (groupe « Tokens CLI ») ; les lire exige le mot de passe maître et le fichier clé, par application.
- Chromium, principale surface d'attaque, tourne sous un compte Unix dédié et dans Bubblewrap (§7) : il ne voit pas du tout le home de la session (ni `~/.claude` ni `~/.gemini`), ne joint ni l'IPC Hyprland ni `systemd --user`, et son socket Wayland est un contexte de sécurité qui lui retire notamment la capture d'écran et le clavier virtuel.
- OpenSnitch signale les connexions sortantes inattendues (§4).

### Limite : disque non chiffré
`/` est en ext4 **sans LUKS** : quiconque accède physiquement au disque (vol du portable, démarrage sur clé USB) lit les cookies, les clés SSH et `~/.claude/.credentials.json` s'il existe encore ; les bases KeePassXC, elles, restent protégées par leur mot de passe. Le coffre en RAM de `keyring-vault` n'y changeait rien. La parade est le chiffrement complet du disque (LUKS). Pour la même raison, un fichier clé KeePassXC rangé sur ce même disque n'ajoute pas de protection en cas de vol.

---

## 6. Sandbox Bubblewrap : principe, limites et première version pour Chromium

Bubblewrap (`bwrap`) lance un programme dans des **namespaces** du noyau, sans root : un namespace utilisateur (le compte de session y devient propriétaire de tout) et un namespace de montage, dont la racine est reconstruite uniquement à partir de ce qu'on y monte (`--ro-bind`, `--bind`, `--tmpfs`, `--dev`, `--proc`…), avec éventuellement un namespace de PID (`--unshare-pid`). `bwrap-app` applique ce modèle aux applications quelconques, et `bwrap-agent` aux agents CLI (§8).

Pour Chromium, la première version (`bwrap-chromium`, 15/09/2026) a été **remplacée le 16/09/2026 par `chromium-sbx`** (§7) : le profil a été migré vers un compte Unix dédié et les anciennes copies supprimées. Cette section garde son historique, car ses leçons valent pour tout sandbox Bubblewrap.

### Failles de la première version (vérifiées le 15/09/2026)

| Choix | Conséquence constatée |
|---|---|
| `--bind "$XDG_RUNTIME_DIR"` entier | depuis le sandbox, l'IPC Hyprland (`hyprctl dispatch exec`), `systemd --user` via D-Bus (`systemd-run --user`) et l'agent GPG étaient joignables : exécution de commandes hors du sandbox |
| lancement direct de `/usr/lib/chromium/chromium` | `chromium-flags.conf` n'est lu que par le lanceur `/usr/bin/chromium` : `--password-store=gnome-libsecret` ignoré, 231 cookies sur 231 chiffrés en `v10` (clé fixe intégrée à Chromium) |
| `--tmpfs /tmp` privé à chaque lancement | le `SingletonSocket` de l'instance ouverte est invisible : un lien ouvert depuis une autre application démarrait un **2e Chromium sur le même profil** (verrou repris, bases en erreur `LOCK`) |
| `--dev /dev` sans `/dev/dri` | pas de GPU : rendu logiciel (`--use-gl=disabled`) |

### Deuxième version de `bwrap-chromium` (15/09/2026)
Ces corrections sont reprises par `bwrap-app` :
- **Bus D-Bus filtré** : un `xdg-dbus-proxy` par lancement, arrêté avec le sandbox (`--sync-fd`). Noms autorisés : `org.freedesktop.secrets`, `org.freedesktop.portal.*`, `org.freedesktop.Notifications`, `org.freedesktop.ScreenSaver` ; possession de `org.mpris.MediaPlayer2.chromium.*` (touches média). Tout le reste, dont `org.freedesktop.systemd1`, est invisible.
- **`$XDG_RUNTIME_DIR` minimal** : seuls le socket Wayland, `pipewire-0`, `pulse/native` et le bus filtré sont montés. Ni IPC Hyprland, ni agents SSH/GPG.
- **`/tmp` partagé entre les lancements** (pas avec l'hôte) : un 2e lancement transmet l'URL à l'instance ouverte (*« Ouverture dans une session de navigateur existante »*).
- **Lanceur `/usr/bin/chromium`** : `chromium-flags.conf` est appliqué.
- **`--new-session`** : le sandbox est détaché du terminal de lancement.
- **GPU** : `/dev/dri` et `/sys/{dev,devices,bus,class}` en lecture seule.

Ses limites restaient :
- **Socket Wayland exposé** : comme toute application Wayland, Chromium pouvait utiliser les protocoles privilégiés du compositeur (clavier virtuel, capture d'écran).
- **PID namespace partagé, volontairement** : avec `--unshare-pid`, le verrou « instance unique » de Chromium (nom d'hôte + PID) risquait d'être pris pour orphelin et le profil ouvert deux fois.
- **Le profil restait lisible par la session** : c'est la raison du passage à `chromium-sbx`, expliquée ci-dessous.

### Bubblewrap est à sens unique (vérifié le 16/09/2026)
Un sandbox Bubblewrap empêche l'application de **sortir**, pas les programmes du même compte d'**entrer**. Tests réalisés :

| Test | Résultat |
|---|---|
| Hôte → sandbox : fichier créé dans un `--tmpfs` privé du sandbox | invisible par son chemin normal, mais **lisible via `/proc/<pid>/root/…`** |
| Hôte → sandbox : variable d'environnement du processus sandboxé | **lisible via `/proc/<pid>/environ`** |
| Hôte → sandbox : profil Chromium monté dans le sandbox | **lisible directement** sur le disque (`~/.local/share/secure-profiles/chromium`) |
| Sandbox → hôte : `/proc/<pid>/root` d'un processus de l'hôte | refusé, même sans `--unshare-pid` |
| Sandbox → hôte : processus visibles | 5 avec `--unshare-pid`, 279 sans |
| Processus sandboxé rendu non inspectable (`PR_SET_DUMPABLE=0`) | `/proc/<pid>/environ` refusé, **mais `/proc/<pid>/root` toujours lisible** ; ce réglage est en plus remis à zéro à chaque `exec` |
| Processus confiné par Landlock (`setpriv --landlock-access fs`) qui lit `/proc/<pid>/environ` d'un autre processus | refusé (75 variables lisibles sans Landlock) |

**Pourquoi.** Le compte qui crée le namespace utilisateur (ici toujours le compte de session) en est propriétaire : tout processus de ce compte a tous les droits dessus. Seul **un autre compte Unix** (ou un module de sécurité du noyau appliqué aux processus de la session, comme Landlock) empêche d'entrer. D'où le §7.

---

## 7. Chromium sous un compte Unix dédié (chromium-sbx)

### Objectif et modèle de menace
**Aucun programme lancé sous le compte de session (malware compris) ne doit pouvoir lire le profil Chromium** (cookies, sessions, Proton Pass, historique) **ni inspecter ses processus**. On suppose la session potentiellement compromise ; root est hors du modèle (il lit tout). C'est le modèle Android : un compte Unix par application. Mis en place le 16/09/2026.

```
SESSION (timothe)                                          COMPTE chromium (uid 963)
─────────────────                                          ─────────────────────────
chromium.desktop ─> ~/.local/bin/chromium-sbx
   │ systemctl --user start
   │   chromium-sbx-wayland.service ── wayland-sandbox-socket ──┐
   │   chromium-sbx-dbus-relay.service ── dbus-uid-relay ───────┤
   │        └─ chromium-sbx-dbus.service ── xdg-dbus-proxy      │  /run/chromium-sbx/ (2750 timothe:chromium)
   │             (socket privé %t/chromium-sbx-dbus)            │    wayland  (contexte de sécurité Hyprland)
   │   pipewire-pulse (adresse en plus, accès restreint) ───────┤    bus      (relais -> bus filtré)
   │                                                            │    pulse    (son restreint)
   └─ sudo -n -u chromium /usr/local/bin/chromium-sbx-inner ────┼──> bwrap ──> Chromium
        (NOPASSWD pour ce seul fichier root)                    │     profil : /var/lib/chromium-sbx (0700)
                                                                └─    téléchargements : /srv/chromium-sbx/Downloads
```

| Composant | Emplacement | Rôle |
|---|---|---|
| compte `chromium` | `/var/lib/chromium-sbx` (0700) | propriétaire du profil et des processus de Chromium |
| `chromium-sbx` | `~/.local/bin/` | lanceur de session : démarre les services, puis passe par sudo |
| `chromium-sbx-inner` | `/usr/local/bin/` (root, 0755) | lanceur exécuté en tant que chromium : vérifications, puis Bubblewrap |
| règle sudo | `/etc/sudoers.d/chromium-sbx` | lancement sans mot de passe ; tout le reste avec le mot de passe du compte |
| `wayland-sandbox-socket` + `chromium-sbx-wayland.service` | `/usr/local/bin/` (root), `~/.config/systemd/user/` | socket Wayland déclaré comme contexte de sécurité |
| `xdg-dbus-proxy` + `chromium-sbx-dbus.service` | `~/.config/systemd/user/`, socket `%t/chromium-sbx-dbus` | bus de session filtré, privé à la session |
| `dbus-uid-relay` + `chromium-sbx-dbus-relay.service` | `~/.local/bin/`, `~/.config/systemd/user/` | relais d'authentification D-Bus entre les deux comptes |
| config PipeWire | `~/.config/pipewire/pipewire-pulse.conf.d/chromium-sbx.conf` | socket son en accès restreint |
| `/run/chromium-sbx` | `/etc/tmpfiles.d/chromium-sbx.conf` | dossier de passage des sockets |
| `/srv/chromium-sbx/Downloads` | 2770 `chromium:chromium` + ACL | téléchargements partagés avec la session |
| `keepass-tokens set-account` / `keepass-tokens sudo` | `~/.local/bin/keepass-tokens` | accès au compte avec un mot de passe rangé dans KeePassXC |
| sources, `build.sh`, `install.sh` | `system/chromium-sbx/` (dépôt chezmoi) | partie root, installée par `sudo ./install.sh` |

### Le compte `chromium`
`useradd --system --user-group --home-dir /var/lib/chromium-sbx --create-home --shell /usr/bin/nologin chromium`, home en `0700`. Pas de shell de connexion. Le mot de passe, verrouillé à la création, est ensuite défini par `keepass-tokens set-account chromium` (voir plus bas). Tout ce que Chromium écrit appartient à ce compte : pour la session, c'est « Permission refusée » sur les fichiers comme sur `/proc/<pid>/{environ,root}`, et elle ne peut même pas envoyer de signal aux processus de Chromium.

### Le lanceur interne `chromium-sbx-inner` (appartient à root)
C'est le seul programme que la session peut faire tourner en tant que `chromium` sans mot de passe. D'où trois précautions :
- **Il appartient à root et n'est modifiable que par root** (`install -o root -g root -m 755`). S'il était modifiable par la session, un malware lui ferait exécuter n'importe quoi en tant que chromium, donc lire le profil.
- **Il refuse toute option** (tout argument commençant par `-`). Chromium a plusieurs options qui lancent un programme (`--renderer-cmd-prefix`, `--gpu-launcher`…) : sans ce filtre, la règle sans mot de passe permettrait de lancer un programme arbitraire en tant que chromium. Les URL et chemins sont transmis après `--`.
- **Il vérifie** qu'il tourne bien en tant que chromium et que les sockets de passage existent.

Il lance ensuite `/usr/bin/chromium` (le lanceur Arch, qui lit `$XDG_CONFIG_HOME/chromium-flags.conf`, c'est-à-dire `/var/lib/chromium-sbx/.config/chromium-flags.conf` : `--password-store=gnome-libsecret`, appartenant au compte chromium) avec `--ozone-platform=wayland`, dans Bubblewrap :
- `/usr`, `/lib`, `/lib64`, `/bin`, `/etc`, `/opt` en lecture seule ; `/dev` minimal plus `/dev/dri` (GPU) ; `/sys/{dev,devices,bus,class}` en lecture seule ; `--proc` ; `--new-session` ;
- le home du compte en lecture-écriture, `/srv/chromium-sbx/Downloads` monté sur son `~/Downloads` ;
- **`/tmp` = `/var/lib/chromium-sbx/.tmp`**, partagé entre les lancements : un 2e lancement (lien ouvert depuis une autre appli) transmet l'URL à l'instance ouverte ;
- `$XDG_RUNTIME_DIR` = `/run/chromium` (`0700`), qui ne contient que `wayland-0`, `bus` et `pulse`, montés depuis `/run/chromium-sbx`.

### La règle sudo
```
Defaults>chromium targetpw, timestamp_timeout=0
timothe ALL=(chromium) ALL
timothe ALL=(chromium) NOPASSWD: /usr/local/bin/chromium-sbx-inner
```
- Sudoers applique la **dernière** règle correspondante : la règle `NOPASSWD` doit rester après la règle générale.
- `targetpw` : toute autre commande en tant que chromium exige le mot de passe **du compte chromium**, pas celui de la session ; `timestamp_timeout=0` : jamais mémorisé.
- `install.sh` vérifie le fichier avec `visudo -cf` avant de l'installer.

**Bug rencontré.** La première version utilisait `runaspw`. Symptôme : `keepass-tokens sudo chromium …` répondait *« 3 saisies de mots de passe incorrectes »*, sans aucun échec enregistré par `faillock` pour chromium. Le diagnostic a écarté les autres causes (compte en état `P`, environnement bien transmis à l'askpass, mot de passe de 40 caractères bien lu dans KeePassXC). Les descriptions intégrées à sudo tranchent : `runaspw` = *« Prompt for the runas_default user's password »*, c'est-à-dire **root** (sans mot de passe) ; `targetpw` = *« Prompt for the target user's password »*. Corrigé en `targetpw`.

### Accès au compte avec un mot de passe rangé dans KeePassXC
- `keepass-tokens set-account chromium` génère un mot de passe aléatoire de 40 caractères (`A-Za-z0-9`, depuis `/dev/urandom`), le range dans l'entrée **« Comptes sandbox/chromium »** de la base (groupe créé si besoin, non exposé au Secret Service), puis l'applique au compte avec `sudo chpasswd` (mot de passe sudo de la session).
- `keepass-tokens sudo chromium <commande>` exécute `sudo -A -u chromium` avec `SUDO_ASKPASS` pointant sur `keepass-tokens` lui-même. Sudo l'appelle pour obtenir le mot de passe : il ouvre la fenêtre `pinentry-gtk` (mot de passe maître KeePassXC), lit l'entrée avec `keepassxc-cli` et renvoie le mot de passe à sudo. Déverrouillage demandé **à chaque fois**. Vérifié : `keepass-tokens sudo chromium /usr/bin/id -un` affiche `chromium`.

### Le dossier de passage `/run/chromium-sbx`
`/etc/tmpfiles.d/chromium-sbx.conf` : `d /run/chromium-sbx 2750 timothe chromium -`.
- La session en est propriétaire et y crée les sockets ; le groupe `chromium` peut y entrer ; les autres comptes non.
- **Bit setgid** : les sockets créés par la session prennent automatiquement le groupe `chromium`.
- **La session n'est pas membre du groupe `chromium`.** Sinon, tous ses programmes, malware compris, hériteraient des droits de groupe sur tout ce que Chromium créerait lisible par son groupe.
- Permissions observées : `wayland` et `bus` en `rw-rw----` ; `pulse` créé par pipewire-pulse en `rwxrwxrwx`, protégé par le dossier.

### Les téléchargements partagés
`/srv/chromium-sbx` (0750 `chromium:chromium`, ACL `u:timothe:x`) et `/srv/chromium-sbx/Downloads` (2770, ACL `u:timothe:rwx` et ACL par défaut pour timothe, l'utilisateur et le groupe chromium). La session accède à **ce seul dossier**. Il est hors du home de chromium : donner à la session le droit de traverser `/var/lib/chromium-sbx` exposerait tout sous-dossier créé avec des droits permissifs.

### L'affichage : socket Wayland « contexte de sécurité »
`wayland-sandbox-socket` (C, `system/chromium-sbx/wayland-sandbox-socket.c`, compilé par `build.sh` avec `wayland-scanner` depuis `/usr/share/wayland-protocols/staging/security-context/security-context-v1.xml`) :
1. se connecte au compositeur et récupère `wp_security_context_manager_v1` ;
2. crée le socket d'écoute `/run/chromium-sbx/wayland` (0660) et un tube ;
3. appelle `create_listener(socket, bout lecture du tube)`, `set_sandbox_engine("chromium-sbx")`, `set_app_id("chromium")`, `commit` ;
4. garde le bout écriture ouvert et reste en vie : quand il s'arrête, le compositeur cesse d'accepter des connexions sur ce socket (vérifié : plus de connexion possible, socket supprimé).

Hyprland marque alors ces clients comme sandboxés et leur retire les protocoles privilégiés. Test avec un client qui liste les protocoles : **71 via le socket normal, 40 via le socket sandbox**. Retirés notamment : `zwlr_screencopy_manager_v1`, `ext_image_copy_capture_manager_v1`, `hyprland_toplevel_export_manager_v1` (capture d'écran et de fenêtres), `zwp_virtual_keyboard_manager_v1`, `zwlr_virtual_pointer_manager_v1` (taper ou cliquer dans d'autres fenêtres), `zwlr_data_control_manager_v1`, `ext_data_control_manager_v1` (lecture globale du presse-papiers), `zwlr_foreign_toplevel_manager_v1`, `ext_foreign_toplevel_list_v1` (liste des autres fenêtres), `zwlr_layer_shell_v1`, `hyprland_input_capture_manager_v1`, `hyprland_global_shortcuts_manager_v1`, `xwayland_shell_v1`. Le copier-coller normal reste disponible. Fenêtre vérifiée : classe `chromium`, `xwayland=false`, GPU actif (pas de `--use-gl=disabled`).

### Le bus D-Bus : proxy filtré + relais d'authentification
**Filtre** (`chromium-sbx-dbus.service`, `xdg-dbus-proxy` sur le socket **privé** `%t/chromium-sbx-dbus`, `UMask=0077`) :
- autorisés : `org.freedesktop.secrets` (KeePassXC), `org.freedesktop.Notifications`, `org.freedesktop.ScreenSaver`, possession de `org.mpris.MediaPlayer2.chromium.*` ; parmi les portails, seulement `Settings` (thème), `ScreenCast` (partage d'écran), `Request`/`Session` et leurs signaux ;
- refusés : le sélecteur de fichiers (le portail tourne sous la session et renverrait des chemins que Chromium ne peut pas lire), l'ouverture d'URL ou de fichier par les applis de la session, la capture d'écran par portail, systemd. Testé : `FileChooser`, `OpenURI`, `Screenshot` → *Access denied* ; `systemd1` → *ServiceUnknown* ; `Settings.ReadOne color-scheme` → `1` ; `ScreenCast version` → `6` ; KeePassXC répond.

**Bug rencontré, et pourquoi le relais.** À la connexion, un client D-Bus s'authentifie (mécanisme `EXTERNAL`) :
- **libdbus** (la bibliothèque de Chromium, et `dbus-send`) **annonce son uid**, ici 963. `xdg-dbus-proxy` transmet cet échange tel quel au bus, qui le refuse : pour lui, la connexion vient du proxy, qui tourne sous l'uid de la session ;
- **sd-bus** (`busctl`) n'annonce pas d'uid : le bus utilise celui de la connexion, et ça passe. Les premiers tests, faits avec `busctl`, **masquaient le problème**.

Symptômes observés : erreurs *« Failed to connect to the bus: Did not receive a reply »* dans Chromium, `dbus-send` en échec direct comme dans Bubblewrap, **22 cookies sur 22 en `v10`** (Chromium n'avait pas joint KeePassXC et était passé sur la clé fixe), `os_crypt.portal.prev_init_success=false`, pas de thème sombre.

`dbus-uid-relay` (Python, `chromium-sbx-dbus-relay.service`, socket `/run/chromium-sbx/bus` en 0660) termine l'authentification côté client (accepte `AUTH EXTERNAL` avec ou sans identité, répond `OK` avec le GUID du proxy, gère `NEGOTIATE_UNIX_FD`). Il s'authentifie lui-même auprès du proxy avec son propre uid, puis relaie les octets et les descripteurs de fichiers (`SCM_RIGHTS`, utilisés par exemple par le partage d'écran) dans les deux sens. L'accès au relais est contrôlé par les permissions de son socket. Vérifié après correction : `dbus-send` en tant que chromium voit `secrets` et les portails, depuis Bubblewrap `color-scheme = 1` et la collection KeePassXC ; dans Chromium, thème sombre appliqué et KeePassXC sollicité.

**Bus système** : volontairement non exposé (NetworkManager, polkit, login1…). Chromium affiche des erreurs `system_bus_socket` et `UPower` sans conséquence.

### Le son : socket PipeWire en accès restreint
`~/.config/pipewire/pipewire-pulse.conf.d/chromium-sbx.conf` ajoute l'adresse `{ address = "unix:/run/chromium-sbx/pulse" client.access = "restricted" }`. Redéfinir `server.address` remplace la liste par défaut : `"unix:native"` y est donc répété. Pour un client `restricted`, WirePlumber attache `default_restricted_pm`, dont les permissions par défaut sont `Perm.RX` (script `client/find-default-access.lua`) : Chromium joue ses propres flux, mais ne peut ni modifier les autres flux ni régler les périphériques. Vérifié : le son fonctionne.

### KeePassXC, cookies et thème
Chromium récupère sa clé de chiffrement par le bus filtré : la **même entrée « Chromium Safe Storage »** que l'ancien profil. Les cookies `v11` du profil migré restent donc lisibles, et la session reste connectée aux sites. Le thème sombre vient du portail `Settings` (`org.freedesktop.appearance color-scheme`).

### Tests réalisés (16/09/2026)
| Vérification | Résultat |
|---|---|
| lanceur interne par sudo sans mot de passe, avec une option | exécuté en tant que chromium, option refusée (code 2) |
| autre commande en tant que chromium sans mot de passe | refusée |
| `keepass-tokens sudo chromium /usr/bin/id -un` | `chromium` (après correction `targetpw`) |
| services `chromium-sbx-wayland`, `-dbus`, `-dbus-relay`, `pipewire-pulse` | actifs, sockets présents |
| lancement de Chromium | processus sous le compte chromium, fenêtre classe `chromium`, `xwayland=false`, GPU actif |
| depuis la session : `ls /var/lib/chromium-sbx`, `/proc/<pid>/environ`, `/proc/<pid>/root`, `kill` | tous refusés |
| `/srv/chromium-sbx/Downloads` depuis la session | accessible |
| libdbus direct et dans Bubblewrap (après le relais) | services visibles, thème `1`, collection KeePassXC |
| son, thème sombre, KeePassXC | fonctionnent |
| profil migré | onglets restaurés, connexions et Proton Pass conservés ; données Proton Pass présentes ; `restore_on_startup = 1` ; profil `chromium:chromium` en 0700 ; illisible depuis la session |

### Migration d'un profil existant
1. Fermer tous les Chromium.
2. `sudo rsync -a --delete --exclude='Singleton*' ~/.local/share/secure-profiles/chromium/ /var/lib/chromium-sbx/.config/chromium/`, puis `chown -R chromium:chromium` et `chmod 700`.
3. Faire pointer `chromium.desktop` sur `~/.local/bin/chromium-sbx %U` (et `chezmoi re-add`).
4. Vérifier : onglets, connexions aux sites, Proton Pass, cookies par préfixe.
5. **Supprimer les anciennes copies lisibles par la session** : `~/.local/share/secure-profiles/chromium` et `~/.config/chromium`. Sans cela, la protection ne sert à rien. Sans chiffrement du disque, des fragments effacés peuvent rester récupérables sur le SSD jusqu'à leur réécriture.

### Limites
- **root lit tout.** Or `sudo -i` avec le mot de passe de la session donne root, puis le compte chromium. Le fermer demanderait `Defaults rootpw` (mot de passe root rangé dans KeePassXC).
- **Une session compromise contrôle les sockets de passage** (elle possède `/run/chromium-sbx`). Elle peut s'interposer sur l'affichage et le son pendant l'utilisation (voir et taper), et demander à KeePassXC la clé des cookies. Mais elle **ne lit ni le profil au repos ni la mémoire de Chromium**.
- Les applications de la session peuvent toujours capturer l'écran, donc ce qu'affiche Chromium.
- Chromium ne voit plus le home de la session : envois et téléchargements passent par `/srv/chromium-sbx/Downloads`.
- Les extensions à hôte natif (vicinae, KeePassXC-Browser) ne fonctionnent pas ; Proton Pass, si.
- OpenSnitch voit un nouveau compte : les autorisations sont redemandées.
- Non testés : partage d'écran et micro à travers le relais et le socket son restreint.

### Maintenance
- **Partie root** : sources dans `system/chromium-sbx/` (dépôt chezmoi, non déployé). Après modification du lanceur interne, des sudoers, de tmpfiles ou de `wayland-sandbox-socket.c` : `./build.sh`, puis `sudo ./install.sh` (idempotent).
- **Fichiers de session**, gérés par chezmoi : `~/.local/bin/chromium-sbx`, `~/.local/bin/dbus-uid-relay`, `~/.config/systemd/user/chromium-sbx-{wayland,dbus,dbus-relay}.service`, `~/.config/pipewire/pipewire-pulse.conf.d/chromium-sbx.conf`. Après modification : `systemctl --user daemon-reload`, et `systemctl --user restart pipewire-pulse` pour la config son.
- **Agir sur le compte** (inspecter le profil, etc.) : `keepass-tokens sudo chromium <commande>`.
- **Revérifier l'ensemble** : `system/chromium-sbx/test.sh`, depuis un terminal normal (pas depuis un agent sandboxé : sudo y est impossible).

---

## 8. Sandbox des agents CLI (bwrap-agent)

### Objectif et choix
`agy` et `claude` sont des agents qui exécutent des commandes. Chacun doit être isolé **de l'autre** (token, config, processus) et **des secrets de la session**, tout en gardant l'accès au reste du PC pour travailler. `keepass-tokens` les lance dans `~/.local/bin/bwrap-agent` (variable `SANDBOX`). Choix faits le 16/09/2026 : **fichiers de démarrage en lecture seule** et **toutes les portes de sortie fermées**.

### Ce que voit un agent
- **Tout le système de fichiers de l'hôte** (`--dev-bind / /`), puis :
  - **en lecture seule**, ce qui s'exécute plus tard hors sandbox, pour qu'un agent ne se ménage pas de porte de sortie : `~/.zshrc`, `~/.zprofile`, `~/.zshenv`, `~/.zlogin`, `~/.zlogout`, `~/.profile`, `~/.bashrc`, `~/.bash_profile`, `~/.bash_login`, `~/.oh-my-zsh`, `~/.gitconfig`, **`~/.config` en entier** (Hyprland, systemd, kitty…), `~/.local/bin`, `~/.local/share/applications`, `~/.local/share/chezmoi`, `~/.local/share/claude` ;
  - **masqués** (dossier → tmpfs vide, fichier → fichier vide), appliqués après la lecture seule : `~/.ssh`, `~/.gnupg`, le fichier clé KeePassXC `~/Documents/KeePass`, `~/.local/share/secure-profiles`, `~/.config/{keepassxc,chromium,mozilla,discord,vesktop,equibop,legcord,Vencord,Equicord,BetterDiscord,spotify}` ; pour agy, `~/.claude` et `~/.claude.json` ; pour claude, `~/.gemini`.
- **`$XDG_RUNTIME_DIR` vide** (tmpfs `0700`) : ni IPC Hyprland, ni `systemd --user`, ni agents SSH/GPG, ni Wayland/PipeWire, ni caches de tokens. Seuls y sont montés un bus D-Bus filtré (`xdg-dbus-proxy` par lancement : `org.freedesktop.Notifications` et `org.freedesktop.portal.*`) et, pour agy, son token en RAM (`--expose`).
- **Bus système masqué** (`/run/dbus/system_bus_socket` → `/dev/null`).
- **`/tmp` privé** : `/tmp` contenait le socket de KeePassXC, celui de l'interface OpenSnitch (`osui.sock`) et les sockets X11.
- **`/dev` et `/dev/pts` neufs** : pas d'accès aux autres terminaux.
- **`--unshare-pid`** : l'agent ne voit ni ne signale les processus de l'hôte, donc pas le `/proc/<pid>/environ` de l'autre agent ; ses propres processus s'arrêtent avec lui.
- **Pas de `--new-session`** : le terminal reste le terminal de contrôle (redimensionnement, Ctrl+C). L'injection de frappes (`TIOCSTI`) est déjà désactivée par le noyau (`dev.tty.legacy_tiocsti=0`).
- **`no_new_privs`** (posé par Bubblewrap) : `sudo` est impossible dans le sandbox.
- Variables retirées : `WAYLAND_DISPLAY`, `DISPLAY`, `HYPRLAND_INSTANCE_SIGNATURE`, `SSH_AUTH_SOCK`, `GPG_AGENT_INFO`, `KITTY_LISTEN_ON`. Réseau inchangé.

Inventaire fait avant de choisir : les seuls sockets abstraits en écoute (non masquables par un namespace de montage) appartiennent à d'autres comptes, dont le serveur X de SDDM ; le pilotage à distance de kitty est désactivé ; Docker n'est pas installé.

### Intégration avec `keepass-tokens`
- claude reçoit son token dans `CLAUDE_CODE_OAUTH_TOKEN` ;
- agy lit son token par le lien `~/.gemini/antigravity-cli/antigravity-oauth-token` → `$XDG_RUNTIME_DIR/secrets/agy/token`, le seul fichier de `$XDG_RUNTIME_DIR` rendu visible (`bwrap-agent agy --expose …`) ;
- le cache de l'autre agent reste invisible.

### Tests
- **Sondes depuis chaque sandbox** : token exposé lisible ; cache et config de l'autre agent invisibles ; écriture dans un dossier de travail possible ; écriture dans `~/.zshrc`, `~/.config/hypr`, `~/.local/bin`, `~/.oh-my-zsh` refusée ; SSH, GPG, fichier clé et config KeePassXC, profil Chromium masqués ; base KeePassXC (chiffrée) visible ; IPC Hyprland, `systemd --user`, bus système et Secret Service bloqués ; sockets de `/tmp` absents ; terminaux de l'hôte invisibles ; moins de 10 processus ; `sudo` refusé ; Bubblewrap imbriqué possible (sandbox de Claude Code) ; git, `claude --version` et `agy --help` fonctionnent.
- **Faux échec** : `busctl status org.freedesktop.Notifications` échoue à travers le proxy (*« Object is remote »* : ses informations de processus ne passent pas) ; un vrai appel `GetServerInformation` répond (`quickshell`).
- **16 scénarios d'intégration** avec de faux agy/claude : chaque agent signale le cache de l'autre comme invisible.
- **En conditions réelles** : une session Claude Code lancée par la fonction `claude` tournait dans le sandbox (6 processus visibles, `NoNewPrivs: 1`, `$XDG_RUNTIME_DIR` limité au bus et aux sockets de Claude Code, sudo refusé avec *« no new privileges »*, pas de bus systemd).

### Limites
- **Les processus lancés hors sandbox peuvent toujours entrer** (§6) : un malware de la session lit les tokens pendant leurs 10 min de déverrouillage.
- Pas de Wayland dans le sandbox : pas de presse-papiers ni de collage d'image par l'agent (le collage par le terminal fonctionne).
- Administration (sudo, systemd, Hyprland, modification de `~/.config` ou des dotfiles) : `command agy` / `command claude`, hors sandbox.
- Mises à jour d'agy et de claude : hors sandbox (leurs binaires sont en lecture seule).
- Un agent peut modifier les fichiers des projets, y compris les hooks git, qui s'exécuteront plus tard hors sandbox.

---

## 9. Protection contre les écoutes réseau & Wi-Fi

### Randomisation de l'adresse MAC (Anti-traçage)
L'adresse MAC physique est l'empreinte unique de votre carte réseau. Sur un réseau public (université, hôtel, gare), les bornes Wi-Fi enregistrent cette adresse pour pister vos allées et venues.  
Dans `/etc/NetworkManager/conf.d/00-mac-randomization.conf` :
- `wifi.scan-rand-mac-address=yes` : Fausse adresse MAC générée lors de la recherche des réseaux.
- `wifi.cloned-mac-address=random` : Nouvelle adresse MAC aléatoire générée à chaque association avec une borne Wi-Fi.

### Chiffrement des requêtes DNS (DNS-over-TLS - DoT)
- **Problème** : En DNS classique (port 53 UDP), chaque nom de domaine auquel vous accédez (`banque.com`, `discord.com`) est transmis en texte brut non chiffré. N'importe qui analysant le réseau Wi-Fi local ou votre FAI peut dresser l'historique complet de votre navigation.
- **Solution** : En activant `DNSOverTLS=yes` dans `systemd-resolved` avec Quad9 (`9.9.9.9`), chaque requête DNS est encapsulée dans un tunnel chiffré TLS sur le port 853. Le contenu des requêtes devient totalement illisible pour les espions sur le réseau local.
