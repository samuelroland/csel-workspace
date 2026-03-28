= Pilotes de périphériques

== Exercice 1

#rect([
  Réaliser un pilote orienté mémoire permettant de mapper en espace utilisateur les registres du microprocesseur en utilisant le fichier virtuel /dev/mem. Ce pilote permettra de lire l’identification du microprocesseur (Chip-ID aux adresses 0x01c1'4200 à 0x01c1'420c) décrit dans l’exercice “Accès aux entrées/sorties” du cours sur la programmation de modules noyau.
])

Pas de problèmes avec ceci, la version proposé par l'étudiant défini la taille de page à 4KB à la place d'utiliser `getpagesize`, ce qui serait plus propre.

On n'utilise pas de `volatile` car c'est une valeur qui ne sera jamais modifiée.

Version étudiant disponible dans le workspace `src/03_drivers/exercice01/main.c`

#line()

== Exercice 2

#rect([
Implémenter un pilote de périphérique orienté caractère. Ce pilote sera capable de stocker dans une variable globale au module les données reçues par l’opération write et de les restituer par l’opération read. Pour tester le module, on utilisera les commandes echo et cat.
])

Pour cet exercice, afin de compiler le code dans ma machine (sans les dev-container docker), les fichiers `buildroot_path` et `kernel_settings` ont dû être modifiés. En effet, ces fichiers ont le chemin vers les artifacts buildroot hard-codés sur `/buildroot/output`. Ceci est vrai pour les dev containers qui font un mount du volume dans `/buildroot` mais en natif ceci n'est pas le cas.

Dans ma machine, la compilation buildroot s'est faite dans le répertoire `output`, dans le workspace directement et non dans le répertoire buildroot. Ceci a été fait en spécifiant le paramètre `O` lors de la commande `make defconfig`.

```bash
make defconfig O=../output BR2_DEFCONFIG=configs/csel_defconfig
```

Pour cette raison, les deux fichiers ont été modifiées pour tenir compte d'une variable supplémentaire: `BUILDROOT_OUTPUT_DIR`:

```make
BUILDROOT_OUTPUT_DIR ?= /buildroot/output
```

L'utilisation de l'opérateur `?=` garantit que cela continue de marcher si l'on utilise les devcontainers mais me permet de la définir pour modifier les chemins.

```bash
export BUILDROOT_OUTPUT_DIR="/path/to/csel-workspace/output"
```

Une fois ces modifications, la compilation peut se faire sans soucis.

Une fois le module loadé avec `insmod`, on peut trouver le major avec:

```sh
cat /proc/devices | grep mymodule
511 mymodule
```

```sh
> echo "test" > /dev/mymodule 
> cat /dev/mymodule 
test
```

Il y a aussi un bug dans l'implémentation de `skeleton_read`, dans le cas où `off` est supérieur à la longueur, `remaining` prendra une valeur négative et on essayera de copier un nombre négatif de bytes

```c
static ssize_t skeleton_read(struct file* f,
                             char __user* buf,
                             size_t count,
                             loff_t* off)
{
    // compute remaining bytes to copy, update count and pointers
    ssize_t remaining = BUFFER_SZ - (ssize_t)(*off);
    char* ptr         = s_buffer + *off;
    if (count > remaining) count = remaining;
    *off += count;

    // copy required number of bytes
    if (copy_to_user(buf, ptr, count) != 0) count = -EFAULT;

    pr_info("skeleton: read operation... read=%ld\n", count);

    return count;
}
```

Pour la résoudre il suffit de retourner 0 si `remaining` est négatif ou égal à `0`.

Un autre problème est dans la fonction `skeleton_init`. Si la fonction `alloc_chrdev_region` retourne une erreur, cette erreur n'est pas propagé. 

```c
static int __init skeleton_init(void)
{
    int status = alloc_chrdev_region(&skeleton_dev, 0, 1, "mymodule");
    if (status == 0) {
        cdev_init(&skeleton_cdev, &skeleton_fops);
        skeleton_cdev.owner = THIS_MODULE;
        status              = cdev_add(&skeleton_cdev, skeleton_dev, 1);
    }

    pr_info("Linux module skeleton loaded\n");
    return 0;
}
```

