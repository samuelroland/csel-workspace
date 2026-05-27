= Processus, signaux et communication

Le challenge de cette première partie a été surtout lié à l'usage de `read` et `write` sur un socketpair, en supportant les lectures partielles et arrêts causés par des interruptions.

Notre programme `procs` crée un `socketpair`, puis `fork` un processus enfant. Le parent se contraint au CPU 0 et l'enfant fait de même sur le CPU 1. L'enfant envoie `Hello 1`, `Hello 2`, `Hello 3`, `Hello 4`, puis finalement `exit`, à travers ce socket. Une attente d'une seconde est faite entre chaque message.

```
Procs
parent: Parent process continues !
parent: Waiting for messages from child
child: Child process started !
child: Sending message 1 to parent
parent: Got message: 'Hello 1'
parent: Waiting for messages from child
child: Sending message 2 to parent
parent: Got message: 'Hello 2'
parent: Waiting for messages from child
child: Sending message 3 to parent
parent: Got message: 'Hello 3'
parent: Waiting for messages from child
child: Sending message 4 to parent
parent: Got message: 'Hello 4'
parent: Waiting for messages from child
child: Sending exit command to parent
parent: Got message: 'exit'
```

Le défi a été de réussir à éviter la double récupération de message en cas d'interruption lancée en `Ctrl+c`, comme le montre l'exemple suivant avec `Hello 2` affiché 2 fois. Ce bug était lié à la comparaison de la valeur de retour de `read` (`if (res == EINTR)`) au lieu de `errno` et à la comparaison entre `res < buflen` quand `res` est à -1, ce qui causait un underflow avec la conversion du à la comparaison `int < size_t`. Ces deux problèmes empêchaient de bloquer correctement dans `safe_read_msg`, ainsi le buffer `message` était réaffiché comme s'il avait été modifié.
```
parent: Waiting for messages from child
parent: Got message: 'Hello 2'
parent: Waiting for messages from child
^CIgnored signal 2
Ignored signal 2
parent: Got message: 'Hello 2'
child: Sending message 3 to parent
parent: Waiting for messages from child
parent: Got message: 'Hello 3'
```

Les tests de support des signaux ont été fait en lançant les 5 signaux supportés à travers une boucle while Fish.
```fish
while true; kill -1 procs; kill -2 procs; kill -3 procs; kill -6 procs; kill -15 procs; end
```
On remarque alors (avec plus de logs), que les interruptions ne touchent que `sleep` et `read` mais jamais `write`. Peut-être que cela s'explique parce le non-blocage de l'appel `write`, grâce par les petits messages. La fonction de gestion des signaux affiche bien son message (`Ignored signal 3`).
```
...
Ignored signal 2
child: Sending message 3 to parent
parent: Got message: 'Hello 3'
parent: Waiting for messages from child
Ignored signal 3
Ignored signal 3
child: Sending message 4 to parent
parent: Got message: 'Hello 4'
parent: Waiting for messages from child
Ignored signal 6
Ignored signal 6
child: Sending exit command to parent
parent: Got message: 'exit'
```

Une version safe de sleep n'a pas été intégrée comme elle existait déjà dans le cours. De plus, il n'est pas évident de tester si les contraintes sur les coeurs marchent vraiment, comme l'activité CPU est faible.

== CGroups
Pas de difficulté particulière à écrire cet exemple, exception faite sur une légère confusion avec la consigne. Le texte #quote("Allouer un nombre défini de blocs de mémoire d’un mébibyte, par exemple 50") semble indiquer d'allouer 50 fois 1 mébibyte d'un seul coup, ce qui n'est pas très intéressant puisque la limite de 20MB est immédiatement dépassée. Nous avons donc alloué 1 mébibyte, 50 fois de suite en vérifiant entre chaque fois si l'allocation fonctionne.

=== Réponses aux questions
#rect("Quel effet a la commande echo $$ > ... sur les cgroups ?")
La variable `$$` contient le PID du shell. En écrivant dans le fichier `/sys/fs/cgroup/memory/mem/tasks`, on va inclure le PID du shell dans la liste des processus incluses dans ce groupe de contrôle.

