# Publier une version

Une version, c'est une image disque signée sur la page des versions GitHub, avec
l'`appcast.xml` que lisent les Chord installés (décision 0005).

## Une fois

- La clé des mises à jour : `engine/scripts/sparkle-tool.sh generate_keys` la crée dans le
  Trousseau (déjà fait ; la clé publique est dans `engine/scripts/package.sh`). La
  sauvegarder hors du Mac : `engine/scripts/sparkle-tool.sh generate_keys -x sparkle-key` (ignoré par git),
  puis ranger le fichier en lieu sûr (gestionnaire de mots de passe) et le supprimer.
- `gh auth login` avec un compte qui peut publier sur `kevbesset/Chord`.
- Plus tard, avec un compte Apple Developer : un certificat « Developer ID Application »
  dans le Trousseau, et `xcrun notarytool store-credentials chord-notary --apple-id …
  --team-id …`. `package.sh` notarise alors tout seul.

## À chaque version

```bash
# 1. le numéro dans VERSION (0.1.0 → 0.2.0), commit, push
engine/scripts/build.sh --release   # Chromium optimisé (LTO) : long la première fois
engine/scripts/package.sh           # dist/Chord-<version>.dmg, signé (notarisé si possible)
engine/scripts/release.sh           # appcast signé, puis demande avant de publier
```

`package.sh --dev` empaquette le build de développement, pour essayer la chaîne sans
attendre un build release.

Avant de publier, ouvrir l'image, installer Chord à côté et vérifier qu'il se lance,
que les sites connectés le sont encore et qu'une extension s'installe.
