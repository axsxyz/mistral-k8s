# 4. Premier déploiement, à la main

## Objectif

Déployer le modèle dans le cluster avec quatre fichiers YAML écrits à la main (`k8s/manual/`), et comprendre chaque
objet. Profil CPU, pour isoler Kubernetes du GPU : llama.cpp et le GGUF Q4_K_M officiel de Mistral (2,15 Go).

## Commandes

```bash
kubectl apply -f k8s/manual/
kubectl -n mistral rollout status deploy/ministral --timeout=15m
kubectl -n mistral get pods,pvc,svc
kubectl -n mistral get events --sort-by=.lastTimestamp
curl -s localhost:8080/v1/chat/completions -H 'Content-Type: application/json' \
  -d '{"messages":[{"role":"user","content":"Explique Kubernetes en 2 phrases."}],"max_tokens":120}'
```

## Les 4 objets

| Fichier | Objet | Rôle |
|---|---|---|
| `00-namespace.yaml` | **Namespace** | regroupe le projet (lister ou supprimer d'un coup) |
| `10-pvc.yaml` | **PersistentVolumeClaim** | un disque qui survit au pod : le modèle n'est téléchargé qu'une fois |
| `20-deployment.yaml` | **Deployment** | « garde 1 pod comme ce modèle » |
| `30-service.yaml` | **Service** (NodePort) | une adresse stable vers le pod, publiée sur `localhost:8080` |

## Ce qui s'est passé : la chaîne d'événements

```
ScalingReplicaSet       Scaled up replica set ministral-6f66898587 from 0 to 1
WaitForFirstConsumer    waiting for first consumer to be created before binding
ProvisioningSucceeded   Successfully provisioned volume pvc-4db01d1c-...
Scheduled               Successfully assigned mistral/ministral-... to mistral-control-plane
Pulling / Pulled        image ghcr.io/ggml-org/llama.cpp:server@sha256:e3032e...   (18 s)
Started                 Container started
Unhealthy               Startup probe failed: ... connect: connection refused      <- normal
```

Le pod était prêt en **~50 s**, téléchargement des 2 Go compris.

Le `Startup probe failed` est **normal** : le serveur téléchargeait encore le modèle. La startup probe réessaie jusqu'à
ce que `/health` réponde 200. Avec seulement une liveness probe, Kubernetes aurait tué le pod à ce moment-là.

**La réponse, avec `--temp 0.1` :** propre, sans artefact.

**Vitesses mesurées (4 threads CPU, Q4) :**

| Phase | Vitesse | Durée |
|---|---|---|
| Lecture du prompt (prefill) | ~104 tokens/s | 5,2 s pour 543 tokens |
| Génération | **~19 tokens/s** | 5,4 s pour 104 tokens |

**La réconciliation en vrai :**

```bash
kubectl -n mistral delete pod -l app=ministral
# ministral-6f66898587-hg982   0/1   Running   0   4s   <- un nouveau pod, recréé tout seul
```

Le nouveau pod a démarré plus vite : le modèle était déjà sur le PVC.

## Découverte : le prompt système caché

Ma question fait ~10 tokens, mais le prompt en compte **543**. Avec vLLM (fiche 2), il y en avait 11.

```bash
curl -s localhost:8080/apply-template -H 'Content-Type: application/json' \
  -d '{"messages":[{"role":"user","content":"..."}]}'
# [SYSTEM_PROMPT]You are Ministral-3-3B-Instruct-2512, ... You power an AI assistant called Le Chat. ...
# The current date is {today}. ...[/SYSTEM_PROMPT][INST]...[/INST]
```

**Ce qui se passe :**

- Quand le client n'envoie pas de prompt système, le modèle de conversation du GGUF injecte celui de Mistral par défaut
  (~2 500 caractères).
- Le `{today}` n'y est même pas remplacé.
- vLLM, avec `--tokenizer-mode mistral`, n'injecte rien.

**Conséquence :** sur CPU, ~5 s avant le premier token, même pour une question courte.

**Ce que ça m'apprend :** c'est un compromis, pas un bug. Mistral recommande son prompt système pour la qualité. Chez un
client, il faut savoir ce que le serveur ajoute au prompt, parce que ça coûte en latence (TTFT) et en contexte.

## Concepts

- **Pod.** La plus petite unité : un ou plusieurs conteneurs qui partagent le réseau et les volumes. Les pods sont
  jetables : ils changent d'IP à chaque recréation.
- **Deployment → ReplicaSet → Pod.**
  - Le Deployment gère les versions (rollout, rollback).
  - Le ReplicaSet maintient le nombre de pods.
  - Le nom du pod (`ministral-6f66898587-8dmmw`) contient le hash du ReplicaSet.
- **Labels et selectors.** Le Service et le Deployment trouvent leurs pods par label (`app=ministral`), pas par nom.
- **Service.** Une IP et un nom DNS stables (`ministral.mistral.svc`) devant des pods qui changent.
  - **ClusterIP** (par défaut) : joignable seulement depuis l'intérieur du cluster.
  - **NodePort :** ouvre aussi un port sur chaque nœud.
  - **LoadBalancer :** demande une IP externe au cloud.
- **PVC, PV et StorageClass.**
  - Le PVC est une demande (« 5 Gi, en lecture-écriture par un seul nœud »).
  - Le PV est le volume réel.
  - La StorageClass sait les créer : dans kind, `standard` (local-path).
  - `WaitForFirstConsumer` : le volume est créé là où le pod est placé.
- **requests et limits.**
  - `requests` : ce que le scheduler **réserve** sur le nœud, et qui sert à placer le pod.
  - `limits.memory` : le plafond. Au-delà, le conteneur est tué (**OOMKilled**).
  - Pas de limite CPU, volontairement : une limite CPU **ralentit** le conteneur (throttling) au lieu de le tuer.
    `--threads 4` aligne llama.cpp sur la request.
- **Les trois probes :**

| Probe | Question | Si elle échoue |
|---|---|---|
| startup | « as-tu fini de démarrer ? » | réessaie ; trop d'échecs (ici 60 × 10 s) et le conteneur redémarre ; elle met les deux autres en pause |
| readiness | « peux-tu recevoir du trafic ? » | le pod est retiré du Service, sans redémarrage |
| liveness | « es-tu encore vivant ? » | le conteneur redémarre |

- **Stratégie `Recreate`.** On arrête l'ancien pod avant de lancer le nouveau. C'est obligatoire ici : le volume est
  ReadWriteOnce, et un GPU ne peut pas porter deux serveurs.

## Pièges

- **Ne pas confondre `port` et `targetPort` d'un Service.**
  - `port` : le port du Service.
  - `targetPort` : celui du conteneur (ici, par son nom, `http` → 8080).
  - `nodePort` : celui ouvert sur le nœud.
- **llama.cpp utilise par défaut tous les cœurs de la machine,** pas ceux réservés au pod. D'où `--threads`.
- **L'image llama.cpp n'a plus d'étiquette par build** depuis la v1.0.0 : on l'épingle par **digest**.

## Questions d'entretien

- **Un pod de modèle redémarre en boucle au démarrage, pourquoi ?**
  Le plus souvent, une liveness probe qui échoue pendant le chargement du modèle. Il faut une startup probe dimensionnée
  sur le temps de démarrage réel. Autres causes : un OOMKilled (limite mémoire trop basse, à voir dans
  `kubectl describe pod`) ou un téléchargement qui échoue.
- **Différence entre readiness et liveness ?**
  La readiness retire le pod du trafic sans le tuer, pour une surcharge ou un état temporaire. La liveness le
  redémarre, pour un blocage.
- **Comment éviter de retélécharger 10 Go de poids à chaque redémarrage ?**
  Un PVC pour le cache. En production : des poids pré-intégrés dans l'image, un cache local au nœud, ou un volume
  partagé.
- **Pourquoi la latence est-elle mauvaise alors que la question est courte ?**
  Regarder `prompt_tokens` : le modèle de conversation peut injecter un long prompt système. Puis comparer le
  prefill (TTFT) à la génération (tokens/s).
