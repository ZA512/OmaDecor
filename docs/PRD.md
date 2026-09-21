# PRD — OmaDecor

**Version :** 0.2
**Date :** 20 septembre 2026
**Statut :** Architecture de décoration approuvée
**Nom de travail :** OmaDecor

---

## 1. Vision

OmaDecor est un plugin Omarchy destiné à enrichir visuellement les fenêtres Hyprland sans remplacer le compositor ni modifier en profondeur la configuration de l’utilisateur.

Le produit regroupe trois fonctions indépendantes :

1. **Window Decorations** — décorations visuelles autour des fenêtres.
2. **Window HUD** — informations contextuelles affichées autour de la fenêtre active.
3. **Window Effects** — effets graphiques liés au cycle de vie des fenêtres : ouverture, fermeture, déplacement, resize, focus, changement de workspace, etc.

Les trois fonctions doivent pouvoir être activées ou désactivées indépendamment.

OmaDecor doit privilégier :

* la stabilité ;
* une dégradation propre lorsqu’une dépendance n’est pas disponible ;
* la réversibilité ;
* l’absence de modification intrusive d’Omarchy ;
* une architecture modulaire permettant d’ajouter ensuite de nouveaux styles de décoration, HUD et effets.

---

# 2. Principe architectural

OmaDecor **ne doit pas réimplémenter le moteur de shaders de Hyprland**.

Pour les effets graphiques, il s’appuie sur le projet externe **HyprWindowShade**, développé par ManofJELLO.

HyprWindowShade fournit actuellement les shaders par fenêtre ainsi que des événements spécifiques tels que :

* open ;
* close ;
* move ;
* resize ;
* workspace ;
* fullscreen enter/exit ;
* float/tile ;
* urgent ;
* focus ;
* unfocus ;
* état active/inactive.

Il supporte également des règles fallback `_default`, la composition de plusieurs shaders et l’exclusion automatique du fullscreen par défaut.

Le code actuel de HyprWindowShade s’identifie lui-même comme :

* nom : `HyprWindowShade` ;
* auteur : `ManofJELLO` ;
* version : `1.4` dans l’état actuel du dépôt ;
* description : `Native CShader Injection (v0.56)`.

Cette information est exposée à Hyprland et peut être récupérée depuis la liste des plugins chargés.

OmaDecor constitue donc la couche :

**GUI + configuration + compatibilité + décoration + HUD + orchestration des effets.**

---

# 3. Contrainte fondamentale : dépendance externe

## 3.1 HyprWindowShade n'est pas embarqué

HyprWindowShade doit rester un projet externe.

Ne pas :

* forker HyprWindowShade dans OmaDecor ;
* copier son code dans OmaDecor ;
* modifier son binaire ;
* présenter son moteur comme une fonctionnalité développée par OmaDecor.

OmaDecor doit clairement indiquer :

> Window effects powered by HyprWindowShade
> Created by ManofJELLO
> External project — MIT License

Une section **About / Credits / Licenses** doit fournir ces informations.

---

# 4. Installation et dépendances

L’installation standard d’un plugin Omarchy clone et valide le dépôt, mais n’exécute volontairement ni install hook, ni installation de dépendance, ni commande `sudo`. OmaDecor doit respecter ce modèle.

Par conséquent :

## Installation OmaDecor

L’utilisateur installe normalement OmaDecor via le système de plugins Omarchy.

OmaDecor doit utiliser le système de plugins actuel d’Omarchy :

```text
manifest.json
kinds:
  - service
  - panel
```

Le `service` exécute le HUD, l’interface et l’orchestration. La décoration s’exécute dans le plugin natif Hyprland.

Le `panel` fournit l’interface de configuration.

Le service doit rester chargé tant que le plugin est activé.

Omarchy exécute actuellement les plugins tiers à l’intérieur du processus Quickshell principal ; OmaDecor ne doit donc **jamais lancer une seconde instance autonome de Quickshell**.

---

# 5. Installation de HyprWindowShade

OmaDecor **ne doit pas installer automatiquement HyprWindowShade**.

Lorsque l’utilisateur ouvre l’onglet Effects, OmaDecor vérifie sa présence.

### État : absent

Afficher :

> Effects engine not installed
> OmaDecor uses HyprWindowShade for GPU window effects.
> Decorations and HUD continue to work normally.

Afficher les commandes d’installation recommandées par le projet :

```bash
hyprpm add https://github.com/ManofJELLO/HyprWindowShade
hyprpm enable HyprWindowShade
```

