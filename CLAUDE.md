# CLAUDE.md — GMNS Python Port

Guidance for Claude Code working in this repository. Read the three spec files under
`.kiro/specs/python-port/` (`requirements.md`, `design.md`, `tasks.md`) before starting
any task; they are normative and include two amendments (A1, A2) that override earlier
text where marked. This file is the short version of the constraints that are easy to
violate by writing "obvious" code that contradicts a decision already made.

## What this project is

Port the GlobalMobileNetworkSim discrete-event network simulation from MATLAB to Python.
Python is the **primary, authoritative** implementation. The existing MATLAB version is a
**frozen comparison baseline** — not an oracle, not a spec. It was tested against its own
specification, never independently verified, so it may contain latent defects. We do not
replicate its behavior; we verify against first principles and compare informatively.

The port exists to enable a standards-facing roadmap that is impractical in MATLAB:
real UCI message exchange over the simulated network, C2SIM interoperation, BFO/CCO
semantic exports, LangGraph agent emulation, and MCP exposure. GMNS is a component of the
Acquisition Knowledge System (AKS, umbrella ADR 0007). The umbrella repo,
`acquisition-knowledge-system`, holds specs and decisions only; it is not a monorepo. Whether
GMNS ever folds into a monorepo, or shares its seams as versioned packages instead, is open
(umbrella ADR 0008, proposed).

## Non-negotiable governance (violating these wastes work)

1. **MATLAB is never invoked in this repo's CI** (Req 7.5, 13.5, design D9). CI consumes
   only committed comparison datasets under `tests/comparison/` (git-lfs). MATLAB runs on a
   separate licensed machine and publishes those datasets. Do not add a MATLAB step, a
   `matlab` dependency, or any code that shells out to MATLAB.

2. **No parity/replay machinery** (Amendment A2 removed it). There is no draw-file import,
   no `ReplaySource`, no record-for-record event-log matching against MATLAB, no tolerance
   table. If you find yourself building any of these, stop — that was the pre-A2 design.
   Correctness comes from `tools/verify/` (first-principles benchmarks against closed-form
   ground truth and published reference vectors), not from matching MATLAB.

3. **Core isolation** (design D6). Nothing in `src/gmns/core/` may import from `agents`,
   `icam`, `mcp`, `semantics`, or `io`. Enforced by import-linter; keep it green.

4. **Extraction seams stay GMNS-free** (Req 13.1, design D8). `src/gmns/semantics/`, the
   codec registry in `src/gmns/model/message.py`, and `tools/compare/` must not import any
   GMNS-specific module — they are the future shared packages `sa-semantics`, `sa-codecs`,
   `sa-compare`. Import-linter enforces this too.

5. **Determinism** (Req 1.2). Fixed seed + fixed config ⇒ byte-identical event logs.
   Event queue is `heapq` keyed `(time, seq)` with a monotonic `seq` for FIFO tie-breaking.
   Never iterate dicts/sets in a way that feeds event insertion order; sort explicitly.

6. **Payloads are bytes** (Req 8, design D5). Messages carry `payload: bytes`,
   `content_type`, `digest`. Transmission delay is computed from `len(payload)`. Serialize
   once at send; relays forward bytes untouched; verify digest on delivery. This is what
   makes the later UCI codec a drop-in — do not shortcut it with a size-only abstraction.

7. **git-lfs before first large commit** (Req 13.3). Comparison datasets and any binary
   test artifact go through LFS from their first commit. CI fails on >1 MB non-LFS files.

8. **Single-source CCO pin** (Req 13.4). The pinned CCO release lives only in
   `ontology/cco.lock`. All ontology tooling reads it there; never hard-code the version
   elsewhere. It is the AKS shared pin (umbrella ADR 0006): change it in the umbrella's
   ontology steering first, never here alone. CCO is vendored in `ontology/imports/` (git-lfs),
   hash-checked against `cco.lock`, and resolved through `ontology/catalog-v001.xml`; never
   load it over the network. The ontology files `ontology/gmns.ttl` and
   `ontology/gmns-shapes.ttl` already exist (authored separately) and validate against the
   pinned release.

## Stack and layout

- Python 3.11+, uv workspace, src-layout. GMNS is the first workspace member; the root is
  prepared for more. `pip install`-able, OCI-containerizable, **no commercial-license deps**.
- Tooling: `heapq` (DES), GeographicLib (geodesy — deliberately replaces Vincenty, validated
  against its own published test set), sgp4/skyfield (orbits), networkx (routing), pydantic
  (scenario schema), NumPy PCG64 (seeded RNG), LangGraph (agents), FastMCP (MCP),
  rdflib + pyshacl (semantic CI stage).
- CI stages as reusable path-filtered workflow files (Req 13.2):
  lint (ruff) → type (mypy strict on `core`) → unit → verification → comparison(informative)
  → semantic → benchmark. Coverage ≥90% on `gmns.core`.

```
src/gmns/{core,model,io,semantics,agents,icam,mcp}/   cli.py
tools/{verify,compare}/   tools/semantic_validate.py
ontology/{gmns.ttl,gmns-shapes.ttl,cco.lock,term-bindings.json}
tests/{unit,property,semantic,comparison(lfs)}/
scenarios/   .kiro/specs/python-port/   CLAUDE.md   pyproject.toml
```

## Where to start and how to work

- **Begin at task 5** (workspace scaffold + import-linter contracts + CI skeleton +
  `cco.lock`). Tasks 1 and 3 are MATLAB-side dataset capture done on the licensed machine,
  not here; task 2 was removed by A2. Do not block on them — the verification suite
  (task 16) does not need MATLAB; the comparison study (task 17) does and runs when those
  datasets land.
- **Work task-by-task in the order in tasks.md.** Phase 3 (tasks 16–20) is the gate: do not
  start Phases 4–6 until Milestone M1 (verification suite green, differential study
  dispositioned, no open Python defects). Check the box in tasks.md as each completes.
- **Each task is a small PR**: implementation + its tests + green CI. Prefer extending the
  verification suite over adding assertions that merely restate MATLAB output.
- **When a requirement seems wrong or underspecified, stop and ask** rather than guessing —
  the specs encode decisions with reasons, and a few are counterintuitive on purpose
  (MATLAB-as-baseline-not-oracle is the big one). Surfacing a real spec gap is useful;
  silently coding around it is not.
- **Do not fold into a monorepo** (tasks 33–34) until M1, and not at all unless umbrella
  ADR 0008 chooses that model. Build here as a standalone repo;
  the readiness constraints above make the later move mechanical.

## Quick self-check before committing

- Did I invoke or depend on MATLAB anywhere in repo code or CI? (must be no)
- Does `core/` still import only from `core/` and stdlib/third-party? (import-linter green)
- Do the seam packages still avoid GMNS imports? (import-linter green)
- Fixed seed ⇒ identical event log? (determinism test green)
- New physics in `core/`? Then I updated/extended `tools/verify/`, not a MATLAB comparison.
- Any new binary/dataset committed through git-lfs?
