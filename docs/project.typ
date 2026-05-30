= Mini Projet

== Démarrage rapide

Ces commandes permettent de build et de déployer le module, daemon et application cli:

```bash
# build module kernel
cd src/07_miniproj/kernel
make
cd ..

# build user space daemon and cli tool
cd usr
cmake -B build
cmake --build build -j$(nproc)
cd ..

# déploiement dans la cible à travers ssh
ssh root@192.168.53.14 "mkdir -p /opt/cpu-fan-ctrl"
# module et daemon
scp kernel/cpu_fan_ctrl.ko usr/build/fanctrl_daemon root@192.168.53.14:/opt/cpu-fan-ctrl
# application cli
scp usr/build/fanctrl_client root@192.168.53.14:/usr/bin
# init script
scp deployment/S99cpufanctrl root@192.168.53.14:/etc/init.d/
ssh root@192.168.53.14 "reboot"
```

Après le reboot, vous devez voir l'écran qui s'allume avec les informations du système.

Les boutons sont désormais fonctionnels et l'application cli peut être utilisée dans la cible

```bash
fanctrl_client -i # mode interactif
```

```bash
Usage:
  Single command:    fanctrl_client <up | down | toggle>
  Interactive mode:  fanctrl_client -i
```

#pagebreak()

== Module noyau

Le module noyau constitue la couche la plus basse du système. Il est responsable
de la lecture périodique de la température du processeur, du pilotage de la LED
Status par un timer et de l'exposition d'une interface de configuration via le
_sysfs_. Cette section décrit les choix de conception ainsi que les primitives
noyau mises en œuvre.

== Choix d'architecture : platform device et platform driver

Les deux approches vus en cours pour la conception du module se basaient sur 
l'utilisation des sous-sytèmes `misc` et `platform`.

Un _miscdevice_ crée automatiquement une entrée dans `/dev` et convient
lorsqu'on souhaite offrir une interface de type fichier à l'espace utilisateur
(lecture, écriture, `ioctl`). Dans notre cas, l'interaction avec le module se
fait exclusivement via le _sysfs_ ; une entrée dans `/dev` n'aurait donc aucune
utilité et constituerait un artefact superflu.

Le _platform driver_, à l'inverse, s'inscrit pleinement dans le modèle de
périphériques Linux. Il sépare clairement la *description du matériel* (le
`platform_device`) du *code qui le pilote* (le `platform_driver`). 

Dans cet exercice l'implémentation instancie un `platform_device` dans la fonction `init`
du driver donc il peut paraître superflu mais en réalité, le fait de l'avoir nous permettrait plus 
facilement d'évoluer vers une architecture plus moderne où le device serait défini dans le Device Tree et on laisserait
le kernel l'instancier auprès de notre driver.

```c
static struct platform_driver fan_drv = {
    .driver = { .name = DRIVER_NAME, .owner = THIS_MODULE },
    .probe  = fan_probe,
    .remove = fan_remove,
};
```

La fonction `fan_probe()` est appelée automatiquement par le noyau lorsque le
périphérique et le pilote portent le même nom. Elle centralise toute
l'initialisation : allocation des ressources, configuration du GPIO, création
des attributs _sysfs_ et démarrage des mécanismes de surveillance.

Comme dit précédemment, le probe est indirectement appellé dans notre fonction `init` 
avec un appel à `platform_device_register_simple`.

```c
    fan_pdev = platform_device_register_simple(DRIVER_NAME, -1, NULL, 0);
    if (IS_ERR(fan_pdev)) {
        return PTR_ERR(fan_pdev);
    }
```

== Interface sysfs

Le module expose trois attributs dans le répertoire du périphérique sous
`/sys/devices/platform/cpu-fan-ctrl/` :

- *`mode`* (lecture/écriture) : `0` pour le mode manuel, `1` pour le mode
  automatique.
- *`frequency`* (lecture/écriture) : fréquence de clignotement en Hz. L'écriture
  n'est autorisée qu'en mode manuel ; une tentative en mode automatique retourne
  `-EINVAL`.
