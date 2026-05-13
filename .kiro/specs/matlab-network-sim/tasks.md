# Implementation Plan: MATLAB Network Simulator

## Overview

Build the simulator incrementally in four phases that mirror the package structure: (1) DES foundation (`+sim`) and geographic/orbital utilities (`+network` core), (2) full network layer including routing, outage, and background traffic, (3) agent behavior layer, and (4) I/O, reporting, and visualization. Each phase ends with a checkpoint. Property-based tests are placed immediately after the component they validate so errors surface early.

All MATLAB classes live in their respective `+sim`, `+network`, `+agent`, and `+io` package folders. Unit tests live under `tests/` mirroring the package structure. Property-based tests use the `matlab-prop-test` library and are tagged with `% Feature: matlab-network-sim, Property N: <title>`.

## Tasks

- [x] 1. Set up project structure and testing framework
  - Create the `+sim`, `+network`, `+agent`, `+io` package folders and a `tests/` directory tree mirroring the package structure
  - Add a `tests/run_all_tests.m` script that discovers and runs all `matlab.unittest.TestCase` files
  - Add a `tests/run_property_tests.m` script that runs all property-based test files
  - Confirm `matlab.unittest.TestRunner` can discover and execute an empty placeholder test without error
  - _Requirements: 1.1, 7.1, 8.1_

- [x] 2. Implement geographic and orbital utilities (`+network` core)
  - [x] 2.1 Implement `network.GeoUtils` with `vincenty` and `isLOSVisible`
    - Write `+network/GeoUtils.m` as a static-methods class
    - Implement Vincenty's iterative formula on the WGS-84 ellipsoid for `vincenty(lat1, lon1, lat2, lon2)` returning distance in metres
    - Implement `isLOSVisible(mobileLat, mobileLon, mobileAltM, stationLat, stationLon, coverageRadiusM)` accounting for Earth curvature via WGS-84
    - _Requirements: 2.4, 2.5, 10.1, 10.2_

  - [ ]* 2.2 Write property test for `GeoUtils.vincenty` WGS-84 accuracy
    - **Property 12: WGS-84 Distance Accuracy**
    - **Validates: Requirements 10.1**
    - Tag: `% Feature: matlab-network-sim, Property 12: WGS-84 distance accuracy`
    - Generator: random lat/lon pairs including poles, equator, and near-antipodal cases; assert error ≤ 0.1% vs reference

  - [ ]* 2.3 Write property test for `GeoUtils.isLOSVisible` Earth-curvature exclusion
    - **Property 13: LOS Visibility Accounts for Earth Curvature**
    - **Validates: Requirements 2.5, 10.2**
    - Tag: `% Feature: matlab-network-sim, Property 13: LOS visibility and Earth curvature`
    - Generator: random positions beyond the geometric horizon; assert `isLOSVisible` returns false

  - [x] 2.4 Implement `network.OrbitalPropagator`
    - Write `+network/OrbitalPropagator.m` as a static-methods class
    - Implement `propagate(keplerElems, epochSec, simTimeSec)` returning `[lat, lon, altM]`
    - Solve Kepler's equation via Newton-Raphson (tolerance 1e-10 rad), convert ECI → ECEF → geodetic (WGS-84)
    - _Requirements: 10.3, 10.4_

  - [ ]* 2.5 Write property test for orbital period round-trip
    - **Property 14: Orbital Period Round-Trip**
    - **Validates: Requirements 10.3**
    - Tag: `% Feature: matlab-network-sim, Property 14: Orbital period round-trip`
    - Generator: random circular orbits (eccentricity = 0, varying altitude 400–42000 km, inclination, RAAN); propagate by T = 2π√(a³/μ); assert position within 1 m of start

- [x] 3. Implement the DES engine (`+sim`)
  - [x] 3.1 Implement `sim.EventCalendar`
    - Write `+sim/EventCalendar.m` as a handle class backed by a binary min-heap keyed on `event.time`
    - Implement `schedule(event)`, `popNext()`, `isEmpty()`, `reschedule(eventId, newTime)`
    - Define the event struct schema (fields: `time`, `type`, `id`, `payload`) and the full set of event type string constants
    - _Requirements: 8.1_

  - [x] 3.2 Implement `sim.SimController` skeleton and DES main loop
    - Write `+sim/SimController.m` as a handle class accepting a `scenario` struct
    - Implement `run()`, `pause()`, `resume()`, `stop()`, and `inspect()` per the design interface
    - Implement the DES main loop: pop next event, dispatch to handler stubs, advance `SimClock`
    - Wire `SIM_END` event to terminate the loop and enforce the configurable time limit (Requirement 8.4)
    - _Requirements: 8.1, 8.2, 8.3, 8.4_

  - [ ]* 3.3 Write property test for event time ordering
    - **Property 17: Event Time Ordering**
    - **Validates: Requirements 13.5**
    - Tag: `% Feature: matlab-network-sim, Property 17: Event time ordering`
    - Generator: random sequences of events with random times; assert `popNext` always returns non-decreasing times

