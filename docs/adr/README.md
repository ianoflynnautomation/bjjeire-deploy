# Architecture Decision Records

Decisions with lasting consequences for these charts, and the reasoning behind
them. Several look like inconsistencies from the outside — the ADR explains why
they are deliberate and what breaks if reversed.

Format: [MADR](https://adr.github.io/madr/). One file per decision, numbered
sequentially, never renumbered.

| ADR | Decision | Status |
|---|---|---|
| [0001](0001-umbrella-chart-with-local-path-dependencies.md) | Umbrella chart composes subcharts via `file://` paths, with build output gitignored | Accepted |
| [0002](0002-distribute-charts-as-oci-artifacts.md) | Charts are distributed as OCI artifacts on GHCR, not a chart repository | Accepted |
| [0003](0003-seeder-runs-as-a-helm-hook.md) | The seeder runs as a Helm hook, and is off by default | Accepted |
| [0004](0004-one-release-line-per-chart.md) | Each chart has one release-please line; versions are never tagged out of band | Accepted |
| [0005](0005-environment-values-are-not-the-deployment-source.md) | Deployed values live in `bjjeire-gitops`, not in this repository | Accepted |
| [0006](0006-mongodb-volumeclaimtemplate-labels.md) | MongoDB's `volumeClaimTemplates` carry selector labels only, never chart-version labels | Accepted |
| [0007](0007-values-schema-is-required.md) | `values.schema.json` requires every top-level section | Accepted |

## Adding one

Copy [`0000-template.md`](0000-template.md), take the next number, and link it
from the table above — and from [AGENTS.md](../../AGENTS.md) if someone could
plausibly try to reverse it.
