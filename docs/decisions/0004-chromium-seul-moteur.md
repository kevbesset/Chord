# 0004 — Chromium, seul moteur, développement compris

**Statut :** acceptée, 24 octobre 2026. Remplace 0003.

## Contexte

La décision 0003 donnait à l'interface une app de développement sur WebKit
(ChordDev), parce que chaque changement aurait sinon demandé de recompiler Chromium.
Le spike 0 a montré que ce n'est pas le cas : ChordUI.framework n'est pas lié à
Chromium, `//chord` le charge à l'exécution. Recompiler l'interface et la remettre
dans Chord.app prend quelques secondes. Deux moteurs, c'était deux comportements à
comprendre (le Trousseau, les DevTools, les extensions n'existaient que d'un côté).

## Décision

Chord ne tourne que sur Chromium, y compris pendant le développement. ChordDev et
son moteur WebKit sont retirés. La boucle quotidienne est `engine/scripts/run.sh`
(ChordUI seul) ; `engine/scripts/build.sh` reconstruit Chromium quand `//chord` ou
les patchs changent.

## Conséquences

- Ce qu'on voit en développement est ce qui sera livré : extensions, DevTools,
  `chrome://`, rendu.
- Il faut avoir construit Chromium une fois (plusieurs heures) avant de toucher à
  l'interface.
- La règle d'architecture reste : ChordUI ne dépend que des protocoles
  `ChordWebEngine` / `ChordWebPage`, ce qui garde ouverte la porte d'autres moteurs.
