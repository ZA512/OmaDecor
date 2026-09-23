# PRD — OmaDecor Effects Platform

**Version :** 0.1
**Statut :** Architecture / implementation planning
**Produit parent :** OmaDecor
**Périmètre :** Window Effects uniquement

---

# 1. Objet de ce document

Ce PRD remplace la conception précédente dans laquelle OmaDecor considérait essentiellement HyprWindowShade et son catalogue de shaders comme « le système d'effets ».

La nouvelle direction est :

> **OmaDecor doit être une plateforme de gestion d'effets de fenêtres et de packs, indépendante du moteur d'exécution sous-jacent.**

HyprWindowShade reste, à court terme, le backend privilégié pour Hyprland.

Il ne doit cependant pas devenir l'API publique ou le modèle de données d'OmaDecor.

L'objectif à long terme est de pouvoir exploiter plusieurs écosystèmes d'effets existants :

* shaders natifs OmaDecor ;
* shaders compatibles HyprWindowShade ;
* shaders Niri adaptés par une compatibility layer ;
* effets provenant de Burn My Windows lorsque leur licence et leur architecture le permettent ;
* autres packs communautaires compatibles.

---

# 2. Motivation

Les premiers tests avec des collections de shaders destinées à HyprWindowShade ont démontré que :

* le moteur fonctionne ;
* le nombre d'effets disponible peut être important ;
* la qualité visuelle des shaders est très variable ;
* certains effets nommés `Fire`, `Glass`, etc. sont loin du niveau visuel obtenu avec Burn My Windows.

Le problème principal n'est donc pas nécessairement le moteur HyprWindowShade.

Le problème est :

> **la qualité, la provenance, la configuration et la compatibilité des effets disponibles.**

Burn My Windows démontre qu'un fragment shader limité au rectangle d'une fenêtre peut produire des animations très convaincantes.

Il n'est donc pas nécessaire de reproduire les particules historiques de Compiz ni de dessiner à l'extérieur de la fenêtre pour atteindre l'objectif visuel d'OmaDecor.

---

# 3. État actuel de l'écosystème

## HyprWindowShade

HyprWindowShade est actuellement un plugin Hyprland capable d'appliquer des shaders individuels aux fenêtres.

Il prend notamment en charge :

```text
always
active
inactive
floating
tiled

open
close

move
resize
workspace

fullscreen-enter
fullscreen-exit

float
tile

urgent

focus
unfocus
```

Il fournit notamment aux shaders :

```text
tex
progress
seed

surface_size

velocity
size_velocity

peak_velocity
peak_size_velocity

move_delta
move_remaining
size_delta

is_active
is_floating
is_fullscreen

is_moving
is_resizing
is_dragging

window_box
window_rect

anim_kind
curve
duration
```

Il supporte également le stacking de shaders et des animations distinctes par événement.

Cela en fait actuellement une excellente couche d'exécution pour OmaDecor.

---

# 4. Hyprland natif : évolution à surveiller

Une Pull Request Hyprland existe actuellement pour ajouter des animations open/close basées sur des shaders.

Cette proposition expose notamment :

```text
surface texture
coordinates
surface size
progress
randomSeed
```

et indique explicitement viser une compatibilité proche des shaders Niri.

La PR est actuellement toujours en état Draft et ne doit donc pas être considérée comme disponible.

Conséquence architecturale :

> OmaDecor ne doit jamais exposer directement HyprWindowShade comme son API publique.

À terme :

```text
                     OmaDecor
                        │
                 Effects Platform
                        │
             ┌──────────┴──────────┐
             │                     │
      HyprWindowShade       Hyprland Native
         backend               backend
```

doit être possible.

Les packs d'effets ne doivent pas nécessiter de changement si le backend évolue.

---

# 5. Niri comme format d'inspiration

Niri possède nativement des shaders personnalisés pour :

```text
window-open
window-close
```

avec un contrat GLSL relativement simple.

Niri fournit notamment aux shaders des helpers liés :

* à la texture ;
* aux coordonnées ;
* à la progression ;
* à un random seed.

Ce support a créé un écosystème communautaire important d'animations.

L'intérêt pour OmaDecor n'est pas d'adopter Niri comme compositor.

L'intérêt est :

> **le format d'effets Niri constitue une excellente source d'effets portables.**

---

# 6. Preuve qu'une compatibility layer est réaliste

Le projet `mj0x0/kwin-niri-shaders-port` a déjà démontré qu'il n'est pas nécessaire de porter manuellement chaque shader Niri.

