# CLAUDE.md — GlobalMobileNetworkSim (GMNS)

Guidance for AI coding tools working in this repository. The Kiro specs in `.kiro/specs/`
are the source of truth for what is built. This file is the short version of the standing
decisions that are easy to violate by writing "obvious" code that contradicts one.

> **Authority note (Amendment A3, 2026-11-12).** The **MATLAB implementation is the
> authoritative, actively-developed source** for GMNS. The Python port described under
> `.kiro/specs/python-port/` is **deferred and not started** — no `src/gmns/`, no
> `pyproject.toml` exists, and none is expected until the port is explicitly reactivated.
> This reverses Amendment A2 of the python-port specs (which had made Python primary and
> MATLAB a frozen baseline); A2 is superseded by A3 and retained only as historical record.
> Do not treat the python-port spec set as describing current work. See
> `.kiro/specs/python-port/requirements.md` Amendment A3 for the full disposition. The
> umbrella records the same decision as AKS ADR 0011.

## What this project is

GMNS is a MATLAB discrete-event simulation of a global mobile communications network —
nodes, links (fiber / GEO / LEO / line-of-sight), routing, outages, LLM-driven agent
behavior emulation, and an ICAM (identity, credential, access management) layer. It is a
component of the Acquisition Knowledge System (AKS; umbrella ADR 0007). The umbrella repo,
`acquisition-knowledge-system`, holds specs and decisions only; it is not a monorepo.

The codebase is organized as MATLAB packages:
- `+sim/` — discrete-event engine (event calendar, SimController)
- `+network/` — nodes, links, routing, outages, geodesy, mobility
- `+agent/` — LLM agents, role loading, behavior tracing, fidelity evaluation
- `+icam/` — entity registry, credentials, authentication, policy decision/enforcement
- `+io/` — scenario I/O, reporting, visualization
- `+fabric/`, `+data/`, `+security/` — data fabric (provenance, replication), simulation
  store / query / run registry, and the security-evaluation subsystem. **These were added
  after the python-port specs were written; their own specs under `.kiro/specs/` are the
  source of truth for them — do not infer their design from the python-port documents.**

## Where the specs live and which govern

- `.kiro/specs/matlab-network-sim/` — the authoritative spec for the MATLAB engine
  (requirements, design, correctness properties, tasks). This governs current work.
- `.kiro/specs/python-port/` — **deferred.** A complete plan for an eventual Python port,
  including Amendments A1 (monorepo readiness) and A2 (Python-primary), both now superseded
  by A3. Read it only when the port is reactivated; it does not describe today's codebase.
- Other specs under `.kiro/specs/` (e.g. the security and data-fabric work, the
  mission-video-generator) govern their own packages. When a requirement seems wrong or
  underspecified, stop and ask rather than coding around it.

## Standing governance (violating these wastes work)

1. **Umbrella-owned ontology and shared contracts.** The shared ontology (BFO 2020 + CCO)
   is pinned once in the AKS umbrella (`acquisition-knowledge-system`, umbrella ADR 0006).
   Do not redefine it here. GMNS uses the shared CCO 2.2 pin.

2. **Single-source CCO pin** (ontology Req 13.4). The pinned CCO release lives only in
   `ontology/cco.lock`. It is the AKS shared pin: change it in the umbrella's ontology
   steering first, then here, never here alone. CCO is vendored in `ontology/imports/`
   (git-lfs), hash-checked against `cco.lock`, and resolved through
   `ontology/catalog-v001.xml`; never load it over the network. `ontology/gmns.ttl` and
   `ontology/gmns-shapes.ttl` validate against the pinned release.

3. **git-lfs for large/binary artifacts** (ontology Req 13.3). The vendored CCO file and any
   dataset or binary test artifact go through git-lfs. Keep Turtle (`.ttl`) files as plain
   diffable text, not in LFS.

4. **Shared-seam discipline for the future.** The names `sa-semantics`, `sa-codecs`,
   `sa-compare` are reserved for shared packages that must stay free of GMNS-specific
   imports so other AKS components can consume them (umbrella ADR 0008, proposed). This is a
   forward constraint for the deferred Python port, not a claim that those packages exist.

## If the Python port is reactivated

The full plan is in `.kiro/specs/python-port/`, but its Python-primary framing (Amendment
A2) no longer holds. Before building, reconcile it with reality: MATLAB is the authoritative
source, it has grown (fabric / security / data packages) since the plan was written, and any
Python work would be a port *of the current MATLAB codebase*, not of the version the specs
assumed. Expect to issue a further amendment re-scoping the task list before writing code.
Do not begin the port from the existing tasks.md without that reconciliation.
