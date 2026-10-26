# Budgets de performance

La fluidité est une règle mesurée. Chaque interaction a un budget ; une fonctionnalité
qui le dépasse ne sort pas.

| Interaction | Signpost | Budget |
| --- | --- | --- |
| Ouvrir la barre de commande | `commandbar.open` | 50 ms |
| Replier ou déplier la barre latérale | `sidebar.toggle` | 50 ms |
| Sélectionner un onglet | `tab.select` | 100 ms |
| Changer de Space | `space.switch` | 100 ms |
| Suivre le glissement entre Spaces (une étape) | `space.swipe` | 8 ms |
| Ouvrir un Peek | `peek.open` | 100 ms |
| Ouvrir ou quitter la split view | `split.toggle` | 100 ms |
| Ouvrir une petite fenêtre | `littlewindow.open` | 100 ms |
| Ouvrir les réglages du site | `sitecontrols.open` | 50 ms |
| Lancement jusqu'à la première fenêtre | `app.launch` | 1 000 ms |
| Défilement et animations | — | 120 images/s sur ProMotion, aucune image sautée |

Les budgets vivent aussi dans le code, dans `app/ChordUI/Support/Perf.swift`.
Ils mesurent jusqu'au premier affichage après l'action, pas seulement le code exécuté.

## Mesurer

Chaque interaction ouvre un intervalle `OSSignposter` (sous-système `app.chord`).

- **Instruments** : modèle « Time Profiler » ou « Animation Hitches », instrument
  « Points of Interest ». Chaque intervalle apparaît avec sa durée.
- **Terminal** : un dépassement de budget est journalisé en avertissement.

```bash
log stream --predicate 'subsystem == "app.chord"' --level debug
```

## Plus tard

- Un test d'intégration qui rejoue les interactions et échoue en CI au-dessus du budget
- Les mêmes mesures côté Chromium (création de `WebContents`, premier rendu)
