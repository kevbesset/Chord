# 0001 — Fork de Chromium, interface remplacée

**Statut :** acceptée, 23 octobre 2026

## Contexte

Chord doit garder les extensions Chrome et les DevTools : c'est non négociable pour
des développeurs. Trois façons d'embarquer Chromium dans une app native ont été comparées.

| Option | Extensions Chrome | DevTools | Effort |
| --- | --- | --- | --- |
| CEF (Chromium Embedded Framework) | Partielles | Moins intégrés | Faible |
| Electron | Partielles | Oui | Faible, mais contraire à la fluidité |
| Fork de Chromium, interface remplacée | Complètes | Complets | Élevé |

## Décision

Fork de Chromium (base : ungoogled-chromium), en gardant tout le processus navigateur
(`//chrome/browser`) et en remplaçant l'interface macOS de Chrome par ChordUI.
Concrètement, une classe `ChordBrowserWindow` implémente l'interface `BrowserWindow`
de Chromium à la place de `BrowserView`.

## Conséquences

- Suivre une version majeure de Chromium toutes les quatre semaines : les patchs
  doivent rester petits et isolés dans `//chord`.
- Un premier jalon technique, le spike 0, avant toute autre fonctionnalité :
  une page Chromium dans une fenêtre ChordUI, DevTools et une extension qui fonctionnent.
- ungoogled-chromium désactive l'installation depuis le Chrome Web Store et Widevine :
  il faudra les rétablir pour que les extensions s'installent normalement.
