# OmaDecor Decoration Theme Format — proposition V1

## 0. Statut d'implémentation

La proposition ci-dessous décrit le format cible. Son sous-ensemble normatif
**V1 Core** est désormais matérialisé par :

* `decorations/schema/decoration-theme-v1.schema.json` pour la structure ;
* `decorations/ThemeCompiler.js` pour les capabilities, références, cycles,
  limites et la compilation des valeurs ;
* `decorations/styles/raised-edge.omadecor.json` comme thème de référence.

V1 Core accepte actuellement :

```text
primitive.edge
primitive.frame
primitive.rect
paint.solid
state.focused
color.oklch-derive
```

Dans ce profil initial, `frame.join` vaut uniquement `square` et `clip`
uniquement `none`. Les autres valeurs documentées restent réservées jusqu'à ce
que le renderer expose explicitement leurs capabilities.

Les autres primitives, gradients, modifiers, états et transitions décrits dans
ce document sont **réservés**. Un thème qui les déclare est valide dans l'idée
du format, mais reste indisponible tant que le moteur n'annonce pas les
capabilities correspondantes. Cette distinction évite une prise en charge
partielle ou silencieusement incorrecte.

Le chargeur runtime et le renderer générique sont raccordés. Le service valide
le fichier avant de transmettre son chemin au plugin ; le plugin refait une
validation indépendante, compile deux états (`focused` et `inactive`) puis ne
conserve que les opérations natives. Le JSON n'est jamais interprété pendant
une frame. Si l'une des validations échoue, le backend Raised Edge historique
sert de repli sûr.

Emplacements retenus pour la découverte future :

```text
decorations/styles/*.omadecor.json       thèmes intégrés
~/.config/omadecor/themes/*.omadecor.json thèmes utilisateur
```

Un fichier utilisateur ne peut référencer aucun chemin externe. Le GUI accepte
uniquement son nom de fichier et le résout sous
`~/.config/omadecor/themes/`; aucune saisie de chemin arbitraire n'atteint le
plugin. Sa sélection et, à terme, ses paramètres restent séparés dans
`~/.config/omadecor/config.json`.

## 1. Principe

Un thème OmaDecor est une **recette de dessin déclarative**.

Le fichier décrit :

* les paramètres personnalisables ;
* les couleurs ;
* les primitives graphiques ;
* leur ordre ;
* leur comportement selon l'état de la fenêtre ;
* les transitions entre états.

Il ne contient :

* aucun code ;
* aucune commande shell ;
* aucun JavaScript ;
* aucun GLSL arbitraire ;
* aucun accès réseau ;
* aucun chemin vers un fichier système.

Pipeline :

```text
theme.omadecor.json
        │
        ▼
JSON Schema validation
        │
        ▼
Capability validation
        │
        ▼
Resolve parameters / palette
        │
        ▼
Resolve current window state
        │
        ▼
Compile primitives
        │
        ▼
Native OmaDecor renderer
        │
        ▼
Hyprland IHyprWindowDecoration
```

Hyprland expose actuellement une API `addWindowDecoration(...)` permettant à un plugin d'attacher une `IHyprWindowDecoration` à une fenêtre. OmaDecor doit rester autant que possible sur cette API plutôt que dépendre de hooks internes fragiles.

---

# 2. Extension

```text
*.omadecor.json
```

Exemple :

```text
raised-edge.omadecor.json
neon-corners.omadecor.json
lcars.omadecor.json
terminal-green.omadecor.json
```

---

# 3. Identité du thème

Chaque thème possède une identité stable.

```json
{
    "schemaVersion": 1,
    "kind": "omadecor-decoration",

    "id": "za512/raised-edge",
    "name": "Raised Edge",
    "version": "1.0.0",

    "author": {
        "name": "ZA512"
    },

    "license": "MIT",

    "description": "Simple raised window frame using light and dark edges."
}
```

Le `id` doit être unique.

Format recommandé :

```text
author/theme
```

Exemples :

```text
za512/raised-edge
john/neon-grid
alice/lcars-blue
```

---

# 4. Compatibility par capacités

Éviter de rendre les thèmes dépendants d'une version précise d'OmaDecor.

Préférer :

```json
"requires": [
    "primitive.edge",
    "paint.solid",
    "state.focused"
]
```

