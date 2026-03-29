= Modules noyaux

== Exercice 1

#rect([
  Générez un module noyau out of tree pour la cible NanoPi
])

Sur la section #link("https://mse-csel.github.io/website/lecture/programmation-noyau/modules/module-gen/#generation-out-of-tree")[Génération «out of tree»] du support de cours, le chemin des compilateurs est \ `TOOLS := /buildroot/output/host/usr/bin/aarch64-linux-gnu-` \ et Samuel a du le corriger avec \ `TOOLS := /buildroot/output/host/usr/bin/aarch64-buildroot-linux-gnu-`.

On retrouve bien les informations du module définies par les macros `MODULE_*`.
```sh
> modinfo mymodule.ko
filename:       /home/sam/mse/csel/csel-workspace/src/02_modules/exercice01/mymodule.ko
license:        GPL
description:    Empty module for testing
author:         Samuel Roland
...
```

La comparaison entre `lsmod` et `/proc/modules` n'est pas très différente comme `lsmod` ne fait que formatter joliment l'affichage des informations données par `/proc/modules`. (La man page indique `lsmod is a trivial program which nicely formats the contents of the /proc/modules, showing what kernel modules are currently loaded.`)

```
# lsmod
Module                  Size  Used by    Tainted: G
mymodule               16384  0
ipv6                  462848 18 [permanent]
brcmfmac              253952  0
brcmutil               20480  1 brcmfmac
...
# cat /proc/modules
mymodule 16384 0 - Live 0xffff8000011bf000 (O)
ipv6 462848 18 [permanent], Live 0xffff80000114d000
brcmfmac 253952 0 - Live 0xffff80000110e000
...
```
Notre module `mymodule` est bien activé.

Pour le convertir en module inside tree, nous avons testé de faire un lien symbolique à notre module actuel. La situation est particulière ici comme nous avons le même code, en pratique cela ne fonctionnerait pas. (Au moment de la contribution du lien symbolique qui pointe sur rien, on aurait des gentils commentaires de Linus...).
```sh
> pwd
/workspace/src/02_modules/exo1
> ln -s $PWD/skeleton.c /buildroot/output/build/linux-5.15.148/drivers/misc/mymodule.c
```
Après changement du `Makefile` et `Kconfig` mentionné, recompilation et extraction du rootfs, le module peut être lancé avec `modprobe`.

Nous avons aussi vu une typo dans `Génération «inside tree»`: `Voir ./Documenation/kbuild pour plus de détails ...`


=== Exercice 2

Note: la solution donnée devrait être dans un dossier `exercice02` séparé de `exercice01`.

Nous avons pu définir 3 paramètres
```c
static char* firstname = "?";
static char* lastname = "?";
static int min_temperature = 20;
module_param(firstname, charp, 0);
module_param(lastname, charp, 0);
module_param(min_temperature, int, 0);

static int __init skeleton_init(void) {
    pr_info("Linux module loaded !\n");
    pr_info("You are %s %s and your prefered min temperature is %d !\n",
            firstname, lastname, min_temperature);
    return 0;
}
...
```

Leur usage fonctionne sans problème.
```sh
> pwd
/workspace/src/02_modules/exo1
> insmod mymodule.ko firstname=Samuel lastname=Roland min_temperature=23
[  831.673401] Linux module loaded !
[  831.676797] You are Samuel Roland and your prefered min temperature is 23 !
> rmmod mymodule
[  835.683350] Linux module unloaded !
[  835.686943] Byebye Samuel Roland
```

Par contre il n'est pas clair de pourquoi la solution fournie contient ce changement de PATH, qui n'est pas présent dans le support de cours sous `Génération «out of tree»` ?
```sh
export PATH := /buildroot/output/host/usr/sbin$\
    :/buildroot/output/host/usr/bin/$\
    :/buildroot/output/host/sbin$\
    :/buildroot/output/host/bin/$\
    :$(PATH)
```

== Exercice 3

La réponse est disponible sur https://docs.kernel.org/core-api/printk-basics.html

#quote("The result shows the current, default, minimum and boot-time-default log levels.")
```sh
> cat /proc/sys/kernel/printk
7	4	1	7
```
En interprétant les niveaux de logs, nous avons DEBUG en mode actuel, WARNING par défaut, ALERT au minimum et DEBUG au démarrage. Ces niveaux de logs indique le niveau à partir duquel il ne faut plus afficher les messages dans la console. Ainsi, `dmesg` permet toujours d'accéder aux messages stockés même si une partie pourraient ne pas avoir été visible au moment de leur création.