Et rappeler que les plugins Hyprland doivent être rechargés au démarrage via `hyprpm reload`.

HyprWindowShade recommande actuellement précisément l’installation via `hyprpm`, qui le reconstruit contre les headers correspondant à la version de Hyprland utilisée.

Boutons GUI :

```text
[ Copy installation commands ]
[ Open documentation ]
[ Check again ]
```

Pas de bouton exécutant silencieusement l’installation dans le MVP.

---

# 6. Architecture fonctionnelle

```text
                         OmaDecor
                            │
          ┌─────────────────┼──────────────────┐
          │                 │                  │
     Decorations           HUD              Effects
          │                 │                  │
      Hyprland          Quickshell       HyprWindowShade
   native plugin          overlay             GLSL
          │                 │                  │
  Raised Edge always   hide / settle /       open, close,
  attached to window      reappear           move, focus…
```

Les modules doivent être totalement indépendants.

Les paramètres globaux doivent exposer :

```text
☑ Enable window decorations

☑ Enable window HUD

☑ Enable window effects
```

Désactiver Effects ne doit pas désactiver Decorations ou HUD.

L’absence de HyprWindowShade ne doit jamais empêcher OmaDecor de démarrer.

La décoration ne doit jamais suivre une fenêtre depuis Quickshell. Elle est rendue par un plugin Hyprland via l’API de décoration native. `GeometryTracker` appartient exclusivement au HUD.

---

# 7. Écran principal

Le premier écran doit donner immédiatement l’état du système.

Exemple :

```text
OmaDecor
────────────────────────────────────

WINDOW DECORATIONS       ● Enabled
Raised Edge

WINDOW HUD               ● Enabled
Active window only

WINDOW EFFECTS           ● Enabled
HyprWindowShade 1.4
Compatibility: Validated

────────────────────────────────────

System
Hyprland                 0.xx
Quickshell               0.xx
HyprWindowShade          1.4
Compatibility            ✓ Validated

[ Decorations ] [ HUD ] [ Effects ]
[ Applications ] [ Diagnostics ]
```

Les états doivent utiliser également du texte et des icônes : ne jamais dépendre uniquement de la couleur.

---

# 8. Module Decorations

## 8.1 Objectif MVP

Créer une décoration très simple mais suffisamment visible pour valider l’architecture.

Premier style :

### Raised Edge

Principe visuel :

```text
  ┌────────────────────────────┐
  │                            │
▓ │          WINDOW            │
▓ │                            │
▓ └────────────────────────────┤
▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓
```

Le haut et le côté droit utilisent la même couleur principale.

Le côté gauche et le bas utilisent une version plus sombre de cette couleur et sont légèrement plus épais.

Objectif : créer une impression très légère de volume / relief.

Exemple de paramètres :

```text
Style                  Raised Edge

Main color             Theme Accent
Light edge width       2 px
Dark edge width        5 px
Darkening              30 %

Active opacity         100 %
Inactive opacity        55 %

Corner radius          Follow Hyprland
```

La couleur sombre doit idéalement être **dérivée automatiquement** de la couleur principale.

Ne pas imposer deux couleurs manuelles à l’utilisateur pour ce premier style.

---

# 9. Architecture des styles de décoration

Ne pas coder `Raised Edge` directement dans le moteur.

Créer une abstraction native de type :

```text
DecorationStyle
    id
    name
    description
    nativeRenderer
    settingsSchema
```

Exemple :

```text
native/
    RaisedEdgeDecoration.cpp
    RaisedEdgeDecoration.hpp

decorations/styles/
    RaisedEdge.json
```

À terme, il doit être possible d’ajouter :

```text
Raised Edge
Minimal
Neon
Cyber
LCARS
Glass
Retro
Technical HUD
etc.
```

sans réintroduire de moteur de positionnement Quickshell. Les styles nécessitant du texte ou des métriques relèvent du HUD, pas de la décoration native.

---

# 10. Fenêtres décorées

Par défaut :

* décorer les fenêtres normales ;
* afficher une décoration plus visible sur la fenêtre active ;
* décoration inactive atténuée ;
* ne rien afficher sur une fenêtre fullscreen ;
* ignorer les fenêtres OmaDecor elles-mêmes ;
* pouvoir exclure des applications.

La décoration doit respecter les écrans multiples et les coordonnées logiques Hyprland.

---

# 11. Problème de synchronisation connu

Le précédent prototype a montré qu’essayer de suivre continuellement une fenêtre déplacée avec un overlay Quickshell produit une dérive perceptible.