Il utilise un shim qui fournit aux shaders Niri les fonctions attendues :

```text
niri_clamped_progress
niri_random_seed
niri_tex
niri_geo_to_tex
```

et adapte les différences de coordonnées et de pipeline.

Grâce à cette approche, le projet génère automatiquement 31 ports supplémentaires à partir d'une compatibility layer commune.

C'est un modèle architectural important pour OmaDecor.

L'objectif n'est pas :

```text
port shader 1
port shader 2
port shader 3
...
port shader 50
```

L'objectif est :

```text
source shader
      │
      ▼
compatibility adapter
      │
      ▼
OmaDecor normalized shader
      │
      ▼
backend
```

---

# 7. Burn My Windows

Burn My Windows doit être considéré comme l'une des références visuelles principales du projet.

Il existe actuellement pour GNOME ainsi que pour KWin/Plasma et propose notamment des effets tels que :

```text
Fire
Incinerate
Doom
Energize
Hexagon
Portal
Glide
TV
Glitch
Wisps
Aura Glow
RGB Warp
etc.
```

Les effets KWin sont fournis officiellement par le projet Burn My Windows.

OmaDecor ne doit pas masquer leur provenance.

Lorsqu'un effet est dérivé ou porté de BMW, l'interface doit clairement afficher :

```text
Original project
Burn My Windows

Original author
Simon Schneegans / contributors

Port
OmaDecor compatibility layer

License
GPL-3.0
```

---

# 8. Licence Burn My Windows

Burn My Windows est distribué sous GPL-3.0.

OmaDecor peut utiliser, porter et modifier les shaders GPL sous réserve de respecter cette licence.

Afin d'éviter toute confusion de licence entre OmaDecor et des effets tiers, les effets dérivés de BMW doivent être distribués comme un **pack distinct**.

Architecture recommandée :

```text
OmaDecor
MIT
│
├── GUI
├── EffectsManager
├── backends
└── compatibility layers


OmaDecor BMW Effects Pack
GPL-3.0
│
├── Fire
├── Incinerate
├── Doom
├── ...
├── LICENSE
└── CREDITS
```

Ne pas présenter les effets BMW comme des créations OmaDecor.

La provenance et la licence doivent être conservées dans les métadonnées de chaque effet.

---

# 9. PlasmaZones comme référence architecturale

Le projet PlasmaZones / Phosphor possède actuellement une architecture particulièrement intéressante pour OmaDecor.

Un effet est stocké comme un pack :

```text
my-effect/
├── metadata.json
├── effect.frag
├── zone.vert
├── buffer.frag
├── preview.png
└── helpers.glsl
```

Seuls `metadata.json` et le fragment shader principal sont obligatoires dans leur système.

Le fichier metadata contient :

```text
id
name
category
description
author
version

fragment shader
vertex shader

multipass
buffers

parameters
presets
```

et les paramètres déclarés dans les métadonnées sont automatiquement transformés en contrôles dans le GUI.

Cette philosophie doit être reprise dans OmaDecor.

Nous ne devons cependant pas copier mécaniquement le schéma PlasmaZones.

Il faut créer un schéma OmaDecor adapté à Hyprland et à nos besoins.

---

# 10. Architecture cible

```text
                              OmaDecor
                                 │
                         Effects Manager
                                 │
                    ┌────────────┴────────────┐
                    │                         │
              Effect Registry          Application Rules
                    │
                    │
          ┌─────────┼─────────┐
          │         │         │
       Native      Niri      BMW
       Packs      Packs      Packs
          │         │         │
          │    compatibility  compatibility
          │        shim          shim
          │         │             │
          └─────────┼─────────────┘
                    │
              Normalized Effect
                    │
                    ▼
              Effects Backend
                    │
           ┌────────┴────────┐
           │                 │
 HyprWindowShade        Future Hyprland
     Backend            Native Backend
```

---

# 11. Principe fondamental

Un effet OmaDecor n'est pas :

> « un shader HyprWindowShade ».

Un effet OmaDecor est :

> **un pack avec des métadonnées, des shaders, une provenance, des paramètres et des événements compatibles.**

Le backend décide ensuite comment exécuter cet effet.

---

# 12. Effect Pack

Structure proposée :

```text
effects/
└── incinerate/
    ├── effect.json
    ├── open.glsl
    ├── close.glsl
    ├── preview.webp
    ├── LICENSE
    └── CREDITS
```

Les fichiers optionnels pourront ultérieurement inclure :

```text
helpers.glsl
buffer-0.glsl
buffer-1.glsl
vertex.glsl
```

