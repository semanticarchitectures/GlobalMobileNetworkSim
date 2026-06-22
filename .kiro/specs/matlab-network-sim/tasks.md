# Implementation Plan

## Overview

This plan is organized into eleven phases. Phases 1–8 implement the core simulation layers (network, agents, ICAM). Phase 9 adds the operational archive (`+data/`). Phase 10 adds the simulated enterprise data fabric (`+fabric/`). Phase 11 adds security evaluation (`+security/` and `+io/TrafficReplayLoader`).

Each task lists its requirements, its dependencies, and the files it creates or modifies. Tasks within a phase may be implemented in order; cross-phase dependencies are called out explicitly.

---

## Phase 1: Core Network Simulation

- [x] 1. Set up MATLAB project structure and package layout
  - Create `+sim/`, `+network/`, `+agent/`, `+icam/`, `+io/` package directories
  - Initialize test runner and CI configuration
  - **Requirements**: R1, R7
  - **Dependencies**: None

- [x] 2. Implement Node and Link data models
  - `+network/NodeRegistry.m` — struct-of-arrays for Nodes
  - `+network/LinkRegistry.m` — struct-of-arrays for Links
  - `+network/GeoUtils.m` — WGS-84 distance and LOS coverage
  - **Requirements**: R1, R2, R10
  - **Dependencies**: Task 1

- [x] 3. Implement discrete-event simulation engine
  - `+sim/EventCalendar.m` — binary min-heap event queue
  - `+sim/SimClock.m` — simulation time management
  - `+sim/SimController.m` — DES main loop skeleton
  - **Requirements**: R8
  - **Dependencies**: Task 1

- [x] 4. Implement routing engine
  - `+network/RoutingEngine.m` — Dijkstra shortest-path over active Links
  - Path recomputation on outage state changes
  - **Requirements**: R6
  - **Dependencies**: Tasks 2, 3

- [x] 5. Implement C2 message modeling
  - `+network/C2Message.m` — message struct and scheduling
  - Integrate with RoutingEngine for path selection and latency computation
  - **Requirements**: R5
  - **Dependencies**: Tasks 3, 4

- [x] 6. Implement outage and background traffic modeling
  - Poisson outage generation in `+network/LinkRegistry.m`
  - Background traffic sampling and effective bandwidth computation
  - **Requirements**: R3, R4
  - **Dependencies**: Tasks 2, 3

- [x] 7. Implement scenario loading and validation
  - `+io/ScenarioLoader.m` — JSON parse, validate, build NodeRegistry/LinkRegistry
  - Satellite orbital mechanics in `+network/OrbitalMechanics.m`
  - **Requirements**: R7, R10
  - **Dependencies**: Tasks 2, 4

- [x] 8. Implement statistics and reporting
  - `+io/StatisticsReport.m` — compute and write JSON report
  - `+io/EventLog.m` — write CSV event log
  - `+io/PlotFunctions.m` — latency histogram, outage Gantt chart
  - **Requirements**: R8, R9
  - **Dependencies**: Tasks 3, 5, 6

---

## Phase 2: Agent Layer

- [x] 9. Implement role definition loading
  - `+agent/RoleDefinition.m` — load and validate Markdown role files
  - **Requirements**: R11
  - **Dependencies**: Task 7

- [x] 10. Implement agent registry and network binding
  - `+agent/AgentRegistry.m` — agent-to-node binding, message delivery
  - **Requirements**: R12
  - **Dependencies**: Tasks 3, 9

- [x] 11. Implement LLM agent behavior execution
  - `+agent/LLMAgent.m` — prompt construction, LLM call, action parsing
  - `+agent/BehaviorTrace.m` — record Agent_Actions with timestamps
  - Idle timeout and check-in action generation
  - **Requirements**: R13
  - **Dependencies**: Tasks 10

- [x] 12. Implement reference behavior specification
  - `+agent/ReferenceBehavior.m` — load JSON, validate, strict/unordered modes
  - **Requirements**: R14
  - **Dependencies**: Task 9

- [x] 13. Implement fidelity evaluation
  - `+agent/FidelityEvaluator.m` — compare trace vs reference, network-constrained annotation
  - `+io/EvaluationReport.m` — write JSON evaluation report
  - **Requirements**: R15, R16
  - **Dependencies**: Tasks 11, 12