- [x] 4. Implement node and link registries
  - [x] 4.1 Implement `network.NodeRegistry`
    - Write `+network/NodeRegistry.m` as a handle class using struct-of-arrays storage
    - Implement `getPosition(nodeId, simTimeSec)`, `updatePositions(simTimeSec)`, `indexOf(nodeId)`
    - `updatePositions` must linearly interpolate waypoint trajectories for Mobile nodes and call `OrbitalPropagator.propagate` for satellite nodes
    - Validate trajectory definitions on construction; throw `netsim:node:malformedTrajectory` with node ID and field name on error
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 10.3, 10.4_

  - [x] 4.2 Implement `network.LinkRegistry`
    - Write `+network/LinkRegistry.m` as a handle class using struct-of-arrays storage
    - Implement `setOutage(linkId, tf)`, `setLOSActive(linkId, tf)`, `refreshBackground(linkId)`, `getEffectiveBandwidth(linkId)`, `getEffectiveLatency(linkId)`
    - On construction, compute `nominalLatencyMs` for Fiber links using `GeoUtils.vincenty` and the 200,000 km/s propagation speed
    - Enforce GEO_Satellite latency floor of 270 ms on construction
    - Validate all node references; throw `netsim:link:unknownNode` on missing node ID
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 3.2, 3.3_

  - [ ]* 4.3 Write property test for GEO satellite latency floor
    - **Property 9: GEO Satellite Latency Floor**
    - **Validates: Requirements 2.2**
    - Tag: `% Feature: matlab-network-sim, Property 9: GEO latency floor`
    - Generator: random GEO link configs with latency values both below and above 270 ms; assert stored and effective latency ≥ 270 ms

  - [ ]* 4.4 Write property test for Fiber link latency from geographic distance
    - **Property 10: Fiber Link Latency from Geographic Distance**
    - **Validates: Requirements 2.4**
    - Tag: `% Feature: matlab-network-sim, Property 10: Fiber latency from distance`
    - Generator: random node pairs with fiber links; assert `nominalLatencyMs` = `vincenty(...)` / 200,000,000 × 1000 within floating-point precision

  - [ ]* 4.5 Write property test for effective bandwidth formula and congestion
    - **Property 11: Effective Bandwidth Formula and Congestion**
    - **Validates: Requirements 3.2, 3.3**
    - Tag: `% Feature: matlab-network-sim, Property 11: Effective bandwidth formula`
    - Generator: random bandwidth B and load fraction f in [0, 2]; assert effective BW = B×(1−f) when f < 1, zero and congested when f ≥ 1

- [x] 5. Checkpoint — Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 6. Implement outage and background traffic models
  - [x] 6.1 Implement `network.OutageEngine`
    - Write `+network/OutageEngine.m` as a handle class
    - Implement `scheduleNextOutage(linkId, currentTimeSec)` drawing inter-arrival times from `exprnd(1/outageRate)` and durations from the configured distribution (exponential, lognormal, fixed)
    - On `OUTAGE_END` processing in `SimController`, call `scheduleNextOutage` to chain the next outage
    - Record `OUTAGE_START` and `OUTAGE_END` events in the Event_Log
    - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5_

  - [x] 6.2 Implement `network.BackgroundTrafficModel`
    - Write `+network/BackgroundTrafficModel.m` as a handle class
    - Implement `resample(linkId)` drawing a new load fraction from the configured distribution (uniform, normal clamped, lognormal clamped) and updating `LinkRegistry`
    - Schedule `BACKGROUND_REFRESH` events at the configurable refresh interval (default 60 s)
    - Validate distribution parameters on construction; throw `netsim:link:invalidBgParams` on invalid values
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5_

- [x] 7. Implement the routing engine
  - [x] 7.1 Implement `network.RoutingEngine`
    - Write `+network/RoutingEngine.m` as a handle class wrapping MATLAB's `digraph` and `shortestpath`
    - Implement `selectPath(srcId, dstId, simTimeSec)` returning `[path, totalLatencyMs]`; use `'Method','positive'` (Dijkstra)
    - Implement `invalidateCache(linkId)` for incremental edge removal/addition on outage transitions
    - Implement `rebuildGraph()` for full reconstruction from active links
    - Edge weights are `effectiveLatencyMs` from `LinkRegistry`; outage links and inactive LOS links are excluded
    - _Requirements: 5.2, 5.3, 5.5, 6.1, 6.2, 6.3, 6.4, 6.5_

  - [ ]* 7.2 Write property test for routing selecting minimum-latency active path
    - **Property 6: Routing Selects Minimum Latency Active Path**
    - **Validates: Requirements 5.2, 6.2**
    - Tag: `% Feature: matlab-network-sim, Property 6: Routing selects minimum latency`
    - Generator: random topologies with 2–20 nodes and 2+ active paths; assert selected path latency ≤ all other active path latencies

  - [ ]* 7.3 Write property test for routing excluding outage links
    - **Property 7: Routing Excludes Outage Links**
    - **Validates: Requirements 6.1**
    - Tag: `% Feature: matlab-network-sim, Property 7: Routing excludes outage links`
    - Generator: random topologies with random subsets of links in outage; assert no selected path contains an outage link

  - [ ]* 7.4 Write property test for messages failing on unavailable paths
    - **Property 8: Messages Fail on Unavailable Paths**
    - **Validates: Requirements 4.4, 5.5**
    - Tag: `% Feature: matlab-network-sim, Property 8: Messages fail on unavailable paths`
    - Generator: random topologies with all paths blocked; assert `C2_MESSAGE_FAIL` recorded with reason `"no available path"` and no `C2_MESSAGE_RX` recorded

- [x] 8. Wire network layer into SimController and implement C2 message handling
  - [x] 8.1 Integrate registries, outage engine, background traffic, and routing into `SimController`
    - Construct `NodeRegistry`, `LinkRegistry`, `OutageEngine`, `BackgroundTrafficModel`, and `RoutingEngine` from the loaded scenario in `SimController`
    - Implement `C2_MESSAGE_TX` handler: call `RoutingEngine.selectPath`; on success schedule `C2_MESSAGE_RX` at `txTime + totalLatencyMs/1000`; on failure schedule `C2_MESSAGE_FAIL`
    - Implement `C2_MESSAGE_RX` handler: write delivery record to Event_Log (msgId, src, dst, txTime, deliveryTime, latencyMs)
    - Implement `OUTAGE_START` / `OUTAGE_END` handlers: update `LinkRegistry`, call `RoutingEngine.invalidateCache`, log events
    - Implement `BACKGROUND_REFRESH` handler: call `BackgroundTrafficModel.resample`
    - Schedule initial outage and background-refresh events for all links on scenario load
    - _Requirements: 4.1, 4.2, 4.3, 4.4, 5.1, 5.2, 5.3, 5.4, 5.5, 5.6, 6.3_

  - [x] 8.2 Update `NodeRegistry` position updates in the DES loop
    - Call `NodeRegistry.updatePositions(simTimeSec)` at each event dispatch to keep Mobile node positions current
    - After position update, call `LinkRegistry.setLOSActive` for all LOS links based on `GeoUtils.isLOSVisible`; trigger `OUTAGE_START` / `OUTAGE_END` events when LOS state changes
    - _Requirements: 1.2, 2.5, 2.6_