Un thème plus évolué pourrait demander :

```json
"requires": [
    "primitive.edge",
    "primitive.polygon",
    "paint.linear-gradient",
    "modifier.glow"
]
```

OmaDecor peut alors afficher :

```text
LCARS Advanced

Requires:
✓ edge
✓ polygon
✓ linear-gradient
✕ glow

Theme unavailable with this OmaDecor version.
```

C'est beaucoup plus propre qu'un simple :

```text
requires OmaDecor >= 1.7
```

On peut néanmoins conserver un `minEngineVersion` informatif si nécessaire.

---

# 5. Unités

Toutes les dimensions physiques utilisent les **logical pixels Hyprland**, jamais directement les pixels physiques de l'écran.

Un nombre simple représente des pixels logiques :

```json
"thickness": 4
```

Pour les coordonnées relatives, définir un type de valeur universel :

```json
{
    "rel": 0.5,
    "px": 10
}
```

Signification :

```text
50 % de la dimension + 10 px
```

Exemples :

```json
0
```

= 0 px

```json
20
```

= 20 px

```json
{
    "rel": 0.25
}
```

= 25 %

```json
{
    "rel": 1.0,
    "px": -10
}
```

= 10 px avant la fin.

Cela évite d'avoir à construire un langage du genre :

```text
calc(100% - 10px)
```

---

# 6. Repère

Le repère principal est la fenêtre :

```text
(0,0)
  ┌───────────────────────┐
  │                       │
  │        WINDOW         │
  │                       │
  └───────────────────────┘
                         (W,H)
```

Les coordonnées peuvent sortir de la fenêtre.

Exemple :

```json
"x": -8
```

permet de dessiner 8 px à gauche.

Ainsi :

```text
        ═════════
     ┌──────────────┐
═════│    WINDOW    │
     └──────────────┘═════
                       ║
```

est parfaitement possible.

---

# 7. Parameters

Un thème doit pouvoir exposer automatiquement ses réglages dans le GUI OmaDecor.

Exemple :

```json
"parameters": {
    "mainColor": {
        "type": "color",
        "label": "Main color",
        "default": {
            "ref": "system.accent"
        }
    },

    "thinWidth": {
        "type": "number",
        "label": "Light edge width",
        "unit": "px",
        "default": 2,
        "min": 1,
        "max": 20,
        "step": 1
    },

    "thickWidth": {
        "type": "number",
        "label": "Dark edge width",
        "unit": "px",
        "default": 5,
        "min": 1,
        "max": 30,
        "step": 1
    },

    "inactiveOpacity": {
        "type": "number",
        "label": "Inactive opacity",
        "default": 0.55,
        "min": 0,
        "max": 1,
        "step": 0.05
    }
}
```

Le GUI peut être généré automatiquement :

```text
Raised Edge

Main color           [ ■ cyan ]

Light edge width     [ 2 px     ]
Dark edge width      [ 5 px     ]

Inactive opacity     [ 55 %     ]
```

Aucun GUI spécifique au thème.

Types V1 :

```text
number
color
boolean
enum
```

---

# 8. Références

Les valeurs peuvent référencer :

```text
system.*
param.*
palette.*
```

Exemples :

```json
{
    "ref": "system.accent"
}
```

```json
{
    "ref": "param.mainColor"
}
```

```json
{
    "ref": "palette.dark"
}
```

---

# 9. Couleurs système

OmaDecor peut fournir une palette abstraite.

Exemple :

```text
system.accent
system.background
system.foreground
system.border
```

Le thème ne doit pas connaître directement le thème Omarchy utilisé.

Cela permet :

```text
Omarchy Aetheria
        ↓
system.accent = violet

OmaDecor Raised Edge
        ↓
violet automatiquement
```

---

# 10. Palette locale

Un thème peut dériver ses propres couleurs.

```json
"palette": {
    "main": {
        "ref": "param.mainColor"
    },

    "dark": {
        "derive": {
            "from": {
                "ref": "palette.main"
            },
            "space": "oklch",
            "lightness": -0.20
        }
    },

    "faint": {
        "derive": {
            "from": {
                "ref": "palette.main"
            },
            "alpha": 0.30
        }
    }
}
```