Le MVP **ne doit pas tenter de résoudre ce problème par du polling agressif**. Le Raised Edge est désormais natif et n’utilise pas cette machine d’état. Celle-ci s’applique uniquement au HUD Quickshell.

## Machine d’état

```text
STABLE
   │
   ├─ geometry change detected
   ↓
FADING_OUT
   ↓
MOVING / RESIZING
   ↓
geometry stable
   ↓
SETTLING
   ↓
POSITION OVERLAY
   ↓
FADING_IN
   ↓
STABLE
```

Pendant un déplacement ou un resize :

* HUD masqué ;
* aucun effort pour suivre visuellement chaque pixel du mouvement.

Lorsque la géométrie est stable :

1. récupérer la nouvelle géométrie ;
2. attendre un court délai de stabilisation ;
3. repositionner le HUD ;
4. fade-in.

Valeurs initiales suggérées :

```text
fadeOut             60–100 ms
settleDelay         80–150 ms
fadeIn              120–180 ms
```

Ces paramètres doivent rester internes dans le MVP mais l’architecture doit permettre de les exposer ultérieurement.

---

# 12. Détection des changements de géométrie du HUD

Utiliser au maximum l’intégration native :

```qml
import Quickshell.Hyprland
```

Quickshell expose notamment :

* `activeToplevel`;
* `toplevels`;
* `rawEvent`;
* `eventSocketPath`;
* `requestSocketPath`;
* `refreshToplevels()` ;
* `HyprlandToplevel.lastIpcObject`.

`lastIpcObject` peut fournir les informations retournées par Hyprland après rafraîchissement.

Hyprland fournit également un flux événementiel via `.socket2.sock`, mais ce flux ne fournit pas actuellement d’événement générique « interactive resize started/ended » ou « window geometry changed » pour chaque mouvement.

Le HUD doit donc implémenter une stratégie hybride :

* événements Hyprland pour open/close/focus/workspace/fullscreen ;
* rafraîchissement géométrique contrôlé ;
* détection de stabilité ;
* **pas de lancement de `hyprctl` à 60 Hz** ;
* aucun polling externe permanent quand rien ne change.

Le résultat recherché n’est pas :

> suivre parfaitement la fenêtre.

Le résultat recherché est :

> ne jamais laisser apparaître un HUD manifestement désynchronisé.

C’est une différence essentielle.

---

# 13. Module HUD

Le HUD du MVP concerne **la fenêtre active uniquement**.

## Haut gauche

Afficher :

```text
Application
Window title
Workspace
```

Exemple :

```text
Firefox
GitHub — OmaDecor
WS 3
```

## Bas droite

Afficher :

```text
CPU
Memory
Network
```

Dans le MVP, ces métriques peuvent être **globales au système**.

Les métriques par processus/application sont hors scope du MVP.

---

# 14. Comportement HUD

Fenêtre stable :

```text
fade-in
HUD visible
```

Déplacement / resize / changement important de layout :

```text
fade-out
HUD hidden
```

Nouvelle géométrie stable :

```text
reposition
fade-in
```

Changement de focus :

```text
old HUD fade-out
resolve new window
position new HUD
new HUD fade-in
```

Fullscreen :

```text
HUD hidden
```

Le HUD ne doit jamais capter les clics ou empêcher l’interaction avec la fenêtre sous-jacente.

---

# 15. Module Effects

Les Effects utilisent exclusivement HyprWindowShade comme moteur.

Le GUI doit présenter les événements disponibles sous forme lisible.

Exemple :

| Event     | Effect   | State |
| --------- | -------- | ----- |
| Open      | Dissolve | On    |
| Close     | Fire     | On    |
| Move      | Wobble   | On    |
| Resize    | Wobble   | On    |
| Focus     | Glow     | On    |
| Unfocus   | None     | Off   |
| Workspace | Warp     | On    |
| Urgent    | Pulse    | On    |

Prévoir dès le modèle de données les événements :

```text
open
close
move
resize
workspace
fullscreenEnter
fullscreenExit
float
tile
focus
unfocus
urgent
```

Tous ne doivent pas obligatoirement avoir un shader disponible dès le MVP.

---

# 16. Catalogue de shaders

Un shader doit posséder des métadonnées.

Modèle :

```json
{
  "id": "fire",
  "name": "Fire",
  "source": "external",
  "pack": "example-pack",
  "author": "...",
  "license": "...",
  "compatibleEvents": [
    "open",
    "close"
  ]
}
```

