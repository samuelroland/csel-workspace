= Perf
=== Validation de l’installation
Il n'est pas clair de comment valider que l'installation fonctionnne à part de voir que `perf list` nous donne les mêmes événements, mais cela semblait être déjà le cas avant la modification.

=== Compilation d’un exemple et utilisation de perf
#rect(
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

#rect(
  "Ce programme contient une erreur triviale qui empêche une utilisation optimale du cache. De quelle erreur s’agit-il ?",
)

Le parcours de la matrice est fait en colonne, ce qui implique des cache-miss constant. La largeur de la matrice étant de 5000 et la ligne de cache étant typiquement de 64 bytes, les lignes de cache ne sont pas valorisées. Notre commande prend un temps très long de *38.78s*.

=== Correction de bug

#rect(
  "Corrigez l’erreur, recompilez et mesurez à nouveau le temps d’exécution (soit avec perf stat, soit avec la commande time). Quelle amélioration constatez-vous ?",
)

Il suffit d'échanger i et j pour parcourir en ligne. On pourrait également parcourir qu'une seule fois la matrice et faire le ++ 10 fois de suite sur la même case plutôt que de parcourir 10 fois la matrice en entier. Le temps est maintenant drastiquement meilleur: *2.43s*. En passant la boucle de 10 tours dans les 2 autres boucles, on gagne effectivement encore du temps (*1.35s*).

=== Validation

#rect([
  Relevez les valeurs du compteur L1-dcache-load-misses pour les deux versions de l’application. Quel facteur constatez-vous entre les deux valeurs ?
  ```
  # perf stat -e L1-dcache-load-misses ./ex1
  ```
])

```
#  perf stat -e L1-dcache-load-misses ./ex1
         406599107      L1-dcache-load-misses
#  perf stat -e L1-dcache-load-misses ./ex1opti
            795585      L1-dcache-load-misses
```
Le ratio est de 795585/406599107 est environ 2 pour mille.

=== Analyse des évènements capturables
#rect("Décrivez brièvement ce que sont les évènements suivants :")

+ *instructions*: le nombre d'instructions exécutée par le processeur sur le programme
+ *cache-misses*: le nombre de fois qu'un accès RAM n'a pas trouvé de ligne de cache contenant déjà la valeur et que la ligne de cache de l'emplacement a été chargé.
+ *branch-misses*: le nombre de fois que le _branch predictor_ a choisi le mauvais chemin dans un branchement
+ *L1-dcache-load-misses*: le nombre de cache-misses au niveau de la cache L1 du processeur, pour la partie data (accès aux données du programme), au contraire de la L1 pour les instructions (accès à la lecture des instructions)
+ *cpu-migrations*: la doc de `perf list` nous indique que cette valeur est le nomber de fois que le processus a changé de CPU
+ *context-switches*: le nombre de changement de contexte (le moment où l'ordonnanceur a décidé de stopper le processus, sauver son état d'exécution en mémoire et le restaurer plus tard sur le même ou un autre coeur).

=== Mesure de l’impact sur la performance

#rect(
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

== Analyse et optimisation d’un programme

Le programme 2 va générer un grand tableau de nombre aléatoires entre 0 et 512 non compris. En parcourant ce tableau 10000 fois, il va faire la somme des valeurs si celles-ci sont supérieur ou égales à 256, ce qui devrait arriver en moyenne une fois sur deux.

#grid(
  columns: (1fr, 1fr),
  [

    === Mesure du temps d’exécution
    ```
    # time ./ex2
    sum=125454290000
    real	0m 26.18s
    ```
  ],
  [
    === Optimisation
    L'optimisation n'apporte bizarrement que 3s de gain...
    ```
    # time ./ex2opti
    sum=125454290000
    real	0m 23.43s
    user	0m 23.37s
    sys	0m 0.00s
    ```
  ],
)

L'accélération est dûe au problème du _branch predictor_ qui ne peut pas prédire le coup suivant du branchement comme cela est alétoire. En triant les éléments du tableau, toutes les valeurs en dessous de 256 seront présentes sur la première moitié, puis toutes les valeurs supérieures. Cette analyse est confirmée par la mesure de `branch-misses` qui donne 33% de miss dans le programme de départ.
```
# perf stat ./ex2base
sum=125454290000
         327858414      branch-misses             #   33.17% of all branches

# perf stat ./ex2opti
sum=125454290000
            821593      branch-misses             #    0.08% of all branches
```
== Parsing de logs apache
Dans le programme 3, dans `perf report`, en pressant Enter sur la fonction, on a une option `Expand [std::operator==<char>] callchain` qui nous donne la liste des appels de fonctions.
```
  std::operator==<char>
     __gnu_cxx::__ops::_Iter_equals_val<std...
     std::__find_if<__gnu_cxx::__normal_ite...
     std::__find_if<__gnu_cxx::__normal_ite...
     std::find<__gnu_cxx::__normal_iterator...
     HostCounter::isNewHost
     HostCounter::notifyHost
     ApacheAccessLogAnalyzer::processFile
...
```

