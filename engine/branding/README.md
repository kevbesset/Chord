# Marque de Chord dans Chromium

`src/` reproduit l'arborescence des sources de Chromium : `engine/scripts/build.sh` y
copie ces fichiers par-dessus ceux de Chromium (seulement quand leur contenu change).
C'est le logo de Chord là où les pages internes de Chromium montrent le sien
(`chord://settings`, `chord://extensions`, « À propos ») :

- `chrome/app/theme/…/product_logo_*.png` et `product_logo.svg` : le symbole sur fond
  clair (`chrome://theme/current-channel-logo`), rendu depuis `design/brand/chord-mark.svg` ;
- `ui/webui/resources/images/chrome_logo_dark.svg` : le symbole sur fond sombre.

- `chrome/app/theme/chromium/mac/Assets.car` et `app.icns` : l'icône de l'app (Dock,
  Finder), compilée par `icon/make-icon.sh` depuis `icon/AppIcon.icon` (format Icon
  Composer : fond indigo, arc blanc, corde en verre).

Les PNG se refont depuis le SVG si le symbole change.
