# Sync ephemeral values

## The problem

`values-ephemeral.yaml` exists in **two repositories**, and the copy in this one
is not the copy that runs.

| Location | Role |
|---|---|
| `bjj-eire/artifact/values-ephemeral.yaml` (here) | Declared source of truth |
| `bjjeire-gitops/kubernetes/apps/base/bjj-eire-preview/controller/values-ephemeral.yaml` | **What actually runs** |

The GitOps copy is loaded as the `bjj-eire-ephemeral-values` ConfigMap by a
`configMapGenerator`:

```yaml
# bjj-eire-preview/controller/kustomization.yaml
- name: bjj-eire-ephemeral-values
  files:
    - values.yaml=values-ephemeral.yaml
```

and consumed by the preview `ResourceSet` through `valuesFrom`, with the
ConfigMap copied into each ephemeral namespace via
`fluxcd.controlplane.io/copyFrom`.

**Editing only the copy in this repository changes nothing.**

## Current drift

The two copies have diverged. The GitOps copy is the one that runs:

| Setting | Here | GitOps (live) |
|---|---|---|
| api / frontend `replicaCount` | 1 | 2 |
| api / frontend cpu requests | 100m | 50m |
| frontend `sysctls: net.ipv4.ip_unprivileged_port_start=0` | absent | **present** |
| `imagePullSecrets: ghcr-pull-secret` | absent | **present** |

Two of those are functional, and copying this repository's version over the
GitOps one would break preview environments:

- Without the **sysctl**, the Caddy frontend cannot bind port 80 as a non-root
  user — pods crashloop on startup.
- Without **`imagePullSecrets`**, the private GHCR images cannot be pulled —
  pods sit in `ImagePullBackOff`.

The rate-limit override (`RATE_LIMIT_PERMIT_LIMIT: "500"`) matches in both; only
the explanatory comment differs. That value is deliberately far above the
deployed-environment default because the acceptance suite is sharded — many
Playwright workers hit one environment at once, and at the normal limit the
frontend's fail-closed feature flags silently redirect every feature route to
`/about` instead of surfacing a 429.

## Changing preview values

1. **Edit the GitOps copy** —
   `bjjeire-gitops/kubernetes/apps/base/bjj-eire-preview/controller/values-ephemeral.yaml`.
   That is the change that takes effect.
2. **Mirror it here** so the declared source of truth stays honest.
3. Open both pull requests together and reference each from the other.

## Reconciling the drift

Do it in this direction, once:

```bash
DEPLOY=~/Sources/bjjeire-deploy/bjj-eire/artifact/values-ephemeral.yaml
GITOPS=~/Sources/bjjeire-gitops/kubernetes/apps/base/bjj-eire-preview/controller/values-ephemeral.yaml

diff "$GITOPS" "$DEPLOY"
```

Take the **GitOps** side for anything functional (sysctls, pull secrets,
replicas, resources) — that is what is proven to work — and take this side's
comments. Then copy the reconciled file to both paths and verify it still
renders:

```bash
cd ~/Sources/bjjeire-deploy
helm dependency build bjj-eire/artifact
helm template bjj-eire bjj-eire/artifact \
  -f bjj-eire/artifact/values.yaml \
  -f bjj-eire/artifact/values-ephemeral.yaml \
  --namespace pr-0 > /dev/null && echo OK
```

## Why not one copy

A Flux `configMapGenerator` can only read files in its own repository, so the
GitOps repo needs a local copy unless the chart itself ships the values — which
would mean a chart release for every preview-tuning change.

The cheap guard against silent drift is a CI check in either repository that
diffs the two files and fails when they disagree. That does not exist yet and
would be worth adding.
