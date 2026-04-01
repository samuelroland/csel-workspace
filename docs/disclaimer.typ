= Notice

#block(
  fill: luma(230),
  inset: 12pt,
  radius: 4pt,
  stroke: (left: 3pt + rgb("#f0a500")),
)[
  *Note sur l'environnement de développement*
  Ce rapport a été produit en utilisant en partie l'environnement Docker officiel du cours (Ubuntu 24. 04) et une partie en dehors. Les parties *Environnement Linux embarqué* et *Pilotes de périphériques*
  ont été réalisés nativement par André sous Fedora 42, une distribution Linux fournissant des versions de paquets sensiblement
  plus récentes que celles présentes dans le conteneur de référence.

  Ce choix délibéré d'André a été fait dans le but de tirer le meilleur parti du cours et d'approfondir la compréhension,
  en confrontant directement les défis d'un environnement réel plutôt qu'un environnement préconfiguré et isolé.
  Cette approche n'est cependant pas recommandée pour les étudiants souhaitant suivre le cours dans des conditions
  optimales, car l'environnement Docker officiel demeure la référence pour reproduire les résultats attendus sans difficulté
  supplémentaire.

  Cette différence d'environnement a causé plusieurs incompatibilités lors de la compilation et de la configuration des outils.
  Chaque problème rencontré a été documenté, ainsi que les étapes supplémentaires nécessaires pour le résoudre. Ces sections
  additionnelles sont clairement identifiées tout au long du rapport afin de les distinguer du contenu strictement lié aux
  objectifs du laboratoire.  Cette documentation détaillée est intentionnelle : elle pourra servir de référence aux futurs
  étudiants qui souhaiteraient également travailler en dehors du conteneur officiel.

  Les résultats obtenus restent fonctionnellement équivalents à ceux attendus dans l'environnement standard.

]