Ne jamais proposer un shader `open/close` comme shader `move` simplement parce que le fichier GLSL existe.

Le moteur doit filtrer les effets selon leur compatibilité avec l’événement.

---

# 17. Packs externes

OmaDecor doit pouvoir gérer des **shader packs**.

Architecture :

```text
ShaderPack
    id
    name
    path
    origin
    author
    license
    version
    effects[]
```

Le projet `jbuck95/Hyprland-Shader` constitue actuellement un exemple intéressant : il contient maintenant 55 paires de shaders open/close et documente une licence MIT ainsi que des attributions tierces.

Mais :

**ne pas redistribuer automatiquement ce pack dans OmaDecor pour le MVP.**

Le dépôt indique que plusieurs shaders proviennent ou sont adaptés d’autres sources, dont liixini/shaders et ShaderToy. Les obligations d’attribution doivent être étudiées avant toute redistribution.

OmaDecor peut en revanche détecter un pack installé séparément.

---

# 18. Shaders OmaDecor

Il est acceptable d’inclure quelques shaders écrits spécifiquement pour OmaDecor.

MVP recommandé :

```text
simple-fade-open
simple-fade-close
soft-focus-pulse
simple-wobble
```

Ils servent principalement :

* aux tests ;
* à garantir quelques effets disponibles ;
* à ne pas dépendre immédiatement d’une collection tierce.

Ils doivent être clairement identifiés :

```text
Source: OmaDecor
```

---

# 19. Configuration HyprWindowShade

OmaDecor doit générer ses propres règles Hyprland.

Toutes les règles doivent avoir un préfixe identifiable :

```text
omadecor-effects-*
```

Exemple conceptuel :

```lua
hl.window_rule({
    name  = "omadecor-effects-close-default",
    match = { class = ".*" },
    tag   = "+shader_close_default:/path/fire_close.glsl",
})
```

OmaDecor ne doit jamais modifier ou supprimer les règles HyprWindowShade créées manuellement par l’utilisateur.

Il ne gère que ses propres règles.

---

# 20. Fichier d’intégration Hyprland

Ne pas modifier automatiquement tout `hyprland.lua`.

Créer un fichier appartenant exclusivement à OmaDecor.

Exemple :

```text
~/.config/hypr/omadecor.lua
```

L’utilisateur ajoute **une fois** dans sa configuration Hyprland l’import requis.

Le README doit expliquer précisément cette étape.

Après cela, OmaDecor est libre de régénérer uniquement `omadecor.lua`.

L’écriture doit être :

* atomique ;
* résistante à une interruption ;
* refusée si la cible est un lien symbolique inattendu ;
* limitée à un chemin appartenant à OmaDecor.

Ne jamais écraser arbitrairement :

```text
hyprland.lua
bindings.lua
windows.lua
```

ou les autres fichiers de l’utilisateur.

---

# 21. Application des changements

Les modifications concernant :

* Decorations ;
* HUD ;

doivent idéalement être appliquées immédiatement.

Les modifications concernant les règles HyprWindowShade peuvent nécessiter une régénération de `omadecor.lua` puis un reload Hyprland.

Le GUI doit dans ce cas utiliser :

```text
Changes pending

[ Apply ]
```

afin d’éviter dix reloads pendant que l’utilisateur modifie plusieurs combobox.

---

# 22. Exclusions et overrides par application

Créer un onglet :

# Applications

Une application peut avoir :

```text
Application: Jellyfin
Class: org.jellyfin.JellyfinDesktop

☑ Disable decorations
☑ Disable HUD
☑ Disable effects
```

Ou seulement certains effets :

```text
Open        Global
Close       None
Move        None
Resize      None
Focus       Global
```

Une application peut également remplacer un effet global :

```text
Application: kitty

Open        Matrix
Close       Fire
Move        Wobble
Focus       Glow
```

Hiérarchie :

```text
GLOBAL
   ↓
APPLICATION OVERRIDE
   ↓
APPLICATION EXCLUSION
```

L’exclusion gagne toujours.

---

# 23. Sélection d’une application

Éviter d’obliger l’utilisateur à connaître `class`.

Prévoir :

```text
[ Add application ]

Running applications:

Firefox
Kitty
Jellyfin
Steam
...
```

Afficher :

```text
Name
Class
Title
Workspace
```

Une option :

```text
Add last active window
```

est également souhaitable.

Le service peut conserver la dernière fenêtre active **hors OmaDecor** avant que le panneau de configuration prenne le focus.

---

# 24. Fullscreen

Valeur par défaut :