Je choisirais **OKLCH** pour les modifications perceptuelles.

Transformations autorisées :

```text
lightness
chroma
hue
alpha
```

Éventuellement plus tard :

```text
mix
```

Exemple :

```json
{
    "mix": {
        "a": {"ref": "palette.main"},
        "b": "#ffffff",
        "ratio": 0.2
    }
}
```

---

# 11. Paint

Une primitive ne possède pas directement une couleur.

Elle possède un **paint**.

Cela permet de passer d'une couleur à un gradient sans changer la primitive.

## Solid

```json
"paint": {
    "type": "solid",
    "color": {
        "ref": "palette.main"
    }
}
```

## Linear gradient

```json
"paint": {
    "type": "linear-gradient",
    "angle": 0,

    "stops": [
        {
            "at": 0,
            "color": "#00ffff"
        },
        {
            "at": 0.5,
            "color": "#3366ff"
        },
        {
            "at": 1,
            "color": "#ff00ff"
        }
    ]
}
```

Cela permet :

```text
CYAN ━━━━━━━ BLUE ━━━━━━━ VIOLET
```

## Radial gradient

À prévoir comme capacité optionnelle :

```text
paint.radial-gradient
```

Pas indispensable au premier renderer.

---

# 12. Architecture des primitives

Je distinguerais deux niveaux.

## Primitives renderer

Le moteur natif sait réellement dessiner :

```text
rect
line
polyline
polygon
arc
```

## Primitives pratiques

Le moteur OmaDecor les transforme en primitives renderer :

```text
edge
frame
corner
repeat
```

Ainsi les thèmes simples restent extrêmement faciles à écrire.

---

# 13. Primitive `edge`

Ce sera probablement la primitive la plus utilisée.

```json
{
    "id": "top-edge",
    "type": "edge",

    "side": "top",

    "start": {
        "rel": 0
    },

    "end": {
        "rel": 1
    },

    "thickness": 3,

    "placement": "outside",

    "distance": 0,

    "paint": {
        "type": "solid",
        "color": "#00ffff"
    }
}
```

Sides :

```text
top
right
bottom
left
```

Placement :

```text
inside
center
outside
```

---

# 14. Segments

Un segment n'a pas besoin d'une primitive différente.

Deux `edge` avec des `start/end` différents suffisent.

```json
{
    "id": "top-left-segment",
    "type": "edge",
    "side": "top",
    "start": {"rel": 0},
    "end": {"rel": 0.25},
    "thickness": 4,
    "paint": {
        "type": "solid",
        "color": "#00ffff"
    }
}
```

Puis :

```json
{
    "id": "top-right-segment",
    "type": "edge",
    "side": "top",
    "start": {"rel": 0.75},
    "end": {"rel": 1},
    "thickness": 4,
    "paint": {
        "type": "solid",
        "color": "#ff00ff"
    }
}
```

Résultat :

```text
━━━━━━━                   ━━━━━━━
```

---

# 15. Plusieurs épaisseurs sur le même côté

Simplement plusieurs layers.

```text
═════════════════════════  1 px white
─────────────────────────  2 px blue
━━━━━━━━━━━━━━━━━━━━━━━━━  4 px dark blue
```

Chaque layer possède son propre `distance`.

Exemple :

```json
{
    "type": "edge",
    "side": "top",
    "thickness": 1,
    "distance": 0
}
```

```json
{
    "type": "edge",
    "side": "top",
    "thickness": 2,
    "distance": 2
}
```

---

# 16. Primitive `frame`

C'est un raccourci extrêmement utile.

```json
{
    "id": "main-frame",
    "type": "frame",

    "top": {
        "thickness": 2,
        "paint": {
            "type": "solid",
            "color": {
                "ref": "palette.main"
            }
        }
    },

    "right": {
        "thickness": 2,
        "paint": {
            "type": "solid",
            "color": {
                "ref": "palette.main"
            }
        }
    },

    "bottom": {
        "thickness": 5,
        "paint": {
            "type": "solid",
            "color": {
                "ref": "palette.dark"
            }
        }
    },

    "left": {
        "thickness": 5,
        "paint": {
            "type": "solid",
            "color": {
                "ref": "palette.dark"
            }
        }
    },

    "placement": "outside",

    "join": "bevel"
}
```

