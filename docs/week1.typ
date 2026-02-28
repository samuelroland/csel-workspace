= Embedded Linux Environment

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
