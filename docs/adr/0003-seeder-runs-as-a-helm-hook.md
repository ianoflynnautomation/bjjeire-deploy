# ADR-0003: The seeder runs as a Helm hook, and is off by default

- **Status:** Accepted
- **Date:** 2026-09-16 (decision predates this record)
- **Applies to:** `bjj-eire/artifact/templates/seeder-job.yaml`, `seeder.*` values

## Context

Dev, staging, and preview environments need a database with data in it. An
empty MongoDB makes every listing page blank and every acceptance test fail on
an empty result rather than on the behaviour under test.

Seeding has to happen after MongoDB is up and before tests run, exactly once
per deployment — not on every pod restart.

## Decision

A `Job` in the umbrella chart, annotated as a Helm hook:

```yaml
annotations:
  "helm.sh/hook": {{ .Values.seeder.hookPolicy }}      # post-install
  "helm.sh/hook-weight": "0"                            # ServiceAccount is -5
  "helm.sh/hook-delete-policy": before-hook-creation,hook-succeeded
```

`restartPolicy: Never`, `backoffLimit: 1`,
`ttlSecondsAfterFinished: 300`.

**`seeder.enabled` defaults to `false`.** Dev and ephemeral turn it on with
`dataset: "test"`; production leaves it off.

The hook weight orders the ServiceAccount (-5) before the Job (0). The delete
policy cleans up a previous attempt before creating a new one and removes the
Job on success, so a re-run is not blocked by a completed Job of the same name.

## Consequences

- Seeding is tied to the release lifecycle, runs once, and is ordered after the
  main resources — which is what a plain `Job` in `templates/` could not
  guarantee.
- **A failing seeder fails the whole release.** Helm treats a failed hook as a
  failed install or upgrade. The `HelmRelease` goes not-ready and remediation
  may roll back an otherwise healthy deployment. This is the single most
  important consequence of choosing a hook over a Job.
- That failure mode is why the default is `false`, and why it has been switched
  off in environments where no matching seeder image existed. A seeder image
  built for a different runtime than the API will take the release down with
  it.
- CI renders with `seeder.enabled=false` for the same reason.
- Hooks are invisible to `helm template` unless explicitly rendered, so schema
  and lint coverage of this Job is thinner than for ordinary templates.
- Because the Job is deleted on success, there is a 300-second window
  (`ttlSecondsAfterFinished`) to read its logs. After that, diagnosing a seeding
  problem means re-running it.

## Alternatives considered

- **A plain `Job` in `templates/`.** Cannot be ordered after MongoDB is ready,
  and Helm will not re-run a completed Job with the same name on upgrade.
- **An init container on the API deployment.** Would run on every pod start and
  every scale-up, not once per release.
- **Seeding from outside the chart** (a CI step running `kubectl` or a Flux
  `Kustomization` with `dependsOn`). Decouples seeding from release success and
  removes the blast radius — the honest fix if the hook keeps taking releases
  down. It costs the ordering guarantee the hook provides for free.
- **`pre-upgrade` instead of `post-install`.** Would reseed on every upgrade,
  which is wrong for long-lived environments.