`frame` est compilé automatiquement en edges/corners.

Joins :

```text
square
miter
bevel
round
```

---

# 17. Primitive `rect`

Pour des blocs décoratifs.

```json
{
    "id": "top-marker",

    "type": "rect",

    "x": {
        "rel": 0.1
    },

    "y": -8,

    "width": {
        "rel": 0.2
    },

    "height": 5,

    "paint": {
        "type": "solid",
        "color": "#ff8800"
    }
}
```

Permet :

```text
     ███████████

┌────────────────────────────┐
│           WINDOW           │
└────────────────────────────┘
```

---

# 18. Primitive `line`

Pour des traits libres, y compris diagonaux.

```json
{
    "type": "line",

    "from": {
        "x": 0,
        "y": 0
    },

    "to": {
        "x": 20,
        "y": -20
    },

    "thickness": 3,

    "paint": {
        "type": "solid",
        "color": "#00ffff"
    }
}
```

---

# 19. Primitive `polyline`

Pour :

```text
┌────
│
│
```

mais également :

```text
╲━━━━
```

ou :

```text
━━━╲
    ╲━━━
```

Exemple :

```json
{
    "type": "polyline",

    "points": [
        {"x": 0, "y": 20},
        {"x": 0, "y": 0},
        {"x": 40, "y": 0}
    ],

    "thickness": 3,

    "join": "bevel",

    "paint": {
        "type": "solid",
        "color": "#00ffff"
    }
}
```

---

# 20. Primitive `polygon`

Très importante pour les designs SF.

Elle permet :

```text
triangle
diamond
chevron
trapèze
angles coupés
flèches
formes LCARS
```

Exemple :

```json
{
    "type": "polygon",

    "points": [
        {"x": 0, "y": 0},
        {"x": 30, "y": 0},
        {"x": 20, "y": 10},
        {"x": 0, "y": 10}
    ],

    "paint": {
        "type": "solid",
        "color": "#ff8800"
    }
}
```

---

# 21. Primitive `arc`

À prévoir.

Elle permet :

```text
╭────
│
```

des quarts de cercle, anneaux, indicateurs techniques, thèmes rétrofuturistes, etc.

```json
{
    "type": "arc",

    "center": {
        "x": 0,
        "y": 0
    },

    "radius": 20,

    "startAngle": 0,
    "endAngle": 90,

    "thickness": 4,

    "paint": {
        "type": "solid",
        "color": "#00ffff"
    }
}
```

Je la classerais éventuellement comme capability V1.1 si sa mise en œuvre native complique le MVP.

---

# 22. Primitive `corner`

`corner` est un helper.

Au lieu d'écrire plusieurs lignes :

```json
{
    "type": "corner",

    "corner": "top-left",

    "style": "bracket",

    "horizontalLength": 40,
    "verticalLength": 25,

    "thickness": 3,

    "paint": {
        "type": "solid",
        "color": "#00ffff"
    }
}
```

Styles possibles :

```text
square
bracket
cut
bevel
round
```

Exemple :

```text
┏━━━━━━

┃
┃
```

---

# 23. Primitive `repeat`

Très intéressante pour des motifs.

Exemple :

```text
■ ■ ■ ■ ■ ■ ■ ■
```

ou :

```text
|||||||||||||||||
```

Déclaration conceptuelle :

```json
{
    "type": "repeat",

    "count": 8,

    "from": {
        "x": 0,
        "y": -6
    },

    "step": {
        "x": 12,
        "y": 0
    },

    "primitive": {
        "type": "rect",
        "width": 6,
        "height": 3,
        "paint": {
            "type": "solid",
            "color": "#00ffff"
        }
    }
}
```

Le moteur impose une limite de répétition.

Pas de boucle arbitraire.

---

# 24. Layers

Toutes les primitives vivent dans une liste ordonnée.

```json
"layers": [
    {
        "id": "shadow",
        ...
    },
    {
        "id": "outer-frame",
        ...
    },
    {
        "id": "main-frame",
        ...
    },
    {
        "id": "markers",
        ...
    }
]
```

Ordre :

```text
premier = arrière
dernier = avant
```

Pas besoin d'un `z-index` sauf si on découvre une nécessité réelle.

L'ordre du JSON suffit.

