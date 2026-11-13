# 2. Servir un modèle avec vLLM (Docker seul)

## Objectif

Faire répondre un modèle Mistral sur le GPU **sans Kubernetes**, pour valider l'image, le modèle et la mémoire avant
d'ajouter une couche de complexité.

## Choix du modèle

J'ai vérifié chaque point sur Hugging Face, pas de mémoire.

| Modèle | Licence | Accès | Poids | Verdict |
|---|---|---|---|---|
| Ministral 3 **3B** Instruct 2512 | Apache 2.0 | libre | FP8, ~4,5 Go | retenu pour commencer |
| Ministral 3 8B Instruct 2512 | Apache 2.0 | libre | FP8 ; « tient dans 12 Go » selon la fiche | trop juste avec ~12 Go libres, à tenter plus tard |
| Mistral 7B Instruct v0.3 | Apache 2.0 | libre | BF16 seulement, ~14,5 Go | ne tient pas |

## Commandes

```bash
bash scripts/serve-docker.sh       # lance vllm/vllm-openai:v0.32.0 avec le 3B
curl -s localhost:8000/v1/chat/completions -H 'Content-Type: application/json' \
  -d '{"model":"mistralai/Ministral-3-3B-Instruct-2512","messages":[{"role":"user","content":"Explique Kubernetes en 2 phrases."}],"max_tokens":120}'
```

Chaque option de `scripts/serve-docker.sh` y est commentée. Les plus importantes :

| Option | Pourquoi |
|---|---|
| `--gpus all` | donner le GPU au conteneur |
| `--ipc=host` | PyTorch partage de la mémoire entre processus ; les 64 Mo par défaut de Docker ne suffisent pas |
| `-v ~/.cache/huggingface:...` | garder les poids sur l'hôte : un redémarrage ne les retélécharge pas |
| `--tokenizer-mode/--config-format/--load-format mistral` | charger les fichiers natifs de Mistral, comme le recommande la fiche du modèle |
| `--max-model-len 8192` | le contexte par défaut (262 000 tokens) réserverait bien plus de KV cache que le GPU n'en a |
| `--gpu-memory-utilization 0.6` | la part des 16 Go que vLLM peut prendre (Windows en occupe déjà ~4) |

## Ce qui s'est passé

Les chiffres viennent des logs de vLLM :

```
Model loading took 4.47 GiB memory and 50.55 seconds
Available KV cache memory: 4.01 GiB
GPU KV cache size: 40,384 tokens, Maximum concurrency for 8,192 tokens per request: 4.93x
init engine (profile, create kv cache, warmup model) took 147.22 s
```

**La réponse est correcte**, mais elle contient un artefact (`^{[V0-X]}`). La fiche du modèle recommande une
**température inférieure à 0,1** en production. Or vLLM applique 1,0 par défaut : le `generation_config.json` du modèle ne fixe pas de température, donc c'est la valeur par défaut de `SamplingParams` qui s'applique (vérifié dans l'image). Corrigé côté serveur par `--override-generation-config` dans le profil GPU (fiche 7) et par `--temp 0.1` côté llama.cpp (fiche 4).

## Concepts

- **Serveur d'inférence.** Programme qui garde le modèle en mémoire GPU et sert des requêtes. vLLM apporte :
  - le **continuous batching** : de nouvelles requêtes rejoignent le lot en cours à chaque pas de génération ;
  - le **PagedAttention** : le KV cache est découpé en pages, comme la mémoire virtuelle, ce qui limite le gaspillage.
- **KV cache.** Pour chaque token déjà traité, le modèle garde ses clés et valeurs d'attention, pour ne pas les
  recalculer. C'est lui qui limite **contexte × nombre de requêtes simultanées** : ici 40 384 tokens au total, soit
  ~5 requêtes à 8 192 tokens.
- **FP8.** Les poids sont stockés sur 8 bits au lieu de 16 (BF16), soit deux fois moins de mémoire avec une perte de
  qualité faible.
- **CUDA graphs.** vLLM enregistre à l'avance les séquences d'opérations GPU pour les rejouer plus vite. C'est une
  partie des 147 s de démarrage.
- **API compatible OpenAI.** `/v1/chat/completions` et `/v1/models` : un client existant fonctionne en changeant
  seulement l'URL.

## Pièges

- **Le premier lancement est long :** l'image fait une dizaine de Go, et `curl` renvoie une réponse vide tant que le
  serveur n'est pas prêt. Attendre `Application startup complete`, ou interroger `/health`.
- **Le démarrage dure ~3 à 4 min** (chargement + compilation + CUDA graphs). Dans Kubernetes, une liveness probe naïve
  tuerait le pod (voir fiche 4).

## Questions d'entretien

- **Qu'est-ce qui limite le nombre de requêtes simultanées sur un GPU ?**
  La mémoire du KV cache : la VRAM moins les poids, les activations et les CUDA graphs. On l'augmente en réduisant le
  contexte maximal, en quantifiant les poids ou le KV cache, ou en prenant un GPU plus gros.
- **Pourquoi fixer `--max-model-len` ?**
  vLLM vérifie qu'au moins une requête de longueur maximale tient dans le KV cache. Avec 262 000 tokens par défaut, ça
  échouerait ou gaspillerait de la mémoire.
- **Pourquoi la compatibilité OpenAI compte-t-elle pour un client ?**
  La migration se fait sans réécrire le code applicatif : on change l'URL de base et le nom du modèle.
