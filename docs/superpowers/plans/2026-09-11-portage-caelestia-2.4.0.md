# Portage du fork caelestia sur caelestia-shell 2.4.0 — plan d'implémentation

> **Pour les agents :** SOUS-COMPÉTENCE REQUISE : utiliser superpowers:subagent-driven-development (recommandé) ou superpowers:executing-plans pour dérouler ce plan tâche par tâche. Les étapes utilisent la syntaxe case à cocher (`- [ ]`).

**Objectif :** faire redémarrer le shell de bureau caelestia en portant les personnalisations du dépôt (fork figé sur l'upstream `0d37255`, ≈ v2.0.3) sur l'API de `caelestia-shell 2.4.0` installé par la réinstallation d'OS.

**Architecture :** merge git 3-voies (base = `0d37255`, nôtre = fork déployé, leur = tag `v2.4.0`) réalisé dans un dépôt jetable, puis résolution des 7 conflits + migration mécanique des imports du plugin + réécriture des 6 fichiers ajoutés par le fork qui utilisent des API supprimées. Le résultat est recopié dans la source chezmoi et déployé.

**Pile technique :** QML / Quickshell 0.3.1, plugin C++ `Caelestia*` fourni par `caelestia-shell 2.4.0-1`, chezmoi, git.

**Spec :** ce document (le diagnostic complet est dans la section « Contexte » ci-dessous ; il n'y a pas de spec séparée).

## Contraintes globales

- Cible unique : `caelestia-shell 2.4.0-1` et `quickshell-git 0.3.1.r10.g2d3b3e9-1`, déjà installés. **Ne pas downgrader, ne pas épingler.**
- **Ne jamais modifier `/etc/xdg/quickshell/caelestia`** : ce répertoire appartient au paquet et sert de référence 2.4.0 en lecture seule.
- Arbre de travail : `/tmp/claude-1000/-home-timothe/ee3bca95-b902-44af-8915-15b03f90b450/scratchpad/port`, branche `fork`, merge `v2.4.0` **en cours** (7 conflits non résolus). Référence upstream clonée : `../upstream-shell`.
- Livraison : recopie vers `~/.local/share/chezmoi/dot_config/quickshell/caelestia`, puis `chezmoi apply`.
- **Test de recette unique**, à relancer après chaque tâche :
  ```bash
  timeout 10 qs -c caelestia 2>&1 | grep -E "Configuration Loaded|ERROR"
  ```
  Succès = la ligne `Configuration Loaded` apparaît et **aucune** ligne `ERROR`.
- Les 4 personnalisations à préserver impérativement :
  1. widget EasyEffects dans la barre (bascule des effets, choix entrée/sortie audio) ;
  2. notifications popup groupées par application ;
  3. cartes d'espaces de travail cliquables dans l'Overview (SUPER+Tab) ;
  4. horloge + résumé de performances en haut de barre (`TopClock`, `PerformanceSummary`).
- Commits : dans le dépôt chezmoi uniquement, à la fin (tâche 9). Le dépôt jetable n'a pas vocation à être poussé.

## Carte de migration de l'API plugin (base → 2.4.0)

| Type | module dans le fork | module en 2.4.0 |
|---|---|---|
| `ImageAnalyser` | `Caelestia` | `Caelestia.Images` |
| `AppDb`, `AppEntry` | `Caelestia` | `Caelestia.Models` |
| `CircularBuffer` | `Caelestia.Internal` | `Caelestia` |
| `SparklineItem`, `VisualiserBars`, `CircularIndicatorManager`, `LinearIndicatorManager`, `LinearIndicatorSegment` | `Caelestia.Internal` | `Caelestia.Components` |
| `HyprDevices`, `HyprExtras`, `HyprKeyboard` | `Caelestia.Internal` | `Caelestia.Services` |
| `LogindManager` | `Caelestia.Internal` | **supprimé** |
| `LyricsBackend` | `Caelestia.Services` | **supprimé** |
| `MonitorConfigManager` | `Caelestia.Config` | **supprimé** |
| `NetworkUsage` | singleton QML `services/NetworkUsage.qml` | singleton plugin `Caelestia.Services` |
| `DrawerVisibilities` | `components/DrawerVisibilities.qml` | renommé `components/ScreenState.qml` |
| `Network` | singleton QML `services/Network.qml` | **supprimé** (utiliser `Nmcli`) |
| `Visibilities` | `services/Visibilities.qml` | **supprimé** (utiliser `ShellState` / `ScreenState`) |

`GlobalConfig` **existe toujours** en 2.4.0 (déclaré par la macro `SINGLETON_DECL` dans `plugin/src/Caelestia/Config/rootnodes.hpp`) : aucun des 69 fichiers qui l'utilisent n'est à toucher.

## Structure des fichiers

**Conflits à résoudre (7) :**
- `components/ScreenState.qml` — état partagé écran/tiroirs (ex-`DrawerVisibilities.qml`)
- `modules/drawers/ContentWindow.qml` — opacité du fond des tiroirs
- `modules/drawers/Overview.qml` *(ajouté par le fork, pas en conflit mais dépendant)* — Overview cliquable
- `modules/bar/Bar.qml` — composition de la barre
- `modules/bar/components/Clock.qml` — horloge de barre
- `modules/bar/components/StatusIcons.qml` — icônes d'état (restructuré upstream en `DelegateChoice`)
- `services/Hypr.qml` — détection de la config Lua
- `shell.qml` — racine du shell

**Fichiers ajoutés par le fork, à porter (6) :**
- `modules/bar/components/PerformanceSummary.qml` — **le seul qui référence encore `Caelestia.Internal`**
- `modules/bar/components/TopClock.qml`
- `modules/bar/popouts/CalendarPopout.qml`
- `modules/bar/popouts/EasyEffects.qml`
- `modules/drawers/Overview.qml`
- `services/EasyEffects.qml`

**Fichiers personnalisés auto-fusionnés que l'upstream a aussi modifiés — à relire (9) :**
`modules/Shortcuts.qml`, `modules/bar/popouts/Content.qml`, `modules/dashboard/Wrapper.qml`,
`modules/drawers/Interactions.qml`, `modules/drawers/Panels.qml`,
`modules/notifications/Content.qml`, `modules/notifications/Notification.qml`,
`services/Audio.qml`, `components/DrawerVisibilities.qml` (doit disparaître au profit de `ScreenState.qml`).

---

### Tâche 1 : état partagé écran/tiroirs (`ScreenState`) et Overview

**Fichiers :**
- Modifier : `components/ScreenState.qml` (conflit, 1 bloc)
- Modifier : `modules/drawers/ContentWindow.qml` (conflit, 1 bloc)
- Supprimer : `components/DrawerVisibilities.qml` s'il subsiste après le merge
- Relire : `modules/drawers/Overview.qml`, `modules/drawers/Panels.qml`, `modules/drawers/Interactions.qml`, `modules/drawers/Regions.qml`, `modules/drawers/Exclusions.qml`

**Interfaces :**
- Produit : `ScreenState.overview` (bool) et `ScreenState.barIsTop` (bool, toujours vrai) consommés par les tâches 2 et 6.

- [x] **Étape 1 : lancer le test de recette et constater l'échec**

```bash
cd /tmp/claude-1000/-home-timothe/ee3bca95-b902-44af-8915-15b03f90b450/scratchpad/port
timeout 10 qs -p ./shell.qml 2>&1 | grep -E "Configuration Loaded|ERROR" | head -5
```
Attendu : ÉCHEC — marqueurs de conflit `<<<<<<<` → erreur de syntaxe QML.

- [x] **Étape 2 : résoudre `components/ScreenState.qml`**

Le fork ajoute `overview`/`barIsTop`, l'upstream ajoute l'état du dashboard. Garder **les deux** :

```qml
    property bool overview
    property bool barIsTop: true
    onBarIsTopChanged: if (!barIsTop) barIsTop = true

    // Dashboard state
    property int dashboardTab
    property date dashboardDate: new Date()
```

- [x] **Étape 3 : résoudre `modules/drawers/ContentWindow.qml`**

Reprendre la forme 2.4.0 (`root.screenState`, l'ancien `visibilities` n'existe plus) et y réinjecter la condition `overview` du fork :

```qml
        opacity: (root.screenState.session && Config.session.enabled) || root.screenState.overview || panels.popouts.detachedMode !== "" ? 0.5 : 0
```

- [x] **Étape 4 : éliminer le doublon `DrawerVisibilities.qml`**

```bash
cd /tmp/claude-1000/-home-timothe/ee3bca95-b902-44af-8915-15b03f90b450/scratchpad/port
ls components/DrawerVisibilities.qml 2>/dev/null && git rm -f components/DrawerVisibilities.qml
grep -rn "DrawerVisibilities" --include='*.qml' . | grep -v '^\./\.git'
```
Attendu : plus aucune occurrence de `DrawerVisibilities`. Chaque occurrence trouvée doit devenir `ScreenState`.

- [x] **Étape 5 : vérifier que le QML compile jusqu'ici**

```bash
timeout 10 qs -p ./shell.qml 2>&1 | grep -E "ScreenState|DrawerVisibilities|Configuration Loaded" | head -5
```
Attendu : plus d'erreur mentionnant `ScreenState` ni `DrawerVisibilities` (d'autres erreurs subsistent, c'est normal).

---

### Tâche 2 : barre — horloge déportée en haut

**Fichiers :**
- Modifier : `modules/bar/Bar.qml` (conflit, 1 bloc)
- Modifier : `modules/bar/components/Clock.qml` (conflit, 2 blocs)
- Relire : `modules/bar/components/TopClock.qml` (ajouté par le fork)

**Interfaces :**
- Consomme : `ScreenState.barIsTop` (tâche 1).
- Produit : l'entrée `taskbarClock` de la barre reste masquée, `TopClock` l'affiche en haut.

- [x] **Étape 1 : comprendre la nouvelle structure de barre**

```bash
cd /tmp/claude-1000/-home-timothe/ee3bca95-b902-44af-8915-15b03f90b450/scratchpad/port
sed -n '1,120p' <(git show v2.4.0:modules/bar/Bar.qml)
```
En 2.4.0 la barre est pilotée par un modèle et des `DelegateChoice`/`EntryWrapper` ; `WrappedLoader` n'existe plus sous cette forme.

- [x] **Étape 2 : résoudre `modules/bar/Bar.qml`**

Conserver la structure 2.4.0 (`EntryWrapper` + `objectName: "taskbarClock"`) et reporter l'intention du fork (horloge de barre masquée car déportée dans `TopClock`) en rendant l'entrée invisible :

```qml
                delegate: EntryWrapper {
                    visible: false

                    Clock {
                        objectName: "taskbarClock"
                    }
```

- [x] **Étape 3 : résoudre les 2 blocs de `modules/bar/components/Clock.qml`**

Bloc 1 — garder la version 2.4.0 (`asynchronous`/`active`/`visible`) : l'ancien `visible: false` du fork est désormais porté par `Bar.qml` (étape 2), le dupliquer ici casserait l'horloge du popout calendrier.

```qml
            asynchronous: true
            active: Config.bar.clock.showDate
            visible: active
```

Bloc 2 — garder intégralement la version 2.4.0 (les `StyledText` jour/date + le `StyledRect` séparateur). Le fork n'avait fait que remplacer ce bloc par un `Rectangle` invisible ; ce masquage est lui aussi repris par `Bar.qml`.

- [x] **Étape 4 : vérifier**

```bash
timeout 10 qs -p ./shell.qml 2>&1 | grep -E "Bar\.qml|Clock\.qml" | head -5
```
Attendu : aucune erreur pointant `Bar.qml` ou `Clock.qml`.

---

### Tâche 3 : icônes d'état et widget EasyEffects

**Fichiers :**
- Modifier : `modules/bar/components/StatusIcons.qml` (conflit, 1 bloc de 135 lignes)
- Relire : `services/EasyEffects.qml`, `modules/bar/popouts/EasyEffects.qml`, `modules/bar/popouts/Content.qml`

**Interfaces :**
- Consomme : singleton `EasyEffects` (`services/EasyEffects.qml`, propriétés `active`, `running`).
- Produit : une entrée d'état nommée `easyeffects` que `modules/bar/popouts/Content.qml` ouvre au clic.

- [x] **Étape 1 : lire la version 2.4.0 en entier avant de toucher au fichier**

```bash
cd /tmp/claude-1000/-home-timothe/ee3bca95-b902-44af-8915-15b03f90b450/scratchpad/port
git show v2.4.0:modules/bar/components/StatusIcons.qml
```
Upstream a remplacé la liste de `WrappedLoader` par un modèle + `DelegateChoice { roleValue: "..." ; delegate: EntryWrapper { ... } }`, avec des sous-composants dédiés dans `modules/bar/components/status/` (`BatteryStatus.qml`, `BluetoothStatus.qml`, `LockStatus.qml`).

- [x] **Étape 2 : résoudre le conflit en gardant la structure 2.4.0**

Prendre la branche `v2.4.0` du bloc en conflit dans son intégralité (volume, micro, disposition clavier, réseau, ethernet, bluetooth sont tous fournis par 2.4.0 — le fork ne faisait que les recopier). **Seul ajout propre au fork à reporter : l'icône EasyEffects.**

- [x] **Étape 3 : réinjecter l'entrée EasyEffects dans le modèle 2.4.0**

En 2.4.0 la liste d'icônes n'est plus codée en dur : elle vient de la config
(`values: root.Config.bar.statusIcons.values.filter(e => e.enabled)`, ligne 64), dont le schéma
est déclaré côté C++ dans `plugin/src/Caelestia/Config/barconfig.hpp` :
`CONFIG_LIST(EntryList, statusIcons, LIST_ENTRY(lockStatus, true), LIST_ENTRY(audio, false), LIST_ENTRY(microphone, false), LIST_ENTRY(kbLayout, false), LIST_ENTRY(network, true), LIST_ENTRY(bluetooth, true), LIST_ENTRY(battery, true))`.
Il n'y a **pas** d'entrée `easyeffects`.

Ajouter d'abord le `DelegateChoice`, dans le `DelegateChooser { role: "id" }` de `iconColumn`,
à la suite des autres (calqué sur `roleValue: "audio"`) :

```qml
                DelegateChoice {
                    roleValue: "easyeffects"
                    delegate: EntryWrapper {
                        margin: Tokens.spacing.extraSmall / 2

                        MaterialIcon {
                            animate: true
                            text: EasyEffects.active ? "graphic_eq" : "equalizer"
                            color: EasyEffects.active ? Colours.palette.m3primary : root.colour
                            opacity: EasyEffects.running ? 1 : 0.55
                            fill: EasyEffects.active ? 1 : 0
                            fontStyle: Tokens.font.icon.medium
                        }
                    }
                }
```

- [x] **Étape 3b : déclarer l'entrée dans la config utilisateur, puis vérifier qu'elle n'est pas mise en quarantaine**

`~/.config/caelestia/shell.json` ne définit pas `bar.statusIcons` : les valeurs par défaut du C++
s'appliquent. Y ajouter la liste complète avec `easyeffects` :

```bash
python3 - <<'PY'
import json, pathlib
p = pathlib.Path.home() / ".config/caelestia/shell.json"
c = json.loads(p.read_text())
c.setdefault("bar", {})["statusIcons"] = [
    {"id": "lockStatus", "enabled": True},
    {"id": "audio", "enabled": True},
    {"id": "microphone", "enabled": False},
    {"id": "kbLayout", "enabled": False},
    {"id": "easyeffects", "enabled": True},
    {"id": "network", "enabled": True},
    {"id": "bluetooth", "enabled": True},
    {"id": "battery", "enabled": True},
]
p.write_text(json.dumps(c, indent=4))
PY
timeout 10 qs -p ./shell.qml 2>&1 | grep -iE "quarantin|statusIcons|unknown"
```

**Règle de décision :** si la sortie signale une quarantaine ou un identifiant inconnu, le schéma C++
refuse l'entrée. Dans ce cas seulement, replier le widget hors du modèle : le placer comme enfant fixe
du `ColumnLayout { id: iconColumn }`, après le `Repeater`, et le câbler au popout en reprenant le
`name` utilisé par `modules/bar/popouts/Content.qml`.

- [x] **Étape 4 : vérifier**

```bash
timeout 10 qs -p ./shell.qml 2>&1 | grep -E "StatusIcons|EasyEffects" | head -5
```
Attendu : aucune erreur pointant `StatusIcons.qml` ni `EasyEffects`.

---

### Tâche 4 : détection de la config Lua (`services/Hypr.qml`)

**Fichiers :**
- Modifier : `services/Hypr.qml` (conflit, 1 bloc)

- [x] **Étape 1 : constater que 2.4.0 gère le Lua nativement**

```bash
cd /tmp/claude-1000/-home-timothe/ee3bca95-b902-44af-8915-15b03f90b450/scratchpad/port
git show v2.4.0:services/Hypr.qml | grep -n "usingLua" 
grep -n "luaProbe" services/Hypr.qml
```
Le fork avait ajouté un `luaProbe` maison parce que la base ne savait pas détecter `hyprland.lua`. La 2.4.0 expose `usingLua` et rappelle `reloadDynamicConfs()` sur changement.

- [x] **Étape 2 : résoudre en faveur de 2.4.0 et supprimer le `luaProbe`**

```qml
    onUsingLuaChanged: reloadDynamicConfs()
    Component.onCompleted: reloadDynamicConfs()
```

Puis retirer la définition devenue morte du `luaProbe` (le `Process`/`FileView` associé) :

```bash
grep -n "luaProbe" services/Hypr.qml
```
Attendu après nettoyage : aucune occurrence.

- [x] **Étape 3 : vérifier**

```bash
timeout 10 qs -p ./shell.qml 2>&1 | grep -E "Hypr\.qml" | head -5
```
Attendu : aucune erreur pointant `Hypr.qml`.

---

### Tâche 5 : racine du shell (`shell.qml`)

**Fichiers :**
- Modifier : `shell.qml` (conflit, 1 bloc)

- [x] **Étape 1 : résoudre en gardant `id: root` (2.4.0) et `watchFiles: false` (fork)**

L'`id: root` est requis par la 2.4.0 (référencé ailleurs dans le fichier). Le `watchFiles: false` est un choix délibéré du fork : le shell est déployé par chezmoi, donc la surveillance de fichiers n'apporte rien et provoque des rechargements parasites.

```qml
    id: root

    settings.watchFiles: false
```

- [x] **Étape 2 : vérifier qu'aucun marqueur de conflit ne subsiste dans tout l'arbre**

```bash
cd /tmp/claude-1000/-home-timothe/ee3bca95-b902-44af-8915-15b03f90b450/scratchpad/port
grep -rn '^<<<<<<<\|^>>>>>>>\|^=======$' --include='*.qml' . | grep -v '^\./\.git'
```
Attendu : aucune sortie.

---

### Tâche 6 : `PerformanceSummary.qml` — dernier consommateur de `Caelestia.Internal`

**Fichiers :**
- Modifier : `modules/bar/components/PerformanceSummary.qml`

**Interfaces :**
- Consomme : `ScreenState` (tâche 1), `NetworkUsage` depuis `Caelestia.Services`, `Nmcli`.

- [x] **Étape 1 : identifier précisément ce que le fichier importe et utilise**

```bash
cd /tmp/claude-1000/-home-timothe/ee3bca95-b902-44af-8915-15b03f90b450/scratchpad/port
grep -nE "^import|NetworkUsage|DrawerVisibilities|\bNetwork\b|SparklineItem|CircularBuffer" modules/bar/components/PerformanceSummary.qml
```

- [x] **Étape 2 : supprimer l'import `Caelestia.Internal`, devenu inutile**

Inventaire réel du fichier : les composants instanciés sont `CircularProgress`, `MaterialIcon`,
`Ref`, `ServiceRef`, `RowLayout`, `StyledRect`, `StyledText`, et les services référencés sont
`Cpu`, `Memory`, `Storage`, `Gpu`, `NetworkUsage` — **tous fournis par `Caelestia.Services` ou
`qs.components*`**. Aucun type de `Caelestia.Internal` n'est utilisé : l'import est vestigial.

Supprimer la ligne 7 :
```qml
import Caelestia.Internal
```

- [x] **Étape 3 : migrer `DrawerVisibilities` vers `ScreenState`**

Ligne 16 :
```qml
    required property ScreenState visibilities
```
(le nom de propriété `visibilities` peut rester ; seul le type change)

Puis répercuter sur les instanciations de `PerformanceSummary` :
```bash
cd /tmp/claude-1000/-home-timothe/ee3bca95-b902-44af-8915-15b03f90b450/scratchpad/port
grep -rn "PerformanceSummary" --include='*.qml' . | grep -v '^\./\.git'
```
Chaque site d'appel doit passer l'objet `ScreenState` de la tâche 1.

**`NetworkUsage.formatBytes`, `downloadSpeed` et `uploadSpeed` existent toujours en 2.4.0**
(`plugin/src/Caelestia/Services/networkusage.hpp`) : les lignes 201 et 218 n'ont pas à changer.
`NetworkUsage` vient désormais de `Caelestia.Services`, déjà importé ligne 6 — rien à ajouter.

- [x] **Étape 4 : prendre modèle sur la carte réseau 2.4.0 pour l'usage de `NetworkUsage`**

```bash
git show v2.4.0:modules/dashboard/performance/NetworkCard.qml | sed -n '1,80p'
```
Elle montre l'API courante : `NetworkUsage.uploadBuffer`, `NetworkUsage.downloadBuffer`, `NetworkUsage.historyLength`, `NetworkUsage.downloadSpeed`, `NetworkUsage.formatBytesRate(...)`.

- [x] **Étape 5 : vérifier qu'aucune API supprimée ne subsiste dans tout l'arbre**

```bash
cd /tmp/claude-1000/-home-timothe/ee3bca95-b902-44af-8915-15b03f90b450/scratchpad/port
grep -rn "Caelestia.Internal\|LogindManager\|MonitorConfigManager\|DrawerVisibilities" --include='*.qml' . | grep -v '^\./\.git'
```
Attendu : aucune sortie.

---

### Tâche 7 : relecture des personnalisations auto-fusionnées

**Fichiers à relire** (git les a fusionnés textuellement, l'upstream les a aussi modifiés — la fusion peut être syntaxiquement correcte mais sémantiquement fausse) :
- `modules/notifications/Content.qml`, `modules/notifications/Notification.qml` → **personnalisation 2 : notifs groupées par application**
- `modules/drawers/Overview.qml`, `modules/drawers/Panels.qml`, `modules/drawers/Interactions.qml` → **personnalisation 3 : Overview cliquable**
- `modules/bar/popouts/Content.qml`, `modules/dashboard/Wrapper.qml`, `modules/Shortcuts.qml`, `services/Audio.qml`
- `modules/bar/popouts/CalendarPopout.qml`, `modules/bar/popouts/ClipWrapper.qml`, `modules/drawers/Regions.qml`, `modules/drawers/Exclusions.qml`, `assets/wrap_term_launch.sh` → ajoutés/modifiés par le fork sans contrepartie upstream : vérifier seulement qu'ils compilent (aucune API supprimée n'y figure d'après l'inventaire).

- [x] **Étape 1 : afficher, pour chaque fichier, ce que le fork avait changé**

```bash
cd /tmp/claude-1000/-home-timothe/ee3bca95-b902-44af-8915-15b03f90b450/scratchpad/port
base=0d37255873b074ba1385a77f3cb658cc3e24a2d4
for f in modules/notifications/Content.qml modules/notifications/Notification.qml \
         modules/drawers/Panels.qml modules/drawers/Interactions.qml \
         modules/bar/popouts/Content.qml modules/dashboard/Wrapper.qml \
         modules/Shortcuts.qml services/Audio.qml; do
  echo "═══════ $f"; git diff "$base" fork -- "$f"
done
```

- [x] **Étape 2 : pour chaque fichier, vérifier que l'intention du fork survit dans le fichier fusionné**

Contrôle ciblé du groupement de notifications :
```bash
grep -n "appName\|grouped\|collapse" modules/notifications/Content.qml modules/notifications/Notification.qml
```
Attendu : la logique de regroupement par `appName` est toujours présente. Si l'upstream a restructuré le fichier au point de l'effacer, la reporter sur la nouvelle structure.

Contrôle ciblé de l'Overview cliquable :
```bash
grep -n "MouseArea\|TapHandler\|dispatch" modules/drawers/Overview.qml
```
Attendu : les cartes d'espace de travail portent toujours un gestionnaire de clic qui appelle `Hypr.dispatch(...)`.

- [x] **Étape 3 : vérifier**

```bash
timeout 10 qs -p ./shell.qml 2>&1 | grep -E "Configuration Loaded|ERROR" | head -10
```
Attendu : `Configuration Loaded`, aucune ligne `ERROR`.

---

### Tâche 8 : recette de chargement et essai réel

- [x] **Étape 1 : chargement propre depuis l'arbre de travail**

```bash
cd /tmp/claude-1000/-home-timothe/ee3bca95-b902-44af-8915-15b03f90b450/scratchpad/port
timeout 10 qs -p ./shell.qml 2>&1 | grep -E "Configuration Loaded|ERROR"
```
Attendu : exactement une ligne `Configuration Loaded`, aucune `ERROR`. **Ne pas passer à la tâche 9 tant que ce n'est pas le cas.**

- [x] **Étape 2 : conclure le merge**

```bash
git add -A && git commit -q -m "port: fork caelestia sur upstream 2.4.0" && git log --oneline -1
```

---

### Tâche 9 : livraison chezmoi

- [x] **Étape 1 : recopier l'arbre porté dans la source chezmoi**

Ne copier que les fichiers du shell (pas `.git`, ni `plugin/`, `nix/`, `extras/`, `scripts/`, `.github/`, `CMakeLists.txt`, `README.md`, `flake.*`, `.envrc`, `.clang-format`, `.gitignore`, `.vscode/`) :

```bash
SRC=/tmp/claude-1000/-home-timothe/ee3bca95-b902-44af-8915-15b03f90b450/scratchpad/port
DST=~/.local/share/chezmoi/dot_config/quickshell/caelestia
rm -rf "$DST" && mkdir -p "$DST"
for d in assets components modules services utils; do cp -a "$SRC/$d" "$DST/"; done
cp -a "$SRC/shell.qml" "$SRC/LICENSE" "$DST/"
find "$DST" -name '*.orig' -delete
```

- [x] **Étape 2 : contrôler le diff chezmoi avant application**

```bash
chezmoi diff .config/quickshell/caelestia | head -40
chezmoi status .config/quickshell/caelestia | head -20
```

- [x] **Étape 3 : appliquer et vérifier sur la cible réelle**

```bash
chezmoi apply .config/quickshell/caelestia
timeout 10 qs -c caelestia 2>&1 | grep -E "Configuration Loaded|ERROR"
```
Attendu : `Configuration Loaded`, aucune `ERROR`.

- [x] **Étape 4 : démarrer le shell pour de vrai et contrôler visuellement**

```bash
qs -c caelestia -d
sleep 3 && pgrep -a qs
```
Attendu : le processus tourne ; barre, horloge en haut, icône EasyEffects visibles. Vérifier SUPER+Tab (Overview cliquable) et une notification de test :
```bash
notify-send "test" "groupement"; notify-send "test" "groupement 2"
```

- [x] **Étape 5 : noter la version de référence pour éviter une nouvelle dérive silencieuse**

C'est la cause racine de la panne : rien dans le dépôt n'indiquait sur quelle version de `caelestia-shell` le fork était aligné. Créer `dot_config/quickshell/caelestia/dot_upstream-version` :

> **Piège découvert à la livraison :** le fichier doit s'appeler `dot_upstream-version` dans la
> source chezmoi (convention `dot_` → déployé comme `.upstream-version` dans `~`). Un fichier
> nommé littéralement `.upstream-version` dans la source serait ignoré par chezmoi (il ignore
> nativement les entrées de la source dont le nom commence par un point littéral) et ne serait
> donc jamais déployé.

```bash
echo "2.4.0" > ~/.local/share/chezmoi/dot_config/quickshell/caelestia/dot_upstream-version
```

Et ajouter dans `install.sh`, juste après l'étape « paquets AUR », un garde-fou :

```bash
step "contrôle de version caelestia-shell"
want=$(cat "$(chezmoi source-path)/dot_config/quickshell/caelestia/dot_upstream-version" 2>/dev/null || echo inconnu)
have=$(pacman -Q caelestia-shell 2>/dev/null | awk '{print $2}' | cut -d- -f1)
[[ $want == "$have" ]] || cat <<MSG
ATTENTION : le fork QML de ~/.config/quickshell/caelestia vise caelestia-shell $want,
mais $have est installé. Le shell risque de ne pas démarrer (API du plugin).
Voir docs/superpowers/plans/ pour la procédure de portage.
MSG
```

- [x] **Étape 6 : commit**

```bash
cd ~/.local/share/chezmoi
git add -A
git commit -m "fix(caelestia): porter le fork QML sur caelestia-shell 2.4.0

Le fork etait fige sur l'upstream 0d37255 (~v2.0.3). La reinstallation d'OS
a installe caelestia-shell 2.4.0, dont le plugin C++ a deplace ImageAnalyser
vers Caelestia.Images et supprime le module Caelestia.Internal : le shell ne
demarrait plus (barre, notifications, lanceur, verrouillage absents).

Merge 3-voies de v2.4.0 dans le fork, migration des imports du plugin et
report des 4 personnalisations (widget EasyEffects, notifs groupees,
Overview cliquable, horloge/perfs en haut de barre).

Ajoute .upstream-version (dot_upstream-version cote depot) et un garde-fou
dans install.sh pour que la prochaine derive soit signalee au lieu de
casser silencieusement."
```

---

### Tâche 10 : écarts mineurs de la réinstallation

**Fichiers :** aucun fichier du dépôt ; actions sur `$HOME`.

- [x] **Étape 1 : créer les dossiers utilisateur XDG**

Ils n'existent pas (pas de `~/Documents`, `~/Videos`, `~/Music`, ni `~/.config/user-dirs.dirs`) :

```bash
xdg-user-dirs-update
ls ~ && cat ~/.config/user-dirs.dirs
```
Attendu : les dossiers standard existent et `user-dirs.dirs` est créé.

- [x] **Étape 2 : garnir `~/Pictures/wallpapers`, actuellement vide**

`install.sh` crée le dossier mais ne le remplit pas ; `waypaper --restore` et `awww` n'ont donc rien à afficher.

```bash
cp /etc/xdg/quickshell/caelestia/assets/wallpaper.webp ~/Pictures/wallpapers/
ls -l ~/Pictures/wallpapers/
```

- [x] **Étape 3 : ajouter la création du dossier XDG à `install.sh`**

Pour que la prochaine réinstallation n'ait pas le même trou, dans `install.sh`, à côté du `mkdir -p ~/Pictures/wallpapers` existant :

```bash
xdg-user-dirs-update
```

- [x] **Étape 4 : commit**

```bash
cd ~/.local/share/chezmoi
git add install.sh
git commit -m "fix(install): creer les dossiers utilisateur XDG"
```
