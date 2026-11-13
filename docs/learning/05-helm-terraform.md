# 5. Helm et Terraform

## Objectif

Remplacer les fichiers YAML écrits à la main par :

- un **chart Helm** : un modèle de déploiement paramétrable ;
- **Terraform**, qui installe et suit ce chart comme de l'infrastructure décrite en code (IaC).

## Commandes

```bash
kubectl delete -f k8s/manual/        # Terraform reprend la gestion : on retire la version manuelle
helm lint charts/ministral
helm template ministral charts/ministral -n mistral     # voir le YAML généré, sans rien installer
cd terraform
terraform init                       # télécharge les providers (versions figées, fichier de lock commité)
terraform plan -out=tfplan           # ce qui VA être fait, enregistré dans un fichier
terraform apply tfplan               # applique exactement ce plan
```

## Ce qui s'est passé

```
Plan: 2 to add, 0 to change, 0 to destroy.
kubernetes_namespace_v1.mistral: Creation complete after 0s [id=mistral]
helm_release.ministral: Creation complete after 36s [id=ministral]
Apply complete! Resources: 2 added, 0 changed, 0 destroyed.
```

Terraform ne voit que **2 ressources** : le namespace et la release Helm. Le Deployment, le Service et le PVC sont
créés par Helm, à l'intérieur de la release. Les 36 s correspondent à l'attente du modèle prêt (`wait = true`).

## Le chart : `charts/ministral/`

```
Chart.yaml           nom, version du chart (0.1.0), version de l'application
values.yaml          les paramètres par défaut = le profil CPU
templates/
  _helpers.tpl       fonctions réutilisées : nom, labels, image (tag ou digest)
  deployment.yaml    le Deployment de l'étape 4, avec des {{ .Values.* }} à la place des valeurs en dur
  service.yaml
  pvc.yaml
  NOTES.txt          message affiché après l'installation
```

**Trois détails qui comptent :**

- **`checksum/values` (retirée ensuite) :** j'avais mis sur le pod une annotation contenant le hash de **toutes** les
  values, pour le redémarrer à chaque changement de config. Erreur de conception, découverte à l'étape 7 :
  - les arguments et variables sont **déjà** dans le template du pod, donc les changer le redémarre de toute façon ;
  - l'annotation redémarrait vLLM (~4 min) pour **n'importe quelle** valeur, même l'intervalle de collecte de
    Prometheus, qui ne concerne pas le pod.

  Le bon usage : un `checksum/config` calculé sur le **contenu d'une ConfigMap ou d'un Secret** monté dans le pod, car
  Kubernetes ne redémarre pas un pod quand ces objets changent.
- **`helm.sh/resource-policy: keep` sur le PVC :** `helm uninstall` laisse le disque et ses poids en place.
- **Labels standards `app.kubernetes.io/*` :** `name`, `instance`, `version` et `managed-by` sont reconnus par tous les
  outils.

## Terraform : `terraform/`

| Fichier | Contenu |
|---|---|
| `versions.tf` | version de Terraform et providers **figés** (`helm 3.3.0`, `kubernetes 3.4.0`) |
| `variables.tf` | `kube_context`, `namespace`, `profile` (`cpu` ou `gpu`, avec validation) |
| `main.tf` | providers branchés sur le contexte `kind-mistral`, namespace, `helm_release` |
| `outputs.tf` | ce qu'on affiche après l'apply (endpoint, profil) |

Le profil GPU ajoutera `values-gpu.yaml` par-dessus les valeurs par défaut, avec
`terraform apply -var profile=gpu`.

## Concepts

- **Helm.** Le gestionnaire de paquets de Kubernetes.
  - Un **chart** est un modèle ; une **release** est une installation de ce chart (nom + namespace).
  - Helm garde l'historique des releases et permet de revenir en arrière (`helm rollback`).
- **values.** Les paramètres d'un chart. On les surcharge par fichiers (`-f values-gpu.yaml`) ou par `--set`. Le
  dernier fichier gagne.
- **Terraform, l'IaC déclarative.** On décrit l'état voulu ; Terraform calcule l'écart et l'applique.
  - **Provider :** le plugin qui parle à une API (Kubernetes, Helm, AWS…).
  - **State :** le fichier où Terraform note ce qu'il gère. Il est **jamais commité**, parce qu'il contient souvent des
    secrets. En équipe, on le met dans un *backend* distant avec verrou (par exemple S3 + DynamoDB, ou GCS).
  - **Lock file (`.terraform.lock.hcl`) :** fixe les versions exactes et les hash des providers. Lui, **on le commite**.
- **`plan -out` puis `apply tfplan`.** On applique exactement ce qu'on a relu. Sans `-out`, `apply` recalcule le plan,
  qui a pu changer entre-temps. En CI : le plan est affiché dans la pull request, et l'apply a lieu après approbation.
- **Pourquoi Terraform par-dessus Helm ?**
  - Une seule commande pour toute la pile : chez un client, le cluster cloud, le réseau, l'IAM et les releases.
  - Un état suivi, et une détection des dérives : quelqu'un modifie à la main, le plan le montre.

## Pièges

- **Basculer de `kubectl apply` à Helm/Terraform sur les mêmes noms d'objets :** il faut supprimer la version manuelle
  d'abord, sinon il y a conflit de propriété.
- **Modifier un chart local sans incrémenter sa `version` :** `terraform plan` ne voit rien. Le provider compare la
  version du chart et les values, pas le contenu des templates. Réflexe : chaque changement de template ou de valeur
  par défaut fait monter `version` dans `Chart.yaml` (0.1.0 → 0.2.0), comme pour n'importe quel paquet.
- **Le provider helm v3 a changé de syntaxe :** `kubernetes = { ... }` est un attribut, plus un bloc.
- **`terraform.tfstate` et `tfplan` sont dans le `.gitignore`.** Le lock file, lui, est commité.

## Questions d'entretien

- **Où stocker le state Terraform en équipe ?**
  Dans un backend distant avec verrouillage (S3 + DynamoDB, GCS, Terraform Cloud), chiffré, avec un accès restreint.
  Jamais dans git.
- **Helm ou Kustomize ?**
  - **Helm :** des templates et des paramètres, un cycle de vie (install, upgrade, rollback), et la distribution de
    paquets.
  - **Kustomize :** des surcouches (patches) sur du YAML pur, sans templates. Les deux se combinent.
- **Qu'est-ce qu'une dérive (drift), et comment la voir ?**
  Un écart entre l'état réel et le code, par exemple un changement fait à la main. `terraform plan` la montre comme un
  changement à appliquer.
- **Comment redémarrer automatiquement les pods quand la config change ?**
  Si la config est dans le template du pod (args, env), c'est automatique. Si elle est dans une ConfigMap ou un Secret
  monté, on ajoute au template une annotation contenant le hash de **ce** contenu (`checksum/config`). Ne pas hasher
  toutes les values : chaque détail redémarrerait le pod.
