# ADR-0004: One release-please line per chart; never tag a version out of band

- **Status:** Accepted
- **Date:** 2026-09-16 (recorded after a real incident)
- **Applies to:** `release-please-config.json`, `.release-please-manifest.json`

## Context

Four charts version independently. release-please tracks each one's current
version in `.release-please-manifest.json` and computes the next version from
conventional commits since that component's last tag.

This only works if release-please's view of "current version" matches reality.
It has one source of truth — the manifest — and no way to discover a tag
someone created by hand.

## Decision

Every chart has exactly one release line, owned by release-please:

| Directory | Component | Tag pattern |
|---|---|---|
| `bjj-eire/artifact` | `umbrella` | `umbrella-v${version}` |
| `bjj-eire-api/artifact` | `api` | `api-v${version}` |
| `bjj-eire-web/artifact` | `web` | `web-v${version}` |
| `bjj-eire-mongodb/artifact` | `mongodb` | `mongodb-v${version}` |

**Versions are bumped only by merging a release PR.** Do not create a release
tag by hand, do not edit `version:` in `Chart.yaml` directly, and do not push a
chart to GHCR outside `publish-chart.yml`.

If a line must be moved — to adopt a version published out of band, or to skip
a burnt version — change `.release-please-manifest.json` deliberately, in a
commit that says why.

## Consequences

- Versions, changelogs, and tags stay consistent, and the OCI tag always
  corresponds to a commit.
- **Reversing this silently orphans a cluster.** This has happened: a manual
  `0.2.0` umbrella tag was published and pinned in `bjjeire-gitops`, while
  release-please continued on the `0.1.x` line. Every subsequent release
  produced `0.1.x` artefacts that the cluster's pin could never see. Nothing
  errored — the cluster simply stopped receiving updates, and the symptom was
  "my chart change never arrived". The fix was to move the manifest baseline to
  `0.2.0` so both agreed.
- The guard against a recurrence is to keep the manifest and the GitOps pin
  reconcilable at a glance. Today `.release-please-manifest.json` says umbrella
  `0.2.3` and `bjjeire-gitops` pins `0.2.3`. **When those two numbers disagree,
  something is wrong** — that comparison is the cheapest health check available.
- A semver range in the GitOps `OCIRepository` (rather than an exact tag) makes
  orphaning impossible on dev, at the cost of exact reproducibility. Staging and
  production keep exact pins deliberately.
- release-please needs a conventional commit touching a component's directory to
  cut that component. A change that touches nothing under `bjj-eire-api/artifact`
  will never produce an `api-v*` release, however it is worded.

## Alternatives considered

- **A single version for all four charts.** Removes the whole class of problem.
  Rejected: every subchart would be republished for an unrelated change, and the
  umbrella's dependency pins would become meaningless.
- **Manual versioning.** What produced the incident above.
- **Semver ranges everywhere in GitOps.** Prevents orphaning but gives up
  reproducible production deployments.
