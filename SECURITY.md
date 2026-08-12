# Politique de sécurité

## Signaler une vulnérabilité

Merci de signaler toute faille de sécurité **en privé**, jamais via une issue ou une PR
publique.

- Écrivez à **security@gafeso.org**.
- Décrivez la vulnérabilité, son impact, et les étapes pour la reproduire.
- Si possible, indiquez la version / le commit concerné et l'appareil de test.

Nous nous efforçons d'accuser réception rapidement et de vous tenir informé du traitement.
Merci de nous laisser un délai raisonnable pour corriger avant toute divulgation publique.

## Portée d'intérêt particulier

Le cœur sensible de ce projet est le **modèle de sécurité de la lecture hors-ligne** :

- contournement du chiffrement au repos ou extraction du contenu en clair ;
- déballage de la clé de contenu hors de l'appareil autorisé ;
- falsification ou rejeu de licence, contournement de l'expiration ou de la révocation ;
- contournement des protections d'écran (`FLAG_SECURE`, filigrane).

Nous savons qu'aucune protection côté client n'est inviolable sur un appareil rooté ;
l'objectif est la **proportionnalité** (empêcher le partage courant, à grande échelle). Les
rapports qui augmentent significativement le coût ou l'échelle d'une attaque nous
intéressent particulièrement.

## Hors périmètre

Rapports purement théoriques sans impact pratique, dénis de service nécessitant un accès
physique prolongé, ou attaques supposant un appareil déjà entièrement compromis (root +
debug actif).