- [x] 9. Checkpoint — Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 10. Implement scenario I/O
  - [x] 10.1 Implement `io.ScenarioLoader`
    - Write `+io/ScenarioLoader.m` with static methods `load(filePath)` and `save(scenario, filePath)`
    - `load`: read JSON via `jsondecode`, validate all node defs (including trajectory and Keplerian elements), link defs (node references, distribution params), agent defs, and reference behavior file path; throw structured errors per the error-handling table
    - `save`: serialize scenario struct to JSON via `jsonencode` and write to file
    - _Requirements: 7.1, 7.2, 7.3, 7.4, 1.4, 2.7, 3.5, 10.4_

  - [ ]* 10.2 Write property test for scenario round-trip fidelity
    - **Property 1: Scenario Round-Trip Fidelity**
    - **Validates: Requirements 7.5**
    - Tag: `% Feature: matlab-network-sim, Property 1: Scenario round-trip`
    - Generator: random scenario structs with 1–50 nodes and 0–200 links; assert `load(save(scenario))` is field-for-field equivalent to original

- [x] 11. Implement statistics collection and report writing
  - [x] 11.1 Implement statistics accumulation in `SimController`
    - Accumulate per-run counters: total C2 messages scheduled, delivered, failed; per-link outage durations, C2 message counts, background load samples
    - Collect all delivered message latencies into a vector for distribution statistics
    - Record wall-clock start time at `run()` entry and compute duration at completion
    - _Requirements: 9.1, 9.2, 9.3_

  - [x] 11.2 Implement `io.ReportWriter`
    - Write `+io/ReportWriter.m` as a handle class
    - Implement `writeEventLog(eventLog)` writing CSV with columns `eventId,simTimeSec,eventType,linkId,msgId,srcNodeId,dstNodeId,latencyMs,reason`
    - Implement `writeStatisticsReport(stats)` writing JSON matching the schema in §4.3, including `agentFidelity` summary block
    - Implement `writeEvaluationReport(evalResult)` writing JSON matching the schema in §4.4
    - Implement `writeBehaviorTraces(agentRegistry)` writing one CSV per agent with columns per §4.6
    - _Requirements: 8.5, 9.1, 9.2, 9.3, 16.1, 16.2, 16.3_

  - [ ]* 11.3 Write property test for statistics report completeness
    - **Property 19: Statistics Report Completeness**
    - **Validates: Requirements 9.1, 9.2**
    - Tag: `% Feature: matlab-network-sim, Property 19: Statistics report completeness`
    - Generator: random simulation results with 1–100 links; assert all required top-level fields and a per-link entry for every link are present in the output JSON

- [x] 12. Implement visualization functions
  - [x] 12.1 Implement `io.PlotFunctions`
    - Write `+io/PlotFunctions.m` with static methods `latencyHistogram(statsReport)`, `outageGantt(statsReport, linkIds)`, and `fidelityBoxPlot(evalReports)`
    - `latencyHistogram`: plot histogram of delivered C2 message latencies from `statsReport.latency` data
    - `outageGantt`: plot per-link outage timelines as a Gantt-style chart over the simulation time span
    - `fidelityBoxPlot`: plot per-agent fidelity scores across multiple runs as a box-and-whisker chart
    - _Requirements: 9.4, 9.5, 15.5_

- [x] 13. Checkpoint — Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 14. Implement agent role loading and LLM client
  - [x] 14.1 Implement `agent.RoleLoader`
    - Write `+agent/RoleLoader.m` with static method `load(filePath)`
    - Validate file exists and is non-empty; extract role name from first H1 heading (`# <name>`)
    - Return struct `{name, sourceRef, fullMarkdown}`
    - Throw `netsim:agent:roleLoadError` with file path if file is unreadable or empty, or if no H1 heading is found
    - _Requirements: 11.1, 11.2, 11.3, 11.4_

  - [x] 14.2 Implement `agent.LLMClient`
    - Write `+agent/LLMClient.m` as a handle class
    - Constructor accepts `config` struct (`baseUrl`, `apiKey`, `model`, `timeoutSec`, `maxTokens`); read `apiKey` from environment variable `NETSIM_LLM_API_KEY` if not provided; never log the key
    - Implement `complete(systemPrompt, userMessage)` via `webwrite`/`webread` to the OpenAI-compatible chat completions endpoint
    - Return struct `{content, finishReason, usageTokens}`; on HTTP failure throw `netsim:agent:llmError` with HTTP status
    - _Requirements: 13.1, 13.2_

- [x] 15. Implement agent registry and behavior tracing
  - [x] 15.1 Implement `agent.BehaviorTracer`
    - Write `+agent/BehaviorTracer.m` as a handle class
    - Implement `record(simTimeSec, triggerEventId, actionType, targetAgentId, msgId)` appending to an internal MATLAB table
    - Implement `getTrace()` returning the full table
    - Implement `exportCSV(filePath)` writing the trace with columns `simTimeSec,agentId,role,actionType,targetAgentId,msgId`
    - _Requirements: 13.3, 16.2_

  - [ ]* 15.2 Write property test for behavior trace completeness
    - **Property 16: Behavior Trace Completeness**
    - **Validates: Requirements 13.3, 16.2**
    - Tag: `% Feature: matlab-network-sim, Property 16: Behavior trace completeness`
    - Generator: random agent action sequences; assert all required fields present in trace table and CSV export contains all required columns with no missing mandatory values

  - [x] 15.3 Implement `agent.AgentRegistry`
    - Write `+agent/AgentRegistry.m` as a handle class
    - Constructor validates each agent's `nodeId` exists in `NodeRegistry`; throw `netsim:agent:unknownNode` on missing node
    - Implement `deliver(agentId, c2Message, simTimeSec)`: call `LLMClient.complete` with role context + message; record resulting actions in `BehaviorTracer`; schedule any outgoing C2 messages as `C2_MESSAGE_TX` events
    - Implement `checkIdle(agentId, simTimeSec)`: if no message received within `idleTimeoutSec`, generate a role-appropriate status action and record it
    - Schedule `AGENT_IDLE_CHECK` events for each agent at startup
    - _Requirements: 12.1, 12.2, 12.3, 12.4, 12.5, 13.1, 13.2, 13.3, 13.4, 13.5, 11.5_

  - [ ]* 15.4 Write property test for agent message delivery timing
    - **Property 15: Agent Message Delivery Timing**
    - **Validates: Requirements 12.4**
    - Tag: `% Feature: matlab-network-sim, Property 15: Agent message delivery timing`
    - Generator: random messages with known transmission times and path latencies; assert receiving agent is notified at `txTime + latencyMs/1000`, not at `txTime`