---

## Phase 3: ICAM — Entity and Credential Model

- [x] 14. Implement entity and sub-entity identity model
  - `+icam/EntityRegistry.m` — struct-of-arrays for Entities and Sub_Entities
  - Identity uniqueness validation on scenario load
  - **Requirements**: R17
  - **Dependencies**: Task 7

- [x] 15. Implement PKI and credential management
  - `+icam/CertificateStore.m` — Certificate struct, Trust_Anchor registry
  - Certificate expiry events and renewal scheduling
  - **Requirements**: R18
  - **Dependencies**: Tasks 3, 14

- [x] 16. Implement authentication exchange protocol
  - `+icam/AuthenticationManager.m` — first-contact handshake, trust store
  - Retry logic and authentication-timeout handling
  - **Requirements**: R19
  - **Dependencies**: Tasks 5, 15

---

## Phase 4: ICAM — Policy Decision and Enforcement

- [x] 17. Implement Policy Decision Point
  - `+icam/PolicyDecisionPoint.m` — load `icam_policy.json`, evaluate (entityId, messageType, enclaveId) tuples, wildcard support
  - PDP query modeled as C2_Message exchange
  - **Requirements**: R20
  - **Dependencies**: Tasks 5, 14

- [x] 18. Implement Policy Enforcement Point
  - `+icam/PolicyEnforcementPoint.m` — intercept send/receive, query PDP or cache
  - Access-denied event logging, agent notification
  - **Requirements**: R21
  - **Dependencies**: Tasks 17

- [x] 19. Implement credential caching
  - `+icam/CredentialCache.m` — per-entity cache with TTL, invalidation on policy-update broadcast
  - Cache hit/miss statistics
  - **Requirements**: R23
  - **Dependencies**: Tasks 17, 18

---

## Phase 5: ICAM — Multi-Enclave and NPE

- [x] 20. Implement multi-enclave role management
  - Role_Binding struct in `+icam/EntityRegistry.m`
  - Role-change event handling, per-enclave cache invalidation
  - **Requirements**: R22
  - **Dependencies**: Tasks 14, 19

- [x] 21. Implement Non-Person Entity support
  - NPE type flag in EntityRegistry, NPE-restricted role binding validation
  - Per-category statistics in Statistics_Report
  - **Requirements**: R24
  - **Dependencies**: Tasks 14, 20

- [x] 22. Wire ICAM into SimController and AgentRegistry
  - Call `PolicyEnforcementPoint.checkSend` before routing each C2_Message
  - Call `PolicyEnforcementPoint.checkReceive` before delivering to agent
  - Annotate Evaluation_Report entries blocked by access-denied
  - Integrate PDP query and policy sync traffic into Background_Traffic accounting
  - **Requirements**: R20, R21, R24
  - **Dependencies**: Tasks 13, 18, 19, 20, 21

---

## Phase 6: Integration and End-to-End Testing

- [x] 23. Write integration tests for network + ICAM
  - End-to-end scenario: multi-enclave, multiple PDPs, credential expiry during run
  - Verify access-denied events, PDP outage fail-open/closed behavior
  - **Requirements**: R20, R21, R22, R23
  - **Dependencies**: Tasks 17–22

- [x] 24. Write integration tests for agents + ICAM
  - Mission scenario with agents blocked by access-denied, annotated in Evaluation_Report
  - Verify Fidelity_Score not penalized for access-denied blocked actions
  - **Requirements**: R15, R16, R21
  - **Dependencies**: Tasks 13, 22, 23

---

## Phase 7: Property-Based Testing (Phases 1–5)

- [x] 25. Property P1 — Round-trip scenario serialization
  - `% Feature: matlab-network-sim, Property 1: ScenarioRoundTrip`
  - **Requirements**: R7
  - **Dependencies**: Task 7

- [x] 26. Property P2 — Routing monotonicity
  - Adding a link never increases minimum-latency path cost
  - **Requirements**: R6
  - **Dependencies**: Task 4

- [x] 27. Property P3 — Outage conservation
  - Total message count = delivered + failed
  - **Requirements**: R4, R5
  - **Dependencies**: Tasks 5, 6