```text
Decorations     OFF
HUD             OFF
Effects          OFF
```

sur les fenêtres fullscreen.

C’est cohérent avec HyprWindowShade, qui désactive déjà ses shaders en fullscreen par défaut afin d’éviter notamment le coût graphique sur les jeux et vidéos.

L’utilisateur pourra éventuellement modifier ce comportement dans une version ultérieure.

---

# 25. Compatibilité HyprWindowShade

Cette fonction est importante.

OmaDecor doit maintenir une **compatibility matrix**.

Exemple conceptuel :

```json
{
  "schemaVersion": 1,
  "validated": [
    {
      "hyprlandVersion": "x.y.z",
      "hyprlandAbi": "...",
      "engine": "HyprWindowShade",
      "engineVersion": "1.4",
      "engineFingerprint": "...",
      "status": "validated"
    }
  ]
}
```

Ne jamais ajouter une combinaison à `validated` sans test réel.

---

# 26. Fingerprint

Construire une abstraction :

```text
EngineFingerprint
```

qui essaie de déterminer :

```text
Hyprland version
Hyprland commit
Hyprland ABI
HyprWindowShade version
HyprWindowShade author
HyprWindowShade description
HyprWindowShade build/commit/hash si disponible
```

`hyprctl plugin list` expose normalement au minimum :

```text
name
author
version
description
```

et Hyprland expose lui-même version/commit/ABI.

Ne jamais prétendre reconnaître exactement un build lorsque seul le numéro de version est disponible.

Prévoir deux niveaux :

```text
VERSION VALIDATED
EXACT BUILD VALIDATED
```

si nécessaire.

---

# 27. États de compatibilité

Le moteur Effects peut être dans l’un des états :

```text
NOT_INSTALLED
INSTALLED_NOT_LOADED
VALIDATED
UNTESTED
DEGRADED
BLOCKED
ERROR
```

## VALIDATED

Afficher :

```text
✓ HyprWindowShade 1.4
Validated with this Hyprland version
```

Effects disponibles normalement.

## UNTESTED

Exemple :

```text
⚠ HyprWindowShade has changed

This version has not yet been validated with OmaDecor.

Decorations and HUD are unaffected.
Window effects have been temporarily suspended.

[ Test effects anyway ]
[ Keep effects disabled ]
```

Il s’agit précisément du comportement attendu après une mise à jour inconnue.

---

# 28. Safe suspension

OmaDecor doit distinguer :

```text
user.effectsEnabled
```

et :

```text
runtime.effectsAllowed
```

Exemple :

```text
user.effectsEnabled = true
runtime.effectsAllowed = false
```

signifie :

> l’utilisateur souhaite les effets, mais OmaDecor les suspend temporairement à cause d’une combinaison non validée.

Cela évite de perdre son réglage.

Lorsque la combinaison devient validée après une mise à jour d’OmaDecor :

```text
runtime.effectsAllowed = true
```

et les effets peuvent reprendre.

Notification :

> HyprWindowShade compatibility validated
> Window effects are available again.

Ne notifier qu’une fois par changement de statut.

---

# 29. Override utilisateur

Pour `UNTESTED` :

```text
[ Test anyway ]
```

doit être disponible.

Cet override est associé **au fingerprint exact**.

Une nouvelle modification de :

* Hyprland ;
* HyprWindowShade ;

annule automatiquement cet override et déclenche une nouvelle validation.

---

# 30. Effets dégradés individuellement

La compatibility matrix doit pouvoir signaler un shader spécifique.

Exemple :

```json
{
  "effect": "fire",
  "event": "close",
  "status": "broken",
  "reason": "Rendering artifact with HyprWindowShade x.y"
}
```

États :

```text
OK
UNTESTED
DEGRADED
BROKEN
```

Dans le GUI :

```text
Fire                    ✓
Dissolve                ✓
Voronoi Shatter         ⚠ degraded
Matrix                   ✕ temporarily disabled
```

Si un shader actuellement sélectionné devient `BROKEN` :

* ne pas faire planter OmaDecor ;
* désactiver uniquement cet événement ;
* afficher une explication ;
* conserver le choix utilisateur afin de pouvoir le restaurer plus tard.

Message :

> Matrix Close is temporarily disabled because it is not compatible with the detected HyprWindowShade version.
> Your preference has been preserved.

---

# 31. Diagnostics

Prévoir une page Diagnostics donnant au minimum :