- *`temperature`* (lecture seule) : dernière température lue en degrés Celsius
  entiers.

```c
DEVICE_ATTR_RO(temperature);
DEVICE_ATTR_RW(mode);
DEVICE_ATTR_RW(frequency);
```

La macro `DEVICE_ATTR_RW` s'attend à que les fonctions de lecture et écriture 
s'appellent `_show` et `_store`. Les valeurs partagées entre le contexte timer (interruption
logicielle) et le contexte processus (écriture sysfs) sont protégées par des
variables `atomic_t`, évitant ainsi tout besoin de mutex ou spinlock explicite pour des
entiers simples.

== Pilotage de la LED : timer noyau et GPIO

Le clignotement de la LED Status est assuré par un timer noyau périodique,
déclaré avec `timer_setup()` et réarmé manuellement à chaque expiration via
`mod_timer()`. Cette approche permet de modifier la fréquence à la volée, sans
devoir arrêter et redémarrer le timer.

```c
static void timer_callback(struct timer_list *timer)
{
    struct dev_data *dd = container_of(timer, struct dev_data, fan_timer);
    dd->led_state = !dd->led_state;
    gpio_set_value(GPIO_LED, dd->led_state);
    rearm_timer(dd);
}

static unsigned long freq_to_jiffies(int hz)
{
    return HZ / hz / 2; /* demi-période : allumé + éteint = 1 période */
}
```

La conversion fréquence -> jiffies divise par deux car le timer se déclenche
deux fois par période (une fois pour allumer, une fois pour éteindre). La
valeur `HZ` représente le nombre de jiffies par seconde, défini à la
compilation du noyau.

Le GPIO est demandé de façon gérée (_managed_) avec `devm_gpio_request()` :
le noyau le libère automatiquement si le `probe` échoue ou lors du `remove`,
évitant de devoir gérer cette ressource manuellement.

```c
devm_gpio_request(&pdev->dev, GPIO_LED, led_name);
gpio_direction_output(GPIO_LED, 0);
```


== Lecture de la température : `thermal` et `delayed_work`

La lecture de la température repose sur deux fonctions du sous-système
`linux/thermal.h` :

```c
struct thermal_zone_device *thermal_zone_get_zone_by_name("cpu-thermal");
int thermal_zone_get_temp(tzd, &temperature); /* résultat en millièmes de °C */
```

La zone `cpu-thermal` est obtenue une seule fois lors du `probe` et conservée
dans la structure de données du pilote. La lecture effective est effectuée dans
un _delayed work_, une tâche différée et exécutée dans le contexte du
_workqueue_ noyau, et non dans le callback du timer.

Ce choix est motivé par deux raisons fondamentales. Premièrement,
`thermal_zone_get_temp()` n'est pas garantie _IRQ-safe_ : elle peut essayer de `sleep`
ou acquérir des mutex, ce qui est interdit dans un contexte d'interruption tel que le callback
d'un timer noyau (Soft-IRQ). Deuxièmement, lire la température à la même fréquence que le clignotement
de la LED (jusqu'à 20 Hz) serait inutilement coûteux et éveillerait le CPU beaucoup plus souvent que
nécessaire. La lecture est donc cadencée à *1 Hz* via `schedule_delayed_work()` :

```c
static void temperature_work_callback(struct work_struct *work)
{
    struct dev_data *dd =
        container_of(work, struct dev_data, temperature_work.work);
    int temperature;

    if (thermal_zone_get_temp(dd->tzd, &temperature)) {
        schedule_delayed_work(&dd->temperature_work, HZ);
        return;
    }
    temperature /= TEMPERATURE_FACTOR; /* millièmes -> degrés */
    atomic_set(&dd->temperature, temperature);

    if (atomic_read(&dd->mode) == MODE_AUTO)
        atomic_set(&dd->hz, temperature_to_hz(temperature));

    schedule_delayed_work(&dd->temperature_work, HZ);
}
```

En mode automatique, la fréquence est mise à jour selon la table suivante :

#align(center)[
  #table(
    columns: (auto, auto),
    inset: (x: 12pt, y: 6pt),
    stroke: 0.5pt + luma(180),
    fill: (col, row) => if row == 0 { luma(220) } else { white },
    [*Température (°C)*], [*Fréquence (Hz)*],
    [< 35],  [2],
    [35–39], [5],
    [40–44], [10],
    [≥ 45],  [20],
  )
]

