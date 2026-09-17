# Local install

Running the full stack on minikube or kind. This is the one path where the
subcharts' nginx `Ingress` templates are still used — deployed environments use
Istio Gateway API instead
([ADR-0005](../adr/0005-environment-values-are-not-the-deployment-source.md)).

## Prerequisites

| Tool | Version |
|---|---|
| kubectl | 1.26+ |
| Helm | 3.16+ |
| minikube or kind | any recent |
| An nginx ingress controller | in the cluster |

## Build images

From the application repository (`bjjeire`):

```bash
docker build -t bjj-api:local -f src/bjjeire-api/Dockerfile .
docker build -t bjj-frontend:local src/bjjeire-app
```

Load them into your cluster (`minikube image load`, `kind load docker-image`),
or build inside minikube's daemon with `eval $(minikube docker-env)`.

`values-local.yaml` expects `bjj-api:local` and `bjj-frontend:local`.

## Install

There is no `charts/` in a fresh checkout — the subcharts are vendored at build
time ([ADR-0001](../adr/0001-umbrella-chart-with-local-path-dependencies.md)):

```bash
helm dependency build bjj-eire/artifact
```

Then:

```bash
MONGO_PW=$(echo -n 'change-me' | base64)

helm upgrade --install bjj-eire bjj-eire/artifact \
  --namespace bjjeire-app --create-namespace \
  -f bjj-eire/artifact/values.yaml \
  -f bjj-eire/artifact/values-local.yaml \
  --set "bjj-api.secrets.mongodbRootPassword.value=${MONGO_PW}" \
  --set "bjj-mongodb.secrets.mongodbRootPassword.value=${MONGO_PW}" \
  --wait --timeout 10m
```

Both the API and MongoDB need the **same** base64 password — they are separate
Secret references to one credential.

Add the hostnames:

```
127.0.0.1  app.bjj.local api.bjj.local
```

The app is then at `https://app.bjj.local`.

## Seeding

The seeder is off by default. To load test data:

```bash
--set seeder.enabled=true --set seeder.dataset=test
```

It runs as a `post-install` hook, so **a failing seeder fails the whole
install** ([ADR-0003](../adr/0003-seeder-runs-as-a-helm-hook.md)). If the
install hangs or rolls back, check the Job before anything else — you have
`ttlSecondsAfterFinished: 300` to read its logs:

```bash
kubectl -n bjjeire-app logs job/bjj-eire-seeder
```

## Render without installing

Useful for reviewing a template change, and what CI does:

```bash
helm template bjj-eire bjj-eire/artifact \
  -f bjj-eire/artifact/values.yaml \
  --set bjj-api.api.image.tag=ci \
  --set bjj-frontend.frontend.image.tag=ci \
  --set seeder.enabled=false \
  --namespace bjjeire-app --debug
```

Values are schema-validated
([ADR-0007](../adr/0007-values-schema-is-required.md)), so a values file missing
a top-level section fails here rather than rendering something partial.

## Teardown

```bash
helm uninstall bjj-eire -n bjjeire-app
kubectl delete namespace bjjeire-app
```

The MongoDB PVC is not removed by `helm uninstall`. Delete it explicitly if you
want a clean database:

```bash
kubectl -n bjjeire-app delete pvc -l app.kubernetes.io/name=bjj-mongodb
```