- [x] 28. Property P4 — Latency non-negativity
  - All delivered message latencies ≥ 0
  - **Requirements**: R5
  - **Dependencies**: Task 5

- [x] 29. Property P5 — Statistics report consistency
  - Reloading JSON report and recomputing totals produces identical values
  - **Requirements**: R9
  - **Dependencies**: Task 8

- [x] 30. Property P6 — Fidelity score bounds
  - FidelityScore ∈ [0.0, 1.0] for all inputs
  - **Requirements**: R15
  - **Dependencies**: Task 13

- [x] 31. Property P7 — Reference behavior round-trip
  - **Requirements**: R14
  - **Dependencies**: Task 12

- [x] 32. Property P8 — Cache consistency
  - Permit/deny decisions identical with and without cache (no policy changes)
  - **Requirements**: R23
  - **Dependencies**: Task 19

- [x] 33. Properties P9–P26 — ICAM correctness suite
  - EntityRegistry uniqueness, Certificate expiry scheduling, Auth-exchange latency non-negative, PDP statistics accounting, Role-binding round-trip, NPE certificate renewal equivalence
  - **Requirements**: R17–R24
  - **Dependencies**: Tasks 14–22

---

## Phase 8: Performance Benchmarks

- [x] 34. Benchmark 1,000-node scenario
  - Verify memory ≤ 16 GB, routing ≤ 100 ms per message
  - **Requirements**: R1, R6
  - **Dependencies**: Tasks 2, 4

- [x] 35. Benchmark 100,000 C2 messages
  - Verify event processing throughput
  - **Requirements**: R5
  - **Dependencies**: Task 5

- [x] 36. Benchmark 10,000 entities with ICAM
  - Verify memory ≤ 16 GB for EntityRegistry + CredentialCache
  - **Requirements**: R17, R24
  - **Dependencies**: Tasks 14, 19

---

## Phase 9: Operational Archive Layer (`+data/`)

- [ ] 37. Implement SimulationStore (HDF5 backend)
  - `+data/SimulationStore.m` — create/open HDF5 archive, write `schemaVersion` attribute, group-per-run layout (`/runs/<uuid>/events`, `/runs/<uuid>/stats`, `/runs/<uuid>/scenario`, `/runs/<uuid>/agent`, `/runs/<uuid>/icam`)
  - `+data/SchemaVersion.m` — version string constants, `registerMigration`, migration application on open
  - Use standard HDF5 numeric datatypes (float64/int64/UTF-8 strings) — no MATLAB-specific encoding
  - Include `README` attribute at root group
  - **Requirements**: R30, R32
  - **Dependencies**: Tasks 3, 8

- [ ] 38. Implement RunRegistry
  - `+data/RunRegistry.m` — JSON flat-file catalog, `list(filters)`, `annotate(runId, key, value)`
  - UUID v4 generation (use `java.util.UUID` or `system('uuidgen')` with `-nojvm` fallback)
  - Corrupt/missing registry: create new empty registry + warning, no halt
  - **Requirements**: R25
  - **Dependencies**: Task 37

- [ ] 39. Implement EventArchiver
  - `+data/EventArchiver.m` — in-memory buffer, flush on 1,000-event or 60-sim-second threshold
  - Final flush on simulation complete/stop
  - Disk-full handling: log warning + events-lost count, do not halt simulation
  - **Requirements**: R26
  - **Dependencies**: Tasks 37, 3

- [ ] 40. Wire DataFabricController (archive mode) into SimController
  - `+data/DataFabricController.m` — orchestrates RunRegistry + EventArchiver + SimulationStore
  - New optional property `sc.dataFabricController` (default `[]`) on SimController
  - On `SimController.run()`: assign UUID, call `dataFabricController.onSimulationStart(sc)`
  - At each DES event dispatch: call `dataFabricController.archiveEvent(event)`
  - On simulation complete: call `dataFabricController.onSimulationComplete(sc)`, flush archiver, write RunRegistry record
  - Zero behavioral regression when `sc.dataFabricController` is empty
  - **Requirements**: R25, R26
  - **Dependencies**: Tasks 38, 39, 3

