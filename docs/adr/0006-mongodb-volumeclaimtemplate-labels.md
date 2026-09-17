# ADR-0006: MongoDB's `volumeClaimTemplates` carry selector labels only

- **Status:** Accepted
- **Date:** 2026-09-16 (records a fix made in `bjj-mongodb` 0.1.4)
- **Applies to:** `bjj-eire-mongodb/artifact/templates/`, `_helpers.tpl`

## Context

Helm charts conventionally stamp a full label set onto every resource —
including `helm.sh/chart`, which embeds the chart version
(`bjj-mongodb-0.1.5`). The `bjj-mongodb` chart did this via its
`bjj-mongodb.labels` helper, and applied it to the StatefulSet's
`volumeClaimTemplates`.

Kubernetes treats a StatefulSet's `volumeClaimTemplates` as **immutable**. Only
`replicas`, `ordinals`, `template`, `updateStrategy`,
`persistentVolumeClaimRetentionPolicy`, and `minReadySeconds` may change.

So every chart version bump changed a label inside an immutable field.

## Decision

`volumeClaimTemplates` carry **`bjj-mongodb.selectorLabels` only** — the stable
subset (`app.kubernetes.io/name`, `app.kubernetes.io/instance`) that does not
contain the chart version. The full `bjj-mongodb.labels` set is still applied to
every other resource.

Never add a version-bearing label — `helm.sh/chart`,
`app.kubernetes.io/version`, `app.kubernetes.io/managed-by` — to a
`volumeClaimTemplate`.

## Consequences

- Chart version bumps no longer touch an immutable field, so MongoDB upgrades
  cleanly.
- **Reversing this produces a rollback loop, not a clear error.** The upgrade
  fails with:

  ```
  StatefulSet.apps "bjj-mongodb" is invalid: spec: Forbidden:
  updates to statefulset spec for fields other than 'replicas', 'ordinals',
  'template', 'updateStrategy', 'persistentVolumeClaimRetentionPolicy'
  and 'minReadySeconds' are forbidden
  ```

  The `HelmRelease` then remediates, rolls back, retries on the next interval,
  and fails again. The cluster looks busy and stays broken.
- The PVC loses the chart-version label it used to carry. Nothing depends on it;
  selectors use `selectorLabels`.
- **Any future VCT change still needs manual intervention on an existing
  StatefulSet** — storage class, size, access mode, or labels. The immutability
  is the API's, not the chart's. The recovery procedure is
  [runbooks/mongodb-statefulset-recovery.md](../runbooks/mongodb-statefulset-recovery.md).
- This constraint applies to any StatefulSet added to these charts, not just
  MongoDB.

## Alternatives considered

- **Full labels on the VCT** — the Helm convention, and what caused the
  incident.
- **Recreate the StatefulSet on every chart bump.** Would work and is
  catastrophic: recreating the StatefulSet with its PVCs destroys the database.
- **`persistentVolumeClaimRetentionPolicy` plus deliberate recreation.** Viable
  for a stateless-ish store, not for the platform's only database.
- **A managed MongoDB (Cosmos DB / Atlas).** Removes StatefulSet management
  entirely. A real option if persistence becomes more trouble than it is worth;
  rejected today on cost.
