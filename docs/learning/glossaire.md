# Glossaire

| Terme | En une ligne |
|---|---|
| **API server** | La porte d'entrée unique du cluster : tout (kubectl, contrôleurs, kubelet) passe par lui. |
| **CDI** | Container Device Interface : un fichier standard qui décrit quoi injecter dans un conteneur pour un périphérique. |
| **Chart (Helm)** | Le paquet : des templates YAML et des valeurs par défaut. |
| **CNI** | Le plugin réseau qui donne une IP à chaque pod (kindnet dans kind). |
| **containerd** | Le runtime de conteneurs qu'utilise le kubelet ; Docker l'utilise aussi en dessous. |
| **Continuous batching** | vLLM ajoute ou retire des requêtes du lot à chaque pas de génération, au lieu d'attendre la fin du lot. |
| **Control plane** | API server, etcd, scheduler et controller-manager : le cerveau du cluster. |
| **CUDA graphs** | Des séquences d'opérations GPU enregistrées puis rejouées, pour aller plus vite ; elles allongent le démarrage. |
| **DaemonSet** | « Un pod par nœud » : pour les agents (device plugin, collecte de logs…). |
| **Deployment** | « Garde N pods comme ce modèle » : gère les mises à jour et les retours en arrière. |
| **Device plugin** | Il annonce au kubelet des ressources matérielles (`nvidia.com/gpu`) et les attribue aux pods. |
| **Digest** | L'empreinte sha256 d'une image : elle ne peut pas être déplacée, contrairement à un tag. |
| **etcd** | La base clé-valeur qui stocke l'état voulu du cluster. |
| **GPU Operator** | L'opérateur NVIDIA qui installe et gère pilote, toolkit, device plugin, NFD et métriques sur les nœuds GPU. |
| **FP8 / Q4_K_M** | Formats de poids sur 8 bits (GPU) ou ~4 bits (GGUF, CPU) : moins de mémoire, perte de qualité faible. |
| **GGUF** | Le format de fichier de modèle de llama.cpp : un seul fichier, quantifié. |
| **KV cache** | La mémoire des clés et valeurs d'attention des tokens déjà vus ; elle limite contexte × requêtes simultanées. |
| **kind** | Kubernetes in Docker : chaque nœud est un conteneur. |
| **MIG / time-slicing** | Partager un GPU : partitions matérielles isolées (A100/H100), ou alternance dans le temps, sans isolation mémoire. |
| **kubelet** | L'agent sur chaque nœud : il démarre les conteneurs des pods et fait tourner les probes. |
| **Label / selector** | Des étiquettes clé=valeur, et la façon de sélectionner des objets par elles (Service → pods). |
| **Namespace** | Un regroupement logique d'objets, pour lister, supprimer ou donner des droits. |
| **NodePort** | Un type de Service qui ouvre un port (30000–32767) sur chaque nœud. |
| **NFD** | Node Feature Discovery : détecte le matériel des nœuds et pose des labels (par exemple, carte NVIDIA présente). |
| **OOMKilled** | Le conteneur a dépassé sa `limits.memory` et a été tué. |
| **Pod** | La plus petite unité : un ou plusieurs conteneurs qui partagent le réseau et les volumes ; jetable. |
| **Prefill / TTFT** | La lecture du prompt, et le temps jusqu'au premier token (time to first token). |
| **Probe** | Un test de santé : startup (a fini de démarrer ?), readiness (peut recevoir du trafic ?), liveness (vivant ?). |
| **Provider (Terraform)** | Le plugin qui parle à une API (Kubernetes, Helm, AWS…). |
| **PVC / PV / StorageClass** | La demande de disque, le disque réel, et ce qui sait créer le disque. |
| **Ressource étendue** | Une ressource déclarée par un device plugin (`nvidia.com/gpu`) : entière, demandée dans les `limits`. |
| **Réconciliation** | La boucle qui compare l'état voulu à l'état réel et corrige l'écart. |
| **Release (Helm)** | Une installation d'un chart : un nom, un namespace et un historique de versions. |
| **ReplicaSet** | Il maintient N pods identiques ; un Deployment en crée un par version. |
| **requests / limits** | Ce que le scheduler réserve, et le plafond (au-delà de la mémoire : tué ; au-delà du CPU : ralenti). |
| **Runtime (nvidia)** | Il enveloppe runc pour injecter le GPU dans le conteneur. |
| **Scheduler** | Il choisit le nœud de chaque nouveau pod selon les ressources demandées et les contraintes. |
| **Service** | Une IP et un nom DNS stables devant des pods qui changent. |
| **State (Terraform)** | Le fichier de ce que Terraform gère ; jamais dans git, dans un backend distant verrouillé en équipe. |
| **vLLM** | Un serveur d'inférence GPU : PagedAttention, continuous batching, API compatible OpenAI. |
