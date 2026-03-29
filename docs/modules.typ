= Modules noyaux

== Exercice 1

#rect([
  Générez un module noyau out of tree pour la cible NanoPi
])
Pas de problème sur cette partie.

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
> insmod mymodule.ko firstname=Samuel lastname=Roland min_temperature=23
[  831.673401] Linux module loaded !
[  831.676797] You are Samuel Roland and your prefered min temperature is 23 !
> rmmod mymodule
[  835.683350] Linux module unloaded !
[  835.686943] Byebye Samuel Roland
```

Problem:
The default entry is the course material is
```sh
TOOLS := /buildroot/output/host/usr/bin/aarch64-linux-gnu-
```

but should be
```sh
TOOLS := /buildroot/output/host/usr/bin/aarch64-buildroot-linux-gnu-
```


```sh
> pwd
/workspace/src/02_modules/exo1
> ln -s $PWD/skeleton.c /buildroot/output/build/linux-5.15.148/drivers/misc/mymodule.c
```

I had to do this to get the latest rootfs
```sh
/usr/local/bin/extract-rootfs.sh
```

```sh
# pwd
/workspace/src/02_modules/exo1
# insmod mymodule.ko firstname=Samuel lastname=Roland min_temperature=23
[ 2324.897330] Linux module loaded !
[ 2324.900729] You are Samuel Roland and your prefered min temperature is 23 !
```


Pourquoi la solution contient ce changement de PATH ???
```sh
export PATH := /buildroot/output/host/usr/sbin$\
    :/buildroot/output/host/usr/bin/$\
    :/buildroot/output/host/sbin$\
    :/buildroot/output/host/bin/$\
    :$(PATH)
```

== Exercice 3

The answer is available on https://docs.kernel.org/core-api/printk-basics.html

> The result shows the current, default, minimum and boot-time-default log levels.
```sh
# cat /proc/sys/kernel/printk
7	4	1	7
```
-> DEBUG in current mode - WARNING by default - ALERT at minimum - DEBUG at boot time


== Exercice 4
This part is working fine, we managed to allocate using `kzmalloc`
```sh
# insmod mymodule.ko elements_count=5 default_text="YEP"
[  693.209602] Linux module loaded !
[  693.213023] Creating dynamically 5 elements with default text 'YEP'!
[  693.219399] Allocating elements
[  693.222539] Showing elements
[  693.225433] ID=0, text=YEP
[  693.228151] ID=1, text=YEP
[  693.230856] ID=2, text=YEP
[  693.233572] ID=3, text=YEP
[  693.236288] ID=4, text=YEP
# rmmod mymodule.ko
[  697.254258] Freeing and removing elements from the list
[  697.259564] Freeing element with ID=0
[  697.263224] Freeing element with ID=1
[  697.266907] Freeing element with ID=2
[  697.270577] Freeing element with ID=3
[  697.274255] Freeing element with ID=4
[  697.277926] Linux module unloaded !
```

We have used `list_for_each_entry_safe` to safely navigate the list while removing the current element and freeing it.

```c
static void __exit skeleton_exit(void)
{
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


== Exercice 5
== Exercice 6
== Exercice 7
== Exercice 8
== Exercice 9
== Exercice 10
