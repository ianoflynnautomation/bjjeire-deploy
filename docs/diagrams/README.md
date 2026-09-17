# Diagrams

## `architecture.drawio.svg`

The chart and delivery topology. It is a **dual-format file**: a plain SVG that
GitHub renders inline anywhere it is referenced, carrying the draw.io model in
the root element's `content` attribute so the same file reopens as a fully
editable diagram.

It reads left to right as the delivery flow — chart source → GitHub Actions →
GHCR OCI artifacts → `bjjeire-gitops` → runtime. The red strip along the bottom
is deliberately **not** part of that flow: it collects the files that look like
deployment configuration and are not.

**To edit:**

- **VS Code** — install the *Draw.io Integration* extension and open the file;
  it opens as a canvas, not as markup.
- **Browser** — open [diagrams.net](https://app.diagrams.net/), then
  *File → Open from → Device*. Export with *File → Export as → SVG* and
  **"Include a copy of my diagram"** ticked, or the file stops being editable.

Keep the `.drawio.svg` extension — it is what signals the editable-SVG format
to both tools.

## Conventions

| Element | Meaning |
|---|---|
| Solid blue edge | Builds, publishes, or deploys |
| Dotted grey edge | Vendored as a chart dependency |
| Dashed amber edge | Image references supplied from elsewhere |
| Dashed purple edge | Automation or preview overlay |
| Solid green edge | Runtime data path |
| Dashed amber box | Conditional — off by default or environment-specific |
| Red panel | Not the deployment path |

## Scope

Two of the five columns belong to other repositories. `bjjeire-gitops` owns
deployment; the container images come from `bjjeire`. See
[../architecture.md](../architecture.md#repository-boundaries).

The Mermaid diagrams in [../ci-cd.md](../ci-cd.md) carry the workflow-level
detail — this file summarises each workflow as one box. Update the Mermaid for
workflow changes; reach for this file when the shape of delivery changes.
