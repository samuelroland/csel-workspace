= Programmation Système

== Exercice - Contrôle de LED avec boutons-poussoirs

#rect([
  Concevoir une application permettant de gérer la fréquence de clignotement de la LED `status` de la carte NanoPi à l'aide des trois boutons-poussoirs. L'application utilisera le multiplexage des entrées/sorties et loggera tous les changements de fréquence avec `syslog`.
])

=== Approche générale

L'application `silly_led_control` fournie en exemple utilise une boucle active avec `clock_gettime` pour gérer le timing de la LED, ce qui consomme 100% d'un cœur CPU. Notre implémentation `not_silly_led_control` résout ce problème en utilisant `epoll` avec un timeout pour gérer à la fois le clignotement de la LED et les événements des boutons-poussoirs, sans jamais effectuer de busy-waiting.

=== Multiplexage avec epoll

Le cœur de l'application repose sur `epoll_wait` avec un timeout correspondant à la période de clignotement courante:

```c
int ret = epoll_wait(epfd, events, event_cnt, period_ms);
```

Ce seul appel remplace toute la logique de timing de l'implémentation originale. Il y a deux cas de retour:

- `ret == 0`: timeout expiré, on toggle la LED
- `ret > 0`: un ou plusieurs boutons ont été pressés, on traite les événements

Les boutons sont configurés en mode `EPOLLERR` (interruption sur front montant côté sysfs GPIO), ce qui permet à `epoll` de les surveiller sans polling. Chaque bouton est associé à son contexte via `epoll_event.data.ptr`, ce qui évite toute recherche lors du traitement des événements:

```c
struct epoll_event event = {
    .events = EPOLLERR,
    .data   = {.ptr = &key_ctx[i]}
};
epoll_ctl(epfd, EPOLL_CTL_ADD, key_ctx[i].btn.fd, &event);
```

=== Toggle de la LED par timeout

Lorsque `epoll_wait` retourne `0`, aucun bouton n'a été pressé et la période est écoulée. On toggle simplement l'état de la LED:

```c
if (ret == 0) {
    if (led.state == GPIO_HIGH) {
        gpio_write(&led, GPIO_LOW);
    } else {
        gpio_write(&led, GPIO_HIGH);
    }
    continue;
}
```

La fréquence de clignotement est ainsi entièrement pilotée par le timeout d'`epoll`, qui est mis à jour dynamiquement à chaque itération via la variable globale `period_ms`.

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
Jan  1 00:46:48 csel daemon.info not_silly_led_control[354]: Decreased period to 900ms
Jan  1 00:46:48 csel daemon.info not_silly_led_control[354]: Decreased period to 800ms
Jan  1 00:46:49 csel daemon.debug not_silly_led_control[354]: Led Off
Jan  1 00:46:50 csel daemon.debug not_silly_led_control[354]: Led On
Jan  1 00:46:51 csel daemon.info not_silly_led_control[354]: Resetting period to 500ms
Jan  1 00:46:52 csel daemon.info not_silly_led_control[354]: Increased period to 600ms
Jan  1 00:46:53 csel daemon.info not_silly_led_control[354]: Increased period to 1000ms
Jan  1 00:46:54 csel daemon.debug not_silly_led_control[354]: Led Off
```

On peut y observer clairement la séparation entre les événements de type `daemon.info` (changements de fréquence) et `daemon.debug` (toggles de LED), ainsi que le PID du processus.

#line()