== Initialisation et libération des ressources

La fonction `fan_probe()` suit un ordre strict : allocation de la structure
privée, récupération de la zone thermique, demande du GPIO, création des
attributs _sysfs_, puis démarrage du timer et du _delayed work_. En cas
d'échec à n'importe quelle étape, les ressources déjà acquises sont libérées
explicitement avant de retourner le code d'erreur.

À la désinscription, `fan_remove()` supprime les attributs _sysfs_, arrête le
timer de façon synchrone avec `del_timer_sync()` (garantissant qu'aucun
callback n'est en cours d'exécution) et annule le _delayed work_ en attente
avec `cancel_delayed_work_sync()`.

```c
static int fan_remove(struct platform_device *pdev)
{
    struct dev_data *dd = dev_get_drvdata(&pdev->dev);
    device_remove_file(&pdev->dev, &dev_attr_mode);
    device_remove_file(&pdev->dev, &dev_attr_frequency);
    device_remove_file(&pdev->dev, &dev_attr_temperature);
    del_timer_sync(&dd->fan_timer);
    cancel_delayed_work_sync(&dd->temperature_work);
    return 0;
}
```

L'utilisation des variantes `_sync` est essentielle pour éviter des
_use-after-free_ : sans elles, le callback pourrait accéder à la structure
`dev_data` après que `fan_remove()` ait rendu la main et que le noyau ait
libéré la mémoire associée au périphérique.

#pagebreak()

= Daemon en espace utilisateur

Le daemon est le chef d'orchestre du système en espace utilisateur. Il agrège
les informations provenant du module noyau, gère les interactions physiques
(boutons, LED), expose une interface IPC et pilote l'écran OLED. Cette section
décrit l'architecture interne et le fonctionnement de
chacun de ses sous-systèmes.

== Prérequis

Avant de passer à l'implémentation, ce daemon avait besoin de deux choses qui n'avaient
pas encore été utilisés dans ce cours, le bus I2C et la led power.

=== Activation du bus I2C pour l'écran OLED

Comme expliqué dans la donnée, l'écran OLED SSD1306 est connecté au NanoPi via le bus I2C0. 
Dans la configuration par défaut du noyau, ce bus est désactivé dans le Device Tree.
Pour l'activer, il suffit d'étendre le fichier `.dts` du projet Buildroot en
ajoutant un fragment qui passe le statut du nœud `i2c0` à `okay` :

```diff
diff --git a/board/friendlyarm/nanopi-neo-plus2/nanopi-neo-plus2.dts b/board/friendlyarm/nanopi-neo-plus2/nanopi-neo-plus2.dts
index f80383b0ff..269c8e7d17 100644
--- a/board/friendlyarm/nanopi-neo-plus2/nanopi-neo-plus2.dts
+++ b/board/friendlyarm/nanopi-neo-plus2/nanopi-neo-plus2.dts
@@ -5,3 +5,7 @@
 / {
         /delete-node/ leds;
 };
+
+&i2c0 {
+    status = "okay";
+};
```

Après cette modification, et la génération du `.dtb`, on a mount la partion 1
de la carte SD et on a modifié le `.dtb` déjà présent, lors du prochain boot, on
a pu valider que cela marchait par la présence de l'entrée `/dev/i2c-0`.

=== Identification du GPIO de la LED Power

