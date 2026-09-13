# ecom-infra

Helm charts and Argo CD applications for the [ecom](https://github.com/himansusekharsahoo/ecom) Next.js frontend.

The application lives in `ecom`. This repository is the GitOps source of truth for how that application runs on Kubernetes.

## Layout

```text
helm/ecom-frontend/     Application chart (frontend + optional Postgres/Redis)
  values.yaml           Shared defaults
  values-dev.yaml       Local / k3d
  values-staging.yaml   Staging
  values-prod.yaml      Production (external DB and cache)
argocd/applications/    Argo CD Application manifests
docs/                   Runbooks
```

## Quick start

Deploy to a local cluster with Helm:

```powershell
helm upgrade --install ecom-frontend ./helm/ecom-frontend `
  -f ./helm/ecom-frontend/values-dev.yaml `
  -n ecommerce-dev --create-namespace
```

Full walkthrough — image build, Helm, ingress hosts, and Argo CD — is in:

**[docs/run-the-app-with-helm-and-argo.md](docs/run-the-app-with-helm-and-argo.md)**
