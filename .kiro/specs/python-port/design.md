# Design Document — GMNS Python Port

**Spec:** `.kiro/specs/python-port/design.md`

> **Amendment A1 (2026-07-22) — Monorepo readiness.** Adds design decisions D8 (extraction seams and workspace layout) and D9, plus migration risk rows. Corresponds to requirements.md Amendment A1 (Req 12.1 revised, Req 13 added).

> **Amendment A2 (2026-07-23) — Verification strategy revision.** MATLAB demoted from oracle to comparison baseline; D2 simplified (draw-file replay removed); D6 authority table rewritten; D9 relabeled; §Parity Tolerances replaced by §Verification Benchmarks and Comparison Disposition; properties P32/P36 rewritten.

## Overview

Python is the primary, authoritative GMNS implementation; the MATLAB branch remains alive as a frozen comparison baseline with no equivalence claim. The design optimizes for three things: (1) verifiable engine correctness against first-principles ground truth and published reference vectors, cross-checked once by a dispositioned differential comparison with MATLAB, (2) a stable core that the standards-facing layers (semantics, UCI, C2SIM, agents, MCP) attach to without engine modification, and (3) deployability into government evaluation environments without commercial licenses.

**Goals:** engine correctness *(A2: verified first-principles, not parity)*, scenario/output compatibility, UCI-ready message model, LangGraph agent layer, semantic exports, MCP exposure.
**Non-goals:** UCI codec and profile (spec `uci-profile`), C2SIM gateway (spec `c2sim-gateway`), new physics, GUI.

## Package Architecture

```
gmns/
├── core/            # Physics-tagged: verification-governed (D6, Req 7)
│   ├── engine.py    # DES loop, event queue, clock
│   ├── events.py    # Event taxonomy (frozen dataclasses)
│   ├── geo.py       # WGS-84 geodesy (geographiclib)
│   ├── orbit.py     # Keplerian propagation
│   ├── mobility.py  # Waypoint interpolation, position schedule
│   ├── network.py   # Nodes, links, bandwidth/latency models
│   ├── outage.py    # Poisson arrivals, duration distributions
│   ├── routing.py   # Dijkstra over active topology, cache
│   └── rng.py       # Seeded streams + deterministic-replay draw source
├── model/           # Scenario & message data model
│   ├── scenario.py  # pydantic schema, loader, validation
│   └── message.py   # Payload-as-bytes, codec registry (Req 8)
├── io/              # Boundary: CSV/JSON writers, JSON-LD/Turtle semantic export,
│   └── ...          # term-bindings loader, golden-file utilities
├── semantics/       # gmns.ttl bindings, SHACL runner hooks (CI-facing)
├── agents/          # LangGraph role emulation, traces, fidelity scoring
├── icam/            # Registry, certificates, AUTH, PDP
├── mcp/             # FastMCP server
└── cli.py
tools/
├── verify/          # First-principles benchmark suite (A2)
├── compare/         # Event-log differ + statistical comparison vs MATLAB datasets (A2)
└── semantic_validate.py
```

*(Amended A1)* The tree above lives under `src/gmns/` in a uv workspace whose root `pyproject.toml` is prepared for additional member packages; `tools/` are workspace scripts. The single-source CCO pin lives at `ontology/cco.lock` (Req 13.4).

Dependency rules (enforced by import-linter in CI): `core` imports nothing from `agents`, `icam`, `mcp`, `semantics`, or `io` — standards layers observe the engine through events and the message codec interface only. *(Amended A1/A2)* Additionally, `semantics`, `model.message` (codec registry), and `tools/compare` import nothing from any `gmns`-specific package (Req 13.1).

## Key Design Decisions

### D1 — Deterministic event ordering
Event queue is `heapq` keyed on `(time, seq)` where `seq` is a monotonic insertion counter, reproducing the MATLAB min-heap's FIFO tie-breaking. All iteration over collections that feed event insertion uses explicitly sorted keys — no dict-order dependence. This is the foundation of Req 1.2 determinism.

### D2 — Randomness *(rewritten by Amendment A2)*
NumPy `Generator(PCG64)` with per-subsystem named streams spawned from the scenario seed gives full determinism (Req 1.2) without any cross-implementation replay machinery. Every stochastic call site in `core` still draws from an injected `DrawSource` interface — retained not for MATLAB replay but because injection makes unit tests deterministic (fixed-sequence sources for outage-logic tests) and keeps stochastic coupling explicit. Statistical correctness is demonstrated first-principles: measured outage inter-arrivals and durations converge to configured parameters within confidence bounds over seeded batches (Req 7.1); comparison with MATLAB distributions is informative only (Req 7.4).