#rect(
  "Quel est le comportement du sous-système memory lorsque le quota de mémoire est épuisé ? Pourrait-on le modifier ? Si oui, comment ?",
)
Notre programme alloue progressivement des blocs de 1 mébibyte, jusqu'à que l'allocation échoue. La limite étant précédemment définie à 20M, il est normal que le programme ne puissent pas allouer au delà de 19 fois un mébibyte.
```
./build/cgroups
Allocated 1 MEBIBYTE, reaching a total of 1048576 bytes
Allocated 1 MEBIBYTE, reaching a total of 2097152 bytes
Allocated 1 MEBIBYTE, reaching a total of 3145728 bytes
... 15x
Allocated 1 MEBIBYTE, reaching a total of 19922944 bytes
[ 4170.517367] cgroups invoked oom-killer: gfp_mask=0xcc0(GFP_KERNEL), order=0, oom_score_adj=0
...
```
Nous nous serions attendu à avoir un pointeur null retourné. Hors, il se passe un crash du program, causé par le OOM (Out Of Memory) killer du module des cgroups qui nous tue le processus.

#rect("Est-il possible de surveiller/vérifier l’état actuel de la mémoire ? Si oui, comment ?")

Il est possible de connaitre la quantité de RAM utilisée par le cgroup en lisant l'attribut `/sys/fs/cgroup/memory/memory.usage_in_bytes`.

=== Réponses aux questions 2

#rect(
  "Les 4 dernières lignes sont obligatoires pour que les prochaines commandes fonctionnent correctement. Pouvez-vous en donner la raison ?",
)

Les 4 dernières lignes configurent les deux sous cgroups créés par les deux `mkdir` précédent. Le premier groupe `high` ne peut tourner que sur le coeur 3, tandis que le second uniquement sur le 2. Le noeud mémoire 0 est attribué aux deux cgroups.

#rect([
  "Ouvrez deux shells distincts et placez une dans le cgroup high et l’autre dans le cgroup low, par exemple :
  ```
  # ssh root@192.168.53.14
  $ echo $$ > /sys/fs/cgroup/cpuset/low/tasks
  ```
  Lancez ensuite votre application dans chacun des shells. Quel devrait être le bon comportement ? Pouvez-vous le vérifier ?",
])
Le comportement attendu devrait être que le terminal avec le shell dans le cgroup `high` devrait être limité au coeur 3 et l'autre shell devrait être limité au coeur 2. Pour le tester il suffit d'ouvrir `htop` dans une troisième session de terminal et de lancer le programme en deux temps pour voir l'usage du coeur en fonction du cgroup.
```
  0[                           0.0%]
  1[                           0.0%]
  2[|||||||||||||||||||||||||100.0%]
  3[|||||||||||||||||||||||||100.0%]
Mem[||||||||             35.9M/474M]
Swp[                          0K/0K]
```
Le programme et les limites imposées par le cgroup fonctionne donc sans problème. Nous avons trouvé intéressant de noter qu'il est possible d'ajuster les coeurs à volée en impactant les programmes existants. Par exemple, `echo 0,2 > /sys/fs/cgroup/cpuset/low/cpuset.cpus` permettrait d'ajouter en plus le coeur 0 et `htop` nous montre que ce changement fonctionne immédiatement.

#rect(
  "Sachant que l’attribut cpu.shares permet de répartir le temps CPU entre différents cgroups, comment devrait-on procéder pour lancer deux tâches distinctes sur le cœur 4 de notre processeur et attribuer 75% du temps CPU à la première tâche et 25% à la deuxième ?",
)

L'attribut `cpu.shares` fonctionne comme les valeurs de l'attribut CSS `flex`. Quand on met une `div` à `flex:3` et une autre à `flex:4`, la première prendra 3/7 de l'espace et la seconde 4/7. Selon #link("https://www.redhat.com/en/blog/cgroups-part-two")[cette article de RedHat], `cpu.shares` est donc un nombre de portions de CPU divisant le total de portions définies. Cela donne un pourcentage final d'accès au CPU. Si le cgroup est un sous groupe, ce pourcentage s'applique sur le pourcentage calculé sur le parent.

