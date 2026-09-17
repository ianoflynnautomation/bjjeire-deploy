# ADR-0001: Umbrella chart composes subcharts via `file://` paths, with build output gitignored

- **Status:** Accepted
- **Date:** 2026-09-16 (recorded; decision predates this record)
- **Applies to:** `bjj-eire/artifact/Chart.yaml`, `.gitignore`

## Context

The platform deploys three components that are always installed together —
API, frontend, and MongoDB — but that change at different rates and are useful
to version independently.

Helm offers two ways to compose them: publish each subchart to a repository and
have the umbrella depend on it by version, or keep them in one repository and
depend on local paths. The first requires a subchart to be published before the
umbrella can even render, which means a subchart change cannot be tested
through the umbrella until it has been released.

## Decision

All four charts live in this repository. The umbrella depends on its siblings by
relative path:

```yaml
dependencies:
  - name: bjj-mongodb
    version: "0.1.5"
    repository: "file://../../bjj-eire-mongodb/artifact"
    condition: bjj-mongodb.mongodb.enabled
```

Each dependency carries a `condition`, so any component can be switched off
from values.

**`charts/`, `Chart.lock`, and `*.tgz` are gitignored.** They are build output.
`helm dependency build` vendors whatever subchart source is committed at the
moment it runs — which, at release time, is the source at the release tag.

## Consequences

- A subchart change is rendered and validated through the umbrella on every
  pull request, before any release exists.
- The `version:` in `Chart.yaml` and the sibling's actual version must agree, or
  `helm dependency build` fails with a version-not-found error. Renovate keeps
  the pin current.
- **The published umbrella contains a snapshot of the subcharts.** Releasing a
  subchart does not change any already-published umbrella, and does not change
  what runs in a cluster. The umbrella must be bumped and re-released too —
  which is exactly what Renovate's `fix:` commit on the dependency pin
  triggers. Forgetting this step is the most common reason a subchart fix
  "didn't do anything".
- Because the lock file is not committed, two builds of the same commit can in
  principle vendor different bytes. In practice the `file://` sources are in the
  same commit, so the risk is limited to a mismatched pin.
- Cloning and running `helm template` requires `helm dependency build` first.
  There is no `charts/` in a fresh checkout.

## Alternatives considered

- **Publish subcharts and depend by version from a repository.** The
  conventional approach, and it makes the umbrella's contents explicit. Rejected
  because it forces a release before a subchart change can be tested through
  the umbrella, which slows every change.
- **One monolithic chart with no subcharts.** Simplest to render and reason
  about. Rejected: it loses independent versioning and the per-component
  `condition` toggles that the ephemeral and local overlays rely on.
- **Commit `charts/` and `Chart.lock`.** Reproducible to the byte, at the cost
  of a binary `.tgz` in every diff and a lock file that conflicts on every
  subchart bump.