Pour le résoudre il suffit de retourner `status`. On peut aussi éviter le `pr_info` si status n'est pas `0` car le module ne sera pas chargé.

Exemple:

```c
static int __init skeleton_init(void)
{
    int status = alloc_chrdev_region(&skeleton_dev, 0, 1, "mymodule");
    if (status) {
        pr_err("alloc_chrdev_region failed %d", status);
        return status;
    }

    cdev_init(&skeleton_cdev, &skeleton_fops);
    skeleton_cdev.owner = THIS_MODULE;
    status              = cdev_add(&skeleton_cdev, skeleton_dev, 1);

    pr_info("Linux module skeleton loaded\n");
    return 0;
}
```

#line()

== Exercice 3

#rect([
Etendre la fonctionnalité du pilote de l’exercice précédent afin que l’on puisse à l’aide d’un paramètre module spécifier le nombre d’instances. Pour chaque instance, on créera une variable unique permettant de stocker les données échangées avec l’application en espace utilisateur.
])

1. Tout d'abord on ajoute le paramètre:

```c
static uint instances = 1;
module_param(instances, uint, 0);
```

On utilise `uint` pour éviter de vérifier si cela est plus petit que `0`.

2. On aura besoin d'un tableau dynamique pour stocker un buffer par instance ainsi qu'un nombre dynamique de `cdevs`, 1 par instance.

```c
struct buffer {
    char data[BUFFER_SZ];
};

static struct buffer* buffers;

static struct cdev* skeleton_cdev;
```

3. Pour savoir quelle instance est en train de faire un `read`/`write`. Nous pouvons stocker le minor number dans `f->private_data` lors de l'appel `open`.

```c
static int skeleton_open(struct inode* i, struct file* f)
{
    ...
    f->private_data = (void*)(uintptr_t)iminor(i);
}
```

Pour après le retrouver dans `read` et `write`:

```c

static ssize_t skeleton_read(struct file* f,
                             char __user* buf,
                             size_t count,
                             loff_t* off)
{
    char* buffer          = NULL;
    char* ptr             = NULL;
    ssize_t remaining     = 0;
    size_t instance_index = (size_t)(uintptr_t)f->private_data;
    if (instance_index >= instances) {
        pr_err("invalid instance index. expected 0..%u", instances - 1);
        return 0;
    }
    buffer = buffers[instance_index].data;
    ...
}
```

4. Finalement, il faut tout initializer correctement dans `skeleton_init`:

```c
static int __init skeleton_init(void)
{
    int err = 0;
    uint i  = 0;
    uint j  = 0;
    if (instances == 0) {
        pr_err("instances must be > 0");
        return -EINVAL;
    }

    err = alloc_chrdev_region(&skeleton_dev, 0, instances, "mymodule");
    if (err) {
        pr_err("alloc_chrdev_region failed %d", err);
        goto err;
    }

    skeleton_cdev = kcalloc(instances, sizeof(*skeleton_cdev), GFP_KERNEL);
    if (!skeleton_cdev) {
        pr_err("No memory for cdevs");
        err = -ENOMEM;
        goto err;
    }

    buffers = kcalloc(instances, sizeof(*buffers), GFP_KERNEL);
    if (!buffers) {
        pr_err("No memory for buffers");
        err = -ENOMEM;
        goto err;
    }

    for (i = 0; i < instances; ++i) {
        cdev_init(skeleton_cdev + i, &skeleton_fops);
        skeleton_cdev[i].owner = THIS_MODULE;
        err = cdev_add(skeleton_cdev + i, MKDEV(MAJOR(skeleton_dev), i), 1);
        if (err) {
            pr_err("cdev_add failed %d", err);
            goto err;
        }
    }
    pr_info("Linux module skeleton loaded. Instance count is %d\n", instances);
    return 0;
err:
    for (j = 0; j < i; ++j) {
        cdev_del(skeleton_cdev + j);
    }
    kfree(buffers);
    kfree(skeleton_cdev);
    unregister_chrdev_region(skeleton_dev, instances);
    return err;
}
```

```sh
> insmod mymodule.ko instances=0
insmod: can't insert 'mymodule.ko': Invalid argument
```