Nous avons de nouvelles contraintes, nous créons donc un nouveau cgroup nommé `shared`. Deux sous cgroups `minor` et `major` permettront de séparer les deux taches. Nous restreignons les tâches dans `shared` au coeur 3 (le 4ème). Ensuite, il suffit d'attribuer une portion de CPUShares de 256 pour `minor` et de 768 pour `major`, qui implémentera ce découpage 25%/75% de 1024 (valeur existante de `/sys/fs/cgroup/cpuset/shared/cpu.shares`).
j
```sh
mkdir /sys/fs/cgroup/cpuset/shared
mkdir /sys/fs/cgroup/cpuset/shared/minor
mkdir /sys/fs/cgroup/cpuset/shared/major
echo 3 > /sys/fs/cgroup/cpuset/shared/cpuset.cpus
echo 768 > /sys/fs/cgroup/cpuset/shared/major/cpu.shares
echo 256 > /sys/fs/cgroup/cpuset/shared/minor/cpu.shares
```

Finalement, il nous reste à changer de cgroup de nos 2 shells existants.
```sh
# terminal 1
echo $$ > /sys/fs/cgroup/cpuset/shared/minor/tasks
# terminal 2
echo $$ > /sys/fs/cgroup/cpuset/shared/major/tasks
```

Après l'erreur suivante
```
# echo $$ > /sys/fs/cgroup/cpuset/shared/minor/tasks
sh: write error: No space left on device
```
résolue en s'inspirant de l'example pour les 3 cgroups et de #link("https://stackoverflow.com/questions/28348627/echo-tasks-gives-no-space-left-on-device-when-trying-to-use-cpuset")[cette article SO].
```
echo 0 > /sys/fs/cgroup/cpuset/shared/cpuset.mems
echo 0 > /sys/fs/cgroup/cpuset/shared/minor/cpuset.mems
echo 0 > /sys/fs/cgroup/cpuset/shared/major/cpuset.mems
echo 3 > /sys/fs/cgroup/cpuset/shared/minor/cpuset.cpus
echo 3 > /sys/fs/cgroup/cpuset/shared/major/cpuset.cpus
```

En ne démarrant que le processus côté `high`, on observe dans `htop` les 2 processus (parent et enfant) qui prennent chacun 50%, donc 100% du coeur 3 au final. C'est normal de ne pas être limité à 75% quand il n'y a pas d'autres demandes.

Pour valider le résultat, il suffit de trier par CPU dans htop et voir que notre premiers process (parent + enfant) sont à $37*2 approx 75%$ et $12*2 approx 25%$. Nous avons donc bien réussi à séparer nos deux tâches aux ratios demandés.
```
 PID USER       PRI  NI  VIRT   RES   SHR S  CPU%-MEM%   TIME+  Command
 418 root        23   3 34888   188   148 S  37.6  0.0  5:28.38 ./build/cgroups
 419 root        22   2 34888    84     0 S  37.6  0.0  5:28.35 ./build/cgroups
 409 root        25   5 34888    88     0 S  12.5  0.0  3:27.16 ./build/cgroups
 408 root        22   2 34888   200   156 S  11.9  0.0  3:27.17 ./build/cgroups
```

Nous avions testé aussi de partager les CPUShares simplement en portion 1/4 et 3/4. Cela ne fonctionne malheureusement pas (le ratio est de 40%/60%), ce qui reste mystérieux pour nous, cela ne correspond pas à la compréhension des calculs donnée par l'article de RedHat...
```
echo 1 > /sys/fs/cgroup/cpuset/shared/minor/cpu.shares
echo 3 > /sys/fs/cgroup/cpuset/shared/major/cpu.shares
```

== Feedback du cours

