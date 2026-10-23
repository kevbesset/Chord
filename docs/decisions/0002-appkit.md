# 0002 — AppKit pour l'interface principale

**Statut :** acceptée, 23 octobre 2026

## Contexte

L'interface de Chord a des budgets de latence stricts (`docs/PERFORMANCE.md`) et des
listes potentiellement longues (plus de cent onglets dans la barre latérale).

## Décision

La fenêtre, la barre latérale, la barre de commande et tout ce qui est sur le chemin
critique sont écrits en AppKit : `NSTableView` pour les listes (cellules recyclées),
couches Core Animation pour le verre et les ombres, Auto Layout explicite.
SwiftUI reste autorisé pour les écrans secondaires (réglages, à propos).

## Conséquences

- Plus de code que SwiftUI pour la même interface.
- Contrôle direct sur ce qui est recalculé et redessiné à chaque interaction.
- Pas de dépendance à la machinerie de mise à jour de SwiftUI dans les chemins mesurés.
