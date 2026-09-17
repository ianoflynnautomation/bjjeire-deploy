# ADR-0005: Deployed values live in `bjjeire-gitops`, not in this repository

- **Status:** Accepted
- **Date:** 2026-09-16 (records a migration that already happened)
- **Applies to:** `values-dev.yaml`, `values-staging.yaml`, `values-prod.yaml`, subchart `templates/ingress.yaml`

## Context

This repository originally deployed the platform itself: a workflow with a
kubeconfig ran `helm upgrade` against dev or prod, using `values-dev.yaml` or
`values-prod.yaml` from this tree. Ingress was nginx.

The platform then moved to GitOps. Flux reconciles a `HelmRelease` in
`bjjeire-gitops`, ingress moved to Istio ambient with Gateway API, and the
cluster gained no inbound path for a CI runner to push to.

The old values files were left in place.

## Decision

**`bjjeire-gitops` owns deployed configuration.** Its `HelmRelease` supplies
`values:` inline and `valuesFrom:` ConfigMaps; it does not reference any
`values-*.yaml` from this repository.

This repository owns:

- `values.yaml` — chart defaults, rendered by CI and by every consumer
- `values-local.yaml` — a working local install on minikube or kind
- `values-ephemeral.yaml` — the **source** for preview environments, whose
  operative copy lives in `bjjeire-gitops`
- `values.schema.json` — the contract every values file must satisfy

`values-dev.yaml`, `values-staging.yaml`, and `values-prod.yaml` are **legacy**.
They are not read by any cluster.

## Consequences

- **The clearest tell is ingress.** Those files configure an nginx `Ingress`
  with `nginx.ingress.kubernetes.io/*` annotations on `api.dev.bjjeire.com` and
  `bjjeire.com`. The clusters run Istio ambient: `bjjeire-gitops` sets
  `ingress.enabled: false` for api and frontend and supplies its own
  `httproute.yaml`. There is no `kind: Ingress` anywhere in the GitOps repo.
- The subcharts' `templates/ingress.yaml` therefore render nothing in any
  deployed environment. They are kept because `values-local.yaml` still uses
  them for a local cluster.
- **Editing `values-prod.yaml` changes nothing.** This is the trap this ADR
  exists to document. A reviewer sees a production values file, reasonably
  assumes production reads it, and ships a change that never lands.
- Changing what a cluster runs means a pull request in `bjjeire-gitops`, not
  here.
- The files are worth keeping only as a reference for what a standalone install
  looks like. If they start being mistaken for live configuration, deleting
  them is the better answer.
- `values-ephemeral.yaml` is the exception and needs care — it is duplicated
  into `bjjeire-gitops`, and the copies have drifted. See
  [runbooks/sync-ephemeral-values.md](../runbooks/sync-ephemeral-values.md).

## Alternatives considered

- **Delete the legacy files.** Honest and removes the trap. Not done yet only
  because they document a working standalone configuration; doing it would be an
  improvement, not a regression.
- **Keep deploying from here with a kubeconfig.** Requires standing cluster
  credentials in CI and an inbound path to the API server. Rejected when the
  platform adopted GitOps.
- **Have GitOps reference these files** via a Flux `GitRepository` on this repo.
  Would make them live again, at the cost of coupling cluster config to chart
  releases — a values change would need a chart release to ship.