- [ ] 41. Implement scenario snapshot (lineage)
  - On simulation start, snapshot fully resolved scenario struct to JSON and write to `/runs/<uuid>/scenario` dataset in HDF5 archive
  - Embed referenced file contents inline (role Markdown, policy JSON, reference behavior JSON)
  - `+data/QueryEngine.getScenario(runId)` — return scenario struct loadable into SimController
  - **Requirements**: R28
  - **Dependencies**: Tasks 37, 40

- [ ] 42. Implement QueryEngine
  - `+data/QueryEngine.m`:
    - `getEvents(runId, filters)` → MATLAB table
    - `getStats(runIds)` → MATLAB table (one row per run)
    - `compareRuns(runId1, runId2)` → diff struct
    - `aggregateStats(runIds)` → mean/median/std/min/max struct
  - Throw `netsim:data:unknownRunId` for missing run identifiers
  - Performance target: ≤ 5 s for 1 M events or 10,000 runs on SSD
  - **Requirements**: R27
  - **Dependencies**: Tasks 37, 41

- [ ] 43. Implement export functions
  - `+data/QueryEngine.exportRun(runId, outputDir, format)` — CSV and JSON formats
  - `+data/QueryEngine.exportBatch(runIds, outputDir, format)` — per-run subdirectory
  - CSV header rows matching schema field names; JSON via `jsonencode` (no MATLAB artefacts)
  - **Requirements**: R29
  - **Dependencies**: Task 42

- [ ] 44. Implement retention policy
  - `+data/DataFabricController.m` — `retentionPolicy` struct (`maxRuns`, `maxAgeDays`, `keepTagged`)
  - Apply after each completed run; `applyRetention()` callable on demand
  - `maxRuns = 0` → disable retention
  - **Requirements**: R31
  - **Dependencies**: Tasks 40, 38

- [ ] 45. Write tests for Phase 9
  - Unit: SimulationStore read-back fidelity, RunRegistry CRUD, EventArchiver flush thresholds, schema migration, QueryEngine error on unknown runId
  - Integration: full run → archive → QueryEngine → export round-trip
  - Property P27: schema round-trip (write then read = identical data)
  - Property P28: QueryEngine consistency (recomputed stats = stored stats)
  - Property P29: export JSON is valid (parseable by `jsondecode`)
  - **Requirements**: R25–R32
  - **Dependencies**: Tasks 37–44

- [ ] 46. Write property-based tests for Phase 9 (P27–P33)
  - P27: Schema read-back fidelity
  - P28: QueryEngine stats consistency
  - P29: Export JSON validity
  - P30: RunRegistry list-filter correctness
  - P31: Retention policy invariant (retained count ≤ maxRuns after apply)
  - P32: Scenario lineage replay equivalence
  - P33: Cross-run aggregate correctness
  - **Requirements**: R25–R32
  - **Dependencies**: Task 45

- [ ] 47. Benchmark Phase 9
  - Archive 10,000-run batch; verify QueryEngine ≤ 5 s for 1 M events
  - Verify EventArchiver overhead ≤ 1 ms per event
  - **Requirements**: R26, R27
  - **Dependencies**: Tasks 39, 42

- [ ] 48. Verify HDF5 external accessibility
  - Integration test: write archive with simulator, open with h5py in subprocess, assert expected group keys
  - Verify UTF-8 string encoding readable by HDFView
  - **Requirements**: R32
  - **Dependencies**: Task 37

---

## Phase 10: Simulated Data Fabric Layer (`+fabric/`)

- [ ] 49. Implement DataItem model and DataCatalog
  - `+fabric/DataItem.m` — struct with all fields from R33.1; struct-of-arrays storage
  - `+fabric/DataCatalog.m` — `containers.Map` for O(1) lookup by DataItem ID, struct-of-arrays backing store
  - `+fabric/ProvenanceGraph.m` — MATLAB `digraph`, `getLineage(dataItemId, maxDepth)`
  - Auto-create `c2_log` DataItem provenance entry on C2_Message delivery (R33.6)
  - **Requirements**: R33, R38
  - **Dependencies**: Tasks 3, 5