- [x] 16. Implement reference behavior loading and fidelity evaluation
  - [x] 16.1 Implement reference behavior loading in `io.ScenarioLoader`
    - Extend `ScenarioLoader.load` to parse the `referenceBehaviorFile` JSON (schema §4.5)
    - Validate all referenced roles exist in the scenario's agent definitions; log `netsim:agent:unassignedRole` warning (do not halt) for roles with no assigned agent
    - Validate all referenced C2 message types exist
    - _Requirements: 14.1, 14.2, 14.4_

  - [x] 16.2 Implement reference behavior save/load round-trip in `io.ScenarioLoader`
    - Add `saveReferenceBehavior(refBehavior, filePath)` and `loadReferenceBehavior(filePath)` static methods
    - _Requirements: 14.3, 14.5_

  - [ ]* 16.3 Write property test for reference behavior round-trip fidelity
    - **Property 2: Reference Behavior Round-Trip Fidelity**
    - **Validates: Requirements 14.5**
    - Tag: `% Feature: matlab-network-sim, Property 2: Reference behavior round-trip`
    - Generator: random reference behavior specs with 1–10 roles, strict and unordered ordering, 1–20 actions each; assert `load(save(spec))` is field-for-field equivalent

  - [x] 16.4 Implement `agent.FidelityEvaluator`
    - Write `+agent/FidelityEvaluator.m` as a handle class
    - Implement `evaluate(behaviorTrace, eventLog)` returning struct `{fidelityScore, missingActions, extraActions, deviations}`
    - Compute `fidelityScore` as fraction of required reference actions present in trace, respecting strict ordering where configured
    - Annotate missing actions caused by network outage/congestion with reason `"network-constrained"` (do not count toward fidelity penalty)
    - Ensure `fidelityScore` is always in [0.0, 1.0]
    - _Requirements: 15.1, 15.2, 15.3, 15.4_

  - [ ]* 16.5 Write property test for fidelity score correctness
    - **Property 4: Fidelity Score Correctness**
    - **Validates: Requirements 15.1, 15.2, 15.3**
    - Tag: `% Feature: matlab-network-sim, Property 4: Fidelity score correctness`
    - Generator: random trace/reference pairs with known overlap fractions; assert score ∈ [0,1] and equals expected fraction; assert consistency with missing/extra action counts

  - [ ]* 16.6 Write property test for network-constrained annotation not penalizing fidelity
    - **Property 5: Network-Constrained Annotation Does Not Penalize Fidelity**
    - **Validates: Requirements 15.4**
    - Tag: `% Feature: matlab-network-sim, Property 5: Network-constrained annotation`
    - Generator: random scenarios with injected network failures on specific message paths; assert fidelity score equals score computed with those actions excluded from reference, and missing actions annotated `"network-constrained"`

- [x] 17. Checkpoint — Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 18. Implement evaluation reporting and batch support
  - [x] 18.1 Wire `FidelityEvaluator` into `SimController` and `ReportWriter`
    - After simulation completes, call `FidelityEvaluator.evaluate` for each agent and collect results
    - Pass evaluation results to `ReportWriter.writeEvaluationReport` and include `agentFidelity` summary in `writeStatisticsReport`
    - Assign a UUID run identifier and ISO-8601 timestamp to each run
    - _Requirements: 15.1, 15.3, 16.1, 16.3_

  - [x] 18.2 Implement batch run support and combined evaluation report
    - Write a `runBatch(scenarioFiles, outputDir)` function (or method on `SimController`) that executes multiple scenario files sequentially
    - Aggregate per-run `EvaluationReport` structs into a combined report with unique `runId` and `timestamp` per run
    - Write the combined report via `ReportWriter`
    - _Requirements: 16.5_

  - [ ]* 18.3 Write property test for evaluation report consistency
    - **Property 3: Evaluation Report Consistency**
    - **Validates: Requirements 16.4**
    - Tag: `% Feature: matlab-network-sim, Property 3: Evaluation report consistency`
    - Generator: random evaluation results with 1–20 agents and random fidelity scores; write to JSON, reload, recompute mean/min/max; assert values identical to those in file

  - [ ]* 18.4 Write property test for batch evaluation report run uniqueness
    - **Property 18: Batch Evaluation Report Run Uniqueness**
    - **Validates: Requirements 16.5**
    - Tag: `% Feature: matlab-network-sim, Property 18: Batch evaluation report uniqueness`
    - Generator: random sets of 2–10 evaluation reports; assert all `runId` values are distinct, all `timestamp` values are distinct ISO-8601 strings, and union of per-run fidelity scores matches individual reports

- [x] 19. Final integration and wiring
  - [x] 19.1 Wire agent layer into `SimController`
    - Construct `AgentRegistry` from scenario agent definitions in `SimController`
    - Implement `C2_MESSAGE_RX` handler path for agent-bound destination nodes: call `AgentRegistry.deliver` at the computed delivery simulation time
    - Implement `AGENT_IDLE_CHECK` handler: call `AgentRegistry.checkIdle`
    - Pause simulation clock while awaiting LLM response (synchronous `LLMClient.complete` call already blocks; ensure `SimClock` does not advance during this period)
    - _Requirements: 12.2, 12.3, 12.4, 13.1, 13.2, 13.5_

  - [x] 19.2 Implement `inspect()` state snapshot in `SimController`
    - Return a struct containing current state of all nodes (positions), all links (active/outage/effective BW), and count of queued C2 messages
    - _Requirements: 8.3_

  - [x] 19.3 Write integration test: 5-node mixed-link scenario
    - Create a 5-node, 6-link scenario (one GEO satellite link, one fiber link, one LOS link, one LEO link, two additional links) as a JSON fixture
    - Run the full simulation and assert: event log CSV is written and parseable; statistics report JSON contains all required fields; LOS link transitions to outage when mobile node moves outside coverage radius; delivered message latencies are consistent with link types
    - _Requirements: 2.2, 2.3, 2.4, 2.5, 2.6, 4.1, 5.4, 8.5, 9.1, 9.2, 9.3_

  - [ ]* 19.4 Write integration test: agent behavior with mock LLM
    - Create a Mission_Scenario fixture with two agents (Aircrew and Command_Staff) bound to nodes
    - Use a mock HTTP server returning canned LLM responses
    - Assert: behavior traces are written with all required columns; fidelity evaluation produces a score in [0,1]; evaluation report JSON contains all required fields; agent messages are delivered at `txTime + latency`, not at `txTime`
    - _Requirements: 12.4, 13.1, 13.3, 15.1, 16.1, 16.2_

