# Chord

Le navigateur pour ceux qui construisent le web : un successeur d'Arc, natif Mac, sur Chromium.

> **Statut : tout début.** La coquille native tourne sur un moteur WebKit provisoire.
> L'intégration de Chromium (le « spike 0 ») est la prochaine étape, voir `engine/README.md`.

## Structure

```
app/                Interface native (Swift, AppKit)
  ChordUI/          framework : fenêtre, barre latérale, Spaces, barre de commande.
                    Ne connaît aucun moteur, seulement le protocole ChordWebEngine.
  ChordDev/         app de développement : ChordUI + moteur WebKit provisoire
  project.yml       définition du projet Xcode (XcodeGen)
engine/             Intégration Chromium : version figée, scripts, patchs, plan du spike 0
docs/               Vision produit, architecture, budgets de performance, décisions
design/             Maquettes de référence et marque (logo, icône)
CLAUDE.md           Contexte du projet pour Claude Code
```

## Lancer l'app de développement

Prérequis : macOS 14 ou plus, Xcode 16 ou plus, Homebrew.

```bash
brew install xcodegen
cd app
xcodegen generate
open Chord.xcodeproj        # schéma « ChordDev », puis ⌘R
```

Ou entièrement en ligne de commande :

```bash
cd app
xcodegen generate
xcodebuild -project Chord.xcodeproj -scheme ChordDev -configuration Debug -derivedDataPath build build
open "build/Build/Products/Debug/Chord Dev.app"
```

`Chord.xcodeproj` est généré : on modifie `project.yml`, jamais le projet lui-même.

## Ce qui fonctionne

- Fenêtre en verre (NSVisualEffectView), page posée dans une carte arrondie, mode edgeless
- Barre latérale : feux et navigation sur une seule ligne, adresse, onglets épinglés,
  section « Aujourd'hui » avec « Nouvel onglet » en tête, Spaces et téléchargements en bas
- Spaces avec leur teinte, changement au clic ou avec ⌥⌘← et ⌥⌘→
- Barre de commande : ⌘T pour un nouvel onglet, ⌘L pour l'adresse de l'onglet courant ;
  onglets ouverts, adresses (localhost compris), actions, recherche
- Barre latérale repliable (⌘S), qui réapparaît en panneau flottant au survol du bord gauche
- Onglets inactifs mis en veille, session restaurée au lancement
- Mesures de latence dès le premier jour, voir `docs/PERFORMANCE.md`

## Pas encore

Moteur Chromium (spike 0), favoris, Peek, split view, petite fenêtre, glisser-déposer
des onglets, import depuis Arc, réglages, localisation.

## Licence

À choisir avant le premier contributeur externe. D'ici là, tous droits réservés.
