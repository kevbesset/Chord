# Chord

Le navigateur pour ceux qui construisent le web : un successeur d'Arc, natif Mac, sur
Chromium. L'interface est écrite en Swift / AppKit ; le moteur est
[ungoogled-chromium](https://github.com/ungoogled-software/ungoogled-chromium).

> **Statut : préversion.** Chord sert tous les jours à son auteur, mais tout peut encore
> changer. Mac Apple Silicon, macOS 14 ou plus.

## Installer

Télécharger `Chord-<version>.dmg` depuis les
[versions publiées](https://github.com/kevbesset/Chord/releases/latest), ouvrir l'image
et glisser Chord dans Applications. Chord se met ensuite à jour tout seul (il vérifie
une fois par jour, installe au lancement suivant ; « Rechercher les mises à jour… »
dans le menu Chord pour vérifier tout de suite).

Tant que Chord n'est pas notarisé par Apple, macOS refuse de l'ouvrir la première fois :
Réglages Système › Confidentialité et sécurité › « Ouvrir quand même ». Ou, dans un
terminal :

```bash
xattr -dr com.apple.quarantine /Applications/Chord.app
```

## Ce qu'il sait faire

- Barre latérale à la Arc : favoris, épinglés avec dossiers, onglets du jour, Spaces
  (chacun sur son profil, glisser à deux doigts pour passer de l'un à l'autre)
- Barre de commande (⌘T, ⌘L), Peek, split view, petite fenêtre pour les liens d'autres apps
- Import d'Arc : barre latérale, connexions, mots de passe, historique, données des
  sites, extensions du Chrome Web Store
- Extensions Chrome, épinglables dans la barre d'adresse ; DevTools ancrés (⌥⌘I)
- Picture-in-picture automatique, demandes d'autorisation discrètes, réglages du site
- Navigation privée, plusieurs fenêtres, mode clair / sombre, raccourcis remappables

## Construire

Prérequis : Mac Apple Silicon, Xcode 16 ou plus, Homebrew, environ 100 Go d'espace
libre. Le premier build de Chromium prend plusieurs heures.

```bash
brew install xcodegen
engine/scripts/bootstrap.sh && engine/scripts/prepare.sh
engine/scripts/build.sh          # Chromium et ChordUI : out/Chord/Chord.app
engine/scripts/run.sh            # au quotidien : l'interface seule, en quelques secondes
```

Détails dans `engine/README.md`. Publier une version : `docs/RELEASING.md`.

## Structure

```
app/                Interface native (Swift, AppKit)
  ChordUI/          framework : fenêtre, barre latérale, Spaces, barre de commande.
                    Ne connaît aucun moteur, seulement le protocole ChordWebEngine.
  project.yml       définition du projet Xcode (XcodeGen)
engine/             Chromium : version figée, //chord, patchs, marque, scripts
docs/               Vision produit, architecture, budgets de performance, décisions
design/             Maquettes de référence et marque (logo, icône)
CLAUDE.md           Contexte du projet pour Claude Code
```

## Licence

Chord est distribué sous la licence publique générale GNU, version 3 (`LICENSE`).
Chromium et ungoogled-chromium, sur lesquels il repose, gardent leurs propres licences
(BSD pour l'essentiel) ; Chord les liste dans `chord://credits`. Sparkle (mises à jour)
est sous licence MIT.
