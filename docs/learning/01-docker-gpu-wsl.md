# 1. Docker et le GPU sous WSL2

## Objectif

Prouver qu'un conteneur voit la RTX 5080. Sans ça, rien de ce qui suit ne marche.

## Commandes

```bash
sudo bash scripts/setup-wsl.sh
```

Le script :

1. ajoute les dépôts apt officiels de Docker et de NVIDIA ;
2. installe Docker Engine et le NVIDIA Container Toolkit ;
3. enregistre le runtime NVIDIA dans Docker (`nvidia-ctk runtime configure`) ;
4. m'ajoute au groupe `docker` ;
5. teste avec :

```bash
docker run --rm --gpus all nvidia/cuda:12.8.0-base-ubuntu24.04 nvidia-smi
```

## Ce qui s'est passé

**Premier essai avec Docker Desktop : échec.** Il n'arrivait pas à attacher son disque de données :

```
wsl.exe --mount --bare --vhd D:\DockerDesktop\...\docker_data.vhdx
Code d'erreur : Wsl/Service/AttachDisk/MountDisk/HCS/E_ACCESSDENIED
```

**Diagnostic :**

- Écarté : le fichier n'était ni compressé ni chiffré, ses ACL étaient normales, et l'accès contrôlé aux dossiers de
  Defender était désactivé.
- Restait : un Docker Desktop ancien (4.43) sur un Windows et un WSL plus récents, et un service privilégié arrêté.

Plutôt que de réparer Docker Desktop, j'ai installé **Docker Engine directement dans Ubuntu**. C'est l'installation
d'un vrai serveur Linux, et l'étape GPU de kind en a besoin (voir fiche 6).

**Après l'installation native, le GPU est visible depuis le conteneur :**

```
| NVIDIA-SMI 610.57.01     KMD Version: 610.88     CUDA UMD Version: 13.3 |
|   0  NVIDIA GeForce RTX 5080   ...   3946MiB / 16303MiB                 |
```

Windows occupe déjà ~4 Go de VRAM pour l'affichage. Il en reste ~12 Go pour les modèles.

## Concepts

- **Image et conteneur.** L'image est un modèle figé, en lecture seule. Le conteneur est une instance qui tourne à
  partir de cette image. `--rm` supprime le conteneur à la sortie.
- **Docker Engine et Docker Desktop.**
  - Docker Engine est le démon Linux (`dockerd`) avec containerd en dessous.
  - Docker Desktop est une application Windows/Mac qui fait tourner ce démon dans une VM, avec une interface en plus.
- **NVIDIA Container Toolkit.** C'est lui qui injecte le GPU dans un conteneur : les fichiers de périphérique et les
  bibliothèques du pilote. `--gpus all` passe par lui.
- **Le GPU sous WSL2.** WSL n'a pas de pilote NVIDIA Linux.
  - Le pilote Windows expose le GPU par **`/dev/dxg`** (DirectX) et les bibliothèques de `/usr/lib/wsl/lib`, dont
    `libcuda.so`.
  - Le toolkit sait gérer ce cas.
- **Groupe `docker`.** Il permet d'utiliser Docker sans sudo. Attention : en être membre revient à être root sur la
  machine.

## Pièges

- **`!` dans Claude Code et `!` dans bash, ce n'est pas la même chose.**
  - Dans le prompt de Claude Code, `! cmd` exécute la commande dans la session.
  - Dans bash, `! cmd` **inverse le code de retour** : la commande s'exécute, mais un succès devient un échec, ce qui
    casse les `&&`.
- **Ne pas lancer `wsl --shutdown`** quand on travaille depuis WSL : ça coupe aussi sa propre session.
- **Après `usermod -aG docker`,** le groupe n'est actif que dans un nouveau shell, ou après `newgrp docker`.

## Questions d'entretien

- **Comment un conteneur accède-t-il au GPU ?**
  Par le NVIDIA Container Toolkit. Au démarrage, il monte les périphériques du GPU et les bibliothèques du pilote de
  l'hôte dans le conteneur. L'image n'embarque que CUDA en espace utilisateur, jamais le pilote.
- **Pourquoi l'image CUDA ne contient-elle pas le pilote ?**
  Parce que le pilote est lié au noyau de l'hôte. C'est la version du pilote de l'hôte qui fixe la version de CUDA
  maximale utilisable dans le conteneur.
- **Qu'a de particulier WSL2 ?**
  Il n'y a pas de pilote Linux : le GPU passe par `/dev/dxg` et les bibliothèques fournies par Windows. Certains outils
  (comme le device plugin Kubernetes) ont un mode spécial pour ce cas.