- [ ] 50. Implement DataStoreRegistry and DataStore node flag
  - `+fabric/DataStoreRegistry.m` — tracks which NodeIds are DataStores, holds per-node DataCatalog and ProvenanceGraph references
  - Extend `+io/ScenarioLoader.m` to parse `"dataStore": true` and `"dataStoreConfig"` from Node JSON; register in DataStoreRegistry
  - Validate: DATA_INGEST/DATA_FETCH routed to non-DataStore node → `data_routing_error` event
  - **Requirements**: R35
  - **Dependencies**: Tasks 7, 49

- [ ] 51. Implement DATA_INGEST event handling
  - Extend SimController event dispatch: `case 'DATA_INGEST'` → `sc.dataFabricController.handleIngest(event, sc.simClock)`
  - `+fabric/FabricEventHandler.handleIngest` — add DataItem to DataCatalog, record `data_ingest_complete`; on failure schedule retry up to `ingestMaxRetries`; on max retries record `data_ingest_dropped`
  - Ingest latency tracking (mean/median/p95 in Statistics_Report)
  - **Requirements**: R34
  - **Dependencies**: Tasks 5, 49, 50

- [ ] 52. Implement DATA_REPLICATE event handling
  - `+fabric/ReplicationEngine.m` — on ingest completion, schedule DATA_REPLICATE C2_Message to each configured peer matching replication policy (`'all'`, `'by_classification:<label>'`, `'by_enclave:<id>'`)
  - Extend SimController: `case 'DATA_REPLICATE'` → `sc.dataFabricController.handleReplicate(event, sc.simClock)`
  - `data_replicated` / `data_replication_failed` / `data_replication_dropped` events
  - Count DATA_REPLICATE messages in per-link Background_Traffic stats separately from operational C2 traffic
  - **Requirements**: R39
  - **Dependencies**: Tasks 51, 50

- [ ] 53. Extend ICAM policy for data item access control
  - No changes to PolicyDecisionPoint logic required — extend `icam_policy.json` schema to allow `messageType: 'data_item:<classification>'` and `messageType: 'data_item:*'`
  - Document extension in ScenarioLoader validation
  - **Requirements**: R36
  - **Dependencies**: Tasks 17, 49

- [ ] 54. Implement DATA_FETCH and DATA_QUERY event handling
  - Extend SimController: `case 'DATA_FETCH'`, `case 'DATA_QUERY'`
  - `FabricEventHandler.handleFetch` — call `PolicyEnforcementPoint.checkReceive` with `messageType: 'data_item:<classification>'`; schedule DATA_FETCH_RESULT (with provenance) or DATA_FETCH_DENIED; handle `item_not_found`
  - `FabricEventHandler.handleQuery` — evaluate query criteria, ICAM check per item, return permitted-only metadata in DATA_QUERY_RESULT
  - DATA_FETCH_RESULT `sizeBytes` = DataItem `sizeBytes`
  - Default permit-all when no ICAM layer configured + warning
  - **Requirements**: R36, R37
  - **Dependencies**: Tasks 53, 51, 18

- [ ] 55. Implement `c2_log` auto-creation
  - In C2_MESSAGE_RX handler, after ICAM permit: if `sc.dataFabricController` non-empty, call `sc.dataFabricController.onC2MessageDelivered(event, sc.simClock)` to create and ingest `c2_log` DataItem with provenance referencing the C2_Message ID
  - Respect `"c2LogDataStore"` config to identify target DataStore; when unreachable, use same retry logic as DATA_INGEST
  - **Requirements**: R33
  - **Dependencies**: Tasks 51, 54

- [ ] 56. Implement agent data integration (new Agent_Action types)
  - Extend `+agent/LLMAgent.m` action parsing to handle `publish_data`, `query_data`, `fetch_data`
  - `publish_data`: create DataItem, schedule DATA_INGEST
  - `query_data`: schedule DATA_QUERY C2_Message
  - `fetch_data`: schedule DATA_FETCH C2_Message
  - Deliver DATA_QUERY_RESULT / DATA_FETCH_RESULT / DATA_FETCH_DENIED to agent via `AgentRegistry.deliver`
  - Annotate DATA_FETCH_DENIED in Behavior_Trace with `reason: 'access_denied'`; do not penalize FidelityScore
  - Extend `+agent/ReferenceBehavior.m` to support `publish_data`, `query_data`, `fetch_data` as expected actions
  - **Requirements**: R40
  - **Dependencies**: Tasks 11, 13, 54

