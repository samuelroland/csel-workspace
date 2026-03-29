== Feedbacks sur la consigne
- `Un fichier task.json (dans le dossier .vscode de chaque “root”)`. Le fichier semble plutôt être au pluriel `tasks.json`.
- `Configurez maintenant l’adaptateur Ethernet de votre PC (ou un adaptateur Ethernet/USB) avec l’adresse IP fixe 192.168.53.4.` Sans l'expérience de SeS, Samuel n'aurait pas fait ça facilement, peut-être qu'ajouter la commande d'exemple suivante peut aider d'autres gens qui débutent. Il faudrait aussi préciser que le nom de l'interface `enp0s20f0u1u3` peut changer et qu'il est récupérable dans `ip a | grep enp`.
  ```sh
  sudo ip addr add 192.168.53.4/24 dev enp0s20f0u1u3
  sudo ip link set enp0s20f0u1u3 up
  ```
- `Écrire aussi le Makefile suivant: `. Il y a un petit problème avec le snippet suivant qui contient 2 espaces au lieu de tabs, ce qui génère une erreur de syntaxe peu claire.
  ```sh
  boot.cifs: boot_cifs.cmd
    mkimage -T script -A arm -C none -d boot_cifs.cmd boot.cifs
  ```
