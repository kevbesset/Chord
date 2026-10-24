# Architecture

Chord est un fork de Chromium dont l'interface est remplacée par une interface native
écrite en Swift. On garde tout ce que Chromium fait bien (moteur, extensions Chrome,
DevTools, profils, mots de passe) et on remplace ce que les utilisateurs voient.

## Vue d'ensemble

```
┌──────────────────────────────── Chord.app ────────────────────────────────┐
│  Processus navigateur de Chromium (NSApplication = BrowserCrApplication)   │
│                                                                            │
│   ChordUI.framework  — Swift, AppKit                                       │
│   fenêtres, barre latérale, Spaces, barre de commande, raccourcis          │
│              ▲                                                             │
│              │  protocoles @objc ChordWebEngine / ChordWebPage             │
│              │                                                             │
│   //chord  — Objective-C++, dans l'arbre de Chromium                       │
│   ChordBrowserWindow : BrowserWindow   (remplace BrowserView)              │
│   ChordPage : ChordWebPage             (enveloppe un WebContents)          │
│              │                                                             │
│   //chrome/browser   Browser, TabStripModel, extensions, profils, DevTools │
│   //content          WebContents, processus de rendu, GPU                  │
└────────────────────────────────────────────────────────────────────────────┘

ChordUI.framework n'est pas lié à Chromium : //chord le charge à l'exécution. Pour
travailler l'interface, `engine/scripts/run.sh` recompile ChordUI seul et relance Chord
(quelques secondes, sans recompiler Chromium).
```

## Règles

1. **ChordUI ne connaît aucun moteur.** Il ne dépend que des protocoles de
   `app/ChordUI/Engine/ChordWebEngine.swift`, jamais d'en-tête de Chromium ni de
   WebKit. C'est ce qui permet de recompiler l'interface sans Chromium, et de brancher
   d'autres moteurs plus tard.
2. **ChordUI ne crée jamais `NSApplication`.** Dans le vrai navigateur, c'est Chromium
   qui possède l'application et la boucle d'événements (`BrowserCrApplication`).
   ChordUI fournit des fenêtres et un menu, par `ChordUIHost` ; Chromium les installe.
3. **ChordUI est la source de vérité de l'organisation** : Spaces, épinglés, « Aujourd'hui ».
   Côté Chromium, un `Browser` par fenêtre et son `TabStripModel` contiennent tous les
   onglets de la fenêtre, pour que les API d'extension (`chrome.tabs`, `chrome.windows`)
   fonctionnent. Le pont garde les deux synchronisés (validé : `chrome.tabs` voit les
   onglets de Chord, un onglet créé par une extension arrive dans ChordUI).
4. **Les protocoles sont `@objc`** pour que des classes Objective-C++ puissent s'y
   conformer sans passer par l'interopérabilité C++ de Swift.

## Modules de ChordUI

| Dossier | Rôle |
| --- | --- |
| `Engine/` | Protocoles que tout moteur implémente |
| `Model/` | Spaces, favoris, onglets, split, sélection, mise en veille, session, import Arc |
| `Window/` | Fenêtre, zone de page (split view, barre d'adresse en haut), Peek, petite fenêtre |
| `Sidebar/` | Barre latérale : navigation, adresse, favoris, liste d'onglets, Spaces |
| `Settings/` | Fenêtre de réglages (SwiftUI, hors du chemin critique) |
| `CommandBar/` | Barre de commande (⌘T, ⌘L) |
| `Menu/` | Menu principal et raccourcis clavier |
| `Support/` | Thème, mesures de performance, réglages, composants partagés |

## Pourquoi AppKit plutôt que SwiftUI

Voir `docs/decisions/0002-appkit.md`. En résumé : la barre latérale doit rester fluide
avec plus de cent onglets, les animations doivent être interruptibles, et chaque
interaction a un budget de latence. AppKit donne un contrôle direct sur tout ça
(recyclage des cellules de `NSTableView`, couches, mise en page). SwiftUI reste possible
pour des écrans secondaires comme les réglages.