- [x] 20. Final checkpoint — Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for a faster MVP; all property-based tests are optional sub-tasks
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation after each major phase
- Property tests use the `matlab-prop-test` library with a minimum of 100 iterations per property
- Unit tests use `matlab.unittest.TestCase` and live under `tests/` mirroring the package structure
- The LLM API key is read from the `NETSIM_LLM_API_KEY` environment variable and must never be logged or committed

---

## Phase 5: ICAM Foundation

- [ ] 21. Set up `+icam/` package structure and test directory
  - Create the `+icam/` package folder at the project root
  - Create the `tests/icam/` test directory mirroring the package structure
  - Add a `tests/icam/README.md` describing the ICAM test suite conventions
  - Add placeholder `.gitkeep` or empty test file so the directory is tracked
  - Confirm `matlab.unittest.TestRunner` can discover the new test directory without error
  - _Requirements: 17.1, 17.2_

- [ ] 22. Implement `icam.EntityRegistry`
  - [ ] 22.1 Implement `icam.EntityRegistry` with struct-of-arrays storage
    - Write `+icam/EntityRegistry.m` as a handle class using struct-of-arrays storage (`entityId`, `nodeId`, `entityType`, `parentEntityId`, `enclaveIds`)
    - Constructor accepts `entityDefs` struct array and a `nodeRegistry` reference; validate every `nodeId` against `NodeRegistry`; throw `netsim:icam:unknownNode` with entity ID + node ID on missing node
    - Detect duplicate `entityId` values on construction; throw `netsim:icam:duplicateEntityId` with the offending ID
    - Implement `addEntity(def)`, `getEntity(entityId)`, `getSubEntities(nodeId)`, `indexOf(entityId)`, `count()`
    - _Requirements: 17.1, 17.2, 17.3, 17.4, 17.5_

  - [ ]* 22.2 Write unit tests for `icam.EntityRegistry`
    - Test construction with valid entity definitions referencing existing nodes
    - Test `netsim:icam:unknownNode` thrown when entity references a missing node
    - Test `netsim:icam:duplicateEntityId` thrown on duplicate entity IDs
    - Test `getSubEntities` returns all and only entities hosted at a given node
    - Test `indexOf` returns the correct integer index; test `count` returns total entity count
    - _Requirements: 17.3, 17.4, 17.5_

  - [ ]* 22.3 Write property test for `EntityRegistry` memory scalability
    - **Property 26 (partial): NPE Identity Equivalence — struct-of-arrays storage**
    - **Validates: Requirements 17.5, 24.4**
    - Tag: `% Feature: matlab-network-sim, Property 26: NPE identity equivalence`
    - Generator: random entity sets of 100–10,000 entities (mix of human and NPE); assert construction completes without memory error and `count()` equals input size

- [ ] 23. Implement `icam.CredentialStore`
  - [ ] 23.1 Implement `icam.CredentialStore` with certificate lifecycle management
    - Write `+icam/CredentialStore.m` as a handle class
    - Implement `issueCertificate(entityId, trustAnchorId, roleBindings, validityPeriodSec, simTimeSec)`: create certificate struct with `expirySec = simTimeSec + validityPeriodSec`, synthetic hex public key, and `isExpired = false`; store keyed by `entityId`
    - Implement `getCertificate(entityId)`: return certificate struct; throw `netsim:icam:noCertificate` if none exists
    - Implement `checkExpiry(simTimeSec)`: return cell array of `entityId` strings whose `expirySec <= simTimeSec` and `isExpired == false`; mark matching certificates as expired
    - Implement `revoke(entityId)`: mark certificate as expired immediately
    - _Requirements: 18.1, 18.2, 18.3, 18.6_

  - [ ]* 23.2 Write unit tests for `icam.CredentialStore`
    - Test `issueCertificate` computes `expirySec = simTimeSec + validityPeriodSec` correctly
    - Test `getCertificate` returns the stored certificate; test `netsim:icam:noCertificate` thrown for unknown entity
    - Test `checkExpiry` returns all and only entities whose expiry time has been reached; verify `isExpired` flag is set
    - Test `revoke` marks certificate expired immediately and `checkExpiry` no longer re-reports it
    - _Requirements: 18.1, 18.3, 18.6_

  - [ ]* 23.3 Write property test for certificate expiry detection
    - **Property 22: Certificate Expiry Detection**
    - **Validates: Requirements 18.3**
    - Tag: `% Feature: matlab-network-sim, Property 22: Certificate expiry detection`
    - Generator: random sets of 1–50 certificates with random `expirySec` values; random `simTimeSec` advances; assert `checkExpiry` returns exactly the set of entities with `expirySec <= simTimeSec` and `isExpired == false` before the call

- [ ] 24. Checkpoint — Ensure all ICAM foundation tests pass
  - Ensure all tests pass, ask the user if questions arise.

---

## Phase 6: Authentication and Policy

