# Known Issues

## Issue 1: ICAM entity-ID mapping uses node IDs instead of entity IDs

**Severity:** High  
**Component:** `+sim/SimController.m` (handleC2MessageTx ICAM gate)  
**Symptom:** All C2 messages in scenarios with ICAM entities get "access-denied" even when policy rules should permit them.

**Root Cause:** The SimController ICAM gate (line ~680) uses `srcEntityId = srcId` where `srcId` is the **node ID** (e.g., "AIRCRAFT"). The policy rules define permissions for **entity IDs** (e.g., "pilot-01", "aircraft-npe") which are hosted on those nodes. Since no entity with ID "AIRCRAFT" exists in the EntityRegistry, the PDP falls through to the catch-all deny rule.

**Expected Behavior:** The ICAM gate should resolve the sending entity from the C2 message context. Options:
1. C2 messages should carry a `senderEntityId` field identifying which entity on the node is sending
2. The SimController should look up the primary entity (or NPE) on the source node via the EntityRegistry
3. The enclave should be resolved from the message context rather than hardcoded to "default"

**Affected Scenarios:** Any scenario with both `entities` and `policyDefinitionFile` — currently `airdrop_icam`, `otis_to_wright_patt`, `simple_auth`.

---

## Issue 2: ICAM enclave hardcoded to "default" in SimController

**Severity:** Medium  
**Component:** `+sim/SimController.m` (handleC2MessageTx)  
**Symptom:** The `enclaveId` parameter passed to `checkSend` is always `'default'`, but scenarios define enclaves like `mission_ops` and `flight_ops`. Policy rules scoped to specific enclaves never match.

**Fix:** Resolve the appropriate enclave from the message context, the sender's role bindings, or the scenario's default enclave configuration.

---

## Issue 3: Video generator crashes on cell-array nodes from jsondecode

**Severity:** Medium (fixed for findNodeDef, may recur elsewhere)  
**Component:** `+io/MissionVideoGenerator.m`  
**Symptom:** "Dot indexing is not supported for variables of this type" when scenario nodes have mixed fields (e.g., some nodes have `dataStore`/`dataStoreConfig`, others don't), causing `jsondecode` to return a cell array instead of a struct array.

**Current State:** Fixed in `findNodeDef`. May still be latent in `renderFrame` if trajectory rendering accesses `scenarioStruct.nodes` directly as a struct array.

**Fix:** Audit all code paths that iterate over `scenarioStruct.nodes` and add cell-array handling.

---

## Issue 4: BACKGROUND_REFRESH events removed from log but still counted in stats

**Severity:** Low  
**Component:** `+sim/SimController.m` (handleBackgroundRefresh)  
**Symptom:** The `stats.bgRefreshCount` counter still increments, but no log entry is written. Stats report shows bgRefreshCount > 0 while event log has no BACKGROUND_REFRESH entries, which could confuse analysis tools expecting consistency.

**Fix:** Either also remove the counter increment, or document that bgRefreshCount reflects internal state not visible in the event log.

---

## Issue 5: MissionVideoGenerator resolution config not fully effective

**Severity:** Low  
**Component:** `+io/MissionVideoGenerator.m` (createFigure / writeVideo)  
**Symptom:** The `config.resolution` field sets the figure Position, but `getframe` captures at the system's actual pixel dimensions (affected by Retina/HiDPI scaling). The workaround (imresize to match first frame) works but means the actual video resolution may differ from the configured value.

**Fix:** Use `print` with `-r` flag to render at exact pixel dimensions, or set the figure `Units` to `pixels` and the renderer to `painters`/`opengl` with explicit `PaperPosition`.

---

## Issue 6: DataFabricController not wired for DATA_* events in DES dispatch loop

**Severity:** Medium  
**Component:** `+sim/SimController.m` (dispatch method)  
**Symptom:** The SimController dispatch switch handles `DATA_INGEST`, `DATA_FETCH`, etc. event types in the EventCalendar constants, but the dispatch method doesn't have `case` entries for them. Data fabric events scheduled by the FabricEventHandler or ReplicationEngine would be unhandled.

**Fix:** Add dispatch cases for all DATA_* event types that delegate to `sc.dataFabricController.handleDataEvent(event, sc.simTimeSec, sc.eventCalendar, sc.icamController)`.

---

## Issue 7: EventArchiver writes overwrite rather than append across flushes

**Severity:** Medium  
**Component:** `+data/SimulationStore.m` (createAndWrite)  
**Symptom:** Each flush overwrites the previous flush's datasets. The `createAndWrite` method deletes and recreates the dataset on each call. For a run with multiple flushes, only the last flush's events survive in the HDF5 archive.

**Fix:** Either:
1. Accumulate all events in the archiver and flush once at finalize (simple but uses more memory)
2. Use HDF5 chunked/extensible datasets and append on each flush
3. Use incrementing dataset names per flush batch (e.g., `/runs/<id>/events/batch_001`, `batch_002`)

---

## Issue 8: SecurityController not wired into SimController

**Severity:** Low (no runtime impact until explicitly configured)  
**Component:** `+sim/SimController.m`  
**Symptom:** The `SecurityController` class exists but there's no `securityController` property on SimController, and no hooks in `run()`/`dispatch()`/`handleSimEnd()` to call `onSimulationStart`/`onEvent`/`onSimulationComplete`.

**Fix:** Add optional `securityController` property (default []) and wire the three lifecycle hooks, guarded by `~isempty(sc.securityController)`.

---

## Issue 9: NODE_POSITION events not generated on first run after `clear classes`

**Severity:** Low (intermittent, session-dependent)  
**Component:** `+sim/SimController.m` (run method)  
**Symptom:** Occasionally after `clear classes`, the first simulation run reports 0 NODE_POSITION events despite `positionUpdateIntervalSec > 0` and a valid nodeRegistry. Subsequent runs in the same session work correctly.

**Likely Cause:** MATLAB class definition caching interacting with the EventCalendar constant resolution. The `sim.EventCalendar.NODE_POSITION` string comparison in the dispatch switch may fail if the constant hasn't been loaded yet.

**Workaround:** Call `rehash path` before running, or don't use `clear classes` before simulation runs.
