# Chord — Vision produit

23 octobre 2026 · Kevin

## Pourquoi Chord

Arc est un navigateur mort-vivant, et la place qu'il laisse est vide. The Browser Company a gelé son développement le 27 mai 2025 pour se consacrer à Dia ; Atlassian a racheté la société pour 610 M$ le 21 octobre 2025. Arc fonctionne encore et reçoit les correctifs de sécurité de Chromium, mais n'aura plus aucune fonctionnalité et n'a pas de date de fin annoncée.

Le trou dans le marché est précis : en 2026, aucun navigateur open source basé sur Chromium ne reprend le modèle complet d'Arc (barre latérale, Spaces, barre de commande, Peek, split view). L'alternative open source la plus proche, Zen, est basée sur Firefox. Vivaldi couvre une partie du périmètre mais son interface est fermée. Et les développeurs, cœur de cible historique d'Arc, n'ont jamais eu de version Linux.

Chord vise cette place : l'Arc open source, sur Chromium, pensé pour ceux qui construisent le web.

Le projet ne fait pas de rétro-ingénierie du binaire d'Arc : la valeur d'Arc est dans son UX, pas dans son code, et une reconstruction « clean room » (observer, documenter, réimplémenter) évite tout risque juridique avec Atlassian.

## Vision

**Arc, en plus rapide, ouvert pour toujours, et pensé pour ceux qui construisent le web.**

Trois credos guident chaque décision :

1. **Un nouvel Arc, modernisé, fluide et ultra rapide.** On reprend l'UX d'Arc telle quelle, parce qu'elle était bonne, et on la rend plus belle et plus réactive. Pas de réinvention.
2. **Une IA discrète.** Pas d'IA injectée partout. C'est précisément ce que la communauté a reproché à Dia. L'IA viendra, plus tard, là où elle sert vraiment, jamais au premier plan.
3. **Le navigateur du développement et de la productivité.** Les outils pour développeurs sont l'horizon qui justifie le positionnement, mais ils n'arrivent qu'une fois la base irréprochable.

L'ordre des priorités est strict : d'abord un très beau et très fluide navigateur, ensuite seulement les grosses fonctionnalités.

## Cible et récit

**Cible :** les développeurs front et full-stack qui jonglent toute la journée entre localhost, staging, production, la documentation, les dashboards, les pull requests et, de plus en plus, leurs agents de code. Et, dès le premier jour, les réfugiés d'Arc qui cherchent leur barre latérale.

**Récit :** Arc a été gelé parce qu'une entreprise l'a décidé. Chord est open source : quoi qu'il arrive au projet, son code lui survit, et n'importe qui peut le reprendre. Chord ne pourra jamais disparaître comme Arc.

Ce récit tient avec n'importe quelle licence open source et ne ferme pas la porte à un rachat ; il promet la survie du code, pas l'absence de propriétaire.

## Principes de design

Chord reprend l'UX d'Arc mais pas son look : là où Arc était coloré et ludique, Chord est calme, premium et natif, dans l'esprit de Safari.

1. **Le contenu d'abord.** L'interface s'efface ; la page web est la star. La page flotte dans une carte aux coins arrondis, et la barre latérale se replie d'un geste.
2. **De la matière plutôt que de la couleur.** Des matériaux translucides natifs de macOS (NSVisualEffectView, le langage Liquid Glass) au lieu des grands aplats colorés. Le fond d'écran traverse la barre latérale et le cadre de la fenêtre. Chaque Space garde sa couleur, sous forme de teinte discrète (environ 7 %) et d'accents : onglet actif, pastille du Space, résultat sélectionné dans la barre de commande.
3. **Un mouvement physique.** Animations à ressort, courtes et interruptibles : on peut changer d'avis en plein geste.
4. **Natif jusqu'au détail.** Interface en Swift, typographie SF Pro, icônes SF Symbols, raccourcis et gestes standards de macOS. Pas d'Electron.
5. **Une densité maîtrisée.** Un développeur a 40 onglets ouverts : la barre latérale doit rester lisible et élégante même chargée.

La barre de commande est la pièce maîtresse : verre translucide, résultats groupés (onglets ouverts, actions, recherche), raccourcis visibles, aide-mémoire en pied. Elle doit être l'élément le plus rapide du navigateur.

