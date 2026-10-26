# Moteur : Chromium

Chord s'appuie sur [ungoogled-chromium](https://github.com/ungoogled-software/ungoogled-chromium)
(licence BSD-3), une version de Chromium sans les services Google. La version est figée
dans `UPSTREAM`.

## Spike 0 — le premier jalon technique

**Rien d'autre n'est construit côté moteur tant qu'il ne tient pas.**
Réussi quand, dans une fenêtre ChordUI :

1. une page web s'affiche, rendue par Chromium ;
2. les DevTools s'ouvrent (⌥⌘I) ;
3. une extension chargée depuis `chrome://extensions` (mode développeur) fonctionne.

### Construire

```bash
engine/scripts/bootstrap.sh    # prérequis (Homebrew : ninja, coreutils, go, esbuild,
                               # typescript, python@3.13) + ungoogled-chromium-macos
engine/scripts/prepare.sh      # sources de Chromium (archive), patchs ungoogled, outils
engine/scripts/build.sh        # ChordUI.framework, puis Chromium avec //chord
engine/scripts/run.sh          # au quotidien : ChordUI seul, remis dans Chord.app
```

`build.sh` produit `engine/vendor/ungoogled-chromium-macos/build/src/out/Chord/Chord.app`,
ChordUI.framework placé dans `Contents/Frameworks`. `run.sh` ne recompile que ChordUI
(quelques secondes), le remplace dans l'app et relance Chord. Réglages de développement
(`engine/chord.gn`) : ni LTO, ni PGO, ni symboles. Le premier build prend plusieurs
heures ; les suivants ne recompilent que ce qui a changé.

À savoir :

- **SDK macOS 26.5.** L'éditeur de liens fourni avec Chromium 155 ne lit pas le SDK
  macOS 27 de Xcode 27. Les scripts utilisent celui des Command Line Tools
  (`/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk`), lié dans le dossier de
  sortie pour GN.
- **Pas d'en-têtes précompilés** : ils échouent avec le clang d'ungoogled-chromium.
- `prepare.sh` reprend là où il s'est arrêté (marqueurs `.chord-step-*` dans les
  sources).

### Comment Chord se branche (étapes 2 à 5)

- **`//chord`** (`engine/chord`, lien `src/chord`) : cible GN `//chord:browser`, liée au
  navigateur par un patch (voir `patches/`).
- **Démarrage** : `ChordBrowserMainExtraParts` empêche Chromium d'ouvrir sa fenêtre
  (`--no-startup-window`), puis, le navigateur démarré, charge `ChordUI.framework` et
  appelle `ChordUIHost.start(engine:…)`. Chromium garde `NSApplication` et son délégué ;
  le menu installé est celui de ChordUI.
- **Fenêtre** : la fabrique `BrowserWindow::CreateBrowserWindow` donne aux navigateurs
  normaux une `ChordBrowserWindow`, sans vue Views, calquée sur `WebUIBrowserWindow`.
  On garde `Browser` et `TabStripModel`, dont dépendent les extensions, les DevTools et
  les fonctionnalités d'onglet ; les DevTools, popups et apps gardent leurs fenêtres
  Chromium.
- **Pont** : `ChordEngine` (conforme à `ChordWebEngine`) crée chaque page comme un
  onglet de son `Browser` ; `ChordPage` (conforme à `ChordWebPage`) enveloppe le
  `WebContents` et donne sa vue native à ChordUI. Les onglets que Chromium ouvre ou
  ferme lui-même (lien en nouvel onglet, `window.open`, extension, `window.close()`)
  remontent à ChordUI par `ChordWebEngineDelegate`. L'onglet sélectionné dans ChordUI
  devient l'onglet actif de Chromium.
- **ChordUI n'est pas lié à Chromium** : il est chargé à l'exécution et joint par le
  runtime Objective-C (`NSClassFromString(@"ChordUIHost")`). Les protocoles ont des noms
  Objective-C fixes, reflétés dans `engine/chord/browser/chord_ui.h`.

## État (24 octobre 2026)

Chord tourne sur Chromium 155. Vérifié par le protocole DevTools : les pages
s'affichent dans les fenêtres de ChordUI (petite fenêtre comprise) ; une extension
non empaquetée injecte ses scripts de contenu dans les pages de Chord ; `chrome.tabs`
voit les onglets de Chord ; un onglet créé par une extension apparaît dans les onglets
du jour. Les DevTools (⌥⌘I) s'ancrent dans la fenêtre de Chord : ils remplissent la
zone de la page (`PageHostView` dans ChordUI) et la page prend la place que leur
disposition lui laisse, comme dans `DevtoolsUIController` de Chromium.

En build de développement, la clé de chiffrement des cookies est dans un trousseau
simulé : sinon macOS demande l'accès au Trousseau à chaque build (la signature change)
et chaque chargement de page attend la réponse.

## Points connus à traiter

- **Icône** : l'app s'appelle Chord mais garde l'icône de Chromium.
- **Pas encore branché** : Peek au ⇧-clic et liens sortant d'un épinglé (une
  `NavigationThrottle` de `//chord`), téléchargements vers le panneau de ChordUI,
  invites de permission (puce d'adresse), plein écran vidéo dans l'interface
  (masquer la barre latérale), recherche dans la page (⌘F).

- **Chrome Web Store** : ungoogled-chromium bloque l'installation d'extensions depuis
  le Web Store. Pour Chord, il faudra la rétablir (patch dédié).
- **Widevine** (Netflix, Spotify…) : absent par défaut, à charger comme composant.
- **Menu principal** : Chromium construit le sien. Choisir entre le remplacer par celui
  de ChordUI et relier ses commandes à celles de ChordUI.
- **Mises à jour** : une version majeure de Chromium toutes les quatre semaines.
  `UPSTREAM` change, les patchs de `patches/` sont réappliqués.

Tout ce qui touche à l'organisation interne de Chromium ci-dessus est un plan,
à confirmer pendant le spike sur la version figée.
