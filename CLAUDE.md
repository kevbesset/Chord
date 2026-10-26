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

Chord, c'est Chromium (ungoogled-chromium) avec ChordUI chargé dedans. Une fois :

```bash
engine/scripts/bootstrap.sh && engine/scripts/prepare.sh
engine/scripts/build.sh          # plusieurs heures la première fois ; à relancer
                                 # quand //chord ou engine/patches changent
```

Au quotidien, pour l'interface (quelques secondes, sans recompiler Chromium) :

```bash
engine/scripts/run.sh            # recompile ChordUI, le remet dans Chord.app, relance
```

Dans Xcode, le schéma **Chord** fait la même chose : Build (⌘B) ou Run (⌘R) compile
ChordUI, l'installe dans Chord.app et relance Chord (journal : `app/build/run-chord.log`).

`Chord.xcodeproj` est généré depuis `app/project.yml` et ignoré par git : on modifie
`project.yml`, jamais le projet. Après une modification de code, toujours recompiler
et corriger les erreurs avant de rendre la main.

## Règles

- **ChordUI ne connaît aucun moteur.** Jamais d'en-tête de Chromium (ni d'`import
  WebKit`) dans `app/ChordUI` : tout passe par les protocoles `@objc` de
  `app/ChordUI/Engine/ChordWebEngine.swift`, que `engine/chord` implémente. Chromium est
  le seul moteur, développement compris (`docs/decisions/0004`).
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

- Interface native complète (ChordUI), sur Chromium : fenêtre en
  verre translucide (aussi inactive), déplaçable depuis tout le vide de la barre latérale,
  barre latérale redimensionnable, profils comme Arc (chaque profil est un vrai profil
  Chromium : session, cookies, extensions et favoris à part ; un nouveau Space a le sien),
  épinglés avec dossiers,
  vraies icônes des sites (cache disque, reprises d'Arc à l'import), glisser-déposer des
  onglets et dossiers (ordre, dossiers, épingler, favoris, autre Space, liens d'autres apps), Spaces (couleur, nom, ⌃1…⌃9,
  glisser deux doigts qui suit les doigts comme Arc), favoris en grille aux rangées pleines, barre de commande (compacte sur le champ d'adresse au clic ou ⌘L, comme Arc), Peek (⇧-clic, liens sortant d'un épinglé),
  split view (⌃⇧=, 2 à 4 volets), petite fenêtre (⌥⌘N, liens d'autres apps), barre
  d'adresse en haut ou latérale (⇧⌘D, copie de l'URL au survol avec confirmation), mode clair/sombre, edgeless, réglages (⌘,) avec raccourcis
  remappables, import d'Arc (barre latérale, puis connexions, mots de passe, historique et
  données des sites de chaque profil Arc dans le profil Chord de ses Spaces), page d'accueil (quand aucun onglet
  n'est ouvert : fermer un onglet ramène au dernier onglet encore actif, jamais à un
  onglet en veille), téléchargements (panneau façon Arc, ⇧⌘J), session.
- **Chord sur Chromium** (spike 0, `engine/`) : ChordUI tourne dans Chromium 155
  (ungoogled-chromium), construit par `engine/scripts/build.sh`. Vérifié : les pages
  s'affichent dans les fenêtres de Chord, les extensions marchent (scripts de contenu,
  `chrome.tabs`, onglets ouverts par une extension adoptés par ChordUI), DevTools (⌥⌘I)
  ancrés dans la fenêtre à droite, à gauche ou en bas, ou dans leur propre fenêtre.
- Plusieurs fenêtres (⌘N) sur les mêmes Spaces, chacune avec son Space et ses onglets
  sélectionnés (`WindowSelection`) ; navigation privée (⇧⌘N) sur le profil incognito de
  Chromium, fenêtre sombre, rien d'enregistré ; ⌘← / ⌘→ pour l'historique (sauf en
  saisie de texte).
- Picture-in-picture comme Arc : une vidéo en lecture passe dans la fenêtre PiP de
  Chromium (flottante, déplaçable, redimensionnable) quand son onglet quitte l'écran,
  et revient à son retour ; « retour à l'onglet » sélectionne l'onglet dans ChordUI ;
  ⌃⌘P à la main ; réglage « Picture-in-picture automatique ».
- Demandes de permission des pages : petite bulle discrète en haut de la page, comme
  Arc (Bloquer / Autoriser), qui ne bloque pas la page ; double-clic sur la vidéo PiP
  ou « retour à l'onglet » : l'onglet revient, Space compris.
- Réglages du site comme Arc (bouton interrupteurs dans le champ d'adresse, barre
  latérale ou barre du haut) : carte avec copier, partager, les notifications et les
  autorisations choisies pour le site (interrupteurs, gardées dans les content settings
  de Chromium) et un lien vers tous les réglages du site.
- `chord://` pour les pages internes de Chromium (`chord://settings`,
  `chord://extensions`, aussi dans la barre de commande).
- Après un plantage, le lancement suivant écrit un rapport lisible dans
  `~/Library/Logs/Chord/latest-crash.md` (pile du fil fautif, message d'erreur de
  Chromium s'il y en a un, capté par //chord dans `last-fatal.txt`) et le propose.
- Pas encore côté Chromium : icône de Chord (l'app s'appelle Chord, icône de Chromium),
  Peek au ⇧-clic, téléchargements dans le panneau de Chord,
  plein écran vidéo dans l'interface, recherche dans la page.
- Licence : pas encore choisie, à trancher avant le premier contributeur externe.
