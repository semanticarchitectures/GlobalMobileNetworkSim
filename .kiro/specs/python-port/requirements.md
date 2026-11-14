# Requirements Document — GMNS Python Port

**Spec:** `.kiro/specs/python-port/requirements.md`
**Related specs:** `matlab-network-sim` (Requirements 1–26 remain normative for engine behavior; Requirements 25–26 ontology conformance carry over unchanged)

> **Amendment A1 (2026-07-22) — Monorepo readiness.** The Semantic Architectures monorepo migration is planned, with GMNS fold-in targeted at Milestone M1. This amendment revises Requirement 12.1 and adds Requirement 13 so the port is executed with monorepo-compatible packaging, extraction seams, CI structure, and repository hygiene from the outset. The migration itself is out of scope for this spec (see ADR `sa-monorepo`, pending).

> **Amendment A2 (2026-07-23) — Verification strategy revision.** The MATLAB implementation is demoted from verification oracle to comparison baseline: it was tested against its own specification, never independently verified, so exact-parity replication would reproduce latent defects and benign implementation differences alike. Requirement 7 is rewritten around first-principles verification (analytical ground truth, published reference vectors, conservation properties) with MATLAB comparison retained as a one-time dispositioned study plus an ongoing informative (non-blocking) check. Python is authoritative for all behavior; the MATLAB branch stays alive and runnable as a frozen baseline with no equivalence claim and no mirroring obligation. Requirements 2.1–2.3, 6.2, 9.3, 10.2, and 13.5 amended accordingly; draw-file replay infrastructure removed.

> **Amendment A3 (2026-11-12) — Port deferred; MATLAB is authoritative.** This reverses the authority direction of Amendment A2. The MATLAB implementation is the **authoritative, actively-developed** source for GMNS; the Python port is **deferred and not started** (no `src/gmns/`, no `pyproject.toml`). A2's premise — Python primary, MATLAB a frozen comparison baseline — no longer holds and is superseded in full by A3; A1 and A2 are retained below only as historical record of the planned port. Since the port never began, no requirement in this document describes current work, so none is edited individually. Two facts invalidate the plan's starting assumptions and must be reconciled before any reactivation: (1) MATLAB kept growing after this spec was written — the `+fabric`, `+data`, and `+security` packages (Phase 10–11 work) did not exist when Requirements 1–26 were framed, so a port would target a larger codebase than specified here; (2) the ontology moved to the AKS umbrella's shared CCO 2.2 pin (umbrella ADR 0006), so Requirement 13.4's "single-source pin" now means the umbrella-owned pin mirrored in `ontology/cco.lock`, not a GMNS-local one. The umbrella records this decision as AKS ADR 0011. **Reactivation requires a further amendment re-scoping the task list against the then-current MATLAB codebase before any code is written.** Until then, treat this spec as a dormant plan, not a work order.

## Introduction

> Superseded by A3 — the following paragraph reflects the deferred plan, not current direction.

Port the GlobalMobileNetworkSim discrete-event simulation core from MATLAB to Python, establishing Python as the primary, authoritative implementation and the MATLAB branch as a live comparison baseline. The port enables the standards-facing roadmap (UCI message exchange, C2SIM interoperation, BFO/CCO semantic exports, LangGraph agent emulation, MCP exposure) that is impractical in MATLAB, while demonstrating engine correctness through first-principles verification and a dispositioned differential comparison rather than replication of unverified behavior.

Non-goals for this spec: the UCI message profile and codec (separate spec `uci-profile`), the C2SIM gateway (separate spec `c2sim-gateway`), any new network-physics features, and the monorepo migration itself (governed by ADR `sa-monorepo`; this spec only guarantees readiness per Requirement 13).

---

### Requirement 1 — Discrete-Event Engine Semantics *(retitled A2)*

**User Story:** As a simulation engineer, I want the Python DES engine to implement the event semantics specified in matlab-network-sim, so that ported results remain traceable to the specification the MATLAB implementation was built against.

**Acceptance Criteria:**