La LED Power de la carte d'extension est connectée à la broche `GPIOL10` du
SoC Allwinner H5. Pour déterminer le numéro de GPIO Linux correspondant, on
consulte le schéma et on valide avec la 
#link("https://wiki.friendlyelec.com/wiki/index.php/GPIO")[documentation]
que c'est la pin `362` .

Le numéro 362 est utilisé directement dans le daemon via l'interface _sysfs_
(`/sys/class/gpio/export`), de la même façon que dans les exercices de
contrôle de GPIO en espace utilisateur.

== Architecture générale : multiplexage par `epoll`

Le daemon est structuré autour d'une boucle `epoll` centrale. Plutôt que
d'utiliser des threads séparés pour chaque source d'événements, tous les
descripteurs de fichiers actifs (GPIO, sockets, timers) sont enregistrés dans
une instance `epoll` unique. Cela permet une gestion non-bloquante,
déterministe et sans conditions de course entre sous-systèmes.

```c
int daemon_run(daemon_t *daemon)
{
    while (1) {
        err = epoll_wait(daemon->epfd, events, daemon->event_count, -1);
        for (size_t i = 0; i < (size_t)err; ++i) {
            daemon_event_ctx_t *ctx = events[i].data.ptr;
            ctx->cb(daemon, ctx->event_data);
        }
    }
}
```

Chaque événement est associé à un contexte `daemon_event_ctx_t` contenant le
descripteur, le masque d'événements epoll, un pointeur de callback et des
données "utilisateur" opaques. Les sous-systèmes s'enregistrent et se
désenregistrent dynamiquement via `daemon_add_event()` et
`daemon_remove_event()`.

```c
typedef void (*daemon_event_cb)(struct daemon* daemon, void* event_data);

typedef struct {
    int events;
    int fd;
    daemon_event_cb cb;
    void* event_data;
} daemon_event_ctx_t;

int daemon_add_event(daemon_t* daemon, daemon_event_ctx_t ctx);
void daemon_remove_event(daemon_t* daemon, int fd);
```

Le daemon est décomposé en quatre modules :

#align(center)[
  #table(
    columns: (auto, auto, auto),
    inset: (x: 10pt, y: 6pt),
    stroke: 0.5pt + luma(180),
    fill: (col, row) => if row == 0 { luma(220) } else { white },
    [*Module*], [*Rôle*], [*Événements epoll*],
    [`daemon`],        [Accès sysfs, orchestration],          [—],
    [`daemon-io`],     [Boutons S1/S2/S3, LED Power],         [3 GPIO + 1 timerfd],
    [`daemon-ipc`],    [Socket Unix, protocole IPC],           [1 serveur + N clients],
    [`daemon-screen`], [Affichage OLED, refresh 30 FPS],      [1 timerfd],
  )
]

== Module `daemon` : accès au driver via sysfs

Le module central lit et écrit les attributs exposés par le module noyau dans
`/sys/devices/platform/cpu-fan-ctrl/`. Les fonctions `daemon_get_frequency()`,
`daemon_get_temperature()`, `daemon_get_mode()`, `daemon_increase_frequency()`,
`daemon_decrease_frequency()` et `daemon_toggle_mode()` encapsulent les
lecture/écriture de ces fichiers. Ce module est le seul point de contact avec le noyau ;
les autres sous-systèmes passent exclusivement par lui.

== Module `daemon-io` : interface physique

=== Gestion des boutons via GPIO sysfs

Les trois boutons (S1, S2, S3) sont lus via l'interface _sysfs_ GPIO, en
configurant chaque broche en entrée avec détection de front (`edge=falling`).
Le descripteur du fichier `value` de chaque GPIO est enregistré dans `epoll`
avec le masque `EPOLLERR`, qui signale les changements de valeur sur les
fichiers sysfs GPIO :

```c
/* Pour chaque boutont*/
daemon_key_create(name);
/* dummy read so it doesn' trigger on start*/
(void)daemon_key_read(key);
daemon_event_ctx_t ev_ctx = {.events = EPOLLERR,
                             .fd     = key_fd,
                             .cb     = read_key_event,
                             .event_data = key};
daemon_add_event(daemon, ev_ctx);
```