- [ ] 25. Implement `icam.AuthenticationManager`
  - [ ] 25.1 Implement `icam.AuthenticationManager` with pair tracking and exchange scheduling
    - Write `+icam/AuthenticationManager.m` as a handle class
    - Use `containers.Map` keyed on canonical pair string (`min(A,B) + '|' + max(A,B)`) to store authentication state per entity pair
    - Implement `isAuthenticated(entityIdA, entityIdB)`: return `true` if pair has a recorded successful authentication
    - Implement `initiateExchange(entityIdA, entityIdB, simTimeSec, eventCalendar)`: schedule `AUTH_REQUEST` event at `simTimeSec`; schedule `AUTH_RESPONSE` event at `simTimeSec + authRequestLatency`; schedule `AUTH_TIMEOUT` event at `simTimeSec + retryLimitSec`
    - Implement `recordSuccess(entityIdA, entityIdB, simTimeSec)`: mark pair as authenticated; cancel pending `AUTH_TIMEOUT`
    - Implement `recordFailure(entityIdA, entityIdB, reason)`: increment retry counter; re-schedule `AUTH_REQUEST` if retries remain; record failure reason
    - _Requirements: 19.1, 19.2, 19.3, 19.4, 19.5, 19.6_

  - [ ]* 25.2 Write unit tests for `icam.AuthenticationManager`
    - Test `isAuthenticated` returns `false` before any exchange and `true` after `recordSuccess`
    - Test `initiateExchange` schedules `AUTH_REQUEST`, `AUTH_RESPONSE`, and `AUTH_TIMEOUT` events with correct types and times
    - Test `recordFailure` increments retry counter; verify `AUTH_REQUEST` is re-scheduled when retries remain
    - Test canonical pair key is order-independent (`A|B` same as `B|A`)
    - _Requirements: 19.3, 19.4, 19.5_

  - [ ]* 25.3 Write property test for authentication exchange completeness
    - **Property 20: Authentication Exchange Completeness**
    - **Validates: Requirements 19.1, 19.3**
    - Tag: `% Feature: matlab-network-sim, Property 20: Authentication exchange completeness`
    - Generator: random entity pairs with no prior auth state; random message types; assert exactly one `AUTH_REQUEST` and one `AUTH_RESPONSE` event are scheduled per `initiateExchange` call before `recordSuccess` is called

- [ ] 26. Implement `icam.PolicyDecisionPoint`
  - [ ] 26.1 Implement `icam.PolicyDecisionPoint` with policy JSON loading and rule evaluation
    - Write `+icam/PolicyDecisionPoint.m` as a handle class
    - Constructor accepts `policyFilePath`; load and validate policy JSON (enclaves, trustAnchors, rules arrays); throw `netsim:icam:policyJsonError` with file path on syntax error
    - Validate all `roleBindings` in entity definitions reference defined enclaves and role names; throw `netsim:icam:unknownEnclave` or `netsim:icam:unknownRole` as appropriate
    - Implement `evaluate(requestingEntityId, targetEntityId, messageType, enclaveId, simTimeSec)`: apply rules in order; first matching rule wins; support `*` wildcard in `messageType` field; return struct `{decision, reason}`
    - Apply `failPolicy` (`'open'` or `'closed'`) when no rule matches or when called with `pdpUnreachable = true`; record `pdp-unreachable` event in Event_Log
    - _Requirements: 20.1, 20.3, 20.5, 22.1, 22.2, 22.5_

  - [ ]* 26.2 Write unit tests for `icam.PolicyDecisionPoint`
    - Test permit and deny decisions for rules with exact `messageType` match
    - Test first-matching-rule semantics (earlier rule takes precedence over later conflicting rule)
    - Test `*` wildcard in `messageType` matches any message type string
    - Test fail-open returns `'permit'` when no rule matches; test fail-closed returns `'deny'`
    - Test `netsim:icam:policyJsonError` thrown on malformed policy JSON
    - _Requirements: 20.3, 20.5_

  - [ ]* 26.3 Write property test for PDP unreachable fail policy
    - **Property 24: PDP Unreachable Fail Policy**
    - **Validates: Requirements 20.5**
    - Tag: `% Feature: matlab-network-sim, Property 24: PDP unreachable fail policy`
    - Generator: random policy configurations with fail-open and fail-closed settings; random query inputs with `pdpUnreachable = true`; assert all decisions are `'permit'` for fail-open and `'deny'` for fail-closed

- [ ] 27. Implement `icam.CredentialCache`
  - [ ] 27.1 Implement `icam.CredentialCache` with TTL-based lookup and invalidation
    - Write `+icam/CredentialCache.m` as a handle class
    - Constructor accepts `ttlConfigMap` (`containers.Map` of `enclaveId → ttlSec`; `0` means caching disabled)
    - Cache key: `entityId + '|' + resourceType + '|' + enclaveId`; cache entry struct: `{decision, timestamp, ttl}`
    - Implement `lookup(entityId, resourceType, enclaveId, simTimeSec)`: return `'permit'`, `'deny'`, or `''` (miss); return `''` if TTL is 0 or entry age exceeds TTL
    - Implement `store(entityId, resourceType, enclaveId, decision, simTimeSec)`: store entry; no-op if TTL is 0
    - Implement `invalidateEnclave(enclaveId)`: remove all cache entries for the specified enclave across all entities
    - Implement `getStats()`: return struct `{hits, misses, invalidations}`
    - _Requirements: 23.1, 23.2, 23.3, 23.4, 23.5, 23.6_

  - [ ]* 27.2 Write unit tests for `icam.CredentialCache`
    - Test cache hit within TTL returns stored decision without calling PDP
    - Test cache miss after TTL expiry returns `''`
    - Test TTL = 0 always returns `''` (caching disabled for enclave)
    - Test `invalidateEnclave` removes only entries for the specified enclave; entries for other enclaves are unaffected
    - Test `getStats` returns correct hit, miss, and invalidation counts
    - _Requirements: 23.2, 23.3, 23.4, 23.5, 23.6_

  - [ ]* 27.3 Write property test for credential cache consistency
    - **Property 21: Credential Cache Consistency**
    - **Validates: Requirements 23.7**
    - Tag: `% Feature: matlab-network-sim, Property 21: Credential cache consistency`
    - Generator: random policy rules and query sequences (same inputs repeated); assert sequence of decisions is identical with cache enabled vs. disabled, provided no policy changes occur between queries

  - [ ]* 27.4 Write property test for multi-enclave role independence
    - **Property 25: Multi-Enclave Role Independence**
    - **Validates: Requirements 22.2, 22.3, 22.4**
    - Tag: `% Feature: matlab-network-sim, Property 25: Multi-enclave role independence`
    - Generator: random entities with 2–5 enclaves; random `invalidateEnclave` calls on one enclave; assert cache entries for all other enclaves are unaffected

