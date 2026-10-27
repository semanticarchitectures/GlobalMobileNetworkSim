# AGENTS.md

Conventions for AI coding tools working in this repo. The Kiro specs in `.kiro/specs/` are the
source of truth for what is built.

## Umbrella context (Acquisition Knowledge System)

- This repo is a component of the Acquisition Knowledge System: https://github.com/semanticarchitectures/acquisition-knowledge-system.
  Before cross-component work, read its `.kiro/steering/product.md` and `portfolio.md`.
- Shared contracts and the shared ontology (BFO 2020 and CCO, pinned once in the umbrella's
  `.kiro/steering/ontology.md`) are defined in the umbrella. Do not redefine them here.
- GMNS's ontology moves to the shared pin (CCO 2.2), which is an IRI migration from CCO 1.x, not a
  version bump. Its UCI-to-CCO mapping uses AOC-DFO's message classes (AKS ADR 0007).
- Shared code (`sa-semantics`, `sa-codecs`, `sa-compare`) keeps no GMNS-specific imports, so it can
  become a package other components consume (AKS ADR 0008, proposed).
- Tasks tagged for this repo in umbrella specs land here; cite them by spec and task number.
