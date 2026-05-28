= Programmation Système

== Exercice - Contrôle de LED avec boutons-poussoirs

#rect([
  Concevoir une application permettant de gérer la fréquence de clignotement de la LED `status` de la carte NanoPi à l'aide des trois boutons-poussoirs. L'application utilisera le multiplexage des entrées/sorties et loggera tous les changements de fréquence avec `syslog`.
])

=== Approche générale

L'application `silly_led_control` fournie en exemple utilise une boucle active avec `clock_gettime` pour gérer le timing de la LED, ce qui consomme 100% d'un cœur CPU. Notre implémentation `not_silly_led_control` résout ce problème en utilisant `epoll` combiné à un `timerfd` pour gérer à la fois le clignotement de la LED et les événements des boutons-poussoirs, sans jamais effectuer de busy-waiting.

Une première approche consistait à utiliser le timeout d'`epoll_wait` directement pour piloter le clignotement. Cependant, cette approche pose un problème : si un bouton est pressé juste avant l'expiration du timeout, `epoll_wait` retourne immédiatement pour traiter le bouton, et le timer repart de zéro. La LED ne clignote alors plus à la bonne fréquence. Pour résoudre ce problème, un `timerfd` est utilisé comme source de timing indépendante, surveillé par `epoll` au même titre que les boutons.

=== Multiplexage avec epoll et timerfd

Le `timerfd` est créé et enregistré dans `epoll` comme n'importe quel autre descripteur de fichier. La clé de la distinction entre un événement timer et un événement bouton est le champ `data.ptr` : il est `NULL` pour le timer, et pointe vers le `key_ctx_t` correspondant pour les boutons:

```c
timerfd = timerfd_create(CLOCK_REALTIME, 0);

struct epoll_event timer_event = {.events = EPOLLIN, .data = {.ptr = NULL}};
epoll_ctl(epfd, EPOLL_CTL_ADD, timerfd, &timer_event);
```

```c
struct epoll_event event = {
    .events = EPOLLERR,
    .data   = {.ptr = &key_ctx[i]}
};
epoll_ctl(epfd, EPOLL_CTL_ADD, key_ctx[i].btn.fd, &event);
```

`epoll_wait` est appelé avec un timeout infini (`-1`), et on utilise `timerfd` pour cadencer les événements:

```c
err = epoll_wait(epfd, events, EVENT_COUNT, -1);
assert(err != 0); /* ne peut jamais être 0 avec timeout infini */
```

Dans la boucle de traitement, on distingue les deux types d'événements via `data.ptr`:

```c
for (size_t i = 0; i < (size_t)err; ++i) {
    key_ctx_t* ctx = (key_ctx_t*)events[i].data.ptr;
    if (ctx) {
        /* événement bouton */
        ctx->key_press_cb(ctx);
        continue;
    }
    /* événement timer -> toggle LED et réarmer */
    ...
    rearm_timer(timerfd);
}
```

#pagebreak()

=== Toggle de la LED et réarmement du timer

