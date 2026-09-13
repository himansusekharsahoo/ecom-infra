# Run ecom with Helm and Argo CD

This runbook deploys the `ecom` Next.js app from the sibling `ecom` repository using the Helm chart in this repo, first with Helm directly, then with Argo CD.

## How the two repos fit together

| Repo | Role |
| --- | --- |
| `ecom` | Application: Next.js (`ecom-frontend`), Dockerfile, Prisma, Redis client, CI image build |
| `ecom-infra` | How it runs: Helm chart, environment values, Argo CD Applications |

The app listens on **port 3000** and needs two environment variables:

- `DATABASE_URL` — PostgreSQL, used by Prisma
- `REDIS_URL` — Redis, used by `src/lib/redis.ts`

`ecom/docker-compose.yml` already wires those as:

```text
postgresql://postgres:postgres@postgres:5432/ecom
redis://redis:6379
```

The Helm chart does the same in-cluster for **dev** and **staging**. **prod** expects you to create a Secret with real URLs and does not start Postgres or Redis.

Raw manifests in `ecom/k8s` and `ecom/deployment` were the previous deploy path. Prefer this chart going forward. You can leave those files in `ecom` for reference, but Argo CD should point at `ecom-infra`, not at `ecom/k8s`.

## Prerequisites

Install these on your machine:

