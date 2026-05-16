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


Exercice #1: Concevez et développez une petite application mettant en œuvre un des services de communication proposés par Linux (par exemple socketpair) entre un processus parent et un processus enfant. Le processus enfant devra émettre quelques messages sous forme de texte vers le processus parent, lequel les affichera sur la console. Le message exit permettra de terminer l’application. Cette application devra impérativement capturer les signaux SIGHUP, SIGINT, SIGQUIT, SIGABRT et SIGTERM et les ignorer. Seul un message d’information sera affiché sur la console. Chacun des processus devra utiliser son propre cœur, par exemple core 0 pour le parent, et core 1 pour l’enfant.

== CGroups

/*
Exercice #2: Concevez une petite application permettant de valider la capacité des groupes de contrôle à limiter l’utilisation de la mémoire.
Quelques indications pour la création du programme :

Allouer un nombre défini de blocs de mémoire d’un mébibyte1, par exemple 50
Tester si le pointeur est non nul
Remplir le bloc avec des 0

Quelques indications pour monter les CGroups :

```
$ mount -t tmpfs none /sys/fs/cgroup $ mkdir /sys/fs/cgroup/memory
$ mount -t cgroup -o memory memory /sys/fs/cgroup/memory $ mkdir /sys/fs/cgroup/memory/mem
$ echo $$ > /sys/fs/cgroup/memory/mem/tasks $ echo 20M > /sys/fs/cgroup/memory/mem/memory.limit_in_bytes
```


=== Réponses aux questions
#quote("Quel effet a la commande echo $$ > ... sur les cgroups ?")

#quote(
  "Quel est le comportement du sous-système memory lorsque le quota de mémoire est épuisé ? Pourrait-on le modifier ? Si oui, comment ?",
)

#quote("Est-il possible de surveiller/vérifier l’état actuel de la mémoire ? Si oui, comment ?")

Exercice #3: Afin de valider la capacité des groupes de contrôle de limiter l’utilisation des CPU, concevez une petite application composée au minimum de 2 processus utilisant le 100% des ressources du processeur.
Quelques indications pour monter les CGroups :

Si ce n’est pas déjà effectué, monter le cgroup de l’exercice précédent.
```
$ mkdir /sys/fs/cgroup/cpuset $ mount -t cgroup -o cpu,cpuset cpuset /sys/fs/cgroup/cpuset
$ mkdir /sys/fs/cgroup/cpuset/high $ mkdir /sys/fs/cgroup/cpuset/low
$ echo 3 > /sys/fs/cgroup/cpuset/high/cpuset.cpus $ echo 0 > /sys/fs/cgroup/cpuset/high/cpuset.mems
$ echo 2 > /sys/fs/cgroup/cpuset/low/cpuset.cpus $ echo 0 > /sys/fs/cgroup/cpuset/low/cpuset.mems
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