- [ ] 57. Wire DataFabricController (fabric mode) into SimController
  - `+fabric/DataFabricController.m` — extends/supersedes archive-mode controller; holds DataStoreRegistry, ReplicationEngine, FabricEventHandler references alongside RunRegistry/EventArchiver
  - Single `sc.dataFabricController` property handles both archive and fabric behaviors
  - **Requirements**: R33–R41
  - **Dependencies**: Tasks 40, 50, 51, 52, 54, 55, 56

- [ ] 58. Implement data fabric statistics in Statistics_Report
  - Add `"dataFabric"` block to `+io/StatisticsReport.m` (present only when ≥1 DataStore configured)
  - Fields per R41: total DataItems, ingest counts/failures/retries, query/fetch/result/denied counts, per-DataStore breakdown, per-classification counts, provenance graph stats
  - Consistency property: recomputed totals = stored totals
  - Implement `io.PlotFunctions.dataFlowDiagram(statsReport)`
  - **Requirements**: R41
  - **Dependencies**: Tasks 51, 54, 52, 49

- [ ] 59. Write unit and integration tests for Phase 10
  - Unit: DataCatalog O(1) lookup, ProvenanceGraph lineage, ReplicationEngine policy matching, ICAM wildcard classification, `data_routing_error` on non-DataStore node
  - Integration: multi-DataStore scenario with replication, agent `publish_data` → ingest → `fetch_data` with ICAM deny, `c2_log` auto-creation and provenance chain
  - Zero-DataStore scenario: fabric block absent from Statistics_Report
  - **Requirements**: R33–R41
  - **Dependencies**: Tasks 49–58

- [ ] 60. Write property-based tests for Phase 10 (P34–P40)
  - P34: DataItem ID uniqueness within run
  - P35: Ingest-retry monotonicity (retry count never decreases)
  - P36: Replication consistency (replicated item present in peer catalog after DATA_REPLICATE_ACK)
  - P37: ICAM wildcard soundness (permit `data_item:*` ⊇ permit `data_item:SECRET`)
  - P38: Provenance depth bound (getLineage depth ≤ maxDepth)
  - P39: DataFabric stats consistency (report totals = sum of per-DataStore values)
  - P40: Access-denied non-penalization (fidelity score unchanged when fetch blocked by ICAM)
  - **Requirements**: R33–R41
  - **Dependencies**: Task 59

- [ ] 61. Benchmark Phase 10
  - 1,000,000 DataItems in single run: verify memory ≤ 16 GB
  - DataCatalog lookup: verify O(1) average for 10,000 items
  - **Requirements**: R33, R35
  - **Dependencies**: Tasks 49, 50

- [ ] 62. Verify data fabric Statistics_Report consistency
  - Automated test: run simulation, write report, reload JSON, recompute per-DataStore totals, assert equality
  - **Requirements**: R41
  - **Dependencies**: Task 58

---

## Phase 11: Security Evaluation Layer (`+security/`, `+io/TrafficReplayLoader`)

- [ ] 63. Implement IntendedPolicyLoader
  - `+security/IntendedPolicyLoader.m` — load and parse `IntendedPolicy.json` (fields: `description`, `defaultOutcome`, `rules` array with `role`, `classification`, `enclave`, `operation`, `outcome`)
  - Wildcard `'*'` support with specificity-based precedence matching existing PDP rule evaluation
  - Validate referenced roles/classifications/enclaves against Scenario; warnings (not errors) for unknowns
  - Round-trip save/load
  - Throw descriptive error on missing/malformed file
  - **Requirements**: R42
  - **Dependencies**: Tasks 17, 7

- [ ] 64. Implement PolicyAnalyzer (static analysis)
  - `+security/PolicyAnalyzer.m` — analyze `icam_policy.json` for:
    - **Gaps**: (role, classification, enclave, operation) combinations with no explicit rule
    - **Conflicts**: rule pairs producing different outcomes for same input
    - **Dead rules**: unreachable rules shadowed by earlier wildcard rules
    - **Orphaned role bindings**: entity roles with no governing policy rule
    - **Intent mismatches** (when IntendedPolicy provided): implementation outcome ≠ intended outcome
  - Produce `PolicyAnalysisReport` JSON; return exit code 0 (no findings) or 1 (findings)
  - **Requirements**: R44
  - **Dependencies**: Tasks 63, 17

