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

### Étape 1 — Build de référence

Valider la chaîne de compilation avant de toucher au code.

```bash
engine/scripts/bootstrap.sh          # prérequis + sources à la bonne version
cd engine/vendor/ungoogled-chromium-macos
./build.sh                           # plusieurs heures
```

Résultat attendu : un Chromium qui se lance. Noter la durée du build et l'espace
disque consommé.

### Étape 2 — `//chord` dans l'arbre

Un dossier `chord/` dans les sources de Chromium (lien vers `engine/chord`),
une cible GN `//chord:core`, liée à `//chrome/browser`.

### Étape 3 — Remplacer la fenêtre

Dans Chromium, `BrowserWindow` (`chrome/browser/ui/browser_window.h`) est une
interface ; `BrowserView` en est l'implémentation à base de Views. Chord fournit la
sienne, `ChordBrowserWindow`, et un patch redirige la fabrique
`BrowserWindow::CreateBrowserWindow` vers elle. La plupart des méthodes commencent
vides ; on les remplit au besoin.

On garde `Browser` et `TabStripModel` : c'est ce que les API d'extension
(`chrome.tabs`, `chrome.windows`) utilisent.

### Étape 4 — Le pont vers ChordUI

`ChordPage`, une classe Objective-C++ conforme au protocole `ChordWebPage`
(`app/ChordUI/Engine/ChordWebEngine.swift`), enveloppe un `content::WebContents`.
Sa vue est `web_contents->GetNativeView().GetNativeNSView()`.
`ChordEngine`, conforme à `ChordWebEngine`, crée les `WebContents` dans le profil.

### Étape 5 — Embarquer ChordUI

`ChordUI.framework`, compilé par Xcode, est copié dans `Chord.app/Contents/Frameworks`
et lié à `//chord:core`. Chromium garde la main sur `NSApplication`
(`BrowserCrApplication`) ; ChordUI ne crée que des fenêtres et un menu.

## Points connus à traiter

- **Chrome Web Store** : ungoogled-chromium bloque l'installation d'extensions depuis
  le Web Store. Pour Chord, il faudra la rétablir (patch dédié).
- **Widevine** (Netflix, Spotify…) : absent par défaut, à charger comme composant.
- **Menu principal** : Chromium construit le sien. Choisir entre le remplacer par celui
  de ChordUI et relier ses commandes à celles de ChordUI.
- **Mises à jour** : une version majeure de Chromium toutes les quatre semaines.
  `UPSTREAM` change, les patchs de `patches/` sont réappliqués.

Tout ce qui touche à l'organisation interne de Chromium ci-dessus est un plan,
à confirmer pendant le spike sur la version figée.
