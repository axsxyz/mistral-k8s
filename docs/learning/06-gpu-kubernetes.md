# 6. Le GPU dans Kubernetes

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

Chaque maillon peut casser. On les a validés un par un, chacun avec sa propre preuve.

## Recherche préalable

- **Le device plugin NVIDIA gère WSL2 depuis la v0.19.1.** Changelog : *« wsl: report a single "all" device to
  kubelet »*.
  - Sous WSL, il n'y a pas de GPU listable un par un : le plugin annonce un seul périphérique « all », qui correspond à
    `/dev/dxg`.
  - On utilise la v0.20.1.
- **La méthode pour donner le GPU à un nœud kind** vient de **nvkind**, l'outil officiel de NVIDIA.

## E1 : l'hôte

```bash
sudo bash scripts/setup-gpu-host.sh
```

1. `nvidia` devient le **runtime par défaut** de Docker (`--set-as-default`, CDI activé). kind ne sait pas passer
   `--gpus` à ses nœuds.
2. L'option `accept-nvidia-visible-devices-as-volume-mounts` est activée. Un conteneur qui monte `/dev/null` sur
   `/var/run/nvidia-container-devices/all` reçoit alors tous les GPU.

```bash
docker run --rm -v /dev/null:/var/run/nvidia-container-devices/all ubuntu:24.04 nvidia-smi -L
# GPU 0: NVIDIA GeForce RTX 5080 (UUID: ...)
```

## E2 : le nœud kind

`kind/cluster-gpu.yaml` est le même cluster, plus ce montage déclencheur (`extraMounts`). Un montage ne s'ajoute pas à
un nœud existant, donc on **recrée** le cluster :

```bash
kind delete cluster --name mistral
kind create cluster --config kind/cluster-gpu.yaml
bash scripts/setup-kind-gpu-node.sh
```