Le MVP doit cependant privilégier les shaders single-pass.

---

# 13. `effect.json`

Exemple conceptuel :

```json
{
    "schemaVersion": 1,

    "id": "bmw/incinerate",
    "name": "Incinerate",
    "version": "1.0.0",

    "description": "Heat-driven dissolve with embers and chromatic distortion.",

    "source": {
        "project": "Burn My Windows",
        "authors": [
            "Simon Schneegans",
            "Burn My Windows contributors"
        ],
        "license": "GPL-3.0",
        "type": "ported"
    },

    "compatibility": {
        "sourceFormat": "bmw",
        "events": [
            "open",
            "close"
        ]
    },

    "shaders": {
        "open": "open.glsl",
        "close": "close.glsl"
    },

    "duration": {
        "defaultMs": 900,
        "minMs": 100,
        "maxMs": 3000
    },

    "parameters": []
}
```

---

# 14. Types de provenance

Supporter explicitement :

```text
native
ported
adapted
external
```

Exemple :

```text
source.type = native
```

signifie :

> effet écrit spécifiquement pour OmaDecor.

```text
source.type = ported
```

signifie :

> adaptation technique d'un effet existant.

```text
source.type = adapted
```

signifie :

> dérivé d'un effet existant avec modifications importantes.

Le GUI doit exposer ces informations.

---

# 15. Paramètres

Les effets doivent pouvoir exposer des paramètres.

Types MVP :

```text
float
int
boolean
color
enum
```

Exemple :

```json
{
    "id": "flameSize",
    "name": "Flame Size",
    "type": "float",
    "default": 1.0,
    "min": 0.2,
    "max": 3.0,
    "step": 0.1
}
```

Le GUI OmaDecor génère automatiquement :

```text
Flame Size
────────●──────
1.0
```

Aucun contrôle spécifique à Incinerate ne doit être codé dans le GUI.

---

# 16. Presets

Un effet pourra proposer :

```json
"presets": {
    "subtle": {
        "flameSize": 0.7,
        "brightness": 0.8
    },

    "default": {
        "flameSize": 1.0,
        "brightness": 1.0
    },

    "dramatic": {
        "flameSize": 1.8,
        "brightness": 1.4
    }
}
```

Le GUI affiche :

```text
Preset

[ Subtle    ]
[ Default   ]
[ Dramatic  ]
```

---

# 17. Événements OmaDecor normalisés

OmaDecor doit exposer son propre vocabulaire d'événements :

```text
open
close

move
resize
workspace

focus
unfocus

urgent

float
tile

fullscreen-enter
fullscreen-exit
```

Ce vocabulaire ne dépend pas du backend.

---

# 18. Capability model

Un backend doit annoncer ses capabilities.

Exemple :

```json
{
    "backend": "hyprwindowshade",

    "capabilities": [
        "event.open",
        "event.close",
        "event.move",
        "event.resize",
        "event.workspace",
        "event.focus",
        "event.unfocus",
        "event.urgent",
        "event.float",
        "event.tile",
        "event.fullscreen-enter",
        "event.fullscreen-exit",

        "shader.progress",
        "shader.random-seed",
        "shader.window-texture",
        "shader.window-size",
        "shader.motion"
    ]
}
```

Un effet annonce lui aussi ses besoins.

Exemple :

```json
"requires": [
    "shader.progress",
    "shader.random-seed",
    "shader.window-texture"
]
```

OmaDecor détermine automatiquement :

```text
Compatible
Partially compatible
Incompatible
Untested
```

---

# 19. Backend HyprWindowShade

Le premier backend doit être :

```text
HyprWindowShadeBackend
```

Responsabilités :

* détecter HyprWindowShade ;
* connaître ses capabilities ;
* installer les règles OmaDecor ;
* résoudre les chemins des shaders ;
* fournir les paramètres nécessaires ;
* associer les événements OmaDecor aux tags HyprWindowShade ;
* gérer la durée ;
* gérer les exclusions ;
* fournir un diagnostic.

Le reste d'OmaDecor ne doit pas générer directement de tags :

```text
shader_close
shader_move
shader_focus
...
```

Seul le backend doit connaître cette syntaxe.

---

# 20. Futur backend Hyprland natif

Créer dès maintenant l'interface abstraite nécessaire :

```text
IEffectsBackend
```

ou équivalent.

Conceptuellement :

```text
isAvailable()
capabilities()
validateEffect()
activateEffect()
deactivateEffect()
applyConfiguration()
diagnostics()
```

