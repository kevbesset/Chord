# 0003 — Moteur WebKit provisoire pour développer l'interface

**Statut :** acceptée, 23 octobre 2026

## Contexte

Compiler Chromium prend plusieurs heures et une centaine de gigaoctets. Itérer sur
l'interface (une animation, un espacement) ne peut pas dépendre de ce cycle.

## Décision

ChordUI ne parle qu'aux protocoles `ChordWebEngine` / `ChordWebPage`. L'app ChordDev
les implémente avec WebKit (`WKWebView`), le moteur fourni avec macOS. Elle sert
uniquement au développement de l'interface et n'est jamais distribuée.

## Conséquences

- Itération sur l'interface en quelques secondes.
- Tout ce qui est propre à un moteur reste hors de ChordUI ; la règle est vérifiable :
  aucun `import WebKit` dans `app/ChordUI`.
- Le comportement web (extensions, DevTools, rendu) ne se juge que sur la version
  Chromium.
- Ce découpage prépare aussi l'horizon multi-moteur : WebKit pourra devenir un vrai
  moteur au choix, plus tard.