Le `timerfd` est configuré en mode one-shot (pas d'intervalle automatique). Après chaque expiration, il faut le réarmer manuellement avec la période courante. Ceci permet de prendre en compte un changement de fréquence effectué par un bouton entre deux expirations:

```c
int rearm_timer(int timerfd)
{
    struct itimerspec its = {
        .it_interval = {0, 0},
        .it_value = {
            .tv_sec  = period_ms / 1000,
            .tv_nsec = (period_ms % 1000) * 1000000L,
        },
    };
    if (timerfd_settime(timerfd, 0, &its, NULL) < 0) {
        perror("timerfd_settime");
        return -errno;
    }
    return 0;
}
```

Lors d'un événement timer, on toggle la LED puis on réarme immédiatement:

```c
if (led.state == GPIO_HIGH) {
    gpio_write(&led, GPIO_LOW);
} else {
    gpio_write(&led, GPIO_HIGH);
}
rearm_timer(timerfd);
```

Grâce à cette architecture, une pression sur un bouton n'interfère pas avec le timing de la LED : le timer continue de s'écouler indépendamment.

=== Gestion des boutons

Trois callbacks sont définies, une par bouton:

- `on_k1_press`: diminue la période de `PERIOD_DELTA_MS` (100ms), augmentant la fréquence
- `on_k2_press`: remet la période à sa valeur initiale (`default_period_ms`)
- `on_k3_press`: augmente la période de `PERIOD_DELTA_MS`, diminuant la fréquence

Des gardes sont présentes pour éviter les débordements:

```c
static void on_k1_press(key_ctx_t* ctx)
{
    (void)gpio_read(&ctx->btn);
    if (period_ms <= PERIOD_DELTA_MS) {
        syslog(LOG_WARNING, "Minimum period reached (%" PRIu64 ")", period_ms);
        return;
    }
    period_ms -= PERIOD_DELTA_MS;
    syslog(LOG_INFO, "Decreased period to %" PRIu64 "ms\n", period_ms);
}
```

=== Gestion des erreurs

Contrairement à l'implémentation originale, toutes les erreurs d'initialisation sont vérifiées et propagées correctement. Si `gpio_init` échoue pour la LED ou l'un des boutons, l'application quitte proprement via le label `cleanup`:

```c
int err = gpio_init(&led);
if (err) {
    ret = EXIT_FAILURE;
    goto cleanup;
}
```

La fonction `gpio_init` elle-même utilise un `goto err` pour dépublier le GPIO en cas d'échec partiel lors de la configuration.

=== Logs avec syslog

Tous les changements de fréquence sont enregistrés via `syslog`. L'application s'enregistre au démarrage avec:

```c
openlog("not_silly_led_control", LOG_PID | LOG_CONS, LOG_DAEMON);
```

Les niveaux de log utilisés sont:
- `LOG_INFO` pour les changements normaux de période
- `LOG_WARNING` lorsqu'une limite (min ou max) est atteinte
- `LOG_DEBUG` pour les toggles de la LED

=== syslog

Afin d'avoir les messages qui sont envoyés dans `syslog`, nous avons d'abord démarré le daemon `syslogd` avec:

```bash
syslogd
```

Par défaut `syslogd` émet les messages dans `/var/log/messages`, ce que l'on peut suivre avec:

```bash
tail -f /var/log/messages
```

Exemple de logs observés lors de l'exécution:

```
Jan  1 00:17:44 csel daemon.info not_silly_led_control[280]: Decreased period to 900ms
Jan  1 00:17:44 csel daemon.info not_silly_led_control[280]: Decreased period to 800ms
Jan  1 00:17:44 csel daemon.debug not_silly_led_control[280]: Led Off
Jan  1 00:17:45 csel daemon.debug not_silly_led_control[280]: Led On
Jan  1 00:17:46 csel daemon.debug not_silly_led_control[280]: Led Off
Jan  1 00:17:46 csel daemon.info not_silly_led_control[280]: Resetting period to 500ms
Jan  1 00:17:46 csel daemon.debug not_silly_led_control[280]: Led On
Jan  1 00:17:47 csel daemon.debug not_silly_led_control[280]: Led Off
Jan  1 00:17:47 csel daemon.debug not_silly_led_control[280]: Led On
Jan  1 00:17:48 csel daemon.debug not_silly_led_control[280]: Led Off
Jan  1 00:17:48 csel daemon.debug not_silly_led_control[280]: Led On
Jan  1 00:17:49 csel daemon.debug not_silly_led_control[280]: Led Off
Jan  1 00:17:49 csel daemon.debug not_silly_led_control[280]: Led On
Jan  1 00:17:50 csel daemon.debug not_silly_led_control[280]: Led Off
Jan  1 00:17:50 csel daemon.debug not_silly_led_control[280]: Led On
Jan  1 00:17:51 csel daemon.debug not_silly_led_control[280]: Led Off
Jan  1 00:17:51 csel daemon.info not_silly_led_control[280]: Increased period to 600ms
Jan  1 00:17:51 csel daemon.debug not_silly_led_control[280]: Led On
Jan  1 00:17:52 csel daemon.info not_silly_led_control[280]: Increased period to 700ms
Jan  1 00:17:52 csel daemon.debug not_silly_led_control[280]: Led Off
Jan  1 00:17:53 csel daemon.debug not_silly_led_control[280]: Led On
Jan  1 00:17:53 csel daemon.debug not_silly_led_control[280]: Led Off
```

On peut y observer clairement la séparation entre les événements de type `daemon.info` (changements de fréquence) et `daemon.debug` (toggles de LED), ainsi que le PID du processus.

#line()

== Feedback
Il est vrai que nous avons parcouru un peu trop vite la consigne avant de s'atteler à la tâche et nous voulions faire les choses l'une après l'autre, c'est pourquoi nous avions loupés une partie des Infos pratiques données. Nous suggérons de déplacer le partie "Infos pratiques" avant "Travail à réaliser" pour l'avoir lue au moins une fois avant de commencer à coder et éviter de croire que cela concerne un autre exercice.
