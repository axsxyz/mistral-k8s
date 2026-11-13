# 6. Le GPU dans Kubernetes *(en cours)*

## Objectif

Qu'un pod Kubernetes demande `nvidia.com/gpu: 1` et serve Ministral avec vLLM sur la RTX 5080, sous WSL2.

## Le chemin du GPU

```
RTX 5080 → pilote Windows → /dev/dxg dans WSL
  → runtime NVIDIA de Docker → conteneur du nœud kind        (E1)
  → runtime NVIDIA de containerd dans le nœud                 (E2)
  → device plugin : le nœud annonce nvidia.com/gpu: 1         (E3)
  → pod vLLM qui demande nvidia.com/gpu: 1                    (E4)
```

Chaque maillon peut casser : on les valide un par un.

## Recherche préalable

- **Le device plugin NVIDIA gère WSL2 depuis la v0.19.1** (changelog : *« wsl: report a single "all" device to
  kubelet »*).
  - Sous WSL, il n'y a pas de GPU listable un par un : le plugin annonce un seul périphérique « all », qui correspond à
    `/dev/dxg`.
  - On utilisera la v0.20.1.
- **Pour donner le GPU à un nœud kind,** on suit la méthode de **nvkind**, l'outil officiel de NVIDIA pour kind avec
  GPU.

## E1 : l'hôte ✅

```bash
sudo bash scripts/setup-gpu-host.sh
```

Le script :

1. fait de `nvidia` le **runtime par défaut** de Docker (`--set-as-default`), avec CDI activé. kind ne sait pas passer
   `--gpus` à ses nœuds, donc tous les conteneurs passent par le runtime NVIDIA ;
2. active `accept-nvidia-visible-devices-as-volume-mounts`. Avec cette option, un conteneur qui monte `/dev/null` sur
   `/var/run/nvidia-container-devices/all` reçoit tous les GPU. kind peut déclarer ce montage sur un nœud
   (`extraMounts`).

Vérification, sans `--gpus` :

```bash
docker run --rm -v /dev/null:/var/run/nvidia-container-devices/all ubuntu:24.04 nvidia-smi -L
# GPU 0: NVIDIA GeForce RTX 5080 (UUID: ...)
```

## E2 à E4

À venir.

## Concepts (pour l'instant)

- **Runtime de conteneur.** Le programme bas niveau qui crée vraiment le conteneur (`runc`). Le « runtime nvidia »
  enveloppe runc pour injecter le GPU au passage.
- **CDI (Container Device Interface).** Un format standard qui décrit, dans un fichier, ce qu'il faut injecter pour un
  périphérique (fichiers de périphérique, bibliothèques, variables). C'est l'approche qui remplace les hooks
  spécifiques à NVIDIA.
- **Device plugin.** Un DaemonSet qui annonce au kubelet des ressources « étendues » (`nvidia.com/gpu`) et dit quoi
  monter dans le conteneur qui les reçoit. Le scheduler ne place un pod GPU que sur un nœud qui en annonce.
