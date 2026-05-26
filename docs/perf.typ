== Perf
=== Prise en main de perf
==== Validation de l’installation
TODO
==== Compilation d’un exemple et utilisation de perf
#quote(
  "Sans options spécifiques, la commande mesure par défaut un certain nombre de compteurs. Relevez par exemple les compteurs du nombre de context-switches et d’instructions ainsi que le temps d’exécution.",
)
```sh
> perf stat ls
Makefile  ex1  main.c

 Performance counter stats for 'ls':

             11.15 msec task-clock                #    0.167 CPUs utilized
                41      context-switches          #    3.676 K/sec
                 0      cpu-migrations            #    0.000 /sec
               138      page-faults               #   12.372 K/sec
           8911310      cycles                    #    0.799 GHz
           3183380      instructions              #    0.36  insn per cycle
            396435      branches                  #   35.541 M/sec
             47003      branch-misses             #   11.86% of all branches
```

#quote(
  "Ce programme contient une erreur triviale qui empêche une utilisation optimale du cache. De quelle erreur s’agit-il ?",
)

Le parcours de la matrice est fait en colonne, ce qui implique des cache-miss constant. La largeur de la matrice étant de 5000 et la ligne de cache étant typiquement de 64 bytes, les lignes de cache ne sont pas valorisées.

Notre commande prend ainsi 38secondes.
```
# time ./ex1
real	0m 38.78s
```

==== Correction de bug

#quote(
  "Corrigez l’erreur, recompilez et mesurez à nouveau le temps d’exécution (soit avec perf stat, soit avec la commande time). Quelle amélioration constatez-vous ?",
)

Il suffit d'échanger i et j pour parcourir en ligne. On pourrait également parcourir qu'une seule fois la matrice et faire le ++ 10 fois de suite sur la même case plutôt que de parcourir 10 fois la matrice en entier. Le temps est maintenant drastiquement meilleur.
```
# time ./ex1
real	0m 2.43s
```

En passant la boucle de 10 tour dans les 2 autres boucles, on gagne effectivement encore du temps.
```
# time ./ex1
real	0m 1.35s
```

==== Validation

#quote([
  Relevez les valeurs du compteur L1-dcache-load-misses pour les deux versions de l’application. Quel facteur constatez-vous entre les deux valeurs ?
  ```
  # perf stat -e L1-dcache-load-misses ./ex1
  ```
])

```
#  perf stat -e L1-dcache-load-misses ./ex1

 Performance counter stats for './ex1':

         406599107      L1-dcache-load-misses

      37.297942935 seconds time elapsed

      36.646664000 seconds user
       0.272702000 seconds sys
#  perf stat -e L1-dcache-load-misses ./ex1opti

 Performance counter stats for './ex1opti':

            795585      L1-dcache-load-misses

       1.353593501 seconds time elapsed

       1.108884000 seconds user
       0.234271000 seconds sys
```
Le ratio est de 795585/406599107 est moins de 1 pour mille.

==== Analyse des évènements capturables
#quote("Décrivez brièvement ce que sont les évènements suivants :")

+ instructions: le nombre d'instructions exécutée par le processeur sur le programme
+ cache-misses: le nombre de fois qu'un accès RAM n'a pas trouvé de ligne de cache contenant déjà la valeur et que la ligne de cache de l'emplacement a été chargé.
+ branch-misses: le nombre de fois que le _branch predictor_ a choisi le mauvais chemin dans un branchement
+ L1-dcache-load-misses: le nombre de cache-misses au niveau de la cache L1 du processeur, pour la partie data (accès aux données du programme), au contraire de la L1 pour les instructions (accès à la lecture des instructions)
+ cpu-migrations: la doc de `perf list` nous indique que cette valeur est le nomber de fois que le processus a changé de CPU
+ context-switches: le nombre de changement de contexte (le moment où l'ordonnanceur a décidé de stopper le processus, sauver son état d'exécution en mémoire et le restaurer plus tard sur le même ou un autre coeur).

==== Mesure de l’impact sur la performance

#quote(
  "Lors de la présentation de l’outil perf, on a vu que celui-ci permettait de profiler une application avec très peu d’impacts sur les performances. En utilisant la commande time, mesurez le temps d’exécution de notre application ex1 avec et sans la commande perf stat.",
)

Il se trouve que l'overhead est quand même de 350ms si on compare le temps 1.35s à 1.70s...
```
# time ./ex1opti
real	0m 1.35s
user	0m 1.14s
sys	0m 0.19s
# time perf stat -e L1-dcache-load-misses ./ex1opti

 Performance counter stats for './ex1opti':

            762197      L1-dcache-load-misses

       1.352246167 seconds time elapsed

       1.097093000 seconds user
       0.243245000 seconds sys

real	0m 1.70s
user	0m 1.10s
sys	0m 0.28s
```

=== Analyse et optimisation d’un programme

Le programme 2 va générer un grand tableau de nombre aléatoires entre 0 et 512 non compris. En parcourant ce tableau 10000 fois, il va faire la somme des valeurs si celles-ci sont supérieur ou égales à 256, ce qui devrait arriver en moyenne une fois sur deux.

=== Mesure du temps d’exécution
```
# time ./ex2
sum=125454290000
real	0m 26.18s
```

=== Optimisation
L'optimisation n'apporte bizarrement que 3s de gain...
```
# time ./ex2opti
sum=125454290000
real	0m 23.43s
user	0m 23.37s
sys	0m 0.00s
```

L'accélération est dûe au problème du _branch predictor_ qui ne peut pas prédire le coup suivant du branchement comme cela est alétoire. En triant les éléments du tableau, toutes les valeurs en dessous de 256 seront présentes sur la première moitié, puis toutes les valeurs supérieures. Cette analyse est confirmée par la mesure de `branch-misses` qui donne 33% de miss dans le programme de départ.
```
# perf stat ./ex2base
sum=125454290000
...
         327858414      branch-misses             #   33.17% of all branches
...

# perf stat ./ex2opti
sum=125454290000
...
            821593      branch-misses             #    0.08% of all branches
...
```

== Retour généraux sur le cours
- Un peu de difficulté avec qqes Makefile (exo 1 et 2 en tous cas) à cause de `cc1: error: bad value ‘cortex-a53’` et aussi parce qu'il compilait avec `cc` et pas `aarch64-linux-gcc` par défaut. Nous avons du chercher comment modifier les contraintes pour que la cross-compilation se fasse...
- Par rapport à la version plus évolue de perf, installée au début du laboratoire: c'est vraiment bien d'avoir mis des commandes pour accélérer le travail, par contre nous aurions bien aimé savoir en quoi la version existante #quote("n’est pas totalement satisfaisante") ??