Ne pas implémenter le backend natif aujourd'hui.

Il doit simplement être possible d'en ajouter un plus tard sans modifier :

* le catalogue ;
* le GUI ;
* les règles utilisateur ;
* les packs d'effets.

---

# 21. Niri Compatibility Layer

Créer :

```text
NiriCompatibility
```

Objectif :

permettre d'utiliser certains shaders Niri sans les réécrire entièrement.

Le spike doit étudier notamment la traduction de :

```text
niri_clamped_progress
niri_random_seed
niri_tex
niri_geo_to_tex
```

vers le contrat fourni par HyprWindowShade.

Le projet `kwin-niri-shaders-port` constitue la référence d'architecture.

Il démontre qu'un shim relativement petit peut adapter de nombreux shaders.

---

# 22. BMW Compatibility Layer

Créer séparément :

```text
BMWCompatibility
```

Ne pas supposer que BMW utilise exactement le même pipeline que Niri.

Étudier :

* shaders GNOME ;
* ports KWin officiels ;
* adaptations PlasmaZones ;
* hyprfx.

Le but est d'identifier le contrat minimal commun nécessaire.

---

# 23. hyprfx

Le projet `xhos/hyprfx` doit être étudié.

Il constitue déjà une tentative de port de Burn My Windows vers Hyprland.

Il contient actuellement notamment :

```text
Aura Glow
Broken Glass
Blur
Glide
```

et son auteur indique explicitement que les shaders sont principalement adaptés de Burn My Windows. Le projet est GPL-3.0.

Ne pas reprendre son architecture automatiquement.

L'étudier afin de comprendre :

```text
BMW → Hyprland
```

et identifier les difficultés déjà résolues.

---

# 24. PlasmaZones comme référence produit

Le GUI Effects d'OmaDecor doit s'inspirer conceptuellement des bonnes idées déjà présentes dans PlasmaZones :

```text
effect gallery
preview
categories
metadata
parameters
presets
pack loading
user-installed packs
hot reload
```

PlasmaZones expose déjà dans ses métadonnées des paramètres `float`, `int`, `bool`, `color`, `image`, ainsi que des presets.

OmaDecor doit conserver une architecture plus simple dans le MVP.

---

# 25. GUI principal Effects

Écran :

```text
WINDOW EFFECTS                         [ ON ]

Engine
HyprWindowShade                        ✓ Ready

Compatibility
Validated                              ✓


OPEN
┌──────────────────────────────────────┐
│ Incinerate                           │
│ Burn My Windows                      │
│ GPL-3.0                              │
│                              [ ▶ ]   │
└──────────────────────────────────────┘


CLOSE
┌──────────────────────────────────────┐
│ Incinerate                           │
│ Burn My Windows                      │
│ GPL-3.0                              │
│                              [ ▶ ]   │
└──────────────────────────────────────┘


MOVE
Wobble                                 [ ▶ ]

FOCUS
Aura Glow                              [ ▶ ]
```

---

# 26. Effect picker

Cliquer sur un événement ouvre :

```text
Choose Close Effect

Search ______________________


FEATURED

Incinerate
Burn My Windows
★★★★


Fire
Burn My Windows


COMMUNITY

Heat Melt
liixini shaders

Smoke
liixini shaders


NONE
No effect
```

Les catégories sont fournies par metadata.

---

# 27. Fiche effet

Chaque effet doit posséder une fiche détaillée :

```text
INCINERATE

[ animated preview ]

Heat-driven dissolve with embers
and chromatic distortion.


Original project
Burn My Windows

Authors
Simon Schneegans / contributors

Port
OmaDecor BMW Compatibility

License
GPL-3.0


Compatible events
Open
Close


Duration
────────●────
900 ms


Parameters
...

[ Use for Open ]
[ Use for Close ]
```

La provenance doit être visible, pas cachée dans About.

---

# 28. Preview

Le preview est important.

Trois niveaux possibles :

### MVP

Preview vidéo/image fournie avec le pack.

### Ensuite

Fenêtre synthétique rendue dans le GUI.

### Plus tard

Preview réel sur une fenêtre de démonstration Hyprland.

Ne pas utiliser une vraie fenêtre utilisateur comme cobaye.

---

# 29. Règles par application

La configuration globale reste :

```text
Open       Incinerate
Close      Incinerate
Move       Wobble
Focus      Aura Glow
```

Une application peut surcharger :

```text
Kitty

Open       Matrix
Close      Incinerate
Move       Global
Focus      Global
```

Une application peut également désactiver :

```text
Jellyfin

Effects       OFF
```