- [ ] 65. Implement SecurityOracle
  - `+security/SecurityOracle.m` — evaluate every DATA_FETCH, DATA_QUERY, AUTH_REQUEST, C2_MESSAGE_TX outcome against IntendedPolicy
  - Classify each: Conformant / Violation / Over-restriction / Unspecified
  - Record `security_violation` events in Event_Log for violations
  - Annotate degraded-condition outcomes with `reason: 'degraded_condition'` in `degradedConditionOutcomes` section
  - Compute `PolicyConformanceScore = conformant / (conformant + violations + over-restrictions)` (unspecified excluded from denominator)
  - **Requirements**: R43
  - **Dependencies**: Tasks 63, 5, 54

- [ ] 66. Implement CoverageGenerator
  - `+security/CoverageGenerator.m` — enumerate all (entity, classification, enclave, operation) combinations from Scenario; schedule one DATA_FETCH/DATA_QUERY/C2_MESSAGE_TX attempt per combination at randomized simulation timestamps
  - Targeted mode: filter by subset of enclaves, classifications, or roles
  - Fallback when no DataStore nodes: C2_MESSAGE_TX between all entity pairs + warning
  - Report coverage percentage (combinations covered / combinations in IntendedPolicy)
  - Populate coverage section of SecurityEvaluationReport
  - **Requirements**: R45
  - **Dependencies**: Tasks 65, 54, 5

- [ ] 67. Implement AdversarialAgentRegistry
  - `+security/AdversarialAgentRegistry.m` — load adversarial agent definitions from Scenario JSON (`"adversarial": true`, `attackPatterns` list)
  - Support attack types: `'unauthorized_data_access'`, `'cross_enclave_access'`, `'expired_credential_access'`, `'pdp_outage_exploitation'`
  - At scenario load: schedule each attack pattern as a DES event at specified `attemptTimeSec`
  - Support insider threat (legitimate credentials) and external attacker (no initial auth state) models
  - Adversarial agents excluded from FidelityEvaluator; evaluated only by SecurityOracle with `adversarialSource: true` flag on violations
  - **Requirements**: R46
  - **Dependencies**: Tasks 65, 63, 11

- [ ] 68. Implement NetworkDegradationTester
  - `+security/NetworkDegradationTester.m` — define degradation scenarios: named configs specifying target nodes/links, outage duration, start time
  - PDP-outage mode: record all access control outcomes during PDP-unreachable window → `degradedConditionOutcomes`
  - Trust-Anchor-outage mode: track entities with expiring certs, monitor expired-credential access outcomes
  - Produce DegradationSecurityMatrix (rows = scenarios, cols = security properties: PDP availability, credential freshness, replication consistency)
  - Batch mode: run all degradation scenarios, combine DegradationSecurityMatrix
  - Annotate violations only under degraded conditions with `'degraded_only': true`
  - **Requirements**: R47
  - **Dependencies**: Tasks 65, 67, 15, 17

- [ ] 69. Implement SecurityReportWriter
  - `+security/SecurityReportWriter.m` — write SecurityEvaluationReport JSON (R43 fields + PolicyAnalysisReport + coverage stats + DegradationSecurityMatrix)
  - Write summary CSV (one row per non-conformant outcome)
  - Include library template name if run instantiated from ScenarioLibrary
  - **Requirements**: R48
  - **Dependencies**: Tasks 64, 65, 66, 67, 68

- [ ] 70. Implement security visualization functions
  - `io.PlotFunctions.policyConformanceHeatmap(securityReport)` — heatmap: role × classification, colored by conformance rate
  - `io.PlotFunctions.attackSurfaceDiagram(securityReport)` — network topology with node/edge security role coloring
  - `io.PlotFunctions.degradationSecurityPlot(securityReport)` — DegradationSecurityMatrix color grid (green = pass, red = fail)
  - **Requirements**: R48
  - **Dependencies**: Task 69

