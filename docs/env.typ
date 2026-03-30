= Environnement Linux embarqué

== Feedbacks sur le support de cours
- `Un fichier task.json (dans le dossier .vscode de chaque “root”)`. Le fichier semble plutôt être au pluriel `tasks.json`.
- `Configurez maintenant l’adaptateur Ethernet de votre PC (ou un adaptateur Ethernet/USB) avec l’adresse IP fixe 192.168.53.4.` Sans l'expérience de SeS, Samuel n'aurait pas su comment faire. Peut-être qu'ajouter la commande d'exemple suivante peut aider d'autres gens qui débutent. Il faudrait aussi préciser que le nom de l'interface `enp0s20f0u1u3` peut changer et qu'il est récupérable dans `ip a | grep enp`.
  ```sh
  sudo ip addr add 192.168.53.4/24 dev enp0s20f0u1u3
  sudo ip link set enp0s20f0u1u3 up
  ```
- `Écrire aussi le Makefile suivant: `. Il y a un petit problème avec le snippet suivant qui contient 2 espaces au lieu de tabs, ce qui génère une erreur de syntaxe peu claire.
  ```sh
  boot.cifs: boot_cifs.cmd
    mkimage -T script -A arm -C none -d boot_cifs.cmd boot.cifs
  ```

== Questions

+ Comment faut-il procéder pour générer l’U-Boot ?

On peut modifier u-boot avec `make uboot-menuconfig`.
Une fois u-boot modifié, relancer `make`, permet de rebuilder les packages modifiés, dont u-boot.
Ou bien, `make uboot-rebuild` permet de rebuilder `uboot` seulement.

+ Comment peut-on ajouter et générer un package supplémentaire dans le Buildroot ?

On peut ajouter un nouveau package depuis le dossier `output` avec `make menuconfig`.
Dans le menu on peut séléctionner le(s) nouveau(x) package(s) à ajouter.

+ Comment doit-on procéder pour modifier la configuration du noyau Linux ?

La configuration du noyau linux se fait avec `make linux-menuconfig`.

+ Comment faut-il faire pour générer son propre rootfs ?

On configure le système via `make menuconfig` (choix du filesystem overlay, des packages, init system, etc.),
on peut ajouter un rootfs overlay (répertoire copié tel quel dans le rootfs final), on lance `make` pour générer l'image
Le `rootfs` généré se trouve dans `output/images/` (ex: rootfs.tar, rootfs.ext4, etc.)

+ Comment faudrait-il procéder pour utiliser la carte eMMC en lieu et place de la carte SD ?

Flasher le contenu sur l'eMMC, avant de booter dessus, il faut y écrire l'image avec éventuellemnt le rootfs, le kernel et DTB:

Ceci doit être fait depuis la cible, après avoir `mount` la flash dans `/dev/mmcblk1p2`

```bash
dd if=image.ext4 of=/dev/mmcblk1p2 bs=1M
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

+ Dans le support de cours, on trouve différentes configurations de l’environnement de développement. Quelle serait la configuration optimale pour le développement uniquement d’applications en espace utilisateur ?

La façon optimale est d'avoir un kernel chargé depuis la carte SD et le rootfs chargé depuis le réseau, cela permet de facilement tester des nouvelles configurations user-space rootfs sans prolonger le boot de façon inutile.

== Adaptations to the original laboratory instructions

#block(
  fill: luma(230),
  inset: 12pt,
  radius: 4pt,
  stroke: (left: 3pt + rgb("#f0a500")),
)[
  === Problem 1 — GCC 15 Incompatible with Buildroot 2022.08.3
  GCC 15 (the default version on Fedora 42) promotes certain warnings to errors,
  which prevents the correct compilation of some Buildroot 2022.08.3 packages,
  which targeted GCC 12 as its modern reference version in 2022 (see #link("https://www.gnu.org/software/gcc/releases.html")[GCC Timeline]). Since GCC 12 is not directly
  available via `dnf`, it must be compiled from source.
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
  Buildroot is then invoked by explicitly specifying the host compiler:
  ```bash
    HOSTCC=/opt/gcc-12/bin/gcc HOSTCXX=/opt/gcc-12/bin/g++ make
  ```
  === Problem 2 — `wget` v2 Incompatible with Buildroot 2022.08.3
  Buildroot 2022.08.3 invokes `wget` with the `--passive-ftp` flag, which is supported by wget v1
  but was removed in wget v2, shipped by default on Fedora 42. The chosen solution
  consists of modifying the `.config` file to remove this parameter, then saving
  the configuration:
  ```bash
    sed -i 's/BR2_WGET="wget --passive-ftp/BR2_WGET="wget/' .config
    make savedefconfig
  ```
  === Adaptation 3 — Replacing CIFS/SMB with SSHFS
  The laboratory proposes mounting the host machine's workspace on the target via
  CIFS/SMB. This approach was replaced by SSHFS, which integrates more naturally
  into a modern Linux environment without requiring an SMB server. The setup
  consists of generating an SSH key on the target, then copying it into the
  `~/.ssh/authorized_keys` file on the host machine:
  ```bash
  ssh-keygen -t ed25519
  ssh-copy-id <user>@192.168.53.4
  ```
  The workspace is then mounted with:
  ```bash
  sshfs <user>@192.168.53.4:/path/to/workspace /workspace
  ```
  #text(style: "italic")[
    *Security note:* This solution is not ideal from a security standpoint, as the
    target machine is an unsecured environment (root without a password). A more
    robust approach would be to use a Docker container with only the host machine's
    workspace mounted inside, similar to the environment provided by the professor.
    This improvement was not implemented as part of this laboratory.
  ]
]
