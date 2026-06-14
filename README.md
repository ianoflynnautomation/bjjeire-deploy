<div align="center">

# BJJ Eire — Helm Deployment

**Kubernetes deployment assets for the BJJ Eire platform** — a full-stack Brazilian Jiu-Jitsu community app built on React 19, ASP.NET Core (.NET 10), and MongoDB, deployed to AKS via Helm.

[![CI](https://github.com/ianoflynnautomation/bjjeire-deploy/actions/workflows/ci.yml/badge.svg)](https://github.com/ianoflynnautomation/bjjeire-deploy/actions/workflows/ci.yml)
[![Release](https://github.com/ianoflynnautomation/bjjeire-deploy/actions/workflows/release.yml/badge.svg)](https://github.com/ianoflynnautomation/bjjeire-deploy/actions/workflows/release.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Helm](https://img.shields.io/badge/Helm-v3.16.4-0f1689?logo=helm)](https://helm.sh)
[![.NET](https://img.shields.io/badge/.NET-10-512BD4?logo=dotnet)](https://dotnet.microsoft.com)
[![React](https://img.shields.io/badge/React-19-61DAFB?logo=react)](https://react.dev)
[![MongoDB](https://img.shields.io/badge/MongoDB-7.0-47A248?logo=mongodb)](https://www.mongodb.com)

</div>

---

## Overview

This repository contains all Helm charts and CI/CD workflows to deploy the BJJ Eire platform to Kubernetes (AKS). The umbrella chart `bjj-eire` composes three subcharts:

| Chart | Description |
|---|---|
| `bjj-api` | ASP.NET Core 10 REST API with Azure AD auth, Prometheus metrics, OpenTelemetry |
| `bjj-frontend` | React 19 + Nginx single-page app |
| `bjj-mongodb` | MongoDB 7.0 with persistent storage |


---

## Repository Structure

```
bjjeire-deploy/
├── .github/
│   └── workflows/
│       ├── ci.yml            # Helm lint + kubeconform validation
│       ├── helm-deploy.yml   # Manual deploy to dev / prod
│       └── release.yml       # Release-Please + push charts to GHCR OCI
├── bjj-eire/artifact/        # Umbrella chart
│   ├── charts/               # Packaged subcharts (dependency build output)
│   ├── values.yaml           # Base values
│   ├── values-local.yaml     # Local cluster overrides
│   ├── values-dev.yaml       # Dev environment overrides
│   └── values-prod.yaml      # Production overrides
├── bjj-eire-api/artifact/    # Standalone API chart
├── bjj-eire-web/artifact/    # Standalone frontend chart
├── bjj-eire-mongodb/artifact/ # Standalone MongoDB chart
└── scripts/deploy.sh         # Manual deploy helper
```

---

## Prerequisites

| Tool | Version |
|---|---|
| kubectl | v1.26+ |
| Helm | v3.16+ |
| Docker | 24+ (for local builds) |
| Kubernetes cluster | AKS or local (minikube / kind) |

---

## Deploying

### Manual deploy via GitHub Actions

1. Go to **Actions → Helm — Deploy to Kubernetes**
2. Click **Run workflow**
3. Select `environment` (`dev` or `prod`) and `image_tag` (e.g. `v1.2.3` or `latest`)

### Required GitHub Secrets

| Secret | Description |
|---|---|
| `KUBECONFIG_DEV` | base64-encoded kubeconfig for the dev cluster |
| `KUBECONFIG_PROD` | base64-encoded kubeconfig for the prod cluster |
| `AZURE_AD_TENANT_ID` | Entra ID tenant GUID |
| `AZURE_AD_CLIENT_ID` | App registration client GUID |
| `AZURE_AD_AUDIENCE` | API audience URI (e.g. `api://<client-id>`) |
| `MONGODB_ROOT_PASSWORD_B64` | Base64-encoded MongoDB root password |
| `GHCR_PAT` | GitHub PAT with `read:packages` scope (optional, private images) |

Generate the MongoDB secret value:

```bash
echo -n 'your-password' | base64
```

### Deploy from the command line

```bash
helm dependency build bjj-eire/artifact

helm upgrade --install bjj-eire bjj-eire/artifact \
  --namespace bjjeire-app \
  --create-namespace \
  -f bjj-eire/artifact/values.yaml \
  -f bjj-eire/artifact/values-dev.yaml \
  --set bjj-api.api.image.tag=latest \
  --set bjj-frontend.frontend.image.tag=latest \
  --set 'bjj-api.api.env.AzureAd__TenantId=<tenant-id>' \
  --set 'bjj-api.api.env.AzureAd__ClientId=<client-id>' \
  --set 'bjj-api.api.env.AzureAd__Audience=<audience>' \
  --set 'bjj-api.secrets.mongodbRootPassword.value=<base64-password>' \
  --set 'bjj-mongodb.secrets.mongodbRootPassword.value=<base64-password>' \
  --wait --timeout 5m
```

---

## Local Development

<details>
<summary>Run on a local Kubernetes cluster (minikube / kind)</summary>

1. Start your local cluster and ensure `kubectl` context is set.

2. Build local images (from the respective app repos):

```bash
docker build -t bjj-api:local .         # from bjjeire-api repo
docker build -t bjj-frontend:local .    # from bjjeire-web repo
```

3. Deploy with local values:

```bash
helm dependency build bjj-eire/artifact

helm upgrade --install bjj-eire bjj-eire/artifact \
  --namespace bjjeire-app \
  --create-namespace \
  -f bjj-eire/artifact/values.yaml \
  -f bjj-eire/artifact/values-local.yaml \
  --set 'bjj-api.secrets.mongodbRootPassword.value=<base64-password>' \
  --set 'bjj-mongodb.secrets.mongodbRootPassword.value=<base64-password>'
```

4. Add to `/etc/hosts`:

```
127.0.0.1  app.bjj.local api.bjj.local
```

5. Access the app at `https://app.bjj.local`.

</details>

---

## Environments

| Environment | Frontend | API |
|---|---|---|
| Local | `app.bjj.local` | `api.bjj.local` |
| Dev | `dev.bjjeire.ie` | `api.dev.bjjeire.ie` |
| Prod | `bjjeire.com` | `api.bjjeire.com` |

---

## Releases & Versioning

Releases are managed by [Release-Please](https://github.com/googleapis/release-please). On merge to `main`, a release PR is opened automatically based on [Conventional Commits](https://www.conventionalcommits.org). Merging the release PR:

- Bumps chart versions
- Generates `CHANGELOG.md`
- Packages and pushes all charts to GHCR OCI (`ghcr.io/ianoflynnautomation`)

Chart image tags:

| Chart | Tag format |
|---|---|
| Umbrella | `umbrella-v*` |
| API | `api-v*` |
| Frontend | `web-v*` |
| MongoDB | `mongodb-v*` |

---

## CI

Every pull request runs:

- `helm lint` on all subcharts
- `helm template` dry-run rendering
- `kubeconform` manifest validation

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). This project follows [Conventional Commits](https://www.conventionalcommits.org) and the [Contributor Covenant](CODE_OF_CONDUCT.md).

---

## Security

See [SECURITY.md](SECURITY.md) for the vulnerability disclosure policy.

---

## License

MIT © [Ian O'Flynn](https://github.com/ianoflynnautomation) — see [LICENSE](LICENSE).