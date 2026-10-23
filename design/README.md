# Design

## Maquettes

`mockups/` contient la source des maquettes de l'interface, une par écran.
Ce sont des fichiers HTML d'un outil de design : ils ne s'ouvrent pas tels quels
dans un navigateur (il leur manque leur moteur de rendu), mais ils servent de
référence exacte pour les couleurs, espacements, rayons, tailles de police et ombres.

La version visuelle et éditable est sur le canvas « Chord — Fenêtre principale »,
dans la galerie d'artefacts du compte Claude de Kevin.

| Fichier | Écran |
| --- | --- |
| `Main.dc.html` | Fenêtre principale, barre de commande ouverte |
| `TopBar.dc.html` | Variante : barre d'adresse en haut, intégrée à la page (32 px) |
| `Collapsed.dc.html` | Barre latérale repliée (⌘S) : seulement le cadre et la page |
| `CollapsedHover.dc.html` | Repliée, survol du bord gauche : barre latérale flottante |
| `Edgeless.dc.html` | Mode edgeless (réglage) |
| `Peek.dc.html` | Peek : aperçu d'un lien par-dessus la page |
| `Split.dc.html` | Split view (⇧⌘D) |
| `Dark.dc.html` | Mode sombre |
| `Desktop.dc.html` | Sur un fond d'écran : test du verre avec une page colorée |
| `Little.dc.html` | Petite fenêtre flottante (⌥⌘N) |
| `LogoConcepts.dc.html` | Les trois pistes de marque étudiées |
| `AppIcon.dc.html` | Icône d'app à toutes les tailles |
| `Wordmark.dc.html` | Logo clair, sombre, monochrome, signature |

## Marque

`brand/chord-mark.svg` (le symbole) et `brand/chord-app-icon.svg` (l'icône d'app
en 1024 px) : l'arc et sa corde. L'arc prend la couleur du texte, la corde l'accent
(`#5B6CFF` par défaut, ou la couleur du Space actif dans l'app).

## Valeurs de référence

| Élément | Valeur |
| --- | --- |
| Largeur de la barre latérale | 256 px |
| Marge autour de la carte de contenu | 10 px (0 en edgeless) |
| Rayon de la carte | 10 à 12 px |
| Teinte du Space sur le verre | 7 % de la couleur du Space |
| Hauteur d'une ligne d'onglet | 32 px |
| Barre de commande | 680 px de large, rayon 16, résultats de 44 px |
| Palette des Spaces | `#5B6CFF` `#2E7D4F` `#B4530A` `#6E56CF` `#0E7490` `#C2410C` |
| Police | SF Pro (système) |