- Docker
- [k3d](https://k3d.io/) (or kind / minikube)
- kubectl
- Helm 3 or 4
- A GitHub repo for `ecom-infra` (Argo CD reads Git, not your local disk)

Optional but used in the Argo section:

- [Argo CD CLI](https://argo-cd.readthedocs.io/en/stable/cli_installation/)

Confirm tools:

```powershell
docker version
kubectl version --client
helm version
k3d version
```

## 1. Create a local cluster

k3d is what `ecom/devUtils/redeploy.ps1` already uses (`ecom-cluster`). Create a cluster with an ingress port:

```powershell
k3d cluster create ecom-cluster `
  --agents 1 `
  -p "80:80@loadbalancer" `
  -p "443:443@loadbalancer"
```

Install ingress-nginx if the cluster does not already have an ingress controller (k3d does not ship nginx; Traefik is the k3d default). This chart defaults to **ingressClassName: nginx**, matching `ecom/deployment/ingress.yaml`.

```powershell
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx `
  --namespace ingress-nginx --create-namespace `
  --set controller.ingressClassResource.default=true
```

If you prefer the k3d Traefik controller instead, override the class when you install:

```powershell
--set ingress.className=traefik
```

Point DNS for the local host at the cluster load balancer (usually `127.0.0.1` with k3d):

```text
127.0.0.1  dev.ecommerce.local
127.0.0.1  staging.ecommerce.local
127.0.0.1  prod.ecommerce.local
```

On Windows, edit `C:\Windows\System32\drivers\etc\hosts` as Administrator.

## 2. Build the app image from ecom

From the `ecom` repo (same image name as `docker-compose.yml` and `devUtils/redeploy.ps1`):

```powershell
cd e:\Development\Practice\GitHub\ecom
docker build -t ecom-frontend-app:latest .
k3d image import ecom-frontend-app:latest -c ecom-cluster
```

Dev values use `ecom-frontend-app:latest` with `imagePullPolicy: IfNotPresent`, so the imported local image is enough. Staging and prod pull `ghcr.io/himansusekharsahoo/ecom` — that must exist in GHCR (see `ecom/.github/workflows/docker-build.yml`) or you must change `image.repository` in those value files.

## 3. Deploy with Helm (no Argo)

From `ecom-infra`:

```powershell
cd e:\Development\Practice\GitHub\ecom-infra

helm lint ./helm/ecom-frontend -f ./helm/ecom-frontend/values-dev.yaml

helm template ecom-frontend ./helm/ecom-frontend `
  -f ./helm/ecom-frontend/values-dev.yaml `
  --namespace ecommerce-dev

helm upgrade --install ecom-frontend ./helm/ecom-frontend `
  -f ./helm/ecom-frontend/values-dev.yaml `
  -n ecommerce-dev --create-namespace
```

What this creates in `ecommerce-dev`:

| Resource | Name | Purpose |
| --- | --- | --- |
| Deployment + Service | `ecom-frontend` | Next.js, port 80 → 3000 |
| Ingress | `ecom-frontend` | `dev.ecommerce.local` / |
| Deployment + Service + PVC | `ecom-frontend-postgres` | Postgres 16, database `ecom` |
| Deployment + Service | `ecom-frontend-redis` | Redis 7 |
| ConfigMap | `ecom-frontend-app` | `NODE_ENV`, `PORT` |
| Secret | `ecom-frontend-app` | `DATABASE_URL`, `REDIS_URL` |

Wait for the rollout:

```powershell
kubectl rollout status deployment/ecom-frontend -n ecommerce-dev
kubectl get pods,svc,ingress -n ecommerce-dev
```

Open [http://dev.ecommerce.local](http://dev.ecommerce.local). You should see the ecom home page (`Main Page loaded..`).

### Other environments with Helm

```powershell
helm upgrade --install ecom-frontend ./helm/ecom-frontend `
  -f ./helm/ecom-frontend/values-staging.yaml `
  -n ecommerce-staging --create-namespace

# Prod needs the Secret first — see section 6
helm upgrade --install ecom-frontend ./helm/ecom-frontend `
  -f ./helm/ecom-frontend/values-prod.yaml `
  -n ecommerce-prod --create-namespace
```

### Useful Helm commands

```powershell
helm list -n ecommerce-dev
helm get values ecom-frontend -n ecommerce-dev
helm history ecom-frontend -n ecommerce-dev
helm rollback ecom-frontend 1 -n ecommerce-dev
helm uninstall ecom-frontend -n ecommerce-dev
```

## 4. Install Argo CD

```powershell
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl rollout status deployment/argocd-server -n argocd
```

Port-forward the UI:

```powershell
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

Get the initial admin password:

```powershell
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | ForEach-Object { [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($_)) }
```
password: lse-YcDgheipJaTi

Log in at [https://localhost:8080](https://localhost:8080) with user `admin` and that password: lse-YcDgheipJaTi

CLI login (skip TLS for local):

```powershell
argocd login localhost:8080 --username admin --insecure
```

## 5. Push ecom-infra and register the apps

Argo CD syncs from Git. This folder is not a Git repository yet. Create one and push it (adjust the remote if your GitHub path differs):

```powershell
cd e:\Development\Practice\GitHub\ecom-infra
git init
git add .
git commit -m "Add Helm chart and Argo CD apps for ecom."
gh repo create himansusekharsahoo/ecom-infra --private --source . --remote origin --push
```

If the GitHub URL is not `https://github.com/himansusekharsahoo/ecom-infra.git`, edit `spec.source.repoURL` in every file under `argocd/applications/`.

If Argo CD runs inside the cluster and the repo is **private**, add a repository credential:

```powershell
argocd repo add https://github.com/himansusekharsahoo/ecom-infra.git `
  --username YOUR_GITHUB_USER `
  --password YOUR_GITHUB_PAT
```

Apply the Application CRs:

```powershell
kubectl apply -f argocd/applications/ecom-dev.yaml
```

Add staging or prod the same way when you want those namespaces:

```powershell
kubectl apply -f argocd/applications/ecom-staging.yaml
kubectl apply -f argocd/applications/ecom-prod.yaml
```

Each Application:

- Reads `helm/ecom-frontend`
- Applies `values.yaml` plus the environment overlay
- Creates its namespace (`ecommerce-dev`, `ecommerce-staging`, `ecommerce-prod`)
- Auto-syncs, prunes deleted resources, and self-heals drift

Watch sync:

```powershell
argocd app get ecom-frontend-dev
argocd app sync ecom-frontend-dev
kubectl get applications -n argocd
```

Or use the Argo CD UI: **ecom-frontend-dev** → Sync / Refresh.

If you already installed the same release with Helm in `ecommerce-dev`, either uninstall the Helm release first or let Argo CD adopt it. Do not run both controllers against the same resources.

```powershell
helm uninstall ecom-frontend -n ecommerce-dev
kubectl apply -f argocd/applications/ecom-dev.yaml
```

## 6. Production Secret (required before prod sync)

`values-prod.yaml` sets `postgres.enabled: false`, `redis.enabled: false`, and `secret.create: false`. Create the Secret Argo CD will mount:

```powershell
kubectl create namespace ecommerce-prod

kubectl create secret generic ecom-frontend-app `
  --namespace ecommerce-prod `
  --from-literal=DATABASE_URL='postgresql://USER:PASSWORD@HOST:5432/ecom' `
  --from-literal=REDIS_URL='redis://HOST:6379'
```

Then apply `argocd/applications/ecom-prod.yaml`.

Do not commit production URLs or passwords into this repo.

## 7. Day-2 operations

**Ship a new app image (local / k3d)**

```powershell
cd e:\Development\Practice\GitHub\ecom
docker build -t ecom-frontend-app:latest .
k3d image import ecom-frontend-app:latest -c ecom-cluster
kubectl rollout restart deployment/ecom-frontend -n ecommerce-dev
```

**Ship a new app image (GitOps)**

1. Build and push from `ecom` CI (`ghcr.io/himansusekharsahoo/ecom`).
2. Change `image.tag` in the environment values file (prefer a git SHA, not `latest`).
3. Commit and push `ecom-infra`. Argo CD syncs the new tag.

**Change replicas, hosts, or resources**

Edit `values-dev.yaml` / `values-staging.yaml` / `values-prod.yaml`, push, and let Argo CD sync. Or pass `--set` for a one-off Helm install.

**Rollback**

```powershell
# Helm
helm rollback ecom-frontend -n ecommerce-dev

# Argo CD
argocd app rollback ecom-frontend-dev
```

## Environment map

| | Dev | Staging | Prod |
| --- | --- | --- | --- |
| Namespace | `ecommerce-dev` | `ecommerce-staging` | `ecommerce-prod` |
| Image | `ecom-frontend-app:latest` | `ghcr.io/himansusekharsahoo/ecom:latest` | `ghcr.io/himansusekharsahoo/ecom:latest` |
| Replicas | 2 | 2 | 3 (HPA 3–10) |
| Host | `dev.ecommerce.local` | `staging.ecommerce.local` | `prod.ecommerce.local` |
| Postgres / Redis | In-cluster | In-cluster | External (Secret) |
| Ingress class | nginx | nginx | nginx |

## Chart values that matter

| Value | What it does |
| --- | --- |
| `image.repository` / `image.tag` | Frontend image from `ecom` |
| `ingress.hosts` | Public hostname |
| `ingress.className` | `nginx` or `traefik` |
| `postgres.enabled` | Start in-cluster Postgres 16 |
| `redis.enabled` | Start in-cluster Redis 7 |
| `database.url` / `cache.url` | Override URLs when in-cluster deps are off |
| `secret.create` / `secret.existingSecret` | Chart-managed Secret vs one you create |
| `autoscaling.enabled` | HPA instead of fixed `replicaCount` |

## Troubleshooting

**ImagePullBackOff on dev**  
The cluster cannot see `ecom-frontend-app:latest`. Rebuild and `k3d image import`, or set `image.repository` to a registry the cluster can pull.

**Pods crash with missing `DATABASE_URL` / `REDIS_URL`**  
On prod, the existing Secret is missing or misnamed. It must be `ecom-frontend-app` (or whatever you set in `secret.existingSecret`) and contain both keys.

**Ingress 404 or host not found**  
Confirm the hosts file entry, that the ingress controller is Ready, and that `ingress.className` matches the controller (`nginx` vs `traefik`).

**Argo CD OutOfSync / ComparisonError**  
`repoURL` or `targetRevision` does not match the real Git remote or default branch. Update the Application manifest. For a private repo, add credentials as in section 5.

**Helm and Argo fight each other**  
Only one of them should own `ecommerce-dev`. Uninstall the Helm release before applying the Argo Application, or skip Argo while you are iterating with `helm upgrade`.

**Chart render errors about DATABASE_URL**  
`secret.create` is true but neither `postgres.enabled` nor `database.url` is set. Enable Postgres or pass a URL.

## Verify the chart without a cluster

```powershell
cd e:\Development\Practice\GitHub\ecom-infra
helm lint ./helm/ecom-frontend -f ./helm/ecom-frontend/values-dev.yaml
helm lint ./helm/ecom-frontend -f ./helm/ecom-frontend/values-staging.yaml
helm lint ./helm/ecom-frontend -f ./helm/ecom-frontend/values-prod.yaml
helm template ecom-frontend ./helm/ecom-frontend -f ./helm/ecom-frontend/values-dev.yaml
```
