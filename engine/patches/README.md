# Patchs Chromium de Chord

Vide pour l'instant. Règles, pour que la mise à jour toutes les quatre semaines
reste un simple rebase :

- Le code de Chord vit dans `//chord`, pas dans les fichiers de Google.
- Un patch ne fait que brancher `//chord` : rediriger une fabrique, ajouter une
  dépendance GN, exposer un point d'entrée. Quelques lignes chacun.
- Un patch par intention, nommé par ce qu'il fait :
  `chord-browser-window-factory.patch`, `chord-restore-web-store.patch`…
- Appliqués par-dessus les patchs d'ungoogled-chromium, dans l'ordre de `series`.
