# 3. Mon premier cluster : kind

## Objectif

Avoir un vrai cluster Kubernetes sur ma machine, et comprendre ce qui tourne dedans.

## Commandes

```bash
bash scripts/install-tools.sh                   # kind, kubectl, helm, terraform dans ~/.local/bin
kind create cluster --config kind/cluster.yaml
kubectl get nodes -o wide
kubectl get pods -A
```

`install-tools.sh` installe des **versions figées**, et vérifie chaque téléchargement avec le **SHA-256 publié par le
projet**. C'est une protection contre un fichier corrompu ou altéré.

## Ce qui s'est passé

```
mistral-control-plane   NotReady   control-plane   4s    v1.37.0   ...   containerd://2.3.4
kube-system   etcd-mistral-control-plane                      1/1   Running
kube-system   kube-apiserver-mistral-control-plane            1/1   Running
kube-system   kube-controller-manager-mistral-control-plane   1/1   Running
kube-system   kube-scheduler-mistral-control-plane            1/1   Running
```

Le nœud est d'abord `NotReady`, puis `Ready` en ~20 s. Il attendait que le réseau du cluster (le CNI) soit en place.

## Concepts

- **kind (Kubernetes in Docker).** Chaque nœud du cluster est un conteneur Docker (`docker ps` montre
  `mistral-control-plane`). C'est parfait pour apprendre et pour la CI, pas pour la production.
- **Nœud.** Une machine (ici, un conteneur) qui fait tourner des pods. Elle y fait tourner le **kubelet**, l'agent qui
  démarre les conteneurs, et un runtime : **containerd**.
- **Le control plane, le « cerveau » du cluster :**
  - **kube-apiserver :** la seule porte d'entrée. `kubectl`, les contrôleurs et le kubelet lui parlent tous.
  - **etcd :** la base clé-valeur où est stocké l'état voulu de tout le cluster.
  - **kube-scheduler :** choisit sur quel nœud placer chaque nouveau pod, selon les ressources demandées.
  - **kube-controller-manager :** les boucles de **réconciliation**. Elles comparent l'état voulu à l'état réel et
    corrigent l'écart.
- **CNI (Container Network Interface).** Le plugin réseau qui donne une IP à chaque pod. kind installe kindnet.
- **Le modèle déclaratif.** On ne dit pas « lance ce conteneur », on dit « je veux 1 pod comme ceci ». Kubernetes
  converge en permanence vers cet état.
- **Contexte kubeconfig.** `~/.kube/config` peut décrire plusieurs clusters. kind crée le contexte `kind-mistral`, que
  Terraform utilise aussi.

## Le fichier `kind/cluster.yaml`

- **Image du nœud figée par digest** (`kindest/node:v1.37.0@sha256:...`) : le même cluster à chaque fois.
- **`extraPortMappings` :** le port 30080 du nœud est publié sur `127.0.0.1:8080`. Le Service NodePort de l'étape 4
  l'utilise.

## Pièges

- **Un nœud kind est un conteneur.** Certains réglages (montages, ports) ne se changent qu'en **recréant** le cluster.
  Ce n'est pas grave si tout ce qu'il contient est décrit en code (étape 5).
- **`kubectl` doit rester à une version mineure près de celle du cluster :** ici kubectl 1.37.1 pour un cluster 1.37.0.

## Questions d'entretien

- **Que se passe-t-il quand je fais `kubectl apply` ?**
  kubectl envoie l'objet à l'API server, qui le valide et l'enregistre dans etcd. Les contrôleurs voient le changement
  et créent les objets dérivés (un Deployment crée un ReplicaSet, qui crée les pods). Le scheduler assigne chaque pod à
  un nœud, puis le kubelet de ce nœud démarre les conteneurs.
- **Si etcd est perdu ?**
  L'état du cluster est perdu. C'est pourquoi on le sauvegarde, et qu'on le fait tourner à 3 ou 5 instances en
  production.
- **kind, minikube, k3s ?**
  - **kind :** des nœuds dans Docker. Rapide, multi-nœuds, idéal en CI.
  - **minikube :** une VM ou Docker, avec beaucoup d'addons.
  - **k3s :** une distribution légère, utilisable en vrai sur de petits serveurs ou en edge.
