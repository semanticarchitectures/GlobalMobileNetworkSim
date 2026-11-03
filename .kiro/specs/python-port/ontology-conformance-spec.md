# Ontology Conformance Specification Additions

**Target files:** `.kiro/specs/matlab-network-sim/requirements.md`, `design.md`, `tasks.md`
**New artifacts:** `ontology/gmns.ttl`, `ontology/gmns-shapes.ttl`, `ontology/term-bindings.json` (generated), `tools/semantic_validate.py`

These additions align GlobalMobileNetworkSim with the January 2024 DoD/IC Chief Data Officer direction establishing Basic Formal Ontology (ISO/IEC 21838-2) and the Common Core Ontologies (CCO) as baseline standards for formal DoD and IC ontology development. Conformance applies to the information artifacts the simulator consumes and emits (scenario specifications, event logs, statistics, behavior traces, ICAM records) — not to engine internals.

---

## Additions to requirements.md

### Requirement 25 — Semantic Data Model Conformance

**User Story:** As a program-office data engineer, I want the simulator's entities, events, and information artifacts to be defined in a BFO/CCO-conformant domain ontology, so that simulation outputs are interoperable with other DoD/IC ontology-aligned systems without bespoke translation.

**Acceptance Criteria:**

25.1. THE SYSTEM SHALL maintain a domain ontology (`ontology/gmns.ttl`) in which every exported entity type, event type, and information artifact type is declared as a class with an asserted `rdfs:subClassOf` path terminating in a Basic Formal Ontology class.

25.2. WHERE a suitable CCO class exists (verified against a pinned CCO release recorded in the ontology header), THE SYSTEM SHALL subclass the CCO class rather than mint a sibling term.

25.3. THE SYSTEM SHALL give every minted class an `rdfs:label` and a genus-differentia `skos:definition`, and SHALL flag contestable modeling decisions with `skos:editorialNote`.

25.4. WHEN the ontology is modified, THE SYSTEM SHALL pass an automated consistency check (OWL reasoner) and referential check (every referenced CCO/BFO IRI resolves in the pinned CCO release) before merge.

25.5. THE SYSTEM SHALL maintain a generated term-binding table (`ontology/term-bindings.json`) mapping each ontology class IRI to the MATLAB type or enum that implements it; CI SHALL fail if an exported MATLAB type lacks a binding.

### Requirement 26 — Semantic Export and Validation

**User Story:** As an analyst consuming simulation results, I want event logs and reports exported as ontology-annotated data, so that I can query, join, and validate them with standard semantic-web tooling.

**Acceptance Criteria:**

26.1. WHEN a scenario completes, THE SYSTEM SHALL emit, alongside the existing CSV/JSON outputs, a semantic event log (JSON-LD or Turtle) in which every record is typed with its GMNS class IRI and every quantity is expressed via a declared datatype property.

26.2. THE SYSTEM SHALL attach a JSON-LD `@context` to `*_stats.json` and `*_eval.json` outputs mapping their keys to GMNS/CCO IRIs.

26.3. WHEN CI runs, THE SYSTEM SHALL validate the semantic event log of the reference scenario (airdrop_mission) against the SHACL shapes in `ontology/gmns-shapes.ttl` with zero violations.

26.4. WHEN CI runs, THE SYSTEM SHALL execute the competency-question query suite (CQ1–CQ10) against the reference scenario's semantic export, and each query SHALL return a non-empty, spot-checked result set.

26.5. IF an exported record cannot be typed against the ontology, THE SYSTEM SHALL emit it with type `gmns:UnclassifiedRecord` and log a warning, rather than fail silently or drop the record.

---

## Competency Questions

Each CQ must be answerable by a SPARQL query over the semantic export of the airdrop_mission scenario. CQs are the semantic analogue of unit tests: they define what the ontology must be able to express.