ou :

```text
Steam

Fullscreen    OFF
Open          Global
Close         Global
```

Le backend traduit ensuite ces intentions en règles HyprWindowShade.

---

# 30. Fullscreen

Les effets restent désactivés par défaut en fullscreen.

C'est également le comportement par défaut de HyprWindowShade.

OmaDecor ne doit pas appliquer de post-processing permanent aux jeux ou vidéos fullscreen sans décision explicite de l'utilisateur.

---

# 31. Pack Registry

Créer :

```text
EffectPackRegistry
```

Il découvre les packs dans plusieurs sources.

Conceptuellement :

```text
built-in
user
third-party
```

Répertoires possibles :

```text
OmaDecor bundled packs

~/.local/share/omadecor/effects/

future package-managed locations
```

Ne pas permettre aux packs de définir des chemins absolus hors de leur propre répertoire.

---

# 32. Sécurité des packs

Un pack d'effet ne doit jamais exécuter :

```text
shell
Python
JavaScript
Lua
arbitrary binary
network access
installer
```

Un pack contient uniquement :

```text
metadata
GLSL
preview assets
license
credits
```

Les includes GLSL doivent être restreints :

```text
pack directory
+
approved OmaDecor compatibility libraries
```

Interdire :

```text
../../
/etc/...
/home/...
```

---

# 33. Validation GLSL

Avant activation :

```text
parse metadata
validate schema
resolve files
validate includes
validate capabilities
compile shader
```

Si compilation impossible :

```text
Effect unavailable

Shader compilation failed.

[ Details ]
```

Ne jamais laisser une erreur de shader casser le compositor lorsque cela peut être évité.

---

# 34. Hot reload

En mode développement :

```text
GLSL saved
      ↓
validate
      ↓
compile
      ↓
reload effect
```

En cas d'échec :

```text
keep previous working version
```

et non :

```text
replace working shader with broken shader
```

---

# 35. Compatibility database

Le système de compatibilité déjà prévu pour HyprWindowShade reste pertinent.

Ajouter :

```text
backend version
effect pack version
compatibility layer version
effect version
```

Exemple :

```json
{
    "backend": "hyprwindowshade",
    "backendFingerprint": "...",

    "compatibility": {
        "niri": "1",
        "bmw": "1"
    }
}
```

---

# 36. États

Effet :

```text
AVAILABLE
UNTESTED
DEGRADED
BROKEN
INCOMPATIBLE
```

Backend :

```text
NOT_INSTALLED
NOT_LOADED
VALIDATED
UNTESTED
DEGRADED
BLOCKED
```

Pack :

```text
VALID
INVALID
LICENSE_MISSING
COMPILATION_ERROR
```

---

# 37. Fail-soft

Si :

```text
Incinerate = broken
```

ne pas désactiver tout le moteur.

Faire :

```text
Close: Incinerate temporarily disabled
Open: Incinerate still available if valid
Move: Wobble unaffected
```

Conserver le choix utilisateur.

Lorsqu'une version validée redevient disponible :

```text
Incinerate restored
```

---

# 38. Attribution

Chaque effet tiers doit pouvoir fournir :

```text
originalProject
originalAuthors
portAuthors
sourceLicense
sourceVersion
adaptationNotes
```

Ces informations doivent apparaître :

* dans le GUI ;
* dans Diagnostics lorsque pertinent ;
* dans les fichiers de crédits distribués avec le pack.

OmaDecor doit avoir comme principe :

> **Third-party creative work is a feature to highlight, not metadata to hide.**

---

# 39. Marketplace de packs — hors MVP

Ne pas créer aujourd'hui :

```text
OmaDecor online store
```

Mais concevoir les packs afin qu'un catalogue puisse exister plus tard.

Un pack installé manuellement doit pouvoir devenir demain un pack installé depuis :

```text
Browse Effects
```

sans changer son format.

---

# 40. Installation externe

Le MVP ne doit télécharger automatiquement aucun dépôt.

La première version peut détecter des packs déjà présents.

Plus tard un gestionnaire de packs pourra être conçu séparément avec :

* sources connues ;
* versions ;
* hashes ;
* licenses ;
* signatures éventuelles ;
* confirmation utilisateur.

Cela ne doit pas bloquer le moteur actuel.

---

# 41. Performance

Un effet doit pouvoir déclarer :

```text
renderingCost
```

Valeurs :

```text
low
medium
high
```

Mais ce champ ne doit pas être accepté aveuglément.

OmaDecor pourra ultérieurement mesurer :