Pour confirmer notre compréhensions de ces paramètres, voici un POC qui confirme notre logique.

```c
static int __init skeleton_init(void) {
    struct rtc_time t = rtc_ktime_to_tm(ktime_get_real());
    pr_info("Linux module loaded !\n");
    pr_emerg("Testing various logs levels at %ptRs\n", &t);

    pr_emerg("LOG with level 0 KERN_EMERG");
    pr_alert("LOG with level 1 KERN_ALERT");
    pr_crit("LOG with level 2 KERN_CRIT");
    pr_err("LOG with level 3 KERN_ERR");
    pr_warn("LOG with level 4 KERN_WARNING");
    pr_notice("LOG with level 5 KERN_NOTICE");
    pr_info("LOG with level 6 KERN_INFO");
    pr_info("LOG with level 7 KERN_DEBUG\n");
    return 0;
}

static void __exit skeleton_exit(void) { pr_info("Linux module unloaded !\n"); }
```

Le niveau actuel étant 7, tous les messages s'affichent.
```sh
> cat /proc/sys/kernel/printk && insmod mymodule.ko; echo stopping; rmmod mymodule
7	4	1	7
[12503.450256] Linux module loaded !
[12503.453650] Testing various logs levels at 1970-01-01 03:58:30
[12503.459509] LOG with level 0 KERN_EMERG
[12503.459513] LOG with level 1 KERN_ALERT
[12503.463354] LOG with level 2 KERN_CRIT
[12503.467187] LOG with level 3 KERN_ERR
[12503.470943] LOG with level 4 KERN_WARNING
[12503.474610] LOG with level 5 KERN_NOTICE
[12503.478626] LOG with level 6 KERN_INFO
[12503.482553] LOG with level 7 KERN_DEBUG
stopping
[12503.502662] Linux module unloaded !
```

En passant au niveau 4, on voit tous les messages inférieur au niveau 4 (0-3). Il est un peu curieux que cela soit différent avec le niveau 7, où on se serait attendu à avoir la même logique (de 0-6 au lieu de 0-7).
```sh
> echo 4 > /proc/sys/kernel/printk
> cat /proc/sys/kernel/printk && insmod mymodule.ko; echo stopping; rmmod mymodule
4	4	1	7
[12879.379819] Testing various logs levels at 1970-01-01 04:04:46
[12879.385698] LOG with level 0 KERN_EMERG
[12879.385702] LOG with level 1 KERN_ALERT
[12879.389547] LOG with level 2 KERN_CRIT
[12879.393394] LOG with level 3 KERN_ERR
stopping
```

En inspectant `dmesg`, les messages suivants (4-7) n'ont pas été ignorés, ils ont bien été stocké sans être affiché dans la console.
```sh
> dmesg
...
[12879.379791] Linux module loaded !
[12879.379819] Testing various logs levels at 1970-01-01 04:04:46
[12879.385698] LOG with level 0 KERN_EMERG
[12879.385702] LOG with level 1 KERN_ALERT
[12879.389547] LOG with level 2 KERN_CRIT
[12879.393394] LOG with level 3 KERN_ERR
[12879.397148] LOG with level 4 KERN_WARNING
[12879.400816] LOG with level 5 KERN_NOTICE
[12879.400821] LOG with level 6 KERN_INFO
[12879.400824] LOG with level 7 KERN_DEBUG
[12879.415250] Linux module unloaded !
```

L'autre point intéressant est que la console du kernel est visible en connexion série, mais n'est pas visible quand on se connecte en SSH.

== Exercice 4 - Gestion de la mémoire, bibliothèque et fonction utile
Cette partie fonctionne sans problème, en allouant à l'aide de `kzmalloc`.
```sh
> insmod mymodule.ko elements_count=5 default_text="YEP"
[  693.209602] Linux module loaded !
[  693.213023] Creating dynamically 5 elements with default text 'YEP'!
[  693.219399] Allocating elements
[  693.222539] Showing elements
[  693.225433] ID=0, text=YEP
[  693.228151] ID=1, text=YEP
[  693.230856] ID=2, text=YEP
[  693.233572] ID=3, text=YEP
[  693.236288] ID=4, text=YEP
> rmmod mymodule.ko
[  697.254258] Freeing and removing elements from the list
[  697.259564] Freeing element with ID=0
[  697.263224] Freeing element with ID=1
[  697.266907] Freeing element with ID=2
[  697.270577] Freeing element with ID=3
[  697.274255] Freeing element with ID=4
[  697.277926] Linux module unloaded !
```