**Network layer**
- **CQ1.** Which Communication Nodes did C2 Message X traverse, in order, and over which Communication Links?
- **CQ2.** What was the end-to-end latency of every C2 Message sent from the Operations Center to the Ground Team Terminal, and which link type dominated each path?
- **CQ3.** During which intervals was each satellite link in a Communication Outage, and which message transmissions overlapped those intervals?
- **CQ4.** Which Mobile Communication Nodes were within Line-of-Sight coverage of the drop zone at time T?

**Agent layer**
- **CQ5.** Which acts in agent A's Behavior Trace realize duties prescribed by its Role Specification, and which prescribed duties have no realizing act?
- **CQ6.** For each Operational Role, what is the Fidelity Score, and how many missed actions were annotated network-constrained?
- **CQ7.** Which Acts of Communication were performed by agents bearing the Air Traffic Management Role during the descent phase?

**ICAM layer**
- **CQ8.** Which entities hold unexpired Digital Certificates, and which certificates were revoked during the scenario?
- **CQ9.** Which Acts of Authentication timed out, and were the timeouts concurrent with a Communication Outage on the path?
- **CQ10.** Which message send/receive attempts were denied by a Policy Decision, and under which Access Control Policy?

**Example SPARQL sketch (CQ6):**

```sparql
PREFIX gmns: <https://semanticarchitectures.com/ont/gmns/>
PREFIX cco:  <https://www.commoncoreontologies.org/>
SELECT ?role ?score (SUM(IF(?nc, 1, 0)) AS ?networkConstrainedMisses)
WHERE {
  ?agent a gmns:NonPersonEntity ;
         cco:ont00001787 ?trace_process .        # agent in
  ?scoreEnt a gmns:FidelityScore ;
            cco:ont00001966 ?trace_process ;     # is a measurement of
            gmns:fidelityScoreValue ?score .
  ?agent obo:BFO_0000101 ?role .                 # bearer pattern per binding
  OPTIONAL { ?miss gmns:networkConstrained ?nc . }
}
GROUP BY ?role ?score
```

---

## Additions to design.md

### Semantic Data Model (new section)

The authoritative semantic model is `ontology/gmns.ttl` (imports CCO merged, pinned release 2026-04-04, which imports BFO). MATLAB runtime types carry no OWL logic; they are bound to class IRIs through `ontology/term-bindings.json`, loaded by `+io`. Representative bindings:

| MATLAB construct | GMNS class | CCO/BFO parent |
|---|---|---|
| Node (stationary) | `gmns:StationaryCommunicationNode` | Telecommunication Network Node (`cco:ont00000918`) |
| Node (mobile/orbital) | `gmns:SatelliteRelayNode` | via `gmns:MobileCommunicationNode` |
| Link type `Fiber` | `gmns:FiberLink` | Telecommunication Network Line (`cco:ont00000825`) |
| Link type `GEO_Satellite` | `gmns:GEOSatelliteLink` | Material Artifact (`cco:ont00000995`) |
| C2 message event | `gmns:ActOfC2MessageTransmission` | Act of Communication (`cco:ont00000402`) |
| Outage event | `gmns:CommunicationOutage` | Stasis of Artifact Operationality (`cco:ont00001213`) |
| Role Markdown file | `gmns:RoleSpecification` | Prescriptive ICE (`cco:ont00000965`) |
| Behavior trace CSV row | `gmns:BehaviorTrace` (member act) | Descriptive ICE (`cco:ont00000853`) |
| Fidelity score | `gmns:FidelityScore` | Ratio Measurement ICE (`cco:ont00001022`) |
| EntityRegistry entry | `gmns:NonPersonEntity` / `cco:ont00001262` (Person) | Agent (`cco:ont00001017`) |
| Certificate | `gmns:DigitalCertificate` | Certificate (`cco:ont00002002`) |
| AUTH_* exchange | `gmns:ActOfAuthentication` | Act of Communication (`cco:ont00000402`) |
| PDP decision | `gmns:PolicyDecision` | Prescriptive ICE (`cco:ont00000965`) |
| Policy JSON | `gmns:AccessControlPolicy` | Prescriptive ICE (`cco:ont00000965`) |

