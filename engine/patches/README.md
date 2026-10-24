# Patchs Chromium de Chord

Règles, pour que la mise à jour toutes les quatre semaines reste un simple rebase :

- Le code de Chord vit dans `//chord` (`engine/chord`), pas dans les fichiers de Google.
- Un patch ne fait que brancher `//chord` : rediriger une fabrique, ajouter une
  dépendance GN, exposer un point d'entrée. Quelques lignes chacun.
- Un patch par intention, nommé par ce qu'il fait.
- Appliqués par-dessus les patchs d'ungoogled-chromium, dans l'ordre de `series`, par
  `engine/scripts/build.sh` (une seule fois chacun : un marqueur `.chord-patch-<nom>`
  reste dans l'arbre des sources).

| Patch | Ce qu'il branche |
| --- | --- |
| `chord-link-build.patch` | `//chord:browser` est lié au navigateur (`chrome/BUILD.gn`, groupe `dependencies`, macOS seulement) |
| `chord-start-ui.patch` | Les « extra parts » de Chord : pas de fenêtre Chromium au démarrage, puis ChordUI démarre (`chrome_browser_main.cc`) |
| `chord-browser-window-factory.patch` | Un navigateur normal reçoit la fenêtre de Chord, `ChordBrowserWindow` (`browser_window_factory.cc`) |
| `chord-branding.patch` | L'app s'appelle Chord (`app.chord.Chord`) ; le dossier de données reste `~/Library/Application Support/Chromium` (`chrome/app/theme/chromium/BRANDING`) |
| `chord-fix-development-link.patch` | Correctif de build : en build de développement, un appel à une aide de test qu'ungoogled-chromium supprime empêchait l'édition de liens (`profile_management_disclaimer_service.cc`) |
| `chord-app-controller.patch` | L'icône du Dock rouvre la fenêtre de Chord ; les liens d'autres apps vont à une petite fenêtre ; les menus Signets et Historique de Chromium ne sont plus tenus à jour, le menu étant celui de ChordUI (`app_controller_mac.mm`) |

Les points d'appel sont déclarés dans `engine/chord/browser/chord_hooks.h`.
`--disable-chord-ui` au lancement rend à Chromium son interface, pour déboguer.
