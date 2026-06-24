# Fix Plan — Code Review Issues

Based on the code review dated 23 Jun 2026. Issues are grouped into implementation waves ordered by dependency and criticality.

---

## Wave 1: Critical ICAM & Dispatch Fixes (Issues 1, 2, 3, 4)

These four issues collectively mean the ICAM and data fabric layers are non-functional in the DES loop. They must be fixed together since they share code paths in SimController.

### Fix 1.1: PDP role-based evaluation (Issue #1)

**File:** `+icam/PolicyDecisionPoint.m`

**Change:** Modify `evaluate` to accept the requesting entity's role bindings and check `rule.role` against them (with `*` wildcard support).

```matlab
% Current signature:
function decision = evaluate(obj, requestingEntityId, targetEntityId, messageType, enclaveId, simTimeSec)

% New signature adds roleBindings:
function decision = evaluate(obj, requestingEntityId, targetEntityId, messageType, enclaveId, simTimeSec, roleBindings)
```

- For each rule, if `rule.role` is not `'*'`, check that the requesting entity holds that role in the specified enclave
- Pass role bindings from the EntityRegistry through ICAMController.checkSend
- Backwards-compatible: if roleBindings is omitted, fall back to current behavior (wildcard match on role)

**Tests:** Update `tests/icam/PolicyDecisionPointTest.m` — add tests verifying role-based deny/permit.

---

### Fix 1.2: DATA_* event dispatch in SimController (Issue #2)

**File:** `+sim/SimController.m` (dispatch method)

**Change:** Add case entries for all data fabric event types that delegate to `dataFabricController.handleDataEvent`:

```matlab
case {sim.EventCalendar.DATA_INGEST, sim.EventCalendar.DATA_FETCH, ...
      sim.EventCalendar.DATA_QUERY, sim.EventCalendar.DATA_REPLICATE, ...
      sim.EventCalendar.DATA_FETCH_RESULT, sim.EventCalendar.DATA_FETCH_DENIED, ...
      sim.EventCalendar.DATA_QUERY_RESULT}
    if ~isempty(sc.dataFabricController)
        logEntry = sc.dataFabricController.handleDataEvent(event, sc.simTimeSec, sc.eventCalendar, sc.icamController);
        if ~isempty(logEntry) && isfield(logEntry, 'type')
            sc.appendLog(event, '', '', '', '', NaN, char(logEntry.type));
        end
    end
```

**Tests:** Integration test — schedule a DATA_INGEST event, verify it reaches FabricEventHandler.

---

### Fix 1.3: ICAM auth-pending blocks message routing (Issue #3)

**File:** `+sim/SimController.m` (handleC2MessageTx)

**Change:** When `checkSend` returns `'pending'`:
1. Store the pending message payload in a queue (new property `pendingAuthMessages` — containers.Map keyed by entity pair)
2. Do NOT route the message immediately
3. On `AUTH_RESPONSE` event completion, drain pending messages for the now-authenticated pair

**New property:** `pendingAuthMessages` — `containers.Map('KeyType','char','ValueType','any')`

**Scope consideration:** This is the most complex fix in Wave 1. If time-constrained, an intermediate step is to change `'pending'` to `'deny'` with a log annotation `'auth-pending'` rather than silently routing unauthenticated traffic.

---

### Fix 1.4: Entity-scoped ICAM enforcement (Issue #4)

**File:** `+sim/SimController.m` (handleC2MessageTx)

**Changes:**
1. Add a `senderEntityId` field to the C2 message payload in scenario JSON (optional — falls back to node-based lookup)
2. If no `senderEntityId` in payload, look up the primary entity on the source node via `icamController.entityRegistry`
3. Resolve enclave from the entity's role bindings rather than hardcoding `'default'`

```matlab
% Replace:
srcEntityId = srcId;
enclaveId = 'default';

% With:
srcEntityId = sc.resolveEntityForNode(srcId, p);
enclaveId = sc.resolveEnclaveForEntity(srcEntityId);
```

**New private methods:**
- `resolveEntityForNode(nodeId, payload)` — checks payload.senderEntityId first, then looks up first entity on node
- `resolveEnclaveForEntity(entityId)` — gets entity's primary enclave from role bindings

---

## Wave 2: Performance Fixes (Issues 5, 6, 7)

### Fix 2.1: Incremental event log writing (Issue #5)

**File:** `+sim/SimController.m`