**Design decisions:**
- **Semantics at the boundary.** The DES engine, routing cache, and struct-of-arrays storage remain semantics-free. Only `+io` touches IRIs. This mirrors DoD practice: the ontology governs the data-sharing boundary, not implementation internals.
- **No OWL processing in MATLAB.** Validation, reasoning, and querying run in a Python toolchain (`rdflib`, `pyshacl`) invoked by CI; MATLAB only stamps IRIs from the binding table.
- **Measurement shortcuts.** Quantities are exported with documented datatype-property shortcuts (`gmns:latencyMilliseconds`, etc.); the full CCO measurement pattern (Measurement ICE + `is a measurement of` + `uses measurement unit`) is the normative form and can be materialized by a post-processing step when consumers require it.
- **Flagged modeling decisions.** Wireless links as artifacts, NPE agency, and PolicyDecision as Prescriptive ICE are marked with `skos:editorialNote` for ontology review rather than silently assumed.

### Correctness Properties (append to existing 26)

27. Every record in a semantic event log has an `rdf:type` whose superclass closure includes a BFO class; message transmission acts reference exactly one source and one destination node (SHACL: MessageTransmissionShape, CommunicationLinkShape).
28. All exported latency values are non-negative and carried by typed `gmns:LatencyMeasurement` entities (SHACL: LatencyMeasurementShape).
29. Every Communication Outage is an outage of exactly one Communication Link, and outage intervals in the semantic log equal those in the CSV event log (SHACL: OutageShape + cross-format diff test).
30. Every Fidelity Score lies in [0,1] and is a measurement of a traced agent process; every certificate is issued to exactly one agent; every agent is bound to a node (SHACL: FidelityScoreShape, CertificateShape, AgentBindingShape).

### Testing Strategy (addition)

CI adds a `semantic` stage after the MATLAB test suite: (1) parse `gmns.ttl`, run reasoner consistency + CCO referential check; (2) run airdrop_mission headless; (3) validate semantic export with pyshacl against `gmns-shapes.ttl`; (4) execute CQ1–CQ10 SPARQL suite and compare result counts to golden values. A red semantic stage blocks merge exactly as a red MATLAB test does.

---

## Additions to tasks.md

- **Task 37** — Commit `ontology/gmns.ttl` and `ontology/gmns-shapes.ttl`; add `tools/semantic_validate.py` (rdflib + pyshacl consistency, referential, and shape checks); wire into CI.
- **Task 38** — Implement `+io/TermBindings.m` loading `ontology/term-bindings.json`; generate the binding table from the ontology (Python script) and fail CI on unbound exported types (Req 25.5).
- **Task 39** — Extend `+io` report writer to emit the JSON-LD semantic event log and `@context` for stats/eval JSON (Req 26.1–26.2); regenerate airdrop_mission goldens.
- **Task 40** — Author CQ1–CQ10 as SPARQL files under `tests/semantic/`; add golden result counts; wire into CI (Req 26.4).
- **Task 41** — Ontology review pass: adjudicate the three flagged editorial notes (wireless-link treatment, NPE agency, PolicyDecision placement); minute the decisions in `design.md`.

---

## Traceability note for program-office consumption

Requirement 25 evidences *structural* conformance (every term traces to BFO through CCO, per the DoD/IC CDO baseline direction); Requirement 26 evidences *behavioral* conformance (outputs machine-validated against shapes and competency questions on every build). Together they constitute a testable assurance claim of the form used in Section 7-style T&E acceptance criteria: "GMNS semantic exports conform to the DoD/IC ontology baseline, demonstrated by zero SHACL violations and a passing competency-question suite on the reference scenario at every release."