### D3 — Geodesy substitution
GeographicLib replaces Vincenty deliberately (Karney's algorithm converges where Vincenty can fail near-antipodally and is more accurate). Correctness is established against GeographicLib's published test set (Req 7.2); the delta versus MATLAB Vincenty is recorded in the Comparison Disposition Report as a benign implementation difference — an intended improvement, not a defect. *(Amended A2)*

### D4 — Data layout: clarity first, SoA later
Plain frozen dataclasses for nodes/links/messages initially, not a NumPy struct-of-arrays mirror of the MATLAB layout. Rationale: reference scenarios are ~10² nodes / ~10³ events where object overhead is immaterial; premature SoA would complicate the port. `core.network` keeps state access behind accessor functions so hot paths can be vectorized later without API change if Req 12.2's benchmark demands it.

### D5 — Message payloads are bytes (UCI readiness)
`Message` carries `payload: bytes`, `content_type: str`, `digest: str`. Transmission delay = f(len(payload), link bandwidth). Codec registry maps content types to encode/decode; default JSON codec ships now, UCI codec registers later with zero engine change. Serialize-once at send; relays forward bytes untouched; delivery verifies digest (Req 8).

### D6 — Authority and baseline governance *(rewritten by Amendment A2; supersedes the former parity boundary)*

| Concern | Authoritative implementation | MATLAB baseline obligation |
|---|---|---|
| All simulator behavior (physics, routing, outages, geodesy, orbits) | Python, verified per Req 7.1–7.2 | None — frozen at pinned tag; no mirroring |
| Scenario schema, outputs, semantics, UCI, C2SIM, agents, ICAM, MCP | Python | Never touches MATLAB |
| Comparison scenarios remaining runnable | — | Only permitted MATLAB change class; each change logged in the disposition log (Req 7.5) |

Modules under `gmns/core/` remain physics-tagged, but the CI gate now serves verification rather than parity: a PR modifying physics-tagged modules must update or extend the first-principles verification tests (Req 7.1–7.2) or carry an explicitly reviewed no-behavior-change label.

### D7 — Agent layer
LangGraph graph per agent: `perceive (inbox drain) → deliberate (LLM or scripted policy) → act (emit intents)`. Intents become engine send-events through the agent's bound node — the engine is the only transport (Req 9.2). Scripted policies make the engine testable without LLM calls (Req 9.4). Traces and fidelity scoring reuse the MATLAB algorithm, ported with its unit tests; network-constrained annotation logic is shared with the semantic export (`gmns:networkConstrained`).

### D8 — Extraction seams and workspace layout *(added by Amendment A1)*
Three components are built as monorepo shared-package candidates from day one: `semantics` → `sa-semantics` (CCO pinning, SHACL runner, term-binding generation), the codec registry in `model/message.py` → `sa-codecs` (UCI/C2SIM codecs will register here and serve other simulations), and `tools/compare` → `sa-compare` (generic event-log differ + statistical comparison toolkit, usable by any SA simulation with a reference dataset) *(renamed from sa-parity by A2)*. Each carries an import-linter contract forbidding GMNS-specific imports, so extraction is a directory move plus a pyproject entry — no refactoring. The uv workspace + src-layout means the monorepo fold-in relocates the member package without touching import paths. CI stages are reusable, path-filtered workflow files (Req 13.2) so the monorepo adopts them by reference; other SA projects gain the semantic stage the same way.

### D9 — The comparison baseline participates as data, not as code *(added A1, revised A2)*
MATLAB never enters this repository or its CI. Comparison evidence flows one way: a separately provisioned, licensed runner executes the tagged baseline and publishes comparison datasets (event logs, stats, sampled positions), committed here via git-lfs. The scheduled informative comparison (Req 7.4) and the one-time differential study (Req 7.3) consume these artifacts. Dataset-refresh PRs reference the baseline tag and runner job, keeping every comparison auditable while the monorepo stays free of commercial-license CI dependencies.

## Verification Benchmarks and Comparison Disposition *(replaces §Parity Tolerances, Amendment A2)*

**First-principles benchmarks (blocking, Req 7.1–7.2):**

| Check | Ground truth | Tolerance |
|---|---|---|
| Fiber latency | distance ÷ 200,000 km/s | Exact (floating-point equality of the formula) |
| GEO latency floor | ≥ 270 ms one-way | Invariant — never violated |
| Message conservation | sent = delivered + explicitly failed; relay byte balance | Exact |
| Determinism | fixed seed ⇒ byte-identical event logs | Exact |
| Geodesy | GeographicLib published test set | ≤ 1 mm distance |
| Trajectory interpolation | closed-form great-circle positions | ≤ 1 m |
| Orbital propagation | published two-body vectors (24 h) | ≤ 10 m |
| Outage statistics | configured Poisson/duration parameters | within 99% confidence bounds, ≥ 30 seeds |

**Comparison disposition categories (Req 7.3–7.4, non-blocking after M1):** every material Python-vs-MATLAB discrepancy is classified (a) MATLAB defect (documented; MATLAB optionally left as-is), (b) Python defect (fixed before M1), or (c) benign implementation difference (documented with rationale, e.g., Karney vs Vincenty). The Comparison Disposition Report is a release artifact and a client-facing V&V exhibit.

## Correctness Properties

Properties 1–26 (matlab-network-sim) and 27–30 (semantic) remain normative and are re-implemented as Python tests. New:

31. With a fixed seed and configuration, two runs produce byte-identical event logs. (Req 1.2)
32. *(A2)* All first-principles benchmarks in §Verification Benchmarks pass in CI, and the differential comparison study contains no undispositioned discrepancies and no open category-(b) defects at M1. (Req 7.1–7.3)
33. Delivered payload bytes are digest-identical to sent bytes across any number of relay hops. (Req 8.3)
34. No code path in `gmns.core` imports from standards-facing packages, and no agent traffic bypasses a bound node. (D6, Req 9.2)
35. Every repository scenario loads, validates, and completes under the Python engine. (Req 5.1)
36. *(A2)* Across ≥ 30 seeded runs, measured outage inter-arrival and duration statistics converge to configured parameters within 99% confidence bounds. (Req 7.1)

## Testing Strategy

1. **Unit tests** ported 1:1 from the MATLAB suite with a disposition table for waivers (Req 12.4).
2. **Property-based tests** (hypothesis): queue ordering invariants, routing on random topologies, payload integrity under random relay paths.
3. **Verification & comparison** (`tools/verify/`, `tools/compare/`): first-principles benchmark suite on every merge; one-time differential study with disposition report before M1; scheduled informative statistical comparison thereafter (Req 7).
4. **Semantic stage**: unchanged from matlab-network-sim Req 26 — SHACL zero-violation + CQ1–CQ10 goldens, now against the Python export.
5. **Benchmark**: reference-scenario wall clock tracked in CI against the 2× budget (Req 12.2).

## Error Handling

Scenario errors are load-time and specific (pydantic). Runtime engine errors are fail-fast with event context (Req 1.4). Absence-of-route and AUTH timeout are modeled outcomes, not exceptions. Semantic-export typing gaps degrade to `gmns:UnclassifiedRecord` with a warning (matlab-network-sim Req 26.5).

## Risks

| Risk | Mitigation |
|---|---|
| Latent defects in either implementation *(A2)* | First-principles benchmarks catch ground-truth violations; differential study forces explicit adjudication of every discrepancy |
| Silent MATLAB/Python divergence over time *(A2)* | By design, no equivalence is claimed (Req 7.5); scheduled informative comparison surfaces drift as disposition entries |
| Oracle drift as Python gains features | ~~Superseded by A2~~ — MATLAB frozen; no mirroring obligation exists to drift from |
| Draw-file instrumentation perturbs oracle behavior | ~~Removed by A2~~ — no instrumentation |
| Performance regression vs MATLAB vectorization | D4 accessor seam enables targeted vectorization; CI benchmark gate |
| LLM nondeterminism contaminating engine tests | Scripted-agent mode isolates engine determinism from agent stochasticity |
| Monorepo fold-in destabilizes the port if attempted mid-verification *(A1, reworded A2)* | Fold-in gated at Milestone M1 (verification suite green, differential study dispositioned); Req 13 readiness criteria make the move mechanical; pre-fold hygiene audit (Req 13.6) |
| Public-mirror leakage of sensitive content *(A1)* | Req 13.6 audit checklist run before fold-in and before any mirror split; GMNS repo policy: client-sensitive material never committed |
