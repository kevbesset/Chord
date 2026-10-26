# 0005 — GPL-3.0, versions sur GitHub, mises à jour par Sparkle

**Statut :** acceptée, 26 octobre 2026.

## Contexte

Chord doit pouvoir se partager : une app construite, signée, qui se met à jour seule.
Le dépôt devient public, il lui faut une licence avant le premier contributeur externe.
Il n'y a pas encore de compte Apple Developer payant, donc pas de certificat
Developer ID ni de notarisation.

## Décision

- **Licence : GPL-3.0.** Le code de Chord reste libre, y compris dans ses dérivés. Elle
  est compatible avec les licences de Chromium (BSD et voisines) et de Sparkle (MIT),
  qui restent celles de leur code.
- **Distribution : les versions GitHub du dépôt** (`engine/scripts/release.sh`), une
  image disque par version, Apple Silicon seulement.
- **Mises à jour : Sparkle 2**, flux `appcast.xml` joint à chaque version et lu depuis
  la dernière (`releases/latest/download/appcast.xml`), signé EdDSA. Vérification
  quotidienne, installation silencieuse au lancement suivant, comme Arc.
- **Version** : `VERSION` pour le numéro affiché ; le numéro de build compte les commits,
  ce qui le fait croître d'une version à l'autre.
- **Signature** : `engine/scripts/sign.sh` prend le meilleur certificat disponible
  (Developer ID, sinon Apple Development, sinon ad hoc). Signé par un certificat,
  Chord garde la même identité d'un build à l'autre et range sa clé de chiffrement
  dans le vrai Trousseau (« Chord Safe Storage ») ; ad hoc, dans le trousseau factice
  de Chromium.

## Conséquences

- Sans Developer ID, macOS demande d'autoriser Chord à la première ouverture
  (Confidentialité et sécurité). `package.sh` notarise dès qu'un certificat et des
  identifiants notarytool existent, sans autre changement.
- La clé privée de Sparkle est dans le Trousseau de session de Kevin : la perdre, c'est
  ne plus pouvoir publier de mise à jour que les Chord installés acceptent. Elle se
  sauvegarde avec `sparkle-tool.sh generate_keys -x <fichier>`.
- Les extensions du Chrome Web Store et les composants (Widevine…) passent par les
  serveurs de Google, que ungoogled-chromium coupait : ce sont les seuls.