```text
OmaDecor version
Omarchy version
Quickshell version
Hyprland version
Hyprland commit / ABI
HyprWindowShade installed
HyprWindowShade loaded
HyprWindowShade version
Compatibility status

Decorations status
HUD status
Effects status

Detected monitors
Detected windows
Generated config path
Last config generation
Last error
```

Ajouter :

```text
[ Copy diagnostics ]
```

La sortie doit être facilement collable dans une issue GitHub.

Ne jamais inclure :

* variables d’environnement complètes ;
* tokens ;
* secrets ;
* contenu arbitraire du home ;
* données personnelles inutiles.

---

# 32. Sources et crédits

Créer une page explicite :

```text
OmaDecor
Window decoration, HUD and configuration manager

Window effects engine
HyprWindowShade
Author: ManofJELLO
License: MIT
External project

Shader packs
...
```

Chaque shader externe doit exposer autant que possible :

```text
Effect
Pack
Author
Original author
License
Source
```

La provenance doit également pouvoir apparaître directement dans la fiche de l’effet.

---

# 33. Arborescence cible

Structure suggérée :

```text
manifest.json
README.md
LICENSE

Panel.qml
Service.qml

core/
    ConfigStore.qml
    CompatibilityManager.qml
    Diagnostics.qml
    HyprlandState.qml
    GeometryTracker.qml
    ApplicationRegistry.qml

native/
    Makefile
    main.cpp
    RaisedEdgeDecoration.cpp
    RaisedEdgeDecoration.hpp

decorations/styles/
    RaisedEdge.json

hud/
    HudHost.qml
    HudTopLeft.qml
    HudBottomRight.qml

effects/
    EffectsManager.qml
    EngineDetector.qml
    ShaderCatalog.qml
    ShaderPackRegistry.qml
    RuleGenerator.js

effects/shaders/
    simple-fade-open.glsl
    simple-fade-close.glsl
    soft-focus-pulse.glsl
    simple-wobble.glsl

compatibility/
    hyprwindowshade.json

ui/
    OverviewPage.qml
    DecorationsPage.qml
    HudPage.qml
    EffectsPage.qml
    ApplicationsPage.qml
    DiagnosticsPage.qml
    AboutPage.qml

tests/
```

La structure exacte peut évoluer, mais les responsabilités doivent rester séparées.

---

# 34. Configuration

Modèle logique :

```json
{
  "decorations": {
    "enabled": true,
    "style": "raised-edge",
    "settings": {}
  },

  "hud": {
    "enabled": true,
    "scope": "active-window",
    "topLeft": true,
    "bottomRight": true
  },

  "effects": {
    "enabled": true,
    "events": {
      "open": "simple-fade",
      "close": "fire",
      "move": "simple-wobble",
      "resize": "simple-wobble",
      "focus": "soft-focus-pulse"
    }
  },

  "applications": []
}
```

Utiliser en priorité le mécanisme de settings proposé aux plugins Omarchy.

Ne jamais modifier directement `shell.json` si l’API Omarchy permet la mutation via son facade.

Si les structures complexes nécessaires ne peuvent pas raisonnablement être stockées par l’API du host, utiliser un fichier appartenant à OmaDecor, mais documenter cette décision.

Décision M1 : l’état utilisateur complexe est stocké dans `~/.config/omadecor/config.json`, versionné par `schemaVersion`, validé avant usage et écrit atomiquement. Les valeurs invalides ne sont jamais interpolées dans une commande. Decorations est activé par défaut ; HUD et Effects restent désactivés tant que leurs implémentations ne sont pas livrées.

---

# 35. Sécurité

OmaDecor est destiné au Marketplace Omarchy.

Le développement doit donc respecter dès le début les contraintes de sécurité du Marketplace.

Notamment :

* aucun `curl | sh` ;
* aucun téléchargement suivi d’une exécution non vérifiée ;
* aucun `sudo` ;
* aucun `pkexec` ;
* aucun install hook ;
* aucune modification de sudoers ;
* aucune exécution de dépôt Git distant non pinné ;
* aucune commande construite depuis une valeur utilisateur sans validation ;
* éviter les interpréteurs invoqués uniquement via `$PATH` ;
* utiliser des chemins d’exécutables déterministes lorsque des processus externes sont indispensables ;
* aucune écriture destructive hors des chemins appartenant explicitement à OmaDecor.

Les règles actuelles du Marketplace signalent explicitement les chaînes de téléchargement/exécution non pinnées et les builds Git distants non pinnés.

Préférer les API Quickshell/Hyprland natives aux commandes shell.

---

# 36. Performance

Objectifs :

### Au repos

Pas de polling intensif.