---

# 25. Opacity

Toute primitive peut posséder :

```json
"opacity": 0.75
```

Le paint conserve sa propre alpha éventuelle.

Opacity globale × opacity layer × alpha couleur = alpha final.

---

# 26. Modifiers

Une primitive peut recevoir des effets.

Exemple :

```json
"modifiers": [
    {
        "type": "glow",
        "radius": 10,
        "opacity": 0.3
    }
]
```

Modifiers envisagés :

```text
glow
shadow
```

Plus tard éventuellement :

```text
blur
```

Mais chaque modifier doit correspondre à une capability.

Exemple :

```text
modifier.glow
```

---

# 27. Shadow

Exemple :

```json
{
    "type": "shadow",
    "offset": {
        "x": 5,
        "y": 5
    },
    "radius": 10,
    "opacity": 0.25
}
```

À ne pas confondre avec le shadow natif général de Hyprland, qui possède déjà ses propres paramètres. Hyprland sait notamment configurer couleur, offset et portée de son ombre native.

OmaDecor devra décider si son shadow modifier utilise le renderer OmaDecor ou délègue intelligemment à Hyprland.

---

# 28. États

Le même thème ne doit pas être dupliqué pour :

```text
active
inactive
floating
urgent
```

On définit des **variants**.

États V1 proposés :

```text
focused
floating
tiled
fullscreen
urgent
pinned
grouped
```

Plus tard éventuellement :

```text
moving
resizing
```

---

# 29. Variants

Exemple :

```json
"variants": [
    {
        "when": {
            "focused": false
        },

        "patch": {
            "theme": {
                "opacity": {
                    "ref": "param.inactiveOpacity"
                }
            }
        }
    }
]
```

Tous les critères d'un `when` sont des AND.

```json
"when": {
    "focused": true,
    "floating": true
}
```

signifie :

```text
focused AND floating
```

---

# 30. Patch d'une primitive

Une variante peut modifier un layer particulier grâce à son `id`.

```json
{
    "when": {
        "urgent": true
    },

    "patch": {
        "layers": {
            "main-frame": {
                "paint": {
                    "type": "solid",
                    "color": "#ff3030"
                }
            }
        }
    }
}
```

On peut donc faire :

```text
normal  → cyan
urgent  → rouge
```

sans recopier toute la décoration.

---

# 31. Priorité des variants

Les variants sont évalués dans l'ordre.

Les derniers gagnent.

Exemple :

```text
base
 ↓
floating
 ↓
focused
 ↓
urgent
```

Un `urgent` situé à la fin peut donc remplacer la couleur définie par `focused`.

Simple et prévisible.

---

# 32. Visibility

Chaque layer peut avoir :

```json
"visible": true
```

Une variante peut alors faire :

```json
"patch": {
    "layers": {
        "floating-shadow": {
            "visible": false
        }
    }
}
```

---

# 33. Transitions

Je supporterais les transitions d'état mais **pas les animations permanentes en V1**.

Exemple :

```json
"transitions": {
    "default": {
        "durationMs": 120,
        "easing": "ease-out"
    }
}
```

Le moteur peut interpoler :

```text
opacity
color
thickness
position
```

si la primitive le permet.

Ainsi :

```text
inactive gray
        ↓ 120 ms
focused cyan
```

est fluide.

Mais aucun thème V1 ne peut demander :

```text
tourne indéfiniment
pulse éternellement
anime ce gradient à 60 FPS
```

C'est volontaire.

---

# 34. Pourquoi interdire les animations infinies dans V1

Parce qu'une décoration statique n'a besoin d'être redessinée que lorsque :

* la fenêtre change ;
* le focus change ;
* son état change ;
* le thème change.

Une animation permanente imposerait un redraw continu.

On pourra créer plus tard :

```text
schema V2
animation.*
```

avec un budget GPU explicite.

---

# 35. Clip

Une primitive peut demander :

```json
"clip": "none"
```

ou :

```json
"clip": "window"
```

ou éventuellement :

```json
"clip": "rounded-window"
```

Le default pour une décoration externe devrait être :

```text
none
```

---

# 36. Theme opacity

Le thème entier possède :

```json
"appearance": {
    "opacity": 1.0
}
```

Ce qui facilite énormément les variants inactive.