- [ ] 28. Checkpoint — Ensure all authentication and policy tests pass
  - Ensure all tests pass, ask the user if questions arise.

---

## Phase 7: Enforcement and Integration

- [ ] 29. Implement `icam.PolicyEnforcementPoint`
  - [ ] 29.1 Implement `icam.PolicyEnforcementPoint` with cache-first PDP-fallback enforcement
    - Write `+icam/PolicyEnforcementPoint.m` as a handle class
    - Constructor accepts `credentialCache`, `policyDecisionPoint`, and `eventLog` references
    - Implement `checkSend(srcEntityId, dstEntityId, messageType, enclaveId, simTimeSec)`: call `CredentialCache.lookup` first; on cache miss call `PolicyDecisionPoint.evaluate` and store result in cache; return struct `{decision, reason, cacheHit}`; on deny record `access-denied` event in Event_Log with `srcEntityId`, `dstEntityId`, `messageType`
    - Implement `checkReceive(dstEntityId, messageType, enclaveId, simTimeSec)`: same cache-first pattern; on deny record `access-denied` event
    - _Requirements: 21.1, 21.2, 21.3, 21.4, 21.5_

  - [ ]* 29.2 Write unit tests for `icam.PolicyEnforcementPoint`
    - Test cache hit path: `CredentialCache.lookup` returns decision without calling PDP
    - Test cache miss path: `PolicyDecisionPoint.evaluate` is called and result is stored in cache
    - Test deny path: `access-denied` event is recorded in Event_Log with correct entity IDs and message type
    - Test `checkReceive` enforces receive-side access control independently of `checkSend`
    - _Requirements: 21.2, 21.3, 21.4_

- [ ] 30. Implement `icam.ICAMController`
  - [ ] 30.1 Implement `icam.ICAMController` as the top-level ICAM coordinator
    - Write `+icam/ICAMController.m` as a handle class
    - Implement `initialize(scenario, nodeRegistry, eventCalendar)`: construct `EntityRegistry`, `CredentialStore`, `AuthenticationManager`, `PolicyDecisionPoint`, `CredentialCache`, `PolicyEnforcementPoint`; issue initial certificates for all entities via `CredentialStore.issueCertificate`; schedule initial `CERT_RENEWAL_REQUEST` events for entities with pre-configured expiry times
    - Implement `checkSend(srcEntityId, dstEntityId, messageType, enclaveId, simTimeSec)`: call `AuthenticationManager.isAuthenticated`; if not authenticated call `initiateExchange` and return `'pending'`; call `PolicyEnforcementPoint.checkSend`; return `'permit'` or `'deny'`
    - Implement event handlers: `handleAuthRequest(event)`, `handleAuthResponse(event)`, `handleAuthTimeout(event)`, `handleCertRenewal(event)`
    - Implement `checkExpiredCredentials(simTimeSec)`: delegate to `CredentialStore.checkExpiry`; schedule `CERT_RENEWAL_REQUEST` events for expired entities
    - Implement `buildICAMReport()`: aggregate statistics from all ICAM subsystems into the ICAM statistics struct (§6.4 schema)
    - _Requirements: 17.1, 18.3, 18.4, 18.5, 19.1, 19.2, 19.5, 20.1, 20.6, 21.1, 21.5, 23.6, 24.1, 24.5_

  - [ ]* 30.2 Write unit tests for `icam.ICAMController`
    - Test `initialize` issues certificates for all entities and schedules `CERT_RENEWAL_REQUEST` events for entities with pre-configured expiry
    - Test `checkSend` returns `'deny'` when `PolicyEnforcementPoint` denies; returns `'permit'` when permitted
    - Test `handleAuthResponse` with `success = true` calls `AuthenticationManager.recordSuccess`
    - Test `handleAuthTimeout` calls `AuthenticationManager.recordFailure` with reason `'timeout'`
    - Test `buildICAMReport` returns struct containing all required top-level fields from §6.4
    - _Requirements: 18.3, 19.3, 19.5, 20.6_

- [ ] 31. Wire `ICAMController` into `SimController`
  - [ ] 31.1 Add optional `icamController` property to `SimController` and hook into `C2_MESSAGE_TX` handler
    - Add `icamController` property (default `[]`) to `+sim/SimController.m`
    - In the `C2_MESSAGE_TX` event handler, add ICAM gate: if `~isempty(sc.icamController)`, call `sc.icamController.checkSend(srcEntityId, dstEntityId, msgType, enclaveId, t)`; if decision is `'deny'`, record `ACCESS_DENIED` event in Event_Log and return without routing; if `'permit'`, continue with existing routing logic
    - Add new ICAM event type constants to `sim.EventCalendar`: `AUTH_REQUEST`, `AUTH_RESPONSE`, `AUTH_TIMEOUT`, `CERT_RENEWAL_REQUEST`, `CERT_RENEWAL_RESPONSE`, `POLICY_SYNC`
    - Dispatch ICAM events in the DES main loop to the appropriate `ICAMController` handler methods
    - Call `icamController.checkExpiredCredentials(simTimeSec)` at each event dispatch when `icamController` is present
    - _Requirements: 19.2, 20.2, 20.4, 21.1, 21.2, 21.3_

  - [ ]* 31.2 Write unit tests for ICAM-gated `SimController`
    - Test that `C2_MESSAGE_TX` is discarded and `ACCESS_DENIED` event recorded when `ICAMController.checkSend` returns `'deny'`
    - Test that `C2_MESSAGE_TX` proceeds to routing when `ICAMController.checkSend` returns `'permit'`
    - Test that `SimController` without `icamController` set behaves identically to pre-ICAM behavior (no regression)
    - Test that ICAM event types are dispatched to the correct `ICAMController` handler methods
    - _Requirements: 21.1, 21.2, 21.3_

