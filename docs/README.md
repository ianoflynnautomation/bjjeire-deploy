# Documentation

| Doc | Contents |
|---|---|
| [architecture.md](architecture.md) | Chart composition, delivery chain, **which values files are actually used**, the seeder, dead weight |
| [ci-cd.md](ci-cd.md) | CI, release-please, chart publishing, Renovate |
| [adr/](adr/) | Architecture decision records — *why* it is built this way |
| [runbooks/](runbooks/) | Releasing, MongoDB recovery, ephemeral values, local install |
| [diagrams/](diagrams/) | `architecture.drawio.svg` — renders on GitHub, editable in draw.io |

## Reading order

**New here:** [architecture.md](architecture.md) → [ci-cd.md](ci-cd.md).

**Shipping a change:** [runbooks/release-a-chart.md](runbooks/release-a-chart.md).
Publishing a chart does not deploy it — the pin in `bjjeire-gitops` has to move
too.

**Something is stuck:** [ci-cd.md § common failures](ci-cd.md#common-failures).
If it is MongoDB in a rollback loop, go straight to
[runbooks/mongodb-statefulset-recovery.md](runbooks/mongodb-statefulset-recovery.md).

## Three things that catch people out

1. **Directory names and chart names differ.** `bjj-eire-web/artifact` contains
   the chart `bjj-frontend`. Helm sees chart names; release-please and Renovate
   see directories.
2. **`values-dev.yaml`, `values-staging.yaml`, and `values-prod.yaml` are read
   by no cluster.** Deployed values live in `bjjeire-gitops`
   ([ADR-0005](adr/0005-environment-values-are-not-the-deployment-source.md)).
3. **Releasing a subchart changes nothing on its own.** The umbrella vendors a
   snapshot, so its dependency pin must be bumped and the umbrella re-released
   ([ADR-0001](adr/0001-umbrella-chart-with-local-path-dependencies.md)).

## Keeping these accurate

These pages describe the charts in this repository, not the running system.
When a change alters chart composition, the release flow, or which values a
cluster reads, update the matching page in the same pull request — and add an
ADR if you are making a decision rather than following one.
