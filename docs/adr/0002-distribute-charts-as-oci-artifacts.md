# ADR-0002: Distribute charts as OCI artifacts on GHCR

- **Status:** Accepted
- **Date:** 2026-09-16 (decision predates this record)
- **Applies to:** `.github/workflows/publish-chart.yml`

## Context

Flux needs somewhere to pull charts from. The classic option is a Helm chart
repository — an `index.yaml` plus tarballs, hosted on GitHub Pages or a storage
account. That means running and securing another artefact store, and keeping an
index in sync.

GHCR already holds this project's container images and its OpenAPI and Pact
contracts, already authenticates with `GITHUB_TOKEN`, and supports Helm charts
as OCI artifacts. Flux's `OCIRepository` consumes them natively.

## Decision

`publish-chart.yml` packages a chart and pushes it to
`oci://ghcr.io/ianoflynnautomation/<chart-name>`.

**The OCI tag is the chart version with no `v` prefix.** Git tag
`umbrella-v0.2.3` becomes `oci://…/bjj-eire:0.2.3`.

Publishing is a `workflow_dispatch` that takes a release tag. It resolves the
tag to a chart directory with `parse-release-tag`, checks out **at that tag**,
and verifies `Chart.yaml`'s version matches before pushing. `release.yml`
auto-dispatches it for every tag a release PR creates.

Flux consumes it with an `OCIRepository` and an explicit `layerSelector` for
the Helm chart media type:

```yaml
layerSelector:
  mediaType: application/vnd.cncf.helm.chart.content.v1.tar+gzip
  operation: copy
```

## Consequences

- No chart repository to host, index, or secure. Charts inherit GHCR's
  authentication and retention.
- Charts are private, so every consumer needs credentials: Flux uses
  `ghcr-pull-secret`, Renovate needs `read:packages`. A missing or expired pull
  secret presents as the `OCIRepository` failing to fetch, which stalls the
  `HelmRelease` rather than producing a clear auth error at the top.
- **The `v` prefix asymmetry is a real trap.** Git tags carry it, OCI tags do
  not. A GitOps pin written as `tag: "v0.2.3"` will never resolve.
- Publishing is re-runnable by hand for any tag, which is the recovery path
  when a push fails transiently.
- `expected-version` means a mislabelled artefact fails the workflow instead of
  being published.
- OCI artifacts are less browsable than a chart repo index — there is no
  `helm search`. Listing versions means the GHCR package page or a registry API
  call.

## Alternatives considered

- **GitHub Pages chart repository (`index.yaml`).** Familiar, browsable,
  `helm repo add` works. Rejected: another thing to publish and keep consistent,
  and Flux's OCI support removes the need.
- **Azure Container Registry.** Already in the subscription, but adds a second
  registry and a second set of credentials alongside GHCR, which holds the
  images.
- **Git as the chart source** (Flux `GitRepository` pointed at this repo).
  Removes publishing entirely, but loses immutable versioned artefacts and
  makes `helm dependency build` the cluster's problem.