- [ ] 32. Extend `ScenarioLoader` and `ReportWriter` for ICAM
  - [ ] 32.1 Extend `io.ScenarioLoader` to parse ICAM fields
    - In `+io/ScenarioLoader.m`, extend `load` to parse the top-level `"entities"` array from the scenario JSON (§6.1 schema): entity ID, node ID, type, parent entity ID, enclave IDs, role bindings, and certificate configuration
    - Validate all entity `nodeId` references exist in the loaded node definitions; throw `netsim:icam:unknownNode` on missing node
    - Validate all `roleBindings` reference defined enclaves and role names; throw `netsim:icam:unknownEnclave` or `netsim:icam:unknownRole` as appropriate
    - Parse the `"policyDefinitionFile"` field from the scenario JSON and include it in the returned scenario struct
    - Extend `save` to serialize the `entities` array and `policyDefinitionFile` field back to JSON
    - _Requirements: 17.3, 17.4, 17.6, 22.5_

  - [ ] 32.2 Extend `io.ReportWriter` to write ICAM statistics block
    - In `+io/ReportWriter.m`, extend `writeStatisticsReport(stats)` to include the `"icam"` block (§6.4 schema) when `stats.icam` is present
    - Include `authExchanges`, `cacheHitRate`, `accessDeniedCount`, `certRenewals`, `pdpStats`, `entityCounts`, and `perEnclaveRoleBindingCounts` sub-fields
    - Include per-entity access-denied counts and per-enclave access-denied counts as specified in Requirement 21.5
    - Include NPE counts, authentication event counts, and access-denied event counts as distinct categories per Requirement 24.5
    - _Requirements: 20.6, 21.5, 22.6, 23.6, 24.5_

  - [ ]* 32.3 Write unit tests for ICAM scenario loading and report writing
    - Test `ScenarioLoader.load` correctly parses `entities` array and `policyDefinitionFile` from a fixture JSON
    - Test `netsim:icam:unknownNode` thrown when entity references a missing node
    - Test `netsim:icam:unknownEnclave` thrown when role binding references an undefined enclave
    - Test `ReportWriter.writeStatisticsReport` includes the `"icam"` block with all required sub-fields when `stats.icam` is present
    - Test round-trip: `load(save(scenario))` preserves all entity definitions and policy file path
    - _Requirements: 17.3, 17.6, 20.6, 21.5_

- [ ] 33. Checkpoint — Ensure all ICAM integration tests pass
  - Ensure all tests pass, ask the user if questions arise.

---

## Phase 8: Scenario and Final

- [ ] 34. Add ICAM configuration to the airdrop mission scenario
  - [ ] 34.1 Define entities for crew members and NPE agents in `airdrop_mission.json`
    - Add a top-level `"entities"` array to `scenarios/airdrop_mission/airdrop_mission.json`
    - Define one human Sub_Entity per crew member role (Aircrew, Ground_Personnel, Air_Traffic_Management, Command_Staff), each bound to the appropriate node
    - Define one NPE Sub_Entity per AI agent in the scenario, bound to the same nodes as their human counterparts
    - Assign each entity to the relevant enclaves (`enclave-alpha` for operational traffic, `enclave-bravo` for command traffic)
    - _Requirements: 17.1, 17.2, 22.1, 24.1, 24.2_

  - [ ] 34.2 Define enclaves, policy rules, and Trust_Anchor nodes in the airdrop scenario
    - Create `scenarios/airdrop_mission/icam_policy.json` following the §6.3 schema
    - Define at least two enclaves (`enclave-alpha`, `enclave-bravo`) with distinct `cacheTtlSec` and `failPolicy` settings
    - Define policy rules permitting crew roles to send and receive operational C2 message types; define at least one deny rule to exercise the access-denied path
    - Add Trust_Anchor node definitions to the scenario (stationary nodes acting as certificate authorities)
    - Set `"policyDefinitionFile": "icam_policy.json"` in `airdrop_mission.json`
    - _Requirements: 18.1, 18.2, 20.1, 21.1, 22.1, 22.3_

- [ ] 35. Write integration test: ICAM-enabled airdrop mission
  - [ ] 35.1 Write `tests/integration/ICAMAirdropIntegrationTest.m`
    - Load the ICAM-enabled `airdrop_mission.json` scenario via `ScenarioLoader`
    - Construct `SimController` with `icamController` wired in via `ICAMController.initialize`
    - Run the full simulation and assert:
      - At least one `AUTH_REQUEST` and one `AUTH_RESPONSE` event appear in the Event_Log for first-contact entity pairs
      - At least one PDP query C2_Message is generated (cache miss path exercised)
      - At least one `ACCESS_DENIED` event is recorded in the Event_Log (deny rule exercised)
      - At least one `CERT_RENEWAL_REQUEST` event is scheduled (certificate expiry exercised)
      - The Statistics_Report JSON contains the `"icam"` block with all required sub-fields
      - `authExchanges.successful` > 0 and `certRenewals.total` > 0 in the ICAM report
    - _Requirements: 18.3, 18.4, 19.1, 19.3, 20.2, 20.6, 21.2, 21.5, 23.6, 24.1_

  - [ ]* 35.2 Write property test for NPE identity equivalence
    - **Property 26: NPE Identity Equivalence**
    - **Validates: Requirements 24.1, 24.3**
    - Tag: `% Feature: matlab-network-sim, Property 26: NPE identity equivalence`
    - Generator: random NPE/human entity pairs with equivalent enclave memberships, role bindings, and certificate validity periods; run ICAM event sequences for both; assert sequences are structurally identical (same event types and counts), differing only in entity ID and type fields

  - [ ]* 35.3 Write property test for access-denied does not penalize fidelity
    - **Property 23: Access-Denied Does Not Penalize Fidelity**
    - **Validates: Requirements 21.6**
    - Tag: `% Feature: matlab-network-sim, Property 23: Access-denied does not penalize fidelity`
    - Generator: random scenarios where access-denied decisions block Agent_Actions that appear in the Reference_Behavior; assert Fidelity_Score equals score computed with those actions excluded from the reference set; assert missing actions annotated with `"access-denied"`

- [ ] 36. Final ICAM checkpoint — Ensure all tests pass
  - Run `tests/run_all_tests.m` and confirm all unit, integration, and property tests pass
  - Ensure all ICAM-related tests in `tests/icam/` pass without error
  - Ensure the airdrop mission integration test (`ICAMAirdropIntegrationTest`) passes end-to-end
  - Ensure all tests pass, ask the user if questions arise.