Chaque `daemon_key_create` export, configure la direction et l'edge.

Lors de la pression d'un bouton, `read_key_event()` est appelé. Il lit la
valeur pour acquitter l'événement epoll, puis appelle la fonction appropriée :
- *S1* — `daemon_increase_frequency()` : augmente la fréquence d'un palier
- *S2* — `daemon_decrease_frequency()` : diminue la fréquence d'un palier
- *S3* — `daemon_toggle_mode()` : bascule entre mode automatique et manuel

#pagebreak()

=== Signalisation sur la LED Power via `timerfd`

La pression de S1 ou S2 est signalisée par un clignotement de la LED
Power. La fréquence de clignotement est différente selon le bouton pressé
(augmentation vs diminution), ce qui rend une simple impulsion insuffisante.
Un `timerfd` est utilisé pour gérer ce clignotement de façon non-bloquante,
intégré directement dans la boucle `epoll` :

```c
if (key == &daemon->io.key_speed_up) {
    daemon->io.led_blink_count  = LED_BLINK_COUNT_ON_INCREASE;
    daemon->io.led_blink_period = LED_BLINK_PERIOD_ON_INCREASE;
    daemon_led_set(&daemon->io.led_power, true);
    daemon_increase_frequency(daemon, NULL);
    create_timer_event(daemon);
    daemon_timer_rearm(daemon->io.timer_fd, daemon->io.led_blink_period);
}
```

À chaque expiration du timer, `timer_done_cb()` inverse l'état de la LED et
décrémente un compteur. Lorsque le compteur atteint zéro, l'événement timer
est retiré de `epoll` et la LED est éteinte. Cette approche évite toute
attente active et libère la boucle principale entre deux clignotements.

En cas de plusieurs pressions rapides, `create_timer_event` efface l'ancien évennement
pour ne pas avoir plusieurs évenements `epoll` pour le même file descriptor.

== Module `daemon-ipc` : interface socket Unix

=== Protocole

Le module IPC expose un socket de domaine Unix en mode flux (`SOCK_STREAM`) à
sur `/run/fanctrl-daemon.sock`. Le protocole est volontairement minimaliste :
chaque commande tient en un seul octet, et la réponse est soit un octet
d'erreur, soit un octet de type suivi de quatre octets de valeur entière :

#align(center)[
  #table(
    columns: (auto, auto, auto),
    inset: (x: 10pt, y: 6pt),
    stroke: 0.5pt + luma(180),
    fill: (col, row) => if row == 0 { luma(220) } else { white },
    [*Commande*], [*Valeur*], [*Réponse*],
    [`CMD_FREQ_UP`],     [`0x01`], [`RES_FREQ` + nouvelle fréquence (4 octets)],
    [`CMD_FREQ_DOWN`],   [`0x02`], [`RES_FREQ` + nouvelle fréquence (4 octets)],
    [`CMD_TOGGLE_MODE`], [`0x03`], [`RES_MODE` + nouveau mode (4 octets)],
    [_toute autre valeur_], [—],  [`RES_ERROR` (1 octet)],
  )
]

=== Gestion des connexions

Le descripteur serveur est enregistré dans `epoll` avec `ipc_accept_cb` comme
callback. À chaque connexion entrante, `accept4()` est appelé avec
`SOCK_NONBLOCK | SOCK_CLOEXEC` et le descripteur client est immédiatement
enregistré dans `epoll` avec `ipc_read_cb`. Cette approche permet de gérer
plusieurs clients simultanément sans threads ni `select`. Le fichier socket
résiduel d'une exécution précédente est supprimé par `unlink()` avant le
`bind()` pour éviter une erreur `EADDRINUSE`.

== Module `daemon-screen` : affichage OLED

L'écran OLED est piloté par la bibliothèque `ssd1306` fournie, qui communique
avec le contrôleur via le bus I2C0. Le rafraîchissement est déclenché par un
`timerfd` armé à 33 ms (~30 FPS), enregistré dans la boucle `epoll`.