```text
GPU timing
frame impact
```

Le GUI peut avertir :

```text
High rendering cost
Not recommended for permanent effects.
```

---

# 42. Single-pass d'abord

MVP :

```text
single-pass fragment shaders
```

Le système de metadata doit prévoir :

```text
multipass
```

mais ne pas l'implémenter tant qu'un effet important ne le nécessite pas.

PlasmaZones démontre qu'un format futur peut supporter vertex shaders, multipass, buffers, depth et textures additionnelles.

Ne pas essayer d'atteindre immédiatement cette complexité.

---

# 43. Séparation Decoration / HUD / Effects

Cette évolution ne change pas l'architecture principale :

```text
                   OmaDecor
                      │
       ┌──────────────┼───────────────┐
       │              │               │
 Decorations         HUD           Effects
       │              │               │
 Hyprland native  Quickshell    Effects Platform
                                      │
                               HyprWindowShade
```

Les trois modules restent activables indépendamment.

---

# 44. Interaction avec Decorations

Les effets open/close peuvent visuellement entrer en conflit avec les décorations.

La PR Hyprland native elle-même mentionne ce problème.

Le moteur OmaDecor doit donc prévoir :

```text
decorationVisibilityDuringEffect
```

Valeurs :

```text
keep
hide
effect-defined
```

Default :

```text
open  → hide decoration during transition
close → hide decoration during transition
```

Le rendu doit être testé avant de figer le comportement.

---

# 45. Interaction avec HUD

Lors d'un effet :

```text
open
close
move
resize
workspace
```

le HUD peut être masqué.

Le HUD n'a aucune obligation de participer au shader.

Cela évite toute synchronisation inutile.

---

# 46. MVP Effects Platform

Le MVP n'a pas besoin de 50 effets.

Il doit prouver :

```text
pack discovery
metadata
GUI-generated parameters
backend abstraction
HyprWindowShade execution
Niri compatibility
BMW compatibility
credits/license
application overrides
safe failure
```

avec un très petit nombre d'effets.

---

# 47. Effets de référence pour le spike

Utiliser exactement trois catégories.

## A — Native OmaDecor

Un shader simple :

```text
Simple Dissolve
```

Objectif :

valider le pipeline sans compatibility layer.

---

## B — Niri

Choisir un shader visuellement intéressant mais techniquement simple.

Objectif :

prouver :

```text
Niri shader
   ↓
Niri shim
   ↓
HyprWindowShade
```

sans réécriture majeure.

---

## C — Burn My Windows

Choisir :

```text
Incinerate
```

comme effet de référence.

Pourquoi :

* qualité visuelle connue ;
* fonctionne sans nécessiter de dessin hors fenêtre ;
* suffisamment complexe pour éprouver le moteur ;
* existe déjà dans plusieurs ports ;
* permet une comparaison visuelle avec BMW.

PlasmaZones possède actuellement un Incinerate porté de Burn My Windows et le décrit comme une dissolution thermique avec embers et distorsion chromatique.

---

# 48. Milestone E0 — Research Spike

**Ne pas commencer par coder le GUI complet.**

Créer :

```text
docs/EFFECTS_RESEARCH.md
```

Étudier :

```text
ManofJELLO/HyprWindowShade
Schneegans/Burn-My-Windows
xhos/hyprfx
mj0x0/kwin-niri-shaders-port
fuddlesworth/PlasmaZones
Niri custom shader API
Hyprland PR #13900
```

Documenter pour chacun :

```text
shader inputs
shader outputs
progress semantics
coordinate system
texture format
alpha assumptions
open behavior
close behavior
random seed
duration
parameter handling
licence
```

Puis créer une matrice :

| Feature        | HWS | Niri | BMW/KWin | Hyprland PR |
| -------------- | --- | ---- | -------- | ----------- |
| Window texture |     |      |          |             |
| Progress       |     |      |          |             |
| Random seed    |     |      |          |             |
| Window size    |     |      |          |             |
| Custom params  |     |      |          |             |
| Open           |     |      |          |             |
| Close          |     |      |          |             |
| Motion         |     |      |          |             |

Ne pas deviner.

Chaque case doit être supportée par inspection du code ou documentation.

---

# 49. Milestone E1 — Backend abstraction

Créer l'interface Effects Backend.

Implémenter uniquement :

```text
HyprWindowShadeBackend
```

Les appels depuis le reste d'OmaDecor passent uniquement par cette abstraction.

Interdire toute dépendance directe :

```text
GUI → shader_close
```

ou :

