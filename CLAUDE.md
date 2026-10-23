# Chord — contexte pour Claude Code

Chord est un navigateur macOS open source, successeur d'Arc, pour les développeurs.
Fork de Chromium (base ungoogled-chromium) dont l'interface est remplacée par une
interface native en Swift / AppKit. Projet solo de Kevin, développé avec l'IA.

À lire avant toute tâche importante :
- `docs/VISION.md` : vision produit, priorités, parité Arc de la v1, ce qu'on ne fait pas
- `docs/ARCHITECTURE.md` : découpage ChordUI / moteur, règles d'architecture
- `docs/PERFORMANCE.md` : budgets de latence
- `docs/decisions/` : décisions déjà prises et leurs raisons
- `design/` : maquettes de référence (valeurs exactes) et marque
- `engine/README.md` : plan du spike 0 (intégration Chromium)

## Construire et lancer

```bash
cd app
xcodegen generate                      # après tout ajout/suppression de fichier
xcodebuild -project Chord.xcodeproj -scheme ChordDev -configuration Debug -derivedDataPath build build
open "build/Build/Products/Debug/Chord Dev.app"
```

`Chord.xcodeproj` est généré depuis `app/project.yml` et ignoré par git : on modifie
`project.yml`, jamais le projet. Après une modification de code, toujours recompiler
et corriger les erreurs avant de rendre la main.

## Règles

- **ChordUI ne connaît aucun moteur.** Jamais d'`import WebKit` dans `app/ChordUI`.
  Tout passe par les protocoles `@objc` de `app/ChordUI/Engine/ChordWebEngine.swift`.
  Le moteur WebKit de `app/ChordDev` est provisoire et ne sert qu'au développement de
  l'interface ; le vrai moteur est Chromium.
- **ChordUI ne crée jamais `NSApplication`** : dans le vrai navigateur, Chromium la possède.
- **AppKit, pas SwiftUI**, pour tout ce qui est sur le chemin critique (fenêtre, barre
  latérale, barre de commande). SwiftUI toléré pour les réglages.
- **La fluidité est mesurée.** Toute nouvelle interaction importante ouvre un intervalle
  `Perf.begin(...)` et a un budget dans `Perf.budgets`. Ne pas dépasser les budgets.
- **Beau et fluide d'abord.** Pas de grosse fonctionnalité nouvelle tant que la base
  n'est pas impeccable. Pas d'IA ajoutée dans l'interface.
- **Fidélité à Arc pour l'UX** (raccourcis compris), personnalité visuelle propre :
  calme, premium, natif, dans l'esprit de Safari. Verre (NSVisualEffectView) plutôt
  qu'aplats de couleur.
- **Raccourcis** : tous déclarés dans `app/ChordUI/Menu/MainMenu.swift`.
- **Concurrence** : Swift 5, `SWIFT_STRICT_CONCURRENCY = minimal`. Pas d'annotations
  `@MainActor` explicites sur les types de ChordUI pour l'instant.
- Code et commentaires en anglais ; textes de l'interface et documentation en français
  (localisation prévue plus tard).
- Côté Chromium : le code de Chord vit dans `//chord`, les patchs restent minuscules
  et isolés (`engine/patches/README.md`), pour absorber une version majeure toutes les
  quatre semaines.

## État actuel

- Coquille native fonctionnelle dans ChordDev (moteur WebKit provisoire) : fenêtre en
  verre translucide (aussi inactive), déplaçable depuis tout le vide de la barre latérale,
  barre latérale redimensionnable, favoris par profil (comme Arc), épinglés avec dossiers,
  vraies icônes des sites (cache disque, reprises d'Arc à l'import), glisser-déposer des
  onglets et dossiers (ordre, dossiers, épingler, favoris, autre Space, liens d'autres apps), Spaces (couleur, nom, ⌃1…⌃9,
  glisser deux doigts), barre de commande, Peek (⇧-clic, liens sortant d'un épinglé),
  split view (⌃⇧=, 2 à 4 volets), petite fenêtre (⌥⌘N, liens d'autres apps), barre
  d'adresse en haut ou latérale (⇧⌘D, copie de l'URL au survol avec confirmation), mode clair/sombre, edgeless, réglages (⌘,) avec raccourcis
  remappables, import de la barre latérale d'Arc, page d'accueil (quand aucun onglet
  n'est ouvert : fermer un onglet ramène au dernier onglet encore actif, jamais à un
  onglet en veille), téléchargements (panneau façon Arc, ⇧⌘J), session.
- Pas encore : spike 0 Chromium, import de l'historique / mots de passe / cookies
  (côté Chromium), vrais profils isolés (cookies séparés par profil), extensions.
- Licence : pas encore choisie, à trancher avant le premier contributeur externe.