```sh
> insmod mymodule.ko instances=3
> dmesg | tail -n 1
[  458.203216] Linux module skeleton loaded. Instance count is 3

# Création des noeudsj
> mknod /dev/mymodule0 c 511 0
> mknod /dev/mymodule1 c 511 1
> mknod /dev/mymodule2 c 511 2

# Tests écriture/lecture
> echo "test0" > /dev/mymodule0
> echo "test1" > /dev/mymodule1
> echo "test2" > /dev/mymodule2
> cat /dev/mymodule0
test0
> cat /dev/mymodule1
test1
> cat /dev/mymodule2
test2
```

#line()

== Exercice 4

#rect([
Développer une petite application en espace utilisateur permettant d’accéder à ces pilotes orientés caractère. L’application devra écrire un texte dans le pilote et le relire.
])

Pour cet exercice, la première implémentation consistait à ouvrir chaque fichier, écrire dans ces fichiers et ensuite lire avant de refermer les fichiers. `open()` -> `write()` -> `read()` -> `close()`.

Cependant, ceci ne marche pas car lors du first `write()`, l'offset dans le fichier est déplacé et lors du `read()`, on va lire trop loin dans le buffer.

Pour résoudre ce problème, on peut fermer les fichiers entre le `write()` et `read()` ou bien replacer l'offset à 0, avec `lseek()`.

La première solution marche par défaut, la deuxième demande l'implémentaiton de la callback `llseek` au niveau du module afin de modifier `f_pos`.

```c
loff_t skeleton_llseek(struct file* f, loff_t offset, int whence)
{
    size_t instance_index = (size_t)(uintptr_t)f->private_data;
    loff_t new_offset     = 0;

    if (instance_index >= instances) {
        pr_err("invalid instance index. expected 0..%u", instances - 1);
        return -EINVAL;
    }

    switch (whence) {
        case SEEK_SET:
            new_offset = offset;
            break;
        case SEEK_CUR:
            new_offset = f->f_pos + offset;
            break;
        case SEEK_END:
            new_offset = BUFFER_SZ + offset;
            break;
        default:
            return -EINVAL;
    }

    if (new_offset < 0 || new_offset >= BUFFER_SZ) {
        return -EINVAL;
    }
    f->f_pos = new_offset;
    return new_offset;
}

static struct file_operations skeleton_fops = {
    ...
    .llseek  = skeleton_llseek,
};
```

#line()

== Exercice 5

#rect([
Développer un pilote de périphérique orienté caractère permettant de valider la fonctionnalité du sysfs. Le pilote offrira quelques attributs pouvant être lus et écrites avec les commandes echo et cat. Ces attributs seront disponibles sous l’arborescence /sys/class/....

Dans un premier temps, implémentez juste ce qu’il faut pour créer une nouvelle classe (par exemple : my_sysfs_class)
])

Aucun problème avec la solution proposée

== Exercice 5.1

#rect([

Ajoutez maintenant les opérations sur les fichiers définies à l’exercice #3. Vous pouvez définir une classe comme dans l’exercice précédent, ou vous pouvez utiliser un platform_device, ou encore un miscdevice.
])

Pour cet exercice, la solution contient un problème où le driver n'est pas déinitialisé correctement.
Ceci peut être vérifié en insérant le module, en l'enlevant et finalement en l'insérant à nouveau.

```sh
> insmod mymodule.ko 
> rmmod mymodule
> insmod mymodule.ko 
Segmentation fault
```

Le problème est l'appel à la fonction `device_destroy()`:

```c
    device_destroy(sysfs_class, 0);
```

Ceci essaye de détruire le device MAJOR:MINOR 0:0 ce qui ne correspond pas au device crée précedemment.

Pour corriger il suffit d'utilser le bon `dev_t`:

```c
    device_destroy(sysfs_class, skeleton_dev);
```

```sh
> insmod mymodule.ko 
> rmmod mymodule
> insmod mymodule.ko 
> rmmod mymodule
```

#line()

== Exercice 7

#rect([
Développer un pilote et une application utilisant les entrées/sorties bloquantes pour signaler une interruption matérielle provenant de l’un des switches de la carte d’extension du NanoPI. L’application utilisera le service select pour compter le nombre d’interruptions.
])

Le pilote d'exemple contient un bug, si un des IRQ n'est pas enregistré correctement `devm_request_irq` ne retourne pas `0`, le `misc_device` n'est pas effacé. A ce point, une entrée `sysfs` dans `/sys/class/misc/mymodule` persistera et l'enregistrement suivant va directement rater au moment du `misc_register`.

