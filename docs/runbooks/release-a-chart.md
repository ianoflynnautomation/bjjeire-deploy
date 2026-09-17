# Release a chart

Publishing a chart does **not** deploy it. Getting a template change into a
cluster is three steps across two repositories.

## 1. Merge the change here

Use a conventional commit that touches the chart's own directory:

| Change | Commit must touch |
|---|---|
| API template | `bjj-eire-api/artifact/**` |
| Frontend template | `bjj-eire-web/artifact/**` |
| MongoDB template | `bjj-eire-mongodb/artifact/**` |
| Umbrella / seeder / values | `bjj-eire/artifact/**` |

`feat:` and `fix:` produce a release; `chore:` and `ci:` do not. A commit that
touches nothing under a component's directory will never release that component
([ADR-0004](../adr/0004-one-release-line-per-chart.md)).

CI renders the umbrella on the pull request, so a subchart change is validated
before any release exists.

## 2. Merge the release PR

release-please opens `chore: release <version>`. Merging it:

- bumps `version:` in the chart's `Chart.yaml`
- updates that chart's `CHANGELOG.md`
- creates the tag (`umbrella-v0.2.4`, `api-v0.1.8`, …)
- auto-dispatches `publish-chart.yml`, which packages **at the tag** and pushes
  to `oci://ghcr.io/ianoflynnautomation/<chart>:<version>`

Verify the artifact exists before moving on. The OCI tag has **no `v`**:
`umbrella-v0.2.4` → `bjj-eire:0.2.4`.

### If you released a subchart

The umbrella still pins the old subchart version, so nothing has changed for
any consumer. Renovate opens a `fix:` PR bumping the dependency in
`bjj-eire/artifact/Chart.yaml`. Merge it, then merge the umbrella release PR it
produces, and you have a new umbrella.

To do it by hand: bump `dependencies[].version` in the umbrella's `Chart.yaml`
with a `fix:` commit, and let release-please cut the umbrella release.

## 3. Move the pin in `bjjeire-gitops`

```yaml
# kubernetes/apps/base/bjj-eire/app/ocirepository.yaml
ref:
  tag: "0.2.4"        # was 0.2.3 — no "v"
```

Open a PR there, merge it, and Flux reconciles on its 5-minute interval.

```bash
flux reconcile source oci bjj-eire -n bjjeire-app
flux reconcile helmrelease bjj-eire -n bjjeire-app --with-source
flux get hr -n bjjeire-app
```

Promotion is dev → staging → prod, one pin at a time.

## Health check

`.release-please-manifest.json` here and the `OCIRepository` tag in
`bjjeire-gitops` should be reconcilable at a glance. If the GitOps pin names a
version this manifest has never produced, the release line has orphaned —
[ADR-0004](../adr/0004-one-release-line-per-chart.md).

## Re-publishing

`publish-chart.yml` is `workflow_dispatch`. If a push failed transiently, run it
again with the same tag (`umbrella-v0.2.4`). It re-checks out at the tag and
re-verifies the version, so it cannot publish something different by accident.

## Rollback

Move the GitOps pin back to the previous version and let Flux reconcile. That is
the whole procedure — charts are immutable artifacts, so the old version is
still there.

Do not delete or overwrite a published OCI tag. If a release is bad, release a
new version forward.

Break-glass, when Flux itself is the problem:

```bash
flux suspend helmrelease bjj-eire -n bjjeire-app
# investigate
flux resume helmrelease bjj-eire -n bjjeire-app
```