- [ ] 71. Implement ScenarioLibrary
  - `+security/ScenarioLibrary.m` — ship five parameterized JSON templates: `insider_data_exfiltration`, `outsider_authentication_bypass`, `pdp_outage_exploitation`, `cross_enclave_escalation`, `expired_credential_persistence`
  - `security.ScenarioLibrary.instantiate(templateName, topology)` — substitute node IDs, enclave names, role names; return fully populated Scenario
  - Templates must be instantiable without modifying template files
  - **Requirements**: R50
  - **Dependencies**: Tasks 7, 67, 68

- [ ] 72. Implement TrafficReplayLoader
  - `+io/TrafficReplayLoader.m` — load real-world traffic log from JSON (`'generic'`) or CSV (`'native'`) format
  - Parse event types: message transmission, authentication exchange, data access attempt (per R49.2)
  - Map entity IDs to simulation nodes; schedule C2_MESSAGE_TX events at original timestamps
  - When log contains observed security outcomes: store as RealWorldOutcomes, pass to SecurityOracle
  - Topology import mode: read node positions, link types, latencies, outage parameters from real-world config file
  - **Requirements**: R49
  - **Dependencies**: Tasks 7, 65

- [ ] 73. Implement SecurityOracle ValidationReport
  - Extend `+security/SecurityOracle.m` to accept RealWorldOutcomes from TrafficReplayLoader
  - Produce ValidationReport: total events replayed, matched count, differed count, ModelAccuracyScore = matched/total
  - Per-mismatch detail: event context, simulation-predicted outcome, real-world observed outcome, simulation time
  - **Requirements**: R49
  - **Dependencies**: Tasks 65, 72

- [ ] 74. Wire SecurityController into SimController
  - `+security/SecurityController.m` — orchestrates PolicyAnalyzer, SecurityOracle, CoverageGenerator, AdversarialAgentRegistry, NetworkDegradationTester, SecurityReportWriter
  - New optional property `sc.securityController` (default `[]`) on SimController
  - Wiring hooks:
    - At DES loop startup: `sc.securityController.onSimulationStart(sc.scenario, sc.simClock)`
    - At each event dispatch: `sc.securityController.onEvent(event, sc.simClock)`
    - At simulation completion: `sc.securityController.onSimulationComplete(sc)`
  - Zero behavioral regression when `sc.securityController` is empty
  - **Requirements**: R42–R50
  - **Dependencies**: Tasks 63–73, 3

- [ ] 75. Write unit and integration tests for Phase 11
  - Unit: PolicyAnalyzer gap/conflict/dead-rule/orphan detection, SecurityOracle classification correctness, CoverageGenerator enumeration, AdversarialAgentRegistry attack scheduling, DegradationSecurityMatrix generation, SecurityReportWriter JSON/CSV output, TrafficReplayLoader format parsing, ScenarioLibrary instantiation
  - Integration: full verification run (coverage + adversarial + degradation), full validation run (traffic replay + ModelAccuracyScore), ScenarioLibrary template instantiation and run
  - **Requirements**: R42–R50
  - **Dependencies**: Tasks 63–74

- [ ] 76. Write property-based tests for Phase 11 (P41–P48)
  - P41: Oracle Violation Completeness — every event classified as permit when IntendedPolicy says deny is in violations list
  - P42: PolicyConformanceScore Consistency — recomputing from report fields = stored score
  - P43: Policy Gap Detection Completeness — PolicyAnalyzer finds all (role, classification, enclave, operation) tuples with no explicit rule
  - P44: Policy Conflict Detection Completeness — PolicyAnalyzer finds all rule pairs producing conflicting outcomes for same input
  - P45: Adversarial Containment Soundness — if every adversarial access attempt is denied, `violations` list contains no entries with `adversarialSource: true`
  - P46: Degradation Monotonicity — adding a degradation condition never decreases the violation count (caveat: role-change events during degradation may change access rights; document exception)
  - P47: Coverage Monotonicity — adding more entity/classification/enclave combinations to Scenario never decreases the total combinations enumerated by CoverageGenerator
  - P48: Replay Temporal Fidelity — all replayed events appear in simulation Event_Log at timestamps ≥ their original log timestamps
  - **Requirements**: R42–R50
  - **Dependencies**: Task 75