Les maquettes de référence (fenêtre principale, variantes, états, test du verre) sont sur le canvas « Chord — Fenêtre principale ».

## Budgets de latence

La fluidité est une règle mesurée, pas une promesse : chaque interaction a un budget, vérifié automatiquement en intégration continue. Une fonctionnalité qui dépasse son budget ne sort pas. Le repère est connu : en dessous de 100 ms, une action paraît instantanée.

| Interaction | Budget cible |
| --- | --- |
| Ouvrir la barre de commande | < 50 ms |
| Changer de Space | < 100 ms, animation sans saccade |
| Ouvrir un nouvel onglet | < 100 ms |
| Replier ou déplier la barre latérale | < 50 ms |
| Ouvrir un Peek | < 100 ms |
| Démarrage à froid | < 1 s jusqu'à une fenêtre utilisable |
| Défilement et animations | 120 images/s sur ProMotion, aucune image sautée |
| Onglets inactifs | mise en veille automatique pour libérer la mémoire |

Ces chiffres sont des cibles de départ, à affiner avec les premières mesures sur Apple Silicon.

## Parité Arc de la v1

Un utilisateur d'Arc doit se sentir chez lui dès la première minute. La v1 reprend six fonctionnalités ; les Boosts attendront.

| Fonctionnalité | Ce qu'on garde d'Arc | La touche Chord |
| --- | --- | --- |
| Barre latérale | Onglets verticaux, favoris, épinglés, onglets du jour, « Nouvel onglet » en tête des onglets du jour | Matériau translucide ; ligne compacte feux + navigation + repli ; Spaces et téléchargements en bas ; repliée, elle réapparaît en panneau flottant au survol du bord gauche |
| Spaces | Contextes séparés, glisser pour changer | Teinte discrète, changement < 100 ms |
| Barre de commande | Tout au clavier (⌘L) | La pièce maîtresse : verre, résultats groupés, raccourcis visibles |
| Peek | Aperçu d'un lien sans quitter la page | Fenêtre flottante à ressort, « Ouvrir dans un onglet », split view direct |
| Split view | Plusieurs pages côte à côte (⌃⇧=) | Chaque volet porte sa propre adresse ; volet actif cerclé de la couleur du Space ; redimensionnement à 120 images/s |
| Petite fenêtre (Little Arc) | Mini-fenêtre flottante pour un lien ouvert depuis une autre app (⌥⌘N) | En verre, « Ouvrir dans Chord » ; nom définitif à trouver |

Deux dispositions de la barre d'adresse sont prévues dès la v1 : dans la barre latérale (par défaut, comme Arc) ou intégrée en haut de la page, en 32 px, avec les actions à droite (style Safari).

**Import depuis Arc en un clic, au premier lancement.** Arc stocke sa barre latérale (Spaces, favoris, épinglés, dossiers) dans un fichier JSON local. Au premier lancement, Chord le détecte et propose de tout reprendre à l'identique, avec l'historique, les mots de passe et les cookies comme le fait l'import depuis Chrome. C'est probablement la fonctionnalité d'acquisition la plus efficace du projet : le réfugié d'Arc retrouve son navigateur en un clic.

## Personnalisation et raccourcis

La personnalisation et les raccourcis clavier sont des piliers, pas des options. La v1 reprend les outils de personnalisation d'Arc et en ajoute deux.

**Personnalisation (v1)**

- Couleur et nom de chaque Space
- Mode clair, sombre ou automatique
- Edgeless : la page collée aux bords, sans arrondi ni ombre (nouveau)
- Barre d'adresse : latérale ou en haut de la page (nouveau)
- Largeur de la barre latérale
- Favoris épinglés (4 à 8)
- Thème de la barre de commande
- Raccourcis remappables

**Raccourcis par défaut**

| Raccourci | Action |
| --- | --- |
| ⌘L | Barre de commande |
| ⌘T | Nouvel onglet |
| ⌘S | Replier / déplier la barre latérale |
| ⌃⇧= | Split view |
| ⇧⌘D | Barre d'adresse en haut ou dans la barre latérale |
| ⌥⌘N | Petite fenêtre |
| ⇧⌘C | Copier l'URL |
| ⌃Tab | Onglet suivant |
| ⌥⌘← / → | Space précédent / suivant |
| ⇧⌘J | Téléchargements |
| ⌘W | Fermer l'onglet (archive) |
| ⌘1 à ⌘9 | Onglet épinglé n |