Pas de processus `hyprctl` lancé continuellement.

Pas de redraw permanent des overlays si rien ne change.

### Pendant une interaction

Masquer le HUD plutôt que tenter de suivre une fenêtre à chaque frame. La décoration native reste attachée via le pipeline Hyprland.

### Shaders

Éviter de charger inutilement plusieurs couches permanentes.

HyprWindowShade indique qu’un shader déclarant `time` force un redraw continu, contrairement à un shader statique. Le catalogue doit donc pouvoir signaler les effets continus potentiellement coûteux.

Exemple :

```text
Performance cost
● Low
● Medium
● High
```

Ce classement peut rester manuel dans le MVP.

---

# 37. Multi-monitor

Tester impérativement :

* un écran ;
* deux écrans ;
* résolutions différentes ;
* positions négatives ;
* changement d’écran d’une fenêtre ;
* workspace sur écran différent ;
* scaling différent si disponible.

Toutes les coordonnées doivent être traitées comme coordonnées logiques du compositor, jamais supposées égales aux pixels physiques.

---

# 38. Gestion des erreurs

Une erreur dans un module ne doit pas désactiver l’ensemble de OmaDecor.

Exemples :

```text
HyprWindowShade missing
→ Effects unavailable
→ Decorations OK
→ HUD OK
```

```text
CPU metric unavailable
→ Hide CPU metric
→ HUD remains available
```

```text
Decoration overlay error
→ Disable decorations
→ HUD remains available
→ Effects remain available
```

Le service doit tendre vers une architecture **fail-soft**.

---

# 39. UX des erreurs

Ne pas afficher :

```text
ERROR CODE 74
shader dispatch failed
```

Afficher plutôt :

> Window effects are currently unavailable.

Puis :

```text
Details
HyprWindowShade is installed but not loaded.
```

Et fournir l’action pertinente.

Les détails techniques restent accessibles dans Diagnostics.

---

# 40. Non-objectifs MVP

Ne pas essayer immédiatement de construire :

* un éditeur GLSL ;
* un marketplace de shaders ;
* un système automatique de téléchargement des packs ;
* des métriques CPU/RAM par processus ;
* des décorations interactives avec boutons close/maximize ;
* une synchronisation du HUD overlay à 120 FPS ;
* un remplacement complet des décorations Hyprland ;
* un moteur shader concurrent de HyprWindowShade ;
* des effets fullscreen pour les jeux ;
* une architecture réseau ou télémétrique.

---

# 41. Étapes d’implémentation

## Milestone 0 — Technical Spike

Avant de construire le GUI complet :

1. créer un plugin Omarchy minimal `service + panel` ;
2. construire un plugin de décoration natif pour l’ABI Hyprland exacte ;
3. dessiner Raised Edge avec `IHyprWindowDecoration` ;
4. supprimer toute surface de décoration Quickshell ;
5. tester move/resize interactif et animé ;
6. tester tiled/floating/workspace/fullscreen ;
7. mesurer et documenter les coûts de maintenance ABI ;
8. conserver GeometryTracker uniquement pour le futur HUD.

### Critère GO

La décoration reste attachée à la fenêtre pendant toute interaction et animation, sans détection, masquage ni délai de stabilisation côté Quickshell.

---

# 42. Milestone 1 — Plugin Core

Implémenter :

```text
manifest
service
settings panel
ConfigStore
HyprlandState
Diagnostics
module toggles
```

Aucun effet graphique complexe.

---

# 43. Milestone 2 — Decorations

Implémenter :

```text
NativeDecorationRegistry
RaisedEdge
active/inactive
fullscreen exclusion
application exclusion
```

Valider multi-monitor.

Décision M2 : les styles natifs sont déclarés par `NativeDecorationRegistry` et un schéma de métadonnées séparé du renderer. Raised Edge suit par défaut `qs.Commons.Color.accent`, avec une opacité inactive configurable et un mode couleurs manuelles. Les exclusions applicatives sont stockées comme règles structurées puis traduites en correspondances exactes de classe pour le plugin natif. La validation locale mono-écran ne clôt pas la matrice matérielle multi-écran.

---

# 44. Milestone 3 — HUD

Implémenter :

```text
title
application
workspace

CPU
RAM
network

fade-out on movement
fade-in when stable
```

Décision M3 : le HUD utilise une surface layer-shell passive par écran avec une région d’entrée vide. Seule la surface correspondant au moniteur de la géométrie stable est affichée. Les métriques globales lisent directement `/proc` toutes les deux secondes lorsque le module est actif ; aucune commande externe récurrente n’est lancée. Les exclusions HUD sont indépendantes des exclusions Decorations et réveillent le tracker lorsqu’elles changent.

