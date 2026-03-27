= Pilotes de périphériques

Exercice *1*: Réaliser un pilote orienté mémoire permettant de mapper en espace utilisateur les registres du microprocesseur en utilisant le fichier virtuel /dev/mem. Ce pilote permettra de lire l’identification du microprocesseur (Chip-ID aux adresses 0x01c1'4200 à 0x01c1'420c) décrit dans l’exercice “Accès aux entrées/sorties” du cours sur la programmation de modules noyau.

Pas de problèmes avec ceci, la version proposé par l'étudiant défini la taille de page à 4KB à la place d'utiliser `getpagesize`, ce qui serait plus propre.

On n'utilise pas de `volatile` car c'est une valeur qui ne sera jamais modifiée.

Version étudiant disponible dans le workspace `src/03_drivers/exercice01/main.c`