---

# 37. Raised Edge complet

Notre premier thème pourrait déjà ressembler à ceci :

```json
{
    "schemaVersion": 1,
    "kind": "omadecor-decoration",

    "id": "za512/raised-edge",
    "name": "Raised Edge",
    "version": "1.0.0",

    "author": {
        "name": "ZA512"
    },

    "license": "MIT",

    "requires": [
        "primitive.frame",
        "paint.solid",
        "state.focused"
    ],

    "parameters": {
        "mainColor": {
            "type": "color",
            "label": "Main color",
            "default": {
                "ref": "system.accent"
            }
        },

        "lightWidth": {
            "type": "number",
            "label": "Light edge",
            "unit": "px",
            "default": 2,
            "min": 1,
            "max": 12,
            "step": 1
        },

        "darkWidth": {
            "type": "number",
            "label": "Dark edge",
            "unit": "px",
            "default": 5,
            "min": 1,
            "max": 20,
            "step": 1
        },

        "inactiveOpacity": {
            "type": "number",
            "label": "Inactive opacity",
            "default": 0.55,
            "min": 0,
            "max": 1,
            "step": 0.05
        }
    },

    "palette": {
        "main": {
            "ref": "param.mainColor"
        },

        "dark": {
            "derive": {
                "from": {
                    "ref": "palette.main"
                },
                "space": "oklch",
                "lightness": -0.18
            }
        }
    },

    "layers": [
        {
            "id": "main-frame",

            "type": "frame",

            "placement": "outside",

            "join": "bevel",

            "top": {
                "thickness": {
                    "ref": "param.lightWidth"
                },

                "paint": {
                    "type": "solid",
                    "color": {
                        "ref": "palette.main"
                    }
                }
            },

            "right": {
                "thickness": {
                    "ref": "param.lightWidth"
                },

                "paint": {
                    "type": "solid",
                    "color": {
                        "ref": "palette.main"
                    }
                }
            },

            "bottom": {
                "thickness": {
                    "ref": "param.darkWidth"
                },

                "paint": {
                    "type": "solid",
                    "color": {
                        "ref": "palette.dark"
                    }
                }
            },

            "left": {
                "thickness": {
                    "ref": "param.darkWidth"
                },

                "paint": {
                    "type": "solid",
                    "color": {
                        "ref": "palette.dark"
                    }
                }
            }
        }
    ],

    "variants": [
        {
            "when": {
                "focused": false
            },

            "patch": {
                "theme": {
                    "opacity": {
                        "ref": "param.inactiveOpacity"
                    }
                }
            }
        }
    ],

    "transitions": {
        "default": {
            "durationMs": 120,
            "easing": "ease-out"
        }
    }
}
```

---

# 38. Un thème segmenté

Avec exactement le même moteur :

```text
━━━━━━━       ━━━                   ━━━━━━━
┃
┃                 WINDOW
┃
┃                                     ◆
                 ━━━━━━━━━━━━━━━━━━━━━━━
```

On utilise simplement :

```text
edge
edge
edge
polygon
edge
```

Aucun nouveau code C++.

---

# 39. Un thème LCARS

Même chose :

```text
███████████████╮
               │
██             │       WINDOW
██             │
██
███████            █████████████████████
```

avec :

```text
rect
edge
arc
polygon
```

et différentes couleurs.

Toujours aucun code spécifique LCARS.

---

# 40. Un thème Neon

```text
░░░░░░░░░░░░░░░░░░░
▒███████████████████▒
█                   █
█      WINDOW       █
█                   █
▒███████████████████▒
░░░░░░░░░░░░░░░░░░░
```

Le thème demande simplement :

```text
frame
modifier.glow
```

---

# 41. Ce que le format V1 ne doit PAS autoriser

Même si techniquement OmaDecor pourrait le faire :

```text
shell commands
JavaScript
Lua
Python
arbitrary GLSL
remote URLs
network access
absolute asset paths
input capture
layout modification
Hyprland commands
```

Un thème doit rester **inerte**.

C'est particulièrement important si on permet un jour :

```text
Install theme
```

depuis un catalogue communautaire.

---

# 42. Shaders

Les shaders ne doivent pas faire partie du format de décoration V1.

Ils appartiennent à une extension séparée :

