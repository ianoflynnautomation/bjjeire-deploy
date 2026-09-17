# Agent guide — bjjeire-deploy

Helm charts for the BjjEire platform. This repository **produces OCI chart
artifacts; it does not deploy anything.** Flux does, from `bjjeire-gitops`.

## Read this before you change anything

| If you are touching… | Read first |
|---|---|
| The umbrella's dependencies or `charts/` | [ADR-0001](docs/adr/0001-umbrella-chart-with-local-path-dependencies.md) |
| Publishing or OCI tags | [ADR-0002](docs/adr/0002-distribute-charts-as-oci-artifacts.md) — OCI tags have no `v` |
| The seeder Job | [ADR-0003](docs/adr/0003-seeder-runs-as-a-helm-hook.md) — a failing hook fails the release |
| Chart versions or release tags | [ADR-0004](docs/adr/0004-one-release-line-per-chart.md) — never tag out of band |
| Any `values-*.yaml` | [ADR-0005](docs/adr/0005-environment-values-are-not-the-deployment-source.md) — dev/staging/prod are read by no cluster |
| Anything in the MongoDB StatefulSet | [ADR-0006](docs/adr/0006-mongodb-volumeclaimtemplate-labels.md) — VCTs are immutable |
| `values.schema.json` | [ADR-0007](docs/adr/0007-values-schema-is-required.md) |

Architecture: [docs/architecture.md](docs/architecture.md).
Pipelines: [docs/ci-cd.md](docs/ci-cd.md).
Full index: [docs/README.md](docs/README.md).

## Names

Directory names and chart names are **not** the same. This trips up almost
every change:

| Directory | Chart name |
|---|---|
| `bjj-eire/artifact` | `bjj-eire` (umbrella) |
| `bjj-eire-api/artifact` | `bjj-api` |
| `bjj-eire-web/artifact` | `bjj-frontend` |
| `bjj-eire-mongodb/artifact` | `bjj-mongodb` |

Helm and values keys use **chart** names. release-please, Renovate, and
`publish-chart.yml` use **directories**.

## Hard rules

- **Never `git commit` or `git push`.** Leave changes in the working tree; the
  maintainer commits.
- **Never edit `version:` in a `Chart.yaml` by hand**, and never create a
  release tag manually. Versions move only by merging a release PR. Doing
  otherwise orphans the release line and silently stops a cluster receiving
  updates ([ADR-0004](docs/adr/0004-one-release-line-per-chart.md)).
- **Never add a version-bearing label** (`helm.sh/chart`,
  `app.kubernetes.io/version`) to a `volumeClaimTemplate`. It produces an
  unrecoverable-looking rollback loop on the next chart bump.
- **Never commit `charts/`, `Chart.lock`, or `*.tgz`.** They are build output
  and are gitignored.
- **Never put a secret value in a values file.** Secrets come from Key Vault via
  External Secrets in the GitOps repo; charts reference names only.
- **Do not assume editing `values-prod.yaml` changes production.** It does not.
- **Do not edit only this repo's `values-ephemeral.yaml`** — the operative copy
  is in `bjjeire-gitops` and the two have drifted. See
  [docs/runbooks/sync-ephemeral-values.md](docs/runbooks/sync-ephemeral-values.md).

## Conventions

- Charts are pre-1.0. release-please is configured `bump-minor-pre-major`, so a
  `feat:` bumps the patch and a breaking change bumps the minor.
- Conventional commits, and the commit **must touch the component's directory**
  or that component will never release.
- Every top-level values section (`bjj-mongodb`, `bjj-api`, `bjj-frontend`,
  `seeder`) is required by the schema — adding one is a breaking change for
  every consumer.
- Subchart dependencies carry a `condition`, so components can be switched off
  from values. Keep that property when adding one.

## Commands

```bash
# Vendor subcharts — there is no charts/ in a fresh checkout
helm dependency build bjj-eire/artifact

# Lint everything
helm lint bjj-eire/artifact bjj-eire-api/artifact bjj-eire-web/artifact bjj-eire-mongodb/artifact

# Render the way CI does
helm template bjj-eire bjj-eire/artifact \
  -f bjj-eire/artifact/values.yaml \
  --set bjj-api.api.image.tag=ci \
  --set bjj-frontend.frontend.image.tag=ci \
  --set seeder.enabled=false \
  --namespace bjjeire-app --debug

# Local install: docs/runbooks/local-install.md
```

## Where things live

```
bjj-eire/artifact/            umbrella chart + seeder hook + values-*.yaml
bjj-eire-{api,web,mongodb}/artifact/   subcharts
docs/adr/                     decisions and their rationale
docs/architecture.md          chart composition and delivery
docs/ci-cd.md                 workflows
docs/runbooks/                release, recovery, local install
docs/diagrams/                architecture.drawio.svg
.github/workflows/            ci, release, publish-chart, renovate
```

Two things in the tree are dead: `manifests/` is nine **empty** files from the
initial commit, and `scripts/deploy.sh` is the pre-GitOps manual deploy helper.
Neither is used by anything.

## Related repositories

`bjjeire` (application code and container images) · `bjjeire-gitops` (Flux;
owns the live values and the chart version pin) ·
`bjjeire-terraform-azurerm-aks` (cluster, identities, Key Vault) ·
`bjjeire-ci-templates` (the reusable workflows this CI calls).

A template change reaching production takes three steps: release the chart
here, bump the `OCIRepository` tag in `bjjeire-gitops`, let Flux reconcile. See
[docs/runbooks/release-a-chart.md](docs/runbooks/release-a-chart.md).