Les raccourcis reprennent ceux d'Arc partout où ils existent, pour que les anciens utilisateurs n'aient rien à réapprendre.

## Choix techniques

**Moteur : Chromium, via ungoogled-chromium.** C'est le seul choix compatible avec la cible : les développeurs vivent dans les Chrome DevTools et les extensions Chrome. ungoogled-chromium (licence BSD-3) retire les services Google et fournit déjà un dépôt de packaging Mac, ungoogled-chromium-macos ; Helium, envisagé un temps, est construit sur cette même base mais sous GPL-3, ce qui aurait figé la licence de Chord. Les bonnes idées d'Helium (bloqueur intégré, interface nettoyée) se réimplémentent sans copier son code.

**Intégration : un fork de Chromium avec l'interface remplacée.** C'est l'approche d'Arc. On garde tout le processus navigateur de Chromium (extensions Chrome, DevTools, profils, mots de passe) et on remplace l'interface macOS de Chrome par des fenêtres natives en Swift qui hébergent le contenu web. CEF (Chromium Embedded Framework), plus rapide à démarrer, est écarté : il n'embarque pas la couche navigateur de Chrome et ne supporte les extensions que partiellement. Pas d'Electron non plus. Les matériaux translucides passent par NSVisualEffectView, les animations par des ressorts interruptibles (CASpringAnimation).

**Premier jalon technique : le spike 0.** Une fenêtre Swift qui affiche une page Chromium, avec les DevTools et une extension Chrome qui fonctionnent. Rien d'autre n'est construit avant qu'il tienne.

**Plateforme : macOS uniquement, Apple Silicon d'abord.** Windows et Linux viendront après, si le projet trouve sa communauté.

**Coût à ne pas sous-estimer :** suivre Chromium, c'est absorber une nouvelle version majeure toutes les quatre semaines. En solo, c'est le plus gros risque du projet ; la v1 doit rester volontairement petite.

**Multi-moteur, plus tard.** L'architecture isole le moteur derrière une couche commune (historique, cookies, téléchargements) pour pouvoir brancher WebKit (livré avec macOS, c'est le vrai moteur de Safari) dans une v2, puis explorer Gecko. Ce n'est pas un objectif de la v1.

**DevTools personnalisables.** L'interface des DevTools est un projet open source à part (devtools-frontend, BSD-3), écrit en TypeScript avec des web components, et embarqué dans Chromium. Dans un fork, on peut la modifier entièrement : retravailler le mode responsive, ajouter des panneaux, des options d'émulation. Elle se développe sans recompiler Chromium, en la servant à un navigateur lancé avec le flag `--custom-devtools-frontend`. Règle de maintenance : ajouter des modules plutôt que réécrire les panneaux existants, pour que la mise à jour toutes les quatre semaines reste un rebase simple.

## Open source, licence et modèle économique

Chord est open source. C'est la réponse au problème d'Arc : le code appartient à la communauté et survit au projet.

**Licence : à trancher avant le premier contributeur externe.** Tant que Kevin possède 100 % du code, il peut changer de licence quand il veut. Dès qu'un contributeur arrive, il faut son accord, d'où un CLA (Contributor License Agreement) dès le premier jour, qui garde la possibilité de relicencier, de proposer une édition commerciale, ou d'accepter un rachat. Ce qui a été publié reste ouvert pour toujours ; seules les versions futures peuvent changer.

| Option | Pour le projet | Pour la communauté |
| --- | --- | --- |
| Apache-2.0 | Liberté maximale, rachat simple | N'importe qui peut aussi faire une version fermée |
| MPL-2.0 | Modules propriétaires possibles à côté | Les fichiers modifiés restent ouverts |
| GPL-3 + CLA | Seul le détenteur du CLA peut fermer ou vendre | Garantie forte, mais inspire moins confiance aux entreprises |

**Modèle économique :** gratuit, financé par les dons (GitHub Sponsors, Open Collective). Si le projet grandit, le modèle classique d'un navigateur ouvert est de vendre des services, jamais le code : synchronisation entre appareils, fonctionnalités Pro hébergées, support aux équipes. Aucune monétisation des utilisateurs ni de leurs données.

