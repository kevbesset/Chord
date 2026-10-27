# Chord's brand in Chromium

`src/` mirrors Chromium's source tree: `engine/scripts/build.sh` copies these files over
Chromium's (only when their content changes). This is Chord's logo wherever Chromium's
internal pages show their own (`chord://settings`, `chord://extensions`, "About"):

- `chrome/app/theme/…/product_logo_*.png` and `product_logo.svg`: the symbol on a light
  background (`chrome://theme/current-channel-logo`), rendered from
  `design/brand/chord-mark.svg`;
- `ui/webui/resources/images/chrome_logo_dark.svg`: the symbol on a dark background.

- `chrome/app/theme/chromium/mac/Assets.car` and `app.icns`: the app icon (Dock,
  Finder), compiled by `icon/make-icon.sh` from `icon/AppIcon.icon` (Icon Composer
  format: indigo background, white arc, glass chord).

The PNGs are redone from the SVG if the symbol changes.