Pour le résoudre il suffit de vérifier si `status != 0` pour appeler `misc_deregister`:

```c
    ...
    if (status) {
        misc_deregister(&misc_device);
    }
    pr_info("Linux module skeleton loaded(status=%d)\n", status);
    return status;
```

De plus, le pilote donné en exemple ne permet pas de lire la valeur du bouton pressé, pour ajouter cette fonctionnalité, le code suivant a été ajouté:

1. Utilisation de `static const int` à la place de `#define`, permettant le passage d'un pointeur sur l'identifiant du bouton à l'irq:


```c
static const int K1 = 0;
static const int K2 = 2;
static const int K3 = 3;
```

On peut donc passer des pointeurs sur ces variables sur le paramètre `dev_id`. Exemple pour `K1`:

```c
    devm_request_irq(misc_device.this_device,
                         gpio_to_irq(K1),
                         gpio_isr,
                         IRQF_TRIGGER_FALLING | IRQF_SHARED,
                         k1,
                         (void*)&K1);
```

Ceci est nécéssaire car les IRQs sont du type `shared`, alor linux oblige que `dev_id` ne soit pas `NULL`. Comme `K1` vaut `0`, ceci est interprète comme NULL et le `irq` n'est pas enregistré (error -22). Si l'IRQ n'était pas `SHARED`, on aurait pu tout simplement passer la valeur dans le pointeur:

```c
    #define K1 0
    devm_request_irq(..., (void*)(uintptr_t)K1);
```

2. Stockage de l'identifiant du bouton lors de l'irq:

```c
static int last_key;

irqreturn_t gpio_isr(int irq, void* handle)
{
    int key = *(int*)handle;
    atomic_inc(&nb_of_interrupts);
    last_key = key;
    wake_up_interruptible(&queue);

    pr_info("interrupt %d raised...\n", key);

    return IRQ_HANDLED;
}
```

3. Ajout de la possibilité de lecture de `last_key` dans la callback `read`:

```c
static ssize_t skeleton_read(struct file* f, char __user* buf, size_t sz, loff_t* off) 
{
    char tmp[sizeof(int) + 1];
    int bytes;

    if (sz < sizeof(tmp)) {
        pr_err("sz is too small to hold buffer");
        return -EINVAL;
    }

    bytes = sprintf(tmp, "%d", last_key);
    if (copy_to_user(buf, tmp, bytes + 1)) {
        return -EFAULT;
    }
    return bytes + 1;
}
```


Avec ces ajouts dans le driver, l'application user space suivante peut alors utiliser `poll` pour attendre la pression d'un bouton et afficher par la suite le bouton pressé:

```c


#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/poll.h>
#include <unistd.h>

#define DEV_NAME "/dev/mymodule"

int main(void)
{
    int fd = open(DEV_NAME, O_RDWR);
    if (fd < 0) {
        fprintf(stderr, "failed to open %s (%s)", DEV_NAME, strerror(errno));
        return EXIT_FAILURE;
    }

    printf("Press any (physical) button\n");
    struct pollfd fds = {.fd = fd, .events = POLLIN};

    int ret = poll(&fds, 1, -1);
    if (ret < 1) {
        fprintf(stderr, "poll failed: %s\n", strerror(errno));
        close(fd);
        return EXIT_FAILURE;
    }
    char tmp[8];
    ret = read(fd, tmp, sizeof(tmp));
    if (ret <= 0) {
        fprintf(
            stderr, "Button pressed but couldn't read what it was %d\n", ret);
        close(fd);
        return EXIT_FAILURE;
    }
    printf("You pressed button %s!\n", tmp);
    close(fd);
    return EXIT_SUCCESS;
}
```

```sh
> ./app
Press any (physical) button
You pressed button 3!
> ./app
Press any (physical) button
You pressed button 3!
> ./app
Press any (physical) button
You pressed button 2!
> ./app
Press any (physical) button
You pressed button 2!
> ./app
Press any (physical) button
You pressed button 0!
```

Le manque d'anti-rebond est bien présent, car pas tous les lancements de l'application `app` bloquent pour attendre la pression d'un bouton.