À chaque expiration, `update_screen_cb()` lit la température, le mode et la
fréquence via le module `daemon`, puis ne met à jour que les lignes dont la
valeur a changé depuis le dernier rafraîchissement. Cela évite de réécrire
l'intégralité de l'écran à chaque cycle et réduit le trafic sur le bus I2C :

```c
if (mode != daemon->screen.last_mode) {
    ssd1306_set_position(0, 3);
    snprintf(buffer, sizeof(buffer), "Mode: %5s", mode_to_string(mode));
    ssd1306_puts(buffer);
    daemon->screen.last_mode = mode;
}
```

L'écran affiche en permanence le mode de fonctionnement (AUTO / MANUAL),
la température courante en degrés Celsius et la fréquence de clignotement
en Hz.


= Application CLI

L'application CLI constitue la troisième couche du système. Elle permet à un
opérateur de piloter le daemon depuis un terminal, soit en passant une commande
unique en argument, soit en entrant dans un mode interactif. Elle communique
exclusivement via le socket Unix défini par le module `daemon-ipc`.

== Modes de fonctionnement

L'application supporte deux modes d'utilisation :

```
# Commande unique
fan-ctrl-cli <up | down | toggle>

# Mode interactif
fan-ctrl-cli -i
```

En mode commande unique, l'application envoie la commande, affiche la réponse
et se termine. En mode interactif, une boucle `fgets` lit les commandes au
clavier jusqu'à ce que l'utilisateur tape `exit` ou `quit`, ou ferme le flux
d'entrée (Ctrl+D).

== Envoi d'une commande : `send_cmd()`

Pour chaque commande, l'application ouvre une nouvelle connexion au socket
Unix, envoie un octet de commande et lit la réponse du daemon. La connexion
est fermée immédiatement après la réponse, ce qui est cohérent avec le modèle
_request-response_ du protocole :

```c
int send_cmd(daemon_ipc_cmd_t cmd)
{
    int sock_fd = socket(AF_UNIX, SOCK_STREAM, 0);
    connect(sock_fd, (struct sockaddr *)&addr, sizeof(addr));

    uint8_t payload = (uint8_t)cmd;
    write(sock_fd, &payload, sizeof(payload));

    uint8_t buffer[16];
    read(sock_fd, buffer, sizeof(buffer));

    switch ((daemon_ipc_response_type_t)buffer[0]) {
        case RES_FREQ:  printf("New Frequency: %d\n", *(int *)(buffer + 1)); break;
        case RES_MODE:  printf("New Mode: %d\n",      *(int *)(buffer + 1)); break;
        case RES_ERROR: fprintf(stderr, "Error\n"); break;
    }
    close(sock_fd);
}
```

La réponse est désérialisée en lisant le premier octet comme type, puis les
quatre octets suivants comme entier. Ouvrir une nouvelle connexion par commande
simplifie la gestion des erreurs et évite d'avoir à gérer un état de connexion
persistant côté client.

== Mode interactif

Le mode interactif propose une invite de commande (`fan-ctrl-cli>`) et réutilise
la même fonction `parse_and_send()` que le mode à argument unique. Les lignes
vides sont ignorées et la commande `exit` ou `quit` termine proprement la
boucle :

```c
void run_interactive_mode(void)
{
    char input[256];
    while (1) {
        printf("fan-ctrl-cli> ");
        fflush(stdout);
        if (!fgets(input, sizeof(input), stdin)) break;
        input[strcspn(input, "\n")] = 0;
        if (strlen(input) == 0) continue;
        if (strcasecmp(input, "exit") == 0) break;
        parse_and_send(input);
    }
}
```

Ce mode est particulièrement utile lors du développement et du débogage, car
il évite de retaper le nom du programme pour chaque commande.


= Déploiement et intégration système

Cette section décrit comment le module noyau, le daemon et le client sont
intégrés dans le système Buildroot et chargés automatiquement au démarrage.

