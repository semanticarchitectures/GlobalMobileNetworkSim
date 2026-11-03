# Implementation Plan — GMNS Python Port

**Spec:** `.kiro/specs/python-port/tasks.md`

> **Amendment A1 (2026-07-22) — Monorepo readiness.** Tasks 3, 5, 16, and 31 amended; tasks 33–34 added. See requirements.md Req 13 and design.md D8/D9.

> **Amendment A2 (2026-07-23) — Verification strategy revision.** Task 2 removed (no draw-file instrumentation); tasks 1, 3, 5, 7, 16, 17, 19, 26 amended; Phase 3 retitled; M1 redefined. See requirements.md Req 7 (rewritten) and design.md D2/D6/D9.

## Phase 0 — Freeze and Extract (baseline preparation)

- [ ] 1. *(Amended A2)* Tag the MATLAB repository as `matlab-baseline-v1.0`; record commit hash in this spec. *(Req 7.5)*
- [ ] ~~2. Instrument the MATLAB engine to export a draw file…~~ **Removed by A2** — no replay instrumentation; the baseline runs unmodified.
- [ ] 3. *(Amended A1/A2)* Generate comparison datasets from airdrop_mission and two additional coverage scenarios: event logs, stats/eval JSON, sampled position tables. Configure git-lfs before first commit and commit all datasets under `tests/comparison/` via LFS; add the >1 MB non-LFS CI guard. *(Req 7.3–7.4, 13.3)*
- [ ] 4. Build the MATLAB→Python test disposition table: enumerate all MATLAB test cases with target Python test ID or waiver rationale. *(Req 12.4)*

## Phase 1 — Core Engine

- [ ] 5. *(Amended A1/A2)* Scaffold as a uv workspace with GMNS as first member package in src-layout; ruff/mypy config; import-linter contracts for BOTH the core boundary (D6) and the extraction seams (`semantics`, codec registry, `tools/compare` free of GMNS-specific imports); CI skeleton implemented as reusable, path-filtered workflow files (lint → type → unit → verification → comparison → semantic → benchmark); create `ontology/cco.lock` as the single-source CCO pin consumed by all ontology tooling. *(Req 12.1, 12.3, 13.1, 13.2, 13.4, D6, D8)*
- [ ] 6. Implement `core/events.py` (frozen dataclass event taxonomy) and `core/engine.py` (heapq DES with (time, seq) ordering, fail-fast handler errors). Property-based ordering tests. *(Req 1.1–1.4, P31)*
- [ ] 7. *(Amended A2)* Implement `core/rng.py` with the `DrawSource` interface: `LiveSource` (PCG64 named streams spawned from scenario seed) and a fixed-sequence test-injection source for deterministic unit tests. *(Req 1.2, D2)*
- [ ] 8. Implement `core/geo.py` on GeographicLib; validate ≤1 m against golden position/distance tables; document Vincenty deviation. *(Req 2.1, 2.4, D3)*
- [ ] 9. Implement `core/mobility.py` (waypoint interpolation) and `core/orbit.py` (Keplerian propagation); validate against golden sampled positions (≤1 m / ≤10 m). *(Req 2.2, 2.3)*

## Phase 2 — Network, Outages, Routing

- [ ] 10. Implement `model/message.py`: payload-as-bytes, content-type, digest, codec registry with default JSON codec; serialize-once semantics; property-based relay-integrity tests. *(Req 8, P33)*
- [ ] 11. Implement `core/network.py`: node/link model, four link types, latency models (fiber 200,000 km/s, GEO ≥270 ms floor), bandwidth delay from payload length. *(Req 3.1, 3.2)*
- [ ] 12. Implement `core/outage.py`: Poisson arrivals; exponential/log-normal/fixed durations; all draws via `DrawSource`. *(Req 3.3, D2)*
- [ ] 13. Implement `core/routing.py`: Dijkstra with the matlab-network-sim edge-cost definition; cache invalidation on topology events; `NO_ROUTE` failure events; LOS activation/deactivation hooks. *(Req 3.4, 4.1–4.3)*
- [ ] 14. Implement `model/scenario.py` pydantic schema and loader; validate all repository scenarios load and run; document added strictness. *(Req 5, P35)*
- [ ] 15. Implement `io/` CSV event log and stats/eval JSON writers matching the MATLAB baseline's columns/keys/units. *(Req 6.1)*

## Phase 3 — Verification and Comparison (gate for everything downstream) *(retitled by A2)*

- [ ] 16. *(Rewritten A2)* Build `tools/verify/` first-principles benchmark suite per design.md §Verification Benchmarks: exact fiber-latency formula check, GEO floor invariant, message/byte conservation, determinism check, GeographicLib test-set validation, closed-form trajectory checks, two-body propagation vectors, outage-statistics convergence over ≥30 seeds. Wire as the blocking `verification` CI stage. *(Req 7.1–7.2, P32, P36)*
- [ ] 17. *(Rewritten A2)* Build `tools/compare/` (GMNS-import-free per Req 13.1): event-log differ and KS statistical comparison against the committed MATLAB comparison datasets. Execute the one-time differential comparison study on the reference scenarios; disposition every material discrepancy as (a) MATLAB defect / (b) Python defect / (c) benign difference; fix all (b) items; commit the Comparison Disposition Report as a release artifact. Then schedule the informative (non-blocking) comparison pipeline. *(Req 7.3–7.4, P32)*
- [ ] 18. Port remaining MATLAB unit tests per disposition table until table shows zero unmapped/unwaived cases; CI gate on the table. *(Req 12.4)*
- [ ] 19. *(Amended A2)* Add physics-tag CI gate: PRs touching `gmns/core/` must update or extend the first-principles verification tests, or carry an explicit no-behavior-change label confirmed by an unchanged verification-stage result. *(D6)*
- [ ] 20. Stand up benchmark stage: reference scenario wall clock vs 2× MATLAB-baseline budget; publish trend. *(Req 12.2)*

