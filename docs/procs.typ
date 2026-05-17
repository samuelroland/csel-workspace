== Processus, signaux et communication

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

Les tests de support des signaux ont été fait avec une boucle for dans Fish, pour lancer en boucle les 5 signaux supportés.
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

/*
Exercice #2: Concevez une petite application permettant de valider la capacité des groupes de contrôle à limiter l’utilisation de la mémoire.
Quelques indications pour la création du programme :

Allouer un nombre défini de blocs de mémoire d’un mébibyte1, par exemple 50
Tester si le pointeur est non nul
Remplir le bloc avec des 0

Quelques indications pour monter les CGroups :

```
mount -t tmpfs none /sys/fs/cgroup
mkdir /sys/fs/cgroup/memory
mount -t cgroup -o memory memory /sys/fs/cgroup/memory
mkdir /sys/fs/cgroup/memory/mem
echo $$ > /sys/fs/cgroup/memory/mem/tasks
echo 20M > /sys/fs/cgroup/memory/mem/memory.limit_in_bytes
```
*/


=== Réponses aux questions
#quote("Quel effet a la commande echo $$ > ... sur les cgroups ?")
La variable `$$` contient le PID du shell. En écrivant dans le fichier `/sys/fs/cgroup/memory/mem/tasks`, on va inclure le PID du shell dans la liste des processus incluses dans ce groupe de contrôle.

#quote(
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
Nous nous serions attendu à avoir un pointeur null retourné mais c'est le OOM (Out Of Memory) killer du module des cgroups qui nous tue le processus.

#quote("Est-il possible de surveiller/vérifier l’état actuel de la mémoire ? Si oui, comment ?")

/*
Exercice #3: Afin de valider la capacité des groupes de contrôle de limiter l’utilisation des CPU, concevez une petite application composée au minimum de 2 processus utilisant le 100% des ressources du processeur.
Quelques indications pour monter les CGroups :

Si ce n’est pas déjà effectué, monter le cgroup de l’exercice précédent.
```
mkdir /sys/fs/cgroup/cpuset
mount -t cgroup -o cpu,cpuset cpuset /sys/fs/cgroup/cpuset
mkdir /sys/fs/cgroup/cpuset/high
mkdir /sys/fs/cgroup/cpuset/low
echo 3 > /sys/fs/cgroup/cpuset/high/cpuset.cpus
echo 0 > /sys/fs/cgroup/cpuset/high/cpuset.mems
echo 2 > /sys/fs/cgroup/cpuset/low/cpuset.cpus
echo 0 > /sys/fs/cgroup/cpuset/low/cpuset.mems
```

// Quelques questions :
//
//     Les 4 dernières lignes sont obligatoires pour que les prochaines commandes fonctionnent correctement. Pouvez-vous en donner la raison ?
//     Ouvrez deux shells distincts et placez une dans le cgroup high et l’autre dans le cgroup low, par exemple :
//
//     # ssh root@192.168.53.14
//     $ echo $$ > /sys/fs/cgroup/cpuset/low/tasks
//
//     Lancez ensuite votre application dans chacun des shells. Quel devrait être le bon comportement ? Pouvez-vous le vérifier ?
//     Sachant que l’attribut cpu.shares permet de répartir le temps CPU entre différents cgroups, comment devrait-on procéder pour lancer deux tâches distinctes sur le cœur 4 de notre processeur et attribuer 75% du temps CPU à la première tâche et 25% à la deuxième ?
//

*/

== Feedback cours
A notre avis, le cours sur les cgroups manque certains détails qui aiderait à mieux comprendre leur fonctionnement. Après avoir lu la #link("https://docs.kernel.org/admin-guide/cgroup-v1/cgroups.html")[docs sur les cgroups], les informations suivantes nous semblent être utiles à inclure:
- #quote(
    "No new system calls are added for cgroups - all support for querying and modifying cgroups is via this cgroup file system.",
  )
- #quote("tasks: list of tasks (by PID) attached to that cgroup. This list is not guaranteed to be sorted. Writing a thread ID into this file moves the thread into this cgroup.") Ceci contredit indirectement le cours qui dit #quote("Un CPU ou groupe de CPU peut être assigné à processus"), puisqu'il semble que ce ne sont pas les processus que l'on restreint à des coeurs mais bien des threads. Quand on restreint un processus, on restreint son thread principal.  Selon `man sched_setaffinity`, le paramètre `pid` est en fait surtout un thread ID. Quand on passe la valeur de `getpid()` ça fonctionne car le thread principal aura un TID égal au PID. Il est donc possible, dans un exemple avec des besoins de performances de définir qu'un thread a un CPU dédié que les autres threads ne pourront pas l'utiliser. Il est dommage que les pages du manuels aient utilisé le nom de variable `pid` au lieu de `tid`, peut-être que cette confusion pourrait être clarifiée par les explications et un par un petit exemple.

Voici un exemple qui lance un thread sur le coeur 1 performant et
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