1.1. THE SYSTEM SHALL implement a discrete-event engine with a priority queue ordered by (simulation_time, insertion_sequence), guaranteeing FIFO processing of simultaneous events identical to the MATLAB min-heap engine.

1.2. WHEN the same scenario is executed twice with identical seeds and configuration, THE SYSTEM SHALL produce byte-identical event logs (full determinism).

1.3. THE SYSTEM SHALL support the complete event vocabulary of the MATLAB engine (message send, hop transmit, delivery, delivery failure, outage start, outage end, node position update, agent action, ICAM events), with no event type silently dropped or merged.

1.4. WHEN an event handler raises an error, THE SYSTEM SHALL halt with a diagnostic identifying the event, simulation time, and scenario element — never continue with corrupted state.

### Requirement 2 — Geodesy and Mobility

**User Story:** As a scenario author, I want node positions and distances computed to documented accuracy on the WGS-84 ellipsoid, so that latency and coverage results are defensible.

**Acceptance Criteria:**

2.1. *(Amended A2)* THE SYSTEM SHALL compute geodesic distances on the WGS-84 ellipsoid using GeographicLib (Karney's algorithm), validated against GeographicLib's published geodesic test data within the tolerance in design.md §Verification Benchmarks; the difference from the MATLAB Vincenty implementation SHALL be recorded in the Comparison Disposition Report as a benign implementation difference.

2.2. *(Amended A2)* THE SYSTEM SHALL support waypoint-based trajectory interpolation for mobile nodes, verified against closed-form positions on analytic trajectories (constant-speed great-circle segments) with error ≤ 1 meter at sampled timestamps.

2.3. *(Amended A2)* THE SYSTEM SHALL propagate satellite node positions from Keplerian orbital elements, validated against published two-body propagation test vectors (e.g., Vallado) within 10 meters at sampled timestamps over a 24-hour scenario; MATLAB comparison is informative only.

2.4. WHERE a scenario supplies coordinates outside valid WGS-84 ranges, THE SYSTEM SHALL reject the scenario at load time with a specific validation error.

### Requirement 3 — Network and Outage Model

**User Story:** As an analyst, I want the four link types and stochastic outage model preserved exactly, so that stress results are comparable across implementations.

**Acceptance Criteria:**

3.1. THE SYSTEM SHALL implement Fiber, GEO satellite, LEO satellite, and Line-of-Sight link types with the reference latency models, including fiber propagation at 200,000 km/s over ellipsoid distance and a GEO one-way latency floor of 270 ms.

3.2. THE SYSTEM SHALL implement bandwidth-constrained transmission delay computed from measured payload size in bytes (see Requirement 8).

3.3. THE SYSTEM SHALL implement Poisson outage arrivals with exponential, log-normal, and fixed duration distributions per link configuration.

3.4. WHEN a Line-of-Sight constraint is violated by node movement, THE SYSTEM SHALL deactivate the link and trigger route recomputation, per the matlab-network-sim specification.

### Requirement 4 — Routing

**Acceptance Criteria:**

4.1. THE SYSTEM SHALL compute least-cost routes with Dijkstra's algorithm over the active topology, with the same edge-cost definition as the MATLAB implementation.

4.2. WHEN topology changes (outage start/end, LOS activation/deactivation, node mobility events affecting links), THE SYSTEM SHALL invalidate affected cached routes before the next routing decision.

4.3. WHERE no route exists between source and destination, THE SYSTEM SHALL record a delivery failure event with cause `NO_ROUTE`, not an exception.

### Requirement 5 — Scenario Compatibility

**User Story:** As an existing user, I want every current scenario file to run unmodified, so that the port does not orphan prior work.

**Acceptance Criteria:**

5.1. THE SYSTEM SHALL load all scenario files in the repository's `scenarios/` directory without modification.

5.2. THE SYSTEM SHALL validate scenarios against a published schema (pydantic) at load time, with error messages identifying file, path, and offending value.

5.3. WHERE the Python schema is stricter than MATLAB's parser, THE SYSTEM SHALL document each added constraint in the schema module and CI SHALL verify all repository scenarios still pass.

### Requirement 6 — Output Compatibility

**Acceptance Criteria:**

6.1. THE SYSTEM SHALL emit the CSV event log and statistics/evaluation JSON with the same columns, keys, and units as the MATLAB implementation, plus the semantic exports of matlab-network-sim Requirement 26.

6.2. *(Amended A2)* Numeric values in statistics outputs SHALL satisfy the analytical and reference-vector checks of Requirement 7.1–7.2; differences from MATLAB comparison datasets are handled through the disposition process of Requirement 7.3–7.4 and are not acceptance criteria.

### Requirement 7 — First-Principles Verification and MATLAB Comparison *(rewritten by Amendment A2)*

**User Story:** As a V&V lead, I want engine correctness demonstrated against ground truth and cross-checked by independent comparison, so that the correctness claim does not rest on either implementation's self-consistency.

**Acceptance Criteria:**

7.1. **Analytical verification.** CI SHALL verify engine outputs against closed-form ground truth on every merge: fiber latency exactly equals ellipsoid distance ÷ 200,000 km/s; the GEO one-way floor of 270 ms is never violated; conservation holds (every sent message is delivered or explicitly failed with cause; payload byte counts balance across relay hops); and, over seeded batches, measured outage inter-arrival and duration statistics converge to the configured Poisson and distribution parameters within stated confidence bounds.

7.2. **Reference-vector validation.** Geodesy SHALL validate against GeographicLib's published test set and orbital propagation against published two-body test vectors, per the tolerances in design.md §Verification Benchmarks.

7.3. **Differential comparison study (one-time, bounded).** At engine completion, the reference scenarios SHALL be executed on both implementations and every material discrepancy dispositioned as (a) MATLAB defect, (b) Python defect, or (c) benign implementation difference, in a committed Comparison Disposition Report. Category (b) items SHALL be fixed before Milestone M1; the report is a release artifact.

7.4. **Ongoing comparison (informative, non-blocking).** A scheduled pipeline SHALL run statistical comparison (Kolmogorov–Smirnov at α = 0.01 on end-to-end latency and outage-fraction distributions, ≥ 30 seeds) against committed MATLAB comparison datasets; divergences SHALL open disposition entries and SHALL NOT gate merges.

7.5. **Authority and baseline governance.** Python is authoritative for all simulator behavior. The MATLAB branch is a live, frozen comparison baseline referenced by pinned tag: no equivalence is claimed, no Python change is mirrored to MATLAB, and MATLAB SHALL change only as needed to keep comparison scenarios runnable, with each such change recorded in the disposition log.

### Requirement 8 — UCI-Ready Message Model

**User Story:** As the future uci-profile implementer, I want the message model to carry real serialized payloads, so that UCI integration requires no engine change.

**Acceptance Criteria:**

8.1. THE SYSTEM SHALL represent message payloads as opaque bytes plus a content-type tag; transmission delay SHALL be computed from actual payload length.

8.2. THE SYSTEM SHALL serialize each payload exactly once at send time; relaying SHALL NOT re-serialize.

8.3. THE SYSTEM SHALL preserve payload integrity end-to-end: delivered bytes SHALL be identical to sent bytes, verified by digest in tests.

8.4. The message API SHALL accept a pluggable codec interface (encode/decode/content-type) with a default JSON codec, such that the UCI codec registers without engine modification.

### Requirement 9 — Agent Layer

**Acceptance Criteria:**

9.1. THE SYSTEM SHALL implement LLM agent role emulation as a LangGraph application consuming the existing Markdown Role Specifications unchanged.

9.2. All agent message traffic SHALL pass through the agent's bound Communication Node and be subject to simulated network constraints; no out-of-band channel SHALL exist.

9.3. *(Amended A2)* THE SYSTEM SHALL record Behavior Traces and compute Fidelity Scores per the MATLAB specification, including exclusion of network-constrained missed actions, with the ported algorithm validated against shared test vectors carried over from the MATLAB test suite (disposition table, Req 12.4).

9.4. WHERE no LLM endpoint is configured, THE SYSTEM SHALL run scripted-agent scenarios end-to-end (engine has no hard LLM dependency).

### Requirement 10 — ICAM Layer

**Acceptance Criteria:**

10.1. THE SYSTEM SHALL port the Entity Registry, certificate lifecycle (issue, expire, revoke), first-contact AUTH handshake (AUTH_REQUEST/RESPONSE/TIMEOUT), and policy decision point, preserving MATLAB-specified behavior.

10.2. *(Amended A2)* AUTH exchanges SHALL traverse the simulated network and SHALL time out when path latency or outages exceed the configured window, verified by scenario-level tests constructed from the analytical latency model (Req 7.1).

10.3. Every ICAM event SHALL appear in the semantic export typed per the GMNS ontology (gmns:ActOfAuthentication, gmns:PolicyDecision, etc.).

### Requirement 11 — MCP Exposure

**Acceptance Criteria:**

11.1. THE SYSTEM SHALL expose scenario execution, state inspection, and results retrieval as an MCP server (FastMCP), with tool responses carrying GMNS class IRIs per the term-binding table.

11.2. The MCP server SHALL be read/execute only: no tool SHALL mutate a completed run's recorded results.

### Requirement 12 — Packaging, Performance, and Quality Gates

**Acceptance Criteria:**

12.1. *(Amended A1)* THE SYSTEM SHALL be structured as a uv workspace with src-layout packages, install via `pip install` (pyproject.toml), run on Python 3.11+, and build as an OCI container with no MATLAB or other commercial-license dependency. GMNS SHALL be the workspace's first member package, with the workspace root prepared to host additional members.

12.2. Wall-clock runtime for the reference scenario SHALL NOT exceed 2× the MATLAB baseline on equivalent hardware at port completion, with a tracked benchmark in CI.

12.3. THE SYSTEM SHALL maintain ≥ 90% line coverage on `gmns.core` and pass ruff + mypy (strict on `gmns.core`) in CI.

12.4. The full MATLAB test intent SHALL be preserved: every MATLAB test case SHALL map to a Python test or be explicitly waived in a tracked disposition table; CI SHALL fail on unmapped, unwaived cases.

### Requirement 13 — Monorepo Readiness *(added by Amendment A1)*

**User Story:** As the maintainer of the planned Semantic Architectures monorepo, I want GMNS built with clean extraction seams, portable CI, and repository hygiene, so that fold-in at Milestone M1 is a mechanical relocation with no refactoring.

**Acceptance Criteria:**

13.1. **Extraction seams.** *(Amended A2)* The `semantics` package (with `tools/semantic_validate.py`), the message codec registry, and the comparison tooling (`tools/compare/`) SHALL contain no GMNS-specific imports, enforced by import-linter contracts in CI. These are the designated future shared packages (`sa-semantics`, `sa-codecs`, `sa-compare`) and SHALL be extractable without code change.

13.2. **Portable CI.** *(Amended A2)* All CI stages (lint, type, unit, verification, comparison, semantic, benchmark) SHALL be implemented as reusable, path-filtered workflow files invocable from a parent workflow, such that monorepo CI can adopt them by reference without duplication.

13.3. **Large-artifact storage.** *(Amended A2)* Comparison datasets and any binary test artifacts SHALL be stored via git-lfs from their first commit; CI SHALL fail if a file exceeding 1 MB is committed outside LFS.

13.4. **Single-source CCO pin.** The pinned CCO release SHALL be recorded in exactly one file (`ontology/cco.lock`), read by the ontology header tooling, `semantic_validate.py`, and the term-binding generator; no other file SHALL hard-code the CCO version.

13.5. *(Amended A2)* **Comparison baseline as data.** The MATLAB baseline SHALL remain in its own repository, referenced by pinned tag; this repository's CI SHALL consume only committed comparison datasets and SHALL NOT invoke MATLAB. Baseline runs occur on a separately provisioned licensed runner that publishes comparison artifacts.

13.6. **Public-mirror hygiene.** THE SYSTEM SHALL contain no client-sensitive or CUI-adjacent content (verified by a pre-fold audit checklist), and SHALL make no assumptions about repository root location (resource access via `importlib.resources`, configuration via environment or explicit paths), so the repository can serve as, or be split to, a public read-only mirror of the monorepo subtree.