```text
EffectPack → HyprWindowShade tags
```

---

# 50. Milestone E2 — Effect Pack V1

Définir :

```text
effect.schema.json
```

Implémenter :

```text
EffectPack
EffectPackRegistry
EffectValidator
EffectMetadata
```

Créer :

```text
native/simple-dissolve
```

comme pack de référence.

Décision E2 : le format exécutable est implémenté dans
`effects/schema/effect.schema.json`. Le registre ne découvre que des packs
locaux inertes, exige un fichier `LICENSE`, rejette les traversées et symlinks,
et compile le GLSL utilisateur avant de l'exposer. Le noyau E2 accepte des
shaders single-pass autonomes ; les includes et transformations de formats
source seront matérialisés par les compatibility layers ultérieures. Le pack
`omadecor/simple-dissolve` fournit les variantes `open` et `close` natives.

---

# 51. Milestone E3 — Niri Compatibility Spike

Créer :

```text
compat/niri/
```

Éviter de modifier le shader source lorsque cela est possible.

Objectif :

```text
one compatibility shim
+
one untouched/minimally transformed Niri shader
```

produisant un effet fonctionnel sous HyprWindowShade.

Documenter exactement :

```text
what was compatible
what required translation
what cannot be translated
```

Si le port nécessite de réécrire une grande partie de chaque shader individuellement, marquer l'approche `NO-GO` et documenter pourquoi.

Décision E3 (implémentation locale) : `effects/compat/niri/` fournit un shim
unique pour les shaders Niri `open`/`close` utilisant les quatre symboles
communs. Le pack MIT `liixini/circle` conserve ses deux fonctions GLSL
octet pour octet ; le scanner produit des artefacts HWS validés dans le cache
utilisateur. La compilation, le registre et l'application HWS ont passé les
tests. Les transitions circulaires d'ouverture et de fermeture sont visibles
sur l'écran local ; la fermeture a été confirmée avec une fenêtre GTK opaque.
La portabilité reste à vérifier. Le resize Niri,
les textures précédentes/suivantes et les symboles hors sous-ensemble sont
refusés. Voir `EFFECTS_RESEARCH.md` pour les limites et les preuves.

---

# 52. Milestone E4 — BMW Incinerate Spike

Étudier en priorité :

```text
Burn My Windows Incinerate
BMW KWin port
PlasmaZones Incinerate port
hyprfx architecture
```

Ne pas commencer avec Fire.

Objectif :

> obtenir sous Hyprland un Incinerate visuellement comparable à Burn My Windows.

Préserver :

```text
attribution
license
copyright notices
```

Le pack de test BMW doit être clairement GPL-3.0.

État E4 : le pack `bmw/incinerate` conserve les sources BMW d'origine et
leur licence GPL-3.0-or-later. Un adaptateur HWS limité à ce shader produit
les variantes ouverture/fermeture. Le test local sur une grande fenêtre montre flammes,
fumée et braises, avec disparition finale propre. La fermeture d'une fenêtre
flottante 900×600 montre aussi le front de combustion, la fumée et les braises
quand la configuration a été appliquée avant l'ouverture et que la fermeture
est demandée via Hyprland. Une fermeture GTK distincte confirme que le contenu
de la fenêtre brûle aussi. Les premiers essais sans « Apply » ou avec arrêt
brutal du client ne constituaient pas une validation. La durée interne du bruit
est maintenant compilée selon le slider de chaque événement ; les paramètres
sont éditables dans la fiche effet et les presets sont proposés. Décision :
**expérimental, pas encore GO** ;
ne pas présenter ce port comme une compatibilité BMW générique.

---

# 53. Critère GO pour BMW

GO si :

* l'effet est visuellement convaincant ;
* la fenêtre disparaît proprement ;
* les couleurs et le front de combustion sont comparables au comportement BMW ;
* aucune instabilité compositor ;
* le shader fonctionne sur plusieurs tailles de fenêtres ;
* les paramètres principaux peuvent être exposés ;
* le code d'adaptation est raisonnablement générique.

NO-GO pour la compatibility layer générique si :

* quasiment chaque shader nécessite une réécriture complète ;
* BMW dépend de fonctionnalités impossibles à reproduire avec notre backend ;
* la maintenance du shim est supérieure au bénéfice.

Même en NO-GO, des ports individuels GPL restent possibles.

---

# 54. Milestone E5 — GUI

Après le prototype E4 ; la publication reste soumise à son acceptation.

Implémenter :

```text
Effects overview
Effect picker
Effect details
Preview
Generated parameters
Per-event selection
Per-application overrides
Credits
Compatibility status
```