- Mentionner qu'on utilise cgroup v1 et pas la dernière v2. Nous avions d'abord trouvé #link("https://docs.kernel.org/admin-guide/cgroup-v2.html#memory-interface-files")[dans la section de la documentation cgroup v2], l'attribut `memory.current` qui n'est pas le même que pour la version 1 `memory.usage_in_bytes`.  Rajouter le lien vers la documentation liée.
- Dans les exemples de commandes, s'il est possible de ne pas mettre de dollar au début d'une commande, cela aiderait à copier coller tout d'un coup. Exemple `$ mkdir /sys/fs/cgroup/cpuset` -> `mkdir /sys/fs/cgroup/cpuset`
- A notre avis, le cours sur les cgroups manque certains détails qui aiderait à mieux comprendre leur fonctionnement. Après avoir lu la #link("https://docs.kernel.org/admin-guide/cgroup-v1/cgroups.html")[docs sur les cgroups], les informations suivantes nous semblent être utiles à inclure:
  - #quote("No new system calls are added for cgroups - all support for querying and modifying cgroups is via this cgroup file system."). Je pense que ce détail est important et clarifie le besoin des 2 mounts. Par contre, il n'est pas clair de pourquoi `sched_setaffinity` et `sched_getaffinity` sont des appels systèmes ? Est-ce que la _Processor Affinity_ ne fait pas partie des cgroups ?
  - #quote("Each cgroup is represented by a directory in the cgroup file system containing the following files describing that cgroup:") -> pas évident de voir à quel niveau de la hiérarchie sont les cgroups.
  - #quote("tasks: list of tasks (by PID) attached to that cgroup. This list is not guaranteed to be sorted. Writing a thread ID into this file moves the thread into this cgroup.") Ceci contredit indirectement le cours qui dit #quote("Un CPU ou groupe de CPU peut être assigné à processus"), puisqu'il semble que ce ne sont pas les processus que l'on restreint à des coeurs mais bien des threads. Quand on restreint un processus, on restreint son thread principal.  Selon `man sched_setaffinity`, le paramètre `pid` est en fait surtout un thread ID. Quand on passe la valeur de `getpid()` ça fonctionne car le thread principal aura un TID égal au PID. Il est donc possible, dans un exemple avec des besoins de performances de définir qu'un thread a un CPU dédié que les autres threads ne pourront pas l'utiliser. Il est dommage que les pages du manuels aient utilisé le nom de variable `pid` au lieu de `tid`, peut-être que cette confusion pourrait être clarifiée par les explications et un par un petit exemple.

#pagebreak()
Voici un exemple de code qui lance un thread sur le coeur 1 performant et 3 autres threads sur d'autres coeurs efficients.
#table(
  columns: 2,
  [


    ```c
    #define _GNU_SOURCE
    #include <pthread.h>
    #include <sched.h>
    #include <stdbool.h>
    #include <stddef.h>
    #include <stdint.h>
    #include <stdio.h>
    #include <stdlib.h>
    #include <unistd.h>

    void do_heavy_work() {
        volatile size_t counter = 0;
        while (1) {
            counter ^= (counter << 13);
            counter ^= (counter >> 7);
            counter ^= (counter << 17);
        }
    }

    void do_lighweight_work() {
        volatile size_t counter = 0;
        while (true) {
            usleep(10000);
            counter ^= (counter << 17);
        }
    }

    void *performant_task(void *arg) {
        cpu_set_t set;
        CPU_ZERO(&set);
        CPU_SET(1, &set);// CPU 1 is a performant core
        if (sched_setaffinity(0, sizeof(set), &set) < 0) {
            perror("sched_setaffinity");
            exit(1);
        }
        do_heavy_work();
        return NULL;
    }

    void *light_task(void *arg) {
        cpu_set_t set;
        CPU_ZERO(&set);
        CPU_SET(2, &set);// CPU 2 and 3 are efficient cores
        CPU_SET(3, &set);
        if (sched_setaffinity(0, sizeof(set), &set) < 0) {
            perror("sched_setaffinity");
            exit(1);
        }
        do_lighweight_work();
        return NULL;
    }

    int main(void) {
        pthread_t t1, t2, t3, t4;
        pthread_create(&t1, NULL, performant_task, NULL);
        pthread_create(&t2, NULL, light_task, NULL);
        pthread_create(&t3, NULL, light_task, NULL);
        pthread_create(&t4, NULL, light_task, NULL);
        pthread_join(t1, NULL);
        pthread_join(t2, NULL);
        pthread_join(t3, NULL);
        pthread_join(t4, NULL);
    }
    ```

  ],
  [

    Note: pour que l'exemple à gauche fonctionne, il ne faut pas inclure de `printf` dans le code des threads, car pour une raison étrange, leur exécution n'est pas limitée par les coeurs définis.

    L'appel système confirme la sélection des coeurs. Le TID zéro correspond au thread appelant.
    ```sh
    > strace -f -e trace=sched_setaffinity ./build/main
    strace: Process 313235 attached
    [pid 313235] sched_setaffinity(0, 128, [1]) = 0
    strace: Process 313236 attached
    [pid 313236] sched_setaffinity(0, 128, [2 3]) = 0
    strace: Process 313237 attached
    do_heavy_work
    [pid 313237] sched_setaffinity(0, 128, [2 3]) = 0
    strace: Process 313238 attached
    [pid 313238] sched_setaffinity(0, 128, [2 3]) = 0
    ...
    ```
  ],
)