Le script passe par `docker exec` dans le nœud, sans sudo. Il installe le NVIDIA Container Toolkit, fait de `nvidia` le
runtime par défaut de **containerd** (qui joue dans le nœud le rôle de Docker sur l'hôte), puis vérifie :

```
crw-rw-rw- 1 root root 10, 125 ... /dev/dxg          <- le GPU est arrivé dans le nœud
Wrote updated config to /etc/containerd/conf.d/99-nvidia.toml
GPU 0: NVIDIA GeForce RTX 5080 (UUID: ...)            <- nvidia-smi depuis l'intérieur du nœud
```

## Charger une image de 33 Go dans le nœud

Le nœud kind a son propre containerd. Il ne voit pas les images de Docker.

**`kind load docker-image` a échoué :**

```
ctr: content digest sha256:6ff5ff0d...: not found
```

**Cause :**

- Docker 29 stocke ses images dans containerd, qui ne garde que les couches de **ta** plateforme (linux/amd64) d'une
  image multi-plateformes.
- kind importe avec `--all-platforms`, donc il réclame les couches arm64 et des autres plateformes, que Docker n'a
  jamais téléchargées.

**Solution :** `scripts/load-image-into-kind.sh` exporte une seule plateforme et l'importe directement dans le
containerd du nœud. Résultat : **3 min 36 s**, et `crictl` affiche 9,21 Go. C'est la taille compressée des couches, là
où Docker affiche la taille décompressée sur disque (33 Go).

```bash
docker save --platform linux/amd64 vllm/vllm-openai:v0.32.0 \
  | docker exec -i mistral-control-plane ctr --namespace=k8s.io images import --digests --snapshotter=overlayfs -
```

## E3 et E4 : Terraform avec `profile=gpu`

```bash
cd terraform
terraform plan -var profile=gpu -out=tfplan     # Plan: 4 to add
terraform apply tfplan
```

Ce que le profil GPU ajoute :

| Ressource | Rôle |
|---|---|
| `kubernetes_labels.gpu_node` | pose `nvidia.com/gpu.present=true` sur le nœud ; sans ce label, le DaemonSet du plugin ne se lance pas (en prod, c'est Node Feature Discovery qui le pose) |
| `helm_release.nvidia_device_plugin` | le device plugin v0.20.1 |
| `helm_release.ministral` avec `values-gpu.yaml` | vLLM, `nvidia.com/gpu: 1`, `/dev/shm` en mémoire, volume `model-cache-vllm` de 15 Gi |

`depends_on` garantit l'ordre : label, puis plugin, puis modèle. Sans ça, le pod resterait `Pending` (aucun nœud
n'annoncerait de GPU).

**La dérive détectée :** l'ancien cluster a été supprimé sans passer par Terraform. Le plan l'a signalé :

```
Note: Objects have changed outside of Terraform
  # kubernetes_namespace_v1.mistral has been deleted
```

Terraform a donc tout recréé.

**Résultats :**

```
Allocatable:
  nvidia.com/gpu:     1                                  <- E3 : le GPU est annoncé au cluster
mistral   ministral-76d5ff98bf-wrpwk   1/1   Running        <- E4 : le pod GPU est planifié et prêt
Model loading took 4.47 GiB memory and 47.59 seconds
GPU KV cache size: 40,384 tokens, Maximum concurrency for 8,192 tokens per request: 4.93x
init engine (profile, create kv cache, warmup model) took 150.06 s
```

Ce sont les mêmes chiffres qu'en Docker seul (fiche 2) : **Kubernetes n'ajoute pas de surcoût sur le GPU**. L'apply
complet a pris ~4 min.

**Même question, comparaison CPU et GPU (une requête, `temperature 0.1`) :**

| | CPU : llama.cpp Q4, 4 threads | GPU : vLLM FP8, RTX 5080 |
|---|---|---|
| Tokens du prompt | 543 (prompt système injecté) | 11 |
| Tokens générés | 104 | 113 |
| Temps total | ~10,7 s | **0,89 s** |
| Débit | ~19 tokens/s en génération | **~127 tokens/s** de bout en bout |

## Concepts

- **Runtime de conteneur.** Le programme bas niveau qui crée le conteneur (`runc`). Le runtime `nvidia` enveloppe runc
  pour injecter le GPU. Il y en a ici à **deux niveaux** : Docker sur l'hôte (pour le nœud) et containerd dans le nœud
  (pour les pods).
- **CDI (Container Device Interface).** Un format standard qui décrit dans un fichier quoi injecter pour un
  périphérique (fichiers de périphérique, bibliothèques, variables). Il remplace les hooks spécifiques à chaque
  fabricant.
- **Device plugin.**
  - C'est un **DaemonSet**, donc un pod par nœud.
  - Il annonce au kubelet une **ressource étendue** (`nvidia.com/gpu`) et dit quoi injecter dans le conteneur qui la
    reçoit.
  - Le scheduler ne place un pod qui demande `nvidia.com/gpu: 1` que sur un nœud qui en a de libre.
- **Une ressource étendue n'est pas divisible.** On demande des GPU entiers, uniquement dans les `limits`. Pour
  partager un GPU entre pods, il existe le time-slicing, MIG (sur A100/H100) et MPS.
- **`nodeAffinity` du plugin.** Le chart ne se lance que sur les nœuds étiquetés comme ayant un GPU NVIDIA. Dans un
  vrai cluster, NFD (Node Feature Discovery) détecte la carte PCI et pose le label tout seul.
- **NVIDIA GPU Operator.** En production, il installe et gère l'ensemble à la place de ces étapes manuelles : pilote,
  toolkit, device plugin, NFD, métriques DCGM. Il ne gère pas WSL2.

## Pièges

- **Recréer un cluster kind** pour lui ajouter un montage. Ce n'est pas grave si tout est en code : Terraform a tout
  reconstruit d'un `apply`.
- **`kind load docker-image` avec le magasin d'images containerd de Docker** : `content digest not found`. Il faut
  exporter une seule plateforme.
- **Une image chargée à la main ne garde pas son digest de registre.** Le pod la référence par tag, avec
  `imagePullPolicy: IfNotPresent`, sinon il essaierait de retélécharger 33 Go.
- **Sous WSL, `nvidia-smi` est dans `/usr/lib/wsl/lib`,** qui n'est pas dans le PATH du nœud.
- **Le message `debconf: unable to initialize frontend`** est du bruit d'apt sans terminal. On le supprime avec
  `DEBIAN_FRONTEND=noninteractive`.

## Questions d'entretien

- **Un pod qui demande un GPU reste `Pending`. Que vérifies-tu ?**
  1. `kubectl describe pod` : un événement `Insufficient nvidia.com/gpu` ?
  2. `kubectl describe node` : `nvidia.com/gpu` est-il dans `Allocatable` ?
  3. Le DaemonSet du device plugin tourne-t-il sur ce nœud (labels, affinity, taints) ?
  4. Ses logs.
  5. Le runtime nvidia dans containerd.
  6. Un autre pod tient-il déjà le GPU ?
- **Comment partager un GPU entre plusieurs modèles ?**
  - Time-slicing (configuration du device plugin) : simple, mais sans isolation mémoire.
  - MIG sur A100/H100 : des partitions matérielles isolées.
  - Ou un seul serveur multi-modèles / LoRA.
- **Pourquoi `Recreate` plutôt que `RollingUpdate` pour un pod GPU ?**
  Un rolling update lance le nouveau pod avant d'arrêter l'ancien. Avec un seul GPU, le nouveau reste `Pending`, et le
  rollout bloque.
- **Comment réduire le démarrage à froid d'un nœud GPU ?**
  - Pré-télécharger l'image d'inférence sur les nœuds, ou utiliser le lazy pulling (stargz, SOCI).
  - Mettre les poids en cache local ou dans un volume pré-rempli.
  - Mesurer chaque phase : téléchargement, chargement des poids, compilation, CUDA graphs. Ici : ~48 s de chargement
    et 150 s d'init moteur.
