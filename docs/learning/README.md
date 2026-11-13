# Parcours d'apprentissage

Mon carnet de bord : apprendre Kubernetes de zéro en déployant un vrai modèle Mistral, étape par étape. Chaque fiche suit
le même plan :

1. **Objectif** : ce que l'étape doit prouver.
2. **Commandes** : ce que j'ai lancé.
3. **Ce qui s'est passé** : les vraies sorties, les vrais chiffres.
4. **Concepts** : ce qu'il faut comprendre.
5. **Pièges** : ce qui m'a bloqué ou aurait pu.
6. **Questions d'entretien** : avec une réponse courte, à savoir dire à l'oral.

| # | Fiche | Ce que j'apprends |
|---|---|---|
| 1 | [Docker et le GPU sous WSL2](01-docker-gpu-wsl.md) | conteneurs, NVIDIA Container Toolkit, `/dev/dxg` |
| 2 | [Servir un modèle avec vLLM](02-vllm-docker.md) | serveur d'inférence, VRAM, KV cache, API compatible OpenAI |
| 3 | [Mon premier cluster : kind](03-cluster-kind.md) | nœud, control plane, etcd, API server, scheduler |
| 4 | [Premier déploiement à la main](04-premier-deploiement.md) | Namespace, PVC, Deployment, Service, probes, réconciliation |
| 5 | [Helm et Terraform](05-helm-terraform.md) | chart, values, templates, state, `plan` / `apply` |
| 6 | [Le GPU dans Kubernetes](06-gpu-kubernetes.md) | runtime NVIDIA à deux niveaux, device plugin (mode WSL2), `nvidia.com/gpu`, charger une image de 33 Go |
| 7 | [Observabilité et load test](07-observabilite-load-test.md) | Prometheus, ServiceMonitor, CRD et opérateurs, PromQL, percentiles, TTFT/TPOT, dimensionner un GPU |
| 8 | [Intégration continue](08-ci.md) | GitHub Actions, validation statique et e2e sur kind, moindre privilège |
| 9 | [Stress test et réglage `--max-num-seqs`](09-stress-test-reglage.md) | saturation, loi de Little, préemptions, calcul d'un réglage, avant/après |
| – | [Glossaire](glossaire.md) | tous les termes, en une ligne chacun |

Pour réviser avant un entretien : lire les sections « Questions d'entretien » de chaque fiche, puis le glossaire.