== Structure de déploiement

Les composants sont regroupés sous `/opt/cpu-fan-ctrl/` et le client est placé
dans `/usr/bin/` pour être accessible directement depuis le PATH :

```
/opt/cpu-fan-ctrl/
    cpu_fan_ctrl.ko    // module noyau
    fanctrl_daemon     // daemon

/usr/bin/fanctrl_client  // application CLI
```

Regrouper le module et le daemon dans un même répertoire sous `/opt` simplifie
le déploiement : un seul répertoire à copier suffit pour mettre à jour
l'ensemble du système, et le script d'init sait exactement où trouver chaque
binaire.

== Chargement du module noyau

Plusieurs approches ont été étudiées pour le chargement automatique du module.

La première consistait à installer le `.ko` dans l'arborescence standard des
modules noyau et à enregistrer la dépendance :

```bash
cp cpu_fan_ctrl.ko /lib/modules/5.15.148/extra/
echo "extra/cpu_fan_ctrl.ko:" >> /lib/modules/5.15.148/modules.dep
```

Cela permet d'utiliser `modprobe cpu_fan_ctrl`, qui résout automatiquement les
dépendances. On pourrait alors lister le module dans `/etc/modules` pour un
chargement au démarrage. Cependant, sur ce système BusyBox, `/etc/modules`
n'existe pas par défaut et aucun script d'init ne le traite, même en créant le
fichier manuellement. Il manquerait un script qui appelle `modprobe` pour
chaque entrée, ce qui ne fait pas partie de la configuration de base.

L'approche retenue est donc d'utiliser `insmod` directement depuis le script
d'init avec le chemin absolu vers le `.ko`. Cela ne nécessite pas de
`depmod` et fonctionne de façon fiable indépendamment de l'état de
`modules.dep`.

#pagebreak()

== Script d'init SysV

Un script d'init BusyBox-compatible est placé dans `/etc/init.d/S99cpufanctrl`.
Le préfixe `S99` garantit qu'il est exécuté en dernier, une fois que tous les
autres services système sont démarrés :

```sh
#!/bin/sh
case "$1" in
    start)
        echo "Loading cpu-fan-ctrl module..."
        insmod /opt/cpu-fan-ctrl/cpu_fan_ctrl.ko
        echo "Starting cpu-fan-ctrl daemon..."
        /bin/sh -c '/opt/cpu-fan-ctrl/fanctrl_daemon 2>&1 | logger -t fan-ctrl-daemon' &
        ;;
    stop)
        echo "Stopping cpu-fan-ctrl daemon..."
        killall fanctrl_daemon
        rmmod cpu_fan_ctrl
        ;;
    restart)
        $0 stop
        $0 start
        ;;
    *)
        echo "Usage: $0 {start|stop|restart}"
        exit 1
        ;;
esac
```

Le daemon est lancé via un sous-shell qui redirige l'output vers `logger`.
Cela intègre les messages du daemon dans le journal système (`syslog`) sous
le tag `fan-ctrl-daemon`, aux côtés des messages noyau.

== Journalisation

Le pipe vers `logger` permet de corréler les événements noyau et daemon dans
un flux unique. L'exemple ci-dessous illustre une séquence typique : le daemon
tente d'augmenter la fréquence alors que le mode automatique vient d'être
activé, ce qui provoque un refus du module noyau avec `-EINVAL` :

```
Jan  1 04:34:31 csel kern.info  kernel:         [ 5783.706918] mode set to 1
Jan  1 04:34:34 csel user.notice fan-ctrl-daemon: failed to set frequency
Jan  1 04:34:34 csel kern.err   kernel:         [ 5785.080280] device is not in manual mode
```

Les messages noyau apparaissent avec la facilité `kern` et les messages du
daemon avec `user`, ce qui permet de les filtrer indépendamment si nécessaire.
La consultation se fait en temps réel avec :

```bash
tail -f /var/log/messages
```