État E5 : la fiche accessible depuis le sélecteur affiche description,
provenance, auteurs et licence. Les contrôles float/int/bool/color/enum sont
générés depuis le manifest pour les packs dont le backend sait matérialiser
les paramètres ; Incinerate fournit Scale, Turbulence et Fire Color ainsi que
ses presets. Les valeurs sont persistées par pack, communes à ses événements,
et recompilées avec chaque durée au clic « Apply ». Les previews locaux PNG,
JPEG, WebP et GIF peuvent être affichés ; les GIF s'animent dans la fiche.
Les trois packs livrés ont des GIF générés en lot depuis leurs shaders HWS
compilés dans un contexte EGL hors écran, sur une fenêtre synthétique. Aucune
application utilisateur n'est capturée. Ces aperçus ne prouvent ni la fidélité
du rendu dans Hyprland ni la compatibilité d'Incinerate avec d'autres GPU ; la
validation globale de l'ergonomie reste ouverte.

---

# 55. Milestone E6 — Pack ecosystem

Après validation du moteur :

```text
additional Niri effects
additional BMW effects
community packs
presets
import/export
```

Ne pas viser un nombre d'effets.

Viser :

> **des effets remarquables et fiables.**

Dix excellents effets valent mieux que cinquante médiocres.

---

# 56. Non-objectifs immédiats

Ne pas implémenter maintenant :

```text
online marketplace
automatic Git clone
automatic package downloads
arbitrary GLSL execution from internet
multipass rendering engine
custom vertex shaders
depth buffer
audio reactive shaders
wallpaper shaders
screen shaders
particle engine
effects outside window geometry
Compiz cube
```

Ils pourront être réévalués plus tard.

---

# 57. Direction produit

OmaDecor doit progressivement devenir :

```text
                 OMADECOR

       Window visual customization
                    │
       ┌────────────┼─────────────┐
       │            │             │
 Decorations       HUD         Effects
       │            │             │
 Declarative    Quickshell   Effect Packs
 Themes                         │
       │                   Compatibility
 Community                  Layers
 Themes                         │
                         Rendering Backend
```

L'utilisateur doit pouvoir installer OmaDecor puis choisir :

```text
Decoration
Raised Edge

HUD
Technical

Open effect
Portal

Close effect
Incinerate

Move effect
Wobble

Focus effect
Aura Glow
```

sans connaître :

```text
GLSL
HyprWindowShade tags
Hyprland rules
shader paths
licenses
config syntax
```

---

# 58. Principe communautaire

OmaDecor n'a pas vocation à absorber le travail d'autres projets.

Il doit agir comme un **intégrateur et amplificateur**.

Lorsqu'un effet remarquable provient de :

```text
Burn My Windows
Niri community
liixini/shaders
another project
```

OmaDecor doit mettre cette provenance en évidence.

L'objectif n'est pas :

> « OmaDecor possède 100 effets ».

L'objectif est :

> « OmaDecor permet d'utiliser facilement les meilleurs effets de l'écosystème Linux sous Hyprland. »

---

# 59. Principe de maintenance

Tous les formats externes doivent être encapsulés.

Jamais :

```text
GUI
 ↓
BMW assumptions
```

Jamais :

```text
EffectsManager
 ↓
Niri function names
```

Mais :

```text
External format
      ↓
compatibility adapter
      ↓
NormalizedEffect
      ↓
backend
```

Chaque compatibility layer peut évoluer indépendamment.

---

# 60. Première tâche Codex après lecture de ce PRD

STOP any large-scale Effects implementation.

Do not port collections of shaders yet.

Do not rewrite the existing Decorations/HUD architecture because of this PRD.

First create:

```text
docs/EFFECTS_RESEARCH.md
```

and perform Milestone E0.

Then produce:

```text
1. API comparison matrix
2. license/provenance matrix
3. proposed EffectPack V1 schema
4. proposed IEffectsBackend interface
5. Niri compatibility feasibility assessment
6. BMW compatibility feasibility assessment
7. Incinerate port strategy
8. identified risks
9. recommendation GO / NO-GO for each compatibility layer
```

Do not implement NiriCompatibility or BMWCompatibility until the research document has been reviewed.

The immediate architectural objective is:

> **prove that OmaDecor can normalize third-party effect formats while keeping HyprWindowShade replaceable as a backend.**

The immediate visual objective after that is:

> **make Incinerate under Hyprland look good enough that a user familiar with Burn My Windows does not consider it a downgrade.**