**Milestone M1 (end Phase 3, redefined by A2): Python engine verified — first-principles suite green, differential study fully dispositioned with no open Python defects. Python is authoritative from M1 onward; MATLAB remains a live frozen baseline per Req 7.5. M1 is also the earliest permitted monorepo fold-in point (task 34); fold-in earlier than M1 is prohibited (design.md risk table).**

## Phase 4 — Semantic Layer

- [ ] 21. Port `tools/semantic_validate.py` targets to Python engine outputs; commit `ontology/gmns.ttl`, `ontology/gmns-shapes.ttl` (from ontology-conformance spec) into this repo structure. *(matlab-network-sim Req 25)*
- [ ] 22. Implement `semantics/` + `io/` JSON-LD event log and `@context` for stats/eval JSON; regenerate semantic goldens from the Python engine. *(matlab-network-sim Req 26.1–26.2)*
- [ ] 23. Generate `ontology/term-bindings.json` from the ontology against the actual Python type names; CI gate on unbound exported types. *(matlab-network-sim Req 25.5)*
- [ ] 24. Wire SHACL zero-violation check and CQ1–CQ10 SPARQL suite into the CI semantic stage. *(matlab-network-sim Req 26.3–26.4)*

## Phase 5 — Agents and ICAM

- [ ] 25. Implement `agents/` LangGraph perceive→deliberate→act loop with scripted-policy deliberation; verify all agent traffic transits bound nodes (import-linter + runtime assertion tests). *(Req 9.1, 9.2, 9.4, P34)*
- [ ] 26. *(Amended A2)* Port Behavior Trace recording and Fidelity Scoring incl. network-constrained exclusion; validate against shared test vectors carried over from the MATLAB test suite. *(Req 9.3)*
- [ ] 27. Enable LLM deliberation (configurable endpoint); role Markdown files consumed unchanged as system prompts. *(Req 9.1)*
- [ ] 28. Implement `icam/`: Entity Registry, certificate lifecycle, AUTH handshake over the simulated network with timeout behavior validated in replay mode, PDP with policy JSON. *(Req 10.1, 10.2)*
- [ ] 29. Type all ICAM events in the semantic export; extend SHACL/CQ goldens accordingly. *(Req 10.3)*

## Phase 6 — MCP Exposure and Release

- [ ] 30. Implement `mcp/` FastMCP server: run-scenario, inspect-state, fetch-results tools with GMNS IRIs in responses; read/execute-only enforcement tests. *(Req 11)*
- [ ] 31. *(Amended A1/A2)* Container build (OCI, no commercial deps), CLI polish, README architecture section, authority/baseline governance doc (D6 table) and baseline-as-data procedure (D9) in repo root; verify relocation safety (resource access via `importlib.resources`, no repo-root assumptions) with a run-from-relocated-checkout CI check. *(Req 12.1, 7.5, 13.6)*
- [ ] 32. *(Amended A2)* Release `python-v1.0`: full CI green (verification, comparison-informative, semantic, benchmark, coverage ≥90% core); MATLAB branch marked comparison-baseline with the no-equivalence / no-mirroring policy (Req 7.5) in CONTRIBUTING. *(all)*

**Milestone M2 (end Phase 6): Python is the primary implementation; `uci-profile` and `c2sim-gateway` specs unblocked.**

## Phase 7 — Monorepo Fold-In *(added by Amendment A1; gated on M1, runs parallel to Phases 4–6)*

- [ ] 33. Author ADR `sa-monorepo`: workspace layout, public/private boundary and mirror strategy (private monorepo with public read-only mirror via subtree split for GMNS; decide whether public GMNS history is preserved via split or the existing repo becomes the mirror target), member-package migration order for the rest of the portfolio, and shared-package extraction plan for `sa-semantics` / `sa-codecs` / `sa-compare`. *(Req 13, D8, D9)*
- [ ] 34. Execute fold-in at or after M1 per ADR: run the Req 13.6 pre-fold hygiene audit (no client-sensitive/CUI-adjacent content, LFS verified, relocation-safety check green), relocate GMNS as a workspace member, re-point CI to the reusable workflows from the monorepo parent, and verify full CI green (verification, semantic, benchmark) post-move before any further feature work. *(Req 13, M1 gate)*

## Task Dependencies

Phase 0 → 1 → 2 → 3 strictly sequential at phase level *(A2: tasks 16 and 17 jointly block M1)*. Phases 4 and 5 may proceed in parallel after M1; task 29 depends on 22–24 and 28. Phase 6 requires M1 plus tasks 21–29. *(A1)* Task 33 may begin anytime; task 34 requires M1 and task 33, may run parallel to Phases 4–6, and blocks nothing except that no feature PRs merge during the relocation window.