---

# 45. Milestone 4 — HyprWindowShade integration

Implémenter :

```text
EngineDetector
CompatibilityManager
Effects master toggle
status GUI
installation guidance
safe suspension
```

Aucun téléchargement automatique.

---

# 46. Milestone 5 — Effects configuration

Implémenter :

```text
ShaderCatalog
event → shader mapping
global effects
per-application override
application exclusion
omadecor.lua generation
Apply workflow
```

Tester au minimum :

```text
open
close
move
resize
focus
unfocus
workspace
```

---

# 47. Milestone 6 — Compatibility lifecycle

Implémenter :

```text
fingerprint detection
validated status
untested status
user override
effect-specific broken/degraded status
notifications
diagnostics
```

Simuler artificiellement un changement de version pour vérifier le comportement.

---

# 48. Milestone 7 — Marketplace readiness

Avant publication :

```text
omarchy plugin validate
```

Puis revue :

* manifest ;
* permissions ;
* Process utilisés ;
* filesystem writes ;
* dépendances ;
* README ;
* LICENSE ;
* THIRD_PARTY_NOTICES ;
* diagnostic output ;
* désinstallation.

L’installation Marketplace exige actuellement notamment un dépôt Git public contenant manifest, README et licence, suivi d’une validation sur un commit précis.

---

# 49. Critères d’acceptation MVP

Le MVP est considéré terminé lorsque :

* OmaDecor s’installe comme plugin Omarchy standard ;
* Decorations/HUD fonctionnent sans HyprWindowShade ;
* les trois modules sont activables indépendamment ;
* `Raised Edge` fonctionne ;
* la décoration native reste synchronisée pendant les mouvements/resizes ;
* les overlays HUD ne capturent pas les clics ;
* le HUD disparaît pendant les mouvements/resizes et revient après stabilisation ;
* le HUD fonctionne sur la fenêtre active ;
* fullscreen masque HUD et décoration ;
* HyprWindowShade absent est détecté proprement ;
* HyprWindowShade chargé est détecté ;
* sa version est affichée ;
* une combinaison non validée entraîne un warning et une safe suspension ;
* l’utilisateur peut explicitement tester une version non validée ;
* les effets sont configurables par événement ;
* une application peut être exclue ;
* une application peut avoir des overrides ;
* OmaDecor ne détruit aucune configuration HyprWindowShade existante ;
* toutes les règles générées appartiennent explicitement à OmaDecor ;
* la provenance de HyprWindowShade est visible dans l’interface ;
* Diagnostics produit un rapport exploitable ;
* l’arrêt d’un module n’affecte pas les autres ;
* désinstaller OmaDecor ne laisse pas le desktop dans un état inutilisable.

---

# 50. Principes à respecter pendant le développement

**Ne jamais réintroduire une décoration Quickshell qui poursuit la géométrie d’une fenêtre.**

**Valider GeometryTracker pour le HUD seulement.**

**Ne pas reconstruire HyprWindowShade.**

**Ne pas transformer OmaDecor en gestionnaire de paquets.**

**Ne jamais cacher à l’utilisateur qu’un composant externe est utilisé.**

**Préférer désactiver temporairement une fonction incertaine plutôt que dégrader tout le desktop.**

**Toute dépendance doit avoir un mode absent propre.**

**Toute fonctionnalité graphique doit pouvoir être désactivée immédiatement.**

**Toute configuration générée doit pouvoir être supprimée sans casser Omarchy.**

---

# 51. Prochaine tâche Codex

Terminer le **Milestone 0 — Native Raised Edge Spike** :

1. valider visuellement déplacement et resize interactifs ;
2. valider les animations de workspace ;
3. tester sur plusieurs écrans, dont coordonnées négatives et échelles mixtes ;
4. stabiliser le chargement via `hyprpm` et les commit pins ;
5. vérifier qu’aucun host de décoration Quickshell n’est réintroduit ;
6. documenter les résultats finaux dans `TECHNICAL_SPIKE.md`.

**Ne pas commencer l’intégration HyprWindowShade avant que ce spike soit validé.**

Le premier objectif n’est pas de produire un beau plugin.

Le premier objectif est de démontrer que la décoration native est stable et maintenable. GeometryTracker sera ensuite validé séparément pour le HUD.

Une fois ce point validé, poursuivre les milestones dans l’ordre.
