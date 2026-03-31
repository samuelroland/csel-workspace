= Environnement Linux embarqué

== Feedbacks sur le support de cours

1. _Un fichier task.json (dans le dossier .vscode de chaque “root”)_.

Le fichier semble plutôt être au pluriel `tasks.json`.

2. _Configurez maintenant l’adaptateur Ethernet de votre PC (ou un adaptateur Ethernet/USB) avec l’adresse IP fixe 192.168.53.4._

Sans l'expérience de SeS, Samuel n'aurait pas su comment faire. Peut-être qu'ajouter la commande d'exemple suivante peut aider d'autres gens qui débutent. Il faudrait aussi préciser que le nom de l'interface `enp0s20f0u1u3` peut changer et qu'il est récupérable dans `ip a | grep enp`.

```sh
sudo ip addr add 192.168.53.4/24 dev enp0s20f0u1u3 && sudo ip link set enp0s20f0u1u3 up
```

La solution entrepris par André utilise `nmcli` pour atteindre le même résultat:

```sh
nmcli connection modify <connection_name> ipv4.method manual ipv4.addresses 192.168.53.4/24 ipv4.gateway 192.168.53.1
```

Avec `"Wired connection 2"` qui peut être trouvé avec:

```sh
nmcli connection show
```

3. _Écrire aussi le Makefile suivant:_.

Il y a un petit problème avec le snippet suivant qui contient 2 espaces au lieu de tabs devant `  mkimage`, ce qui génère une erreur de syntaxe peu claire.

== Réponses aux questions

+ _Comment faut-il procéder pour générer l’U-Boot ?_

  On peut modifier u-boot avec `make uboot-menuconfig`.
  Une fois u-boot modifié, relancer `make`, permet de rebuilder les packages modifiés, dont u-boot.
  Ou bien, `make uboot-rebuild` permet de rebuilder `uboot` seulement.

+ _Comment peut-on ajouter et générer un package supplémentaire dans le Buildroot ?_

  On peut ajouter un nouveau package depuis le dossier `output` avec `make menuconfig`.
  Dans le menu on peut séléctionner le(s) nouveau(x) package(s) à ajouter.

+ _Comment doit-on procéder pour modifier la configuration du noyau Linux ?_

  La configuration du noyau linux se fait avec `make linux-menuconfig`.

+ _Comment faut-il faire pour générer son propre rootfs ?_

  On configure le système via `make menuconfig` (choix du filesystem overlay, des packages, init system, etc.),
  on peut ajouter un rootfs overlay (répertoire copié tel quel dans le rootfs final), on lance `make` pour générer l'image.
  Le `rootfs` généré se trouve dans `output/images/` (ex: rootfs.tar, rootfs.ext4, etc.)

+ _Comment faudrait-il procéder pour utiliser la carte eMMC en lieu et place de la carte SD ?_

  Tout d'abord il faut flasher le contenu sur l'eMMC, avant de booter dessus. Pour cela, 
  il faut y écrire l'image avec éventuellemnt le rootfs, le kernel et DTB:

  Ceci doit être fait depuis la cible, car nous n'avons pas d'accès à l'eMMC depuis l'extérieur.
  Pour cela on peut flasher la mémoire avec `dd`:

  ```bash
  dd if=image.ext4 of=/dev/mmcblk1 bs=1M
  ```

  Créer un nouveau boot script `boot.cmd` similaire à celui par défaut qui est fourni dans la définition de la board avec les bons paramètres:

  ```bash
  setenv bootargs console=ttyS0,115200 earlyprintk root=/dev/mmcblk1p2 rootwait
  fatload mmc 0 $kernel_addr_r Image
  fatload mmc 0 $fdt_addr_r nanopi-neo-plus2.dtb
  booti $kernel_addr_r - $fdt_addr_r
  ```

  La différence clé est l'utilisation de `root=/dev/mmcblk1p2` à la place de `root=/dev/mmcblk2p2`.

  Regénérer le `boot.scr`, U-Boot ne lit pas directement le boot.cmd mais sa version compilée :

  ```bash
  mkimage -C none -A arm -T script -d boot.cmd boot.scr
  ```

+ _Dans le support de cours, on trouve différentes configurations de l’environnement de développement. Quelle serait la configuration optimale pour le développement uniquement d’applications en espace utilisateur ?_

  La façon optimale est d'avoir un kernel chargé depuis la carte SD et le rootfs chargé depuis le réseau, cela permet de facilement tester des nouvelles configurations user-space rootfs sans prolonger le boot de façon inutile.

== Adaptations des instructions de laboratoire originales