```text
OmaDecor Advanced Effects
```

ou au système HyprWindowShade.

Un `.omadecor.json` standard reste donc intrinsèquement beaucoup plus sûr.

---

# 43. Assets

Je n'autoriserais pas les images en V1.

Les primitives permettent déjà énormément de choses.

Plus tard :

```text
primitive.image
```

pourrait être ajouté avec :

* fichier obligatoirement contenu dans le package ;
* formats autorisés ;
* taille maximale ;
* aucun chemin absolu ;
* aucune URL.

Mais inutile maintenant.

---

# 44. Configuration utilisateur séparée

Le thème lui-même ne doit jamais être modifié lorsque l'utilisateur change un réglage.

Exemple :

```text
raised-edge.omadecor.json
```

reste intact.

La configuration OmaDecor contient :

```json
{
    "decorations": {
        "theme": "za512/raised-edge",

        "parameters": {
            "lightWidth": 3,
            "darkWidth": 7,
            "inactiveOpacity": 0.45
        }
    }
}
```

Ainsi une mise à jour du thème ne détruit pas les préférences.

---

# 45. Exceptions applicatives séparées

Même principe.

Ne jamais mettre ceci dans un thème :

```text
if app == Jellyfin
```

C'est OmaDecor qui gère :

```json
{
    "applications": [
        {
            "class": "org.jellyfin.JellyfinDesktop",
            "decorations": false
        }
    ]
}
```

Le thème reste universel.

---

# 46. Validation

Avant chargement, OmaDecor vérifie :

```text
JSON valide
schemaVersion supporté
id valide
toutes les refs résolues
aucune référence cyclique
capabilities disponibles
primitives valides
paint valides
paramètres dans leurs limites
variants valides
```

Puis seulement :

```text
compile → render
```

Une erreur de thème ne doit jamais mettre Hyprland en danger.

---

# 47. Budget de rendu

Je mettrais aussi des limites moteur.

Par exemple, au départ :

```text
128 layers maximum
256 draw operations compilées maximum
64 repetitions maximum
64 points par polygon
16 stops par gradient
128 px maximum d'extension extérieure
64 px maximum de glow
```

Les valeurs exactes pourront évoluer.

Le principe compte plus :

> un thème déclaratif possède un budget fini.

OmaDecor pourrait même calculer :

```text
Rendering cost

Low
Medium
High
```

à partir du thème.

---

# 48. Compilation

Une idée importante : ne pas interpréter le JSON pendant chaque frame.

Faire :

```text
JSON
 ↓
validate
 ↓
resolve parameters
 ↓
compile
 ↓
CompiledDecoration
```

Puis le renderer ne voit plus que quelque chose comme :

```text
DrawRect
DrawLine
DrawPolygon
DrawGradient
...
```

Quand le focus change :

```text
resolve variant
 ↓
update changed values only
```

Cela devrait rester extrêmement léger.

---

# 49. Architecture interne

Je proposerais donc :

```text
DecorationTheme
    │
    ├── metadata
    ├── parameters
    ├── palette
    ├── layers
    ├── variants
    └── transitions
            │
            ▼
      ThemeCompiler
            │
            ▼
    CompiledDecoration
            │
            ▼
      NativeRenderer
```

Avec :

```text
PrimitiveRegistry

rect
line
polyline
polygon
edge
frame
corner
repeat
arc
```

et :

```text
PaintRegistry

solid
linear-gradient
radial-gradient
```

et :

```text
ModifierRegistry

glow
shadow
```

---

# 50. Principe d'extension

Le point fondamental :

**ne jamais ajouter un nouveau thème dans le code.**

On ajoute seulement de nouvelles **primitives ou capabilities** quand elles ouvrent réellement une nouvelle famille de possibilités.

Par exemple :

```text
Raised Edge
Minimal Corners
Double Frame
Neon
Cyber HUD
LCARS
Industrial
Retro Terminal
Circuit
Barcode
Tron
Warning
Technical
```

devraient presque tous pouvoir fonctionner avec exactement le même moteur.

Si pour ajouter `LCARS` nous devons écrire `LcArsDecoration.cpp`, l'architecture a échoué.

Si LCARS n'est qu'un nouveau `.omadecor.json`, l'architecture a réussi.
