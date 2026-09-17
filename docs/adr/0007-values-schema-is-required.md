# ADR-0007: `values.schema.json` requires every top-level section

- **Status:** Accepted
- **Date:** 2026-09-16 (decision predates this record)
- **Applies to:** `bjj-eire/artifact/values.schema.json`

## Context

The umbrella's values are four large nested trees — `bjj-mongodb`, `bjj-api`,
`bjj-frontend`, `seeder` — supplied by different consumers: this repository's
own files, an inline `values:` block in a Flux `HelmRelease`, and a ConfigMap
for preview environments.

Helm merges values silently. A typo in a key, or a `-f` overlay that replaces
rather than merges a section, produces a render that succeeds and a deployment
that is subtly wrong — a missing `env` entry, a default image tag, a probe
pointed at the wrong path.

## Decision

`values.schema.json` declares all four top-level sections in `required`. Helm
validates values against it on `template`, `install`, and `upgrade`, so a values
set missing a section fails immediately with a schema error rather than
rendering a partial release.

## Consequences

- Malformed values fail at render time, in CI, with a message naming the
  offending path — before anything reaches a cluster.
- Flux surfaces the same error on the `HelmRelease` rather than deploying a
  half-configured release.
- **Every consumer must supply all four sections**, including `seeder`, even
  when `seeder.enabled: false`. A minimal overlay that only sets an image tag
  still needs the rest to be present through the merge.
- Adding a top-level section to the chart is a breaking change for every
  consumer until they include it. Adding it to `required` and to `values.yaml`
  in the same commit keeps the default merge satisfying the schema.
- The schema constrains structure, not semantics. It will not catch an image
  tag that does not exist or a hostname that is wrong.
- Keeping the schema current is manual. A new values key with no schema entry is
  accepted silently, so the schema protects the sections it knows about and
  nothing else.

## Alternatives considered

- **No schema.** Helm's default. Rejected: the failure mode is a wrong
  deployment rather than a failed render, and with values arriving from three
  repositories that is a real risk.
- **Schema without `required`.** Would catch type errors but not a dropped
  section, which is the more likely mistake when overlays are written by hand.
- **Validation in CI only** (a `helm template` smoke test). Catches the same
  class of error for this repository's own files, but not for the values
  `bjjeire-gitops` supplies — and those are the ones that actually deploy
  ([ADR-0005](0005-environment-values-are-not-the-deployment-source.md)). The
  schema travels with the chart, so it validates every consumer.