#block(
  fill: luma(230),
  inset: 12pt,
  radius: 4pt,
  stroke: (left: 3pt + rgb("#f0a500")),
)[
  === Problème 1 - Incompatibilité de GCC 15 avec Buildroot 2022.08.3
  GCC 15 (la version par défaut sur Fedora 42) transforme certains avertissements en erreurs, ce qui empêche la compilation correcte de certains paquets de Buildroot 2022.08.3. Cette version de Buildroot ciblait GCC 12 comme version de référence moderne en 2022 (voir la #link("[https://www.gnu.org/software/gcc/releases.html](https://www.gnu.org/software/gcc/releases.html)")[chronologie de GCC]). Étant donné que GCC 12 n'est pas directement disponible via `dnf`, il doit être compilé à partir des sources.
  ```bash
    sudo mkdir -p /opt/gcc-12
    sudo chown -R $USER /opt/gcc-12
    wget https://ftp.gnu.org/gnu/gcc/gcc-12.3.0/gcc-12.3.0.tar.gz
    tar xvf gcc-12.3.0.tar.gz
    cd gcc-12.3.0
    ./contrib/download_prerequisites
    mkdir build && cd build
    ../configure --enable-languages=c,c++ --prefix=/opt/gcc-12
    make -j$(nproc)
    make install
  ```
  Buildroot est ensuite invoqué en spécifiant explicitement le compilateur hôte :
  ```bash
    HOSTCC=/opt/gcc-12/bin/gcc HOSTCXX=/opt/gcc-12/bin/g++ make
  ```
  === Problème 2 - Incompatibilité de `wget` v2 avec Buildroot 2022.08.3
  Buildroot 2022.08.3 appelle `wget` avec l'option `--passive-ftp`. Ce paramètre est supporté par wget v1 mais a été supprimé dans la version v2, installée par défaut sur Fedora 42. La solution choisie consiste à modifier le fichier `.config` pour retirer ce paramètre, puis à sauvegarder la configuration :
  ```bash
    sed -i 's/BR2_WGET="wget --passive-ftp/BR2_WGET="wget/' .config
    make savedefconfig
  ```

  === Problème 3 - menuconfig

  Encore lié à la compatibilité du compilateur, `make menuconfig` ne s'éxecute pas correctement:

  ```sh
   *** Unable to find the ncurses libraries or the
   *** required header files.
   *** 'make menuconfig' requires the ncurses libraries.
   *** 
   *** Install ncurses (ncurses-devel or libncurses-dev 
   *** depending on your distribution) and try again.
   *** 
  ```

  L'erreur semble indiquer qu'il manque des libraries mais ceci n'est pas le cas, en réalité le problème provient
  encore d'un warning promu à erreur avec GCC 14, les versions plus modernes de buildroot ayant résolu ce problème, le patch a été
  _cherry-picked_ #link("https://github.com/buildroot/buildroot/commit/a6210d28dbf66b2f0a42d945711dfd93c7329feb")[a6210d2]

  === Adapation 4 - Chemins dans les Makefile

  Les Makefile par défaut essaient de trouver la toolchain dans `/buildroot/output/host/usr/bin/`, ce chemin n'est évidemment pas 
  valable en dehors du container docker. La façon utilisé pour résoudre ceci a été de permettre de définir les variables `CC`, `LD`,
  etc... avec des variables d'environnement. On aurait aussi pu simplement le faire pour le chemin de la toolchain.

  Comme les chemins proposés s'adaptent correctement aux étudiants qui utilisent les containers Docker ainsi que les étudiants en natif,
  ceci a été upstream sur le repo officiel à travers une #link("https://github.com/mse-csel/csel-workspace/pull/8")[pull request].
  La pull request explique aussi la solution prise et comment cela marche.

  === Adaptation 5 - Remplacement de CIFS/SMB par SSHFS

  Le laboratoire propose de monter l'espace de travail de la machine hôte sur la cible via CIFS/SMB. Cette approche a été remplacée par SSHFS, qui s'intègre plus naturellement dans un environnement Linux moderne sans nécessiter de serveur SMB. La mise en place consiste à générer une clé SSH sur la cible, puis à la copier dans le fichier `~/.ssh/authorized_keys` de la machine hôte :
  ```bash
  ssh-keygen -t ed25519
  ssh-copy-id <user>@192.168.53.4
  ```
  L'espace de travail est ensuite monté avec :
  ```bash
  sshfs <user>@192.168.53.4:/chemin/vers/workspace /workspace
  ```
  #text(style: "italic")[
    *Note sur la sécurité :* Cette solution n'est pas idéale d'un point de vue sécuritaire, car la machine cible est un environnement non sécurisé (root sans mot de passe). Une approche plus robuste consisterait à utiliser un conteneur Docker avec uniquement l'espace de travail de l'hôte monté à l'intérieur, similaire à l'environnement fourni par le professeur. Cette amélioration n'a pas été implémentée dans le cadre de ce laboratoire.
  ]
]