**Change:** Replace the growing `eventLog` struct array with a pre-allocated circular buffer that flushes to a file handle periodically (matching the design doc's stated intent).

**Approach:**
1. Pre-allocate `eventLogBuffer(10000)` struct array
2. Track `bufferIdx` counter
3. When buffer is full, append to the CSV file on disk and reset counter
4. Keep `eventLog` property as a reference to the full written log (read from file at end) or accumulate only summary stats in-memory

**Alternative (simpler):** Pre-allocate with `repmat` at scenario start using estimated event count = `simulationDurationSec * estimatedEventsPerSec`.

---

### Fix 2.2: Throttle updateLOSLinks (Issue #6)

**File:** `+sim/SimController.m` (run method, DES loop)

**Change:** Only call `updateLOSLinks()` on NODE_POSITION events or when sim time has advanced by ≥ `positionUpdateIntervalSec` since last LOS check.

```matlab
% Replace unconditional call:
if ~isempty(sc.nodeRegistry) && ~isempty(sc.linkRegistry)
    sc.updateLOSLinks();
end

% With throttled call:
if ~isempty(sc.nodeRegistry) && ~isempty(sc.linkRegistry) && ...
        (event.type == sim.EventCalendar.NODE_POSITION || ...
         sc.simTimeSec - sc.lastLOSCheckTime >= sc.positionUpdateIntervalSec)
    sc.updateLOSLinks();
    sc.lastLOSCheckTime = sc.simTimeSec;
end
```

**New property:** `lastLOSCheckTime` (double, init 0)

---

### Fix 2.3: O(1) agent-node lookup (Issue #7)

**File:** `+agent/AgentRegistry.m`

**Change:** Build a `containers.Map` from agentId → nodeId at construction time. Replace the linear scan in delivery with a map lookup.

---

## Wave 3: Wiring & Integration Fixes (Issues 8, 9, 10)

### Fix 3.1: Wire c2_log auto-creation (Issue #8)

**File:** `+sim/SimController.m` (handleC2MessageRx)

**Change:** After successful delivery, if `dataFabricController` is non-empty:

```matlab
if ~isempty(sc.dataFabricController)
    ingestPayload = sc.dataFabricController.onC2MessageDelivered(event, sc.simTimeSec);
    if ~isempty(fieldnames(ingestPayload))
        ingestEvent.time = sc.simTimeSec;
        ingestEvent.type = sim.EventCalendar.DATA_INGEST;
        ingestEvent.id = sc.nextId();
        ingestEvent.payload = ingestPayload;
        sc.eventCalendar.schedule(ingestEvent);
    end
end
```

---

### Fix 3.2: Replace deprecated datestr (Issue #9)

**Files:** `+sim/SimController.m`, `+data/DataFabricController.m`

**Change:** Replace `datestr(now, 'yyyy-mm-ddTHH:MM:SS')` with:
```matlab
char(datetime('now', 'Format', 'yyyy-MM-dd''T''HH:mm:ss'))
```

---

### Fix 3.3: Sort by simStartTime before retention (Issue #10)

**File:** `+data/DataFabricController.m` (applyRetention)

**Change:** Sort `allRecords` by `simStartTime` ascending before applying count-based removal.

---

## Wave 4: Low-Priority Cleanups (Issues 11, 12, 13, 15)

### Fix 4.1: queuedC2Messages returns actual count (Issue #11)

Scan event calendar for C2_MESSAGE_TX events, or just report total queued events.

### Fix 4.2: NODE_POSITION log schema (Issue #12)

Add a comment to the event log CSV header documenting the field overloading. Long-term: add dedicated columns or a separate position log file.

### Fix 4.3: embedFileContents logs a warning (Issue #13)

Replace empty `catch` blocks with `warning('netsim:data:embedFailed', ...)`.

### Fix 4.4: Update README (Issue #15)

Update requirement/task counts, add `+data/`, `+fabric/`, `+security/` to architecture diagram.

---

## Execution Order

| Wave | Issues | Est. Effort | Priority |
|------|--------|-------------|----------|
| 1 | #1, #2, #3, #4 | 4–6 hours | Must-fix before any ICAM/fabric scenario works |
| 2 | #5, #6, #7 | 2–3 hours | Performance — needed for 1000-node benchmarks |
| 3 | #8, #9, #10 | 1–2 hours | Integration completeness |
| 4 | #11, #12, #13, #15 | 1 hour | Housekeeping |

**Recommended start:** Wave 1 (fixes 1.1–1.4), then run the `airdrop_icam` scenario to validate messages flow correctly with role-based access control.
