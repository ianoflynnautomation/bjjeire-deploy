# MongoDB StatefulSet recovery

## Symptom

A `HelmRelease` upgrade fails, rolls back, retries on the next interval, and
fails again. The cluster looks busy and stays broken. The error is:

```
StatefulSet.apps "bjj-mongodb" is invalid: spec: Forbidden:
updates to statefulset spec for fields other than 'replicas', 'ordinals',
'template', 'updateStrategy', 'persistentVolumeClaimRetentionPolicy'
and 'minReadySeconds' are forbidden
```

## Cause

Something in the StatefulSet's `volumeClaimTemplates` changed. Kubernetes treats
that field as immutable, so Helm cannot apply the update.

Historically this was a chart-version label leaking into the VCT — fixed in
`bjj-mongodb` 0.1.4 and recorded in
[ADR-0006](../adr/0006-mongodb-volumeclaimtemplate-labels.md). If you are
hitting it now, check what changed in the VCT: storage class, size, access
mode, or labels.

## Fix

Delete the StatefulSet **without deleting its pods or PVCs**, then let Flux
recreate it. `--cascade=orphan` is what makes this safe — it leaves the running
pod and, critically, the PersistentVolumeClaim in place.

```bash
# 1. Confirm what you are about to orphan
kubectl -n bjjeire-app get statefulset bjj-mongodb
kubectl -n bjjeire-app get pvc
kubectl -n bjjeire-app get pods -l app.kubernetes.io/name=bjj-mongodb

# 2. Delete the StatefulSet object only
kubectl -n bjjeire-app delete statefulset bjj-mongodb --cascade=orphan

# 3. Confirm the pod and PVC survived
kubectl -n bjjeire-app get pods,pvc

# 4. Force Flux to recreate it from the chart
flux reconcile helmrelease bjj-eire -n bjjeire-app --force --reset
```

`--force` re-runs the upgrade; `--reset` clears the failure counter so
remediation does not immediately roll back again.

Then verify:

```bash
flux get hr -n bjjeire-app
kubectl -n bjjeire-app get statefulset bjj-mongodb
kubectl -n bjjeire-app logs -l app.kubernetes.io/name=bjj-mongodb --tail=50
```

The new StatefulSet adopts the existing pod and PVC by selector, so the data
volume is untouched.

## Do not

- **Do not `kubectl delete statefulset` without `--cascade=orphan`.** The
  default cascade deletes the pods, and depending on the retention policy can
  take the PVCs with them. That destroys the database.
- **Do not delete the PVC** to "start clean" unless you have confirmed the data
  is disposable. On dev with a seeder that is often true; on staging or
  production it is not.
- **Do not add version-bearing labels** (`helm.sh/chart`,
  `app.kubernetes.io/version`) to a `volumeClaimTemplate`. That reintroduces the
  original bug for every future chart bump.

## Before you change a VCT

Any deliberate change to `volumeClaimTemplates` — resizing the volume, changing
the storage class — needs this procedure as part of the rollout, not as
recovery afterwards. Plan it into the change:

1. Merge and release the chart change.
2. Orphan-delete the StatefulSet in the target environment.
3. Move the GitOps pin; Flux recreates with the new VCT.

Do it in dev first. Note that resizing a PVC also requires the storage class to
allow volume expansion — `standard` on dev and `managed-premium` on prod behave
differently.