- [ ] Choisir la licence (avis juridique recommandé)
- [ ] Rédiger le CLA
- [ ] Vérifier le nom « Chord » : domaine, organisation GitHub, marques (INPI, EUIPO)

## Ce qu'on ne fait pas, pour l'instant

- Pas d'IA envahissante à la Dia
- Pas de compte obligatoire
- Pas de Windows ni de Linux
- Pas de multi-moteur en v1
- Pas de Boosts en v1
- Pas de grosse fonctionnalité tant que l'expérience de base n'est pas impeccable

**Horizon, une fois la base solide :** les outils pour développeurs qui justifient le positionnement. Pistes déjà notées : un Space lié à un repo qui détecte les serveurs de dev et l'état des PR ; le changement d'environnement local / staging / prod en un raccourci ; des sessions isolées par onglet ; un split view responsive avec scroll synchronisé ; une barre de commande orientée dev (vider le storage, copier en cURL, ouvrir le composant dans l'éditeur) ; et un serveur MCP intégré pour que les agents de code pilotent le navigateur.

## Feuille de route

Phases sans dates : l'ordre et les portes comptent, pas le calendrier.

| Phase | Contenu |
| --- | --- |
| 0 · Fondations | Build de Chromium, coque Swift et fenêtre, moteur et onglets, latence mesurée en CI |
| 1 · Parité Arc | Barre latérale et Spaces, barre de commande, Peek et split view, petite fenêtre, mode sombre et edgeless |
| *Porte* | *Budgets de latence tenus* |
| 2 · Bêta publique | Dépôt public, licence et CLA, dons activés, import depuis Arc, extensions Chrome |
| *Porte* | *Communauté et dons en place* |
| 3 · Outils pour développeurs | Space lié à un repo, local / staging / prod, commandes dev, serveur MCP |
| 4 · Horizon | Moteur WebKit, Boosts, Windows et Linux, synchronisation |

La phase 1 est la seule qui compte au début : rien ne passe la première porte tant que les budgets de latence ne sont pas tenus. Les outils pour développeurs n'arrivent qu'en phase 3, une fois la communauté installée.

## Identité

**Nom : Chord.** En géométrie, la corde est le segment qui relie les deux extrémités d'un arc. Le nom dit la filiation avec Arc sans la copier, il est court, prononçable dans toutes les langues, et aucun navigateur ne le porte. À vérifier avant toute annonce : le domaine, l'organisation GitHub et les marques déposées (INPI, EUIPO).

**Marque : l'arc et sa corde.** Un arc de cercle ouvert, fermé par la corde qui relie ses deux extrémités. C'est littéralement la définition du mot, et le récit du projet en une forme : Chord est ce qui vient fermer l'arc. L'arc porte la couleur du texte (noir sur clair, blanc sur sombre), la corde porte l'accent, indigo par défaut ou la couleur du Space actif dans l'application. En monochrome, les deux partagent le même trait.

**Icône d'app :** fond indigo profond uni, sans dégradé, l'arc en blanc et la corde en indigo clair. Le trait s'épaissit aux petites tailles pour rester lisible en 16 px ; la barre de menus utilise le glyphe monochrome.

**Logo :** le symbole suivi du mot « Chord » en SF Pro Display Semibold, interlettrage resserré, jamais en capitales. Signature : « The browser that closes the arc. »

Les trois pistes étudiées, l'icône à toutes les tailles et les versions claire, sombre et monochrome du logo sont sur le canvas « Chord — Fenêtre principale », rangée « Identité ».

## Sources

- [Is Arc Browser Dead? (SupaSidebar)](https://supasidebar.com/blog/is-arc-browser-dead)
- [Arc Browser Status 2026 (SuperchargeBrowser)](https://www.superchargebrowser.com/library/arc-browser-status-2026/)
- [Is There an Open-Source Arc Browser? (SupaSidebar)](https://supasidebar.com/blog/open-source-arc-browser)
- [Arc-Like Chromium Browsers Ranked (SuperchargeBrowser)](https://www.superchargebrowser.com/library/open-source-chromium-arc-like-browsers-2026/)
- [ungoogled-chromium (Wikipedia)](https://en.wikipedia.org/wiki/Ungoogled_Chromium)
- [ungoogled-chromium-macos (GitHub)](https://github.com/ungoogled-software/ungoogled-chromium-macos)
- [Helium (GitHub)](https://github.com/imputnet/helium)