Le but du code est en fait de chercher une string parmi un vecteur de strings via la fonction `std::find`. Le gros problème est la recherche dans un vecteur est en $O(N)$.
```cpp
std::vector< std::string > myHosts;
...
return std::find(myHosts.begin(), myHosts.end(), hostname) == myHosts.end();
...
```

Grace aux changements donnés, on obtient de bien meilleur résultat qu'auparavant.
```
# time ./read-apache-logs access_log_NASA_Jul95_samples
Processing log file access_log_NASA_Jul95_samples
Found 14867 unique Hosts/IPs
Command terminated by signal 11
real	0m 1.59s
user	0m 1.37s
sys	0m 0.09s
```

Il est possible et facile d'utiliser une structure encore meilleur. Un `std::set` garantit un accès en $O(log(N))$ alors qu'une table de hachage pour stocker un ensemble garantit un $O(1)$ amorti. Il suffit donc de changer `std::set` par `std::unordered_set` pour gagner encore quelques 500ms.
```cpp
std::unordered_set<std::string> myHosts;
```

```
# time ./read-apache-logs access_log_NASA_Jul95_samples
Processing log file access_log_NASA_Jul95_samples
Found 14867 unique Hosts/IPs
Command terminated by signal 11
real	0m 1.09s
user	0m 0.89s
sys	0m 0.09s
```

Dans l'état actuelle, si on réanalyze via `perf record` et `perf report`, on trouve la fonction probablement appelée pour le calcul du hash au moment du `myHosts.find()`.
```
  Overhead  Command          Shared Object          Symbol
+   10.53%  read-apache-log  read-apache-logs       [.] std::_Hashtable<std::__cxx11::basic_string<char, std::char_traits<char>, std::allocator<char> >, std::__cxx11::basic
+    7.89%  read-apache-log  libstdc++.so.6.0.29    [.] std::__cxx11::basic_string<char, std::char_traits<char>, std::allocator<char> >::find_first_of
+    3.95%  read-apache-log  [kernel.kallsyms]      [k] __arch_copy_to_user
```

Si on y regarde de plus près, on se rend compte que isNewHost va chercher dans la table de hachage pour savoir si on veut insérer ou non l'entrée. Contrairement au vector initiale, nous avons maintenant un ensemble de clés unique et l'insertion ne se fait pas/n'a pas d'impacte si l'entrée existe déjà. Si l'entrée existe, le hash de la string est donc calculé deux fois (une fois pour la trouver, une autre fois pour savoir où l'insérer).

```cpp
    // add the host in the list if not already in
    if (isNewHost(hostname)) {
        myHosts.insert(hostname);
    }
```

En retirant ce if, on retire l'overhead de `10%` montré précédemment et on gagne encore 60ms, pour obtenir 1.03s. Le gain n'est pas énorme car il est proportionnel au nombre d'entrée unique trouvée qui reste limité à 14867.

```
# time ./read-apache-logs access_log_NASA_Jul95_samples
Processing log file access_log_NASA_Jul95_samples
Found 14867 unique Hosts/IPs
Command terminated by signal 11
real	0m 1.03s
user	0m 0.83s
sys	0m 0.08s
```

== Mesure de la latence et de la gigue (jitter)

#rect(
  "Décrivez comment devrait-on procéder pour mesurer la latence et la gigue d’interruption, ceci aussi bien au niveau du noyau (kernel space) que de l’application (user space).",
)

Vous expliquiez en classe qu'il était possible de lever une patte de gpio et de mesurer à l'oscilloscope le délai entre un événement physique et sa réaction.
L'accès au GPIO peut se faire directement depuis le noyau ou bien à travers quelques différentes méthodes depuis l'user space comme vu durant les précédents laboratoires, comme à 
travers `/dev/mem` ou bien `sysfs`.

On peut donc mesurer la latence en togglant un GPIO au début et en fin de tâche.
Une fois plusieurs mesures prises on peut faire une moyenne et calculer le jitter, la différence du temps d'exécution entre plusieurs exécutions de la même tâche.

== Retour généraux sur le cours

- Un peu de difficulté avec quelques Makefile (exo 1 et 2 en tous cas) à cause de `cc1: error: bad value ‘cortex-a53’` et aussi parce qu'il compilait avec `cc` et pas `aarch64-linux-gcc` par défaut. Nous avons du chercher comment modifier les contraintes pour que la cross-compilation se fasse...
- Par rapport à la version plus évolue de perf, installée au début du laboratoire: c'est vraiment bien d'avoir mis des commandes pour accélérer le travail, par contre nous aurions bien aimé savoir en quoi la version existante #quote("n’est pas totalement satisfaisante"), pour pouvoir valider que la mise à jour a réussi. Nous avons eu quelques doutes sur cette mise en place quand vous avez marqué #quote("Vous observez sans doute une nette amélioration sur le temps d’exécution.") et que notre optimisation n'apporte que 3 secondes de gain sur le total de 26 secondes...