Nous avons utilisé `list_for_each_entry_safe` pour naviguer la liste de manière _safe_ tout en retirant l'élément actuel de la liste pour le _free_.

```c
static void __exit skeleton_exit(void) {
    // This is based on https://docs.kernel.org/core-api/list.html#traversing-whilst-removing-nodes
    struct Element* curr;
    struct Element* temp_storage; /* temporary storage for safe iteration */
    pr_info("Freeing and removing elements from the list\n");
    list_for_each_entry_safe(curr, temp_storage, &ELEMENTS_LIST, list)
    {
        pr_info("Freeing element with ID=%d\n", curr->id);
        list_del(&curr->list);
        kfree(curr);
    }
    pr_info("Linux module unloaded !\n");
}
```

== Exercice 5 - Accès aux entrées/sorties

Pourquoi dans la solution, le mappage prend une taille de 4096 bytes alors que selon la datasheet `SID 0x01C1 4000---0x01C1 43FF 1K`, il semble que la zone ne fait que 1024 bytes ?
```c
res[0] = request_mem_region (0x01c14000, 0x1000, "allwiner h5 sid");
```

On peut confirmer le mapping via `request_mem_region`
```sh
> cat /proc/iomem
...
01c14000-01c143ff : ChipID mapping via the 1K zone for SID
...
```
Nous avions le problème de ne pas arriver à réserver la zone pour le capteur de temperature.
```c
// Note: this will fail because another module has already requested this
region reserved_zones[1] = request_mem_region(THERMAL_SENSOR_START_ADDR, 1024, "Thermal sensor mapping via the 1K zone");
```

Nous avons pu le confirmer via `/proc/iomem`.
```c
> cat /proc/iomem  | grep 01c25
01c25000-01c253ff : 1c25000.thermal-sensor thermal-sensor@1c25000
```
Il est maintenant clair de pourquoi la solution contient les lignes commentées de ces réservations.

Nous avions aussi commencé par mapper le minimum, pour le chip id, c'était les 16 bytes `ioremap (0x01c14200, 16);` mais cela ne fonctionnait pas..

Après pas mal d'effort, de coup d'oeil dans la cheatsheet pour comprendre d'où venait ces addresses, de coup d'oeil à la solution pour comprendre l'extraction des bytes, nous avons réussi à sortir les 3 informations. Sans le code de solution pour tester, nous n'aurions pas su que l'adresse MAC était en little endian.
```
[ 4043.595525] CHIPID = 82800001-94004704-5036c304-302c0c0e
[ 4043.603716] temperature register = 1563 and real temperature 37.204 degrees Celsius
[ 4043.611384] MAC address = 02:01:75:7b:97:8c
```

Nous avons implémenté à la main l'affichage à virgule de la temperature puisque le `%f` n'est pas supporté par `printk`. Un autre élément intéressant pour tester au plus vite les modifications est la mise en place d'un mode watch, à l'aide de `entr`.

```sh
> cat test_exo5.sh
ssh root@192.168.53.14 <<EOF
cd /workspace/src/02_modules/exercice05
insmod mymodule.ko
echo stopping
rmmod mymodule
dmesg -c # read + clean ring buffer
EOF
> ls skeleton*.c | entr -c -c -r bash -c "make && clear && ./test_exo5.sh"
# à chaque changement du fichier C, le code compile et se relance sur la carte et l'output est visible ici.
```

== Exercice 6 - Threads du noyau
```sh
> insmod mymodule.ko
[ 4136.760510] Linux module 06 skeleton loaded
[ 4136.771303] Thread started !
>
[ 4141.793734] Tick from thread
[ 4146.910610] Tick from thread

> ls
Makefile	mymodule.ko	mymodule.mod.o	skeleton.o	watch.sh
Module.symvers	mymodule.mod	mymodule.o	skeleton.sol.c
modules.order	mymodule.mod.c	skeleton.c	test_exo6.sh
[ 4152.030698] Tick from thread
```
Le thread actif est bien visible avec `ps`.
```sh
> ps -aux
...
14801 ?        D      0:00 [Simple kthread]
...
```

Retirer le module gère l'arrêt correctement.
```sh
> rmmod mymodule
[ 4310.654599] Tick from thread
[ 4310.657545] Stopping thread
[ 4310.662684] Linux module skeleton unloaded

# pas d'autres messages ensuite.
```

== Exercice 7 - Mise en sommeil

```
```
== Exercice 8 - Interruptions

