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

- [ ] 14. Implement agent role loading and LLM client
  - [ ] 14.1 Implement `agent.RoleLoader`
    - Write `+agent/RoleLoader.m` with static method `load(filePath)`
    - Validate file exists and is non-empty; extract role name from first H1 heading (`# <name>`)
    - Return struct `{name, sourceRef, fullMarkdown}`
    - Throw `netsim:agent:roleLoadError` with file path if file is unreadable or empty, or if no H1 heading is found
    - _Requirements: 11.1, 11.2, 11.3, 11.4_

  - [ ] 14.2 Implement `agent.LLMClient`
    - Write `+agent/LLMClient.m` as a handle class
    - Constructor accepts `config` struct (`baseUrl`, `apiKey`, `model`, `timeoutSec`, `maxTokens`); read `apiKey` from environment variable `NETSIM_LLM_API_KEY` if not provided; never log the key
    - Implement `complete(systemPrompt, userMessage)` via `webwrite`/`webread` to the OpenAI-compatible chat completions endpoint
    - Return struct `{content, finishReason, usageTokens}`; on HTTP failure throw `netsim:agent:llmError` with HTTP status
    - _Requirements: 13.1, 13.2_

- [ ] 15. Implement agent registry and behavior tracing
  - [ ] 15.1 Implement `agent.BehaviorTracer`
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

  - [ ] 15.3 Implement `agent.AgentRegistry`
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

- [ ] 16. Implement reference behavior loading and fidelity evaluation
  - [ ] 16.1 Implement reference behavior loading in `io.ScenarioLoader`
    - Extend `ScenarioLoader.load` to parse the `referenceBehaviorFile` JSON (schema §4.5)
    - Validate all referenced roles exist in the scenario's agent definitions; log `netsim:agent:unassignedRole` warning (do not halt) for roles with no assigned agent
    - Validate all referenced C2 message types exist
    - _Requirements: 14.1, 14.2, 14.4_

  - [ ] 16.2 Implement reference behavior save/load round-trip in `io.ScenarioLoader`
    - Add `saveReferenceBehavior(refBehavior, filePath)` and `loadReferenceBehavior(filePath)` static methods
    - _Requirements: 14.3, 14.5_

  - [ ]* 16.3 Write property test for reference behavior round-trip fidelity
    - **Property 2: Reference Behavior Round-Trip Fidelity**
    - **Validates: Requirements 14.5**
    - Tag: `% Feature: matlab-network-sim, Property 2: Reference behavior round-trip`
    - Generator: random reference behavior specs with 1–10 roles, strict and unordered ordering, 1–20 actions each; assert `load(save(spec))` is field-for-field equivalent

  - [ ] 16.4 Implement `agent.FidelityEvaluator`
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

- [ ] 17. Checkpoint — Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 18. Implement evaluation reporting and batch support
  - [ ] 18.1 Wire `FidelityEvaluator` into `SimController` and `ReportWriter`
    - After simulation completes, call `FidelityEvaluator.evaluate` for each agent and collect results
    - Pass evaluation results to `ReportWriter.writeEvaluationReport` and include `agentFidelity` summary in `writeStatisticsReport`
    - Assign a UUID run identifier and ISO-8601 timestamp to each run
    - _Requirements: 15.1, 15.3, 16.1, 16.3_

  - [ ] 18.2 Implement batch run support and combined evaluation report
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

- [ ] 19. Final integration and wiring
  - [ ] 19.1 Wire agent layer into `SimController`
    - Construct `AgentRegistry` from scenario agent definitions in `SimController`
    - Implement `C2_MESSAGE_RX` handler path for agent-bound destination nodes: call `AgentRegistry.deliver` at the computed delivery simulation time
    - Implement `AGENT_IDLE_CHECK` handler: call `AgentRegistry.checkIdle`
    - Pause simulation clock while awaiting LLM response (synchronous `LLMClient.complete` call already blocks; ensure `SimClock` does not advance during this period)
    - _Requirements: 12.2, 12.3, 12.4, 13.1, 13.2, 13.5_

  - [ ] 19.2 Implement `inspect()` state snapshot in `SimController`
    - Return a struct containing current state of all nodes (positions), all links (active/outage/effective BW), and count of queued C2 messages
    - _Requirements: 8.3_

  - [ ] 19.3 Write integration test: 5-node mixed-link scenario
    - Create a 5-node, 6-link scenario (one GEO satellite link, one fiber link, one LOS link, one LEO link, two additional links) as a JSON fixture
    - Run the full simulation and assert: event log CSV is written and parseable; statistics report JSON contains all required fields; LOS link transitions to outage when mobile node moves outside coverage radius; delivered message latencies are consistent with link types
    - _Requirements: 2.2, 2.3, 2.4, 2.5, 2.6, 4.1, 5.4, 8.5, 9.1, 9.2, 9.3_

  - [ ]* 19.4 Write integration test: agent behavior with mock LLM
    - Create a Mission_Scenario fixture with two agents (Aircrew and Command_Staff) bound to nodes
    - Use a mock HTTP server returning canned LLM responses
    - Assert: behavior traces are written with all required columns; fidelity evaluation produces a score in [0,1]; evaluation report JSON contains all required fields; agent messages are delivered at `txTime + latency`, not at `txTime`
    - _Requirements: 12.4, 13.1, 13.3, 15.1, 16.1, 16.2_

- [ ] 20. Final checkpoint — Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for a faster MVP; all property-based tests are optional sub-tasks
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation after each major phase
- Property tests use the `matlab-prop-test` library with a minimum of 100 iterations per property
- Unit tests use `matlab.unittest.TestCase` and live under `tests/` mirroring the package structure
- The LLM API key is read from the `NETSIM_LLM_API_KEY` environment variable and must never be logged or committed
