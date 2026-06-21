# +fabric/ — Data Fabric Layer

## Package Structure

```
+fabric/
├── DataItem.m            — Value class representing a data item (R33, R38)
├── DataCatalog.m         — In-memory catalog indexing DataItems per DataStore (R35)
├── DataStoreRegistry.m   — Registry of DataStore nodes with catalogs/graphs (R35)
├── FabricEventHandler.m  — Event handler for DATA_INGEST/FETCH/QUERY (R34, R36, R37)
├── ProvenanceGraph.m     — DAG tracking derivation lineage between items (R38)
├── ReplicationEngine.m   — Policy-driven replication across DataStores (R39)
└── README.md             — This file
```

## Overview

The data fabric layer models distributed data management across network nodes
designated as DataStores. Each DataStore maintains its own DataCatalog (index of
items) and ProvenanceGraph (lineage DAG). The fabric integrates with the ICAM
layer for access control and with the simulation event loop for timing.

## Agent Interaction with the Data Fabric

Agents interact with the data fabric through three primary operations, each
mapped to a simulation event type.

### publish_data (DATA_INGEST)

An agent produces a DataItem (e.g., sensor telemetry, mission report) and
publishes it to a target DataStore.

**Event Flow:**

1. Agent action parser in `+agent/AgentRegistry` recognizes `publish_data` action
2. AgentRegistry builds a `DATA_INGEST` event payload:
   - `dataItemId` — unique ID (via `DataItem.generateId()`)
   - `dataItemStruct` — full DataItem fields (type, creator, size, classification, enclave, provenance)
   - `targetDataStoreId` — the DataStore node to ingest into
3. Event is scheduled on `sim.EventCalendar`
4. `DataFabricController.handleDataEvent` dispatches to `FabricEventHandler.handleIngest`
5. Handler adds item to catalog, records provenance, triggers replication if policy requires it
6. Log entry returned for archival

### query_data (DATA_QUERY)

An agent queries a DataStore catalog with structured criteria (type, classification,
time range, creator, etc.) and receives metadata of matching items.

**Event Flow:**

1. Agent action parser recognizes `query_data` action
2. AgentRegistry builds a `DATA_QUERY` event payload:
   - `queryCriteria` — struct with filter fields (dataItemType, classification, timeRange, etc.)
   - `requestingEntityId` — the agent's entity ID
   - `requestingNodeId` — the agent's current node
   - `targetDataStoreId` — which DataStore to query
3. Event is scheduled on `sim.EventCalendar`
4. `DataFabricController.handleDataEvent` dispatches to `FabricEventHandler.handleQuery`
5. Handler queries DataCatalog, filters results through ICAM access control
6. Returns permitted item metadata in log entry (agent observes results via behavior trace)

### fetch_data (DATA_FETCH)

An agent retrieves a specific DataItem by ID from a DataStore, subject to ICAM
access control.

**Event Flow:**

1. Agent action parser recognizes `fetch_data` action
2. AgentRegistry builds a `DATA_FETCH` event payload:
   - `dataItemId` — the item to fetch
   - `requestingEntityId` — the agent's entity ID
   - `requestingNodeId` — the agent's current node
   - `targetDataStoreId` — which DataStore holds the item
3. Event is scheduled on `sim.EventCalendar`
4. `DataFabricController.handleDataEvent` dispatches to `FabricEventHandler.handleFetch`
5. Handler looks up item in catalog, checks ICAM policy (classification + enclave)
6. Returns item metadata if permitted, or `data_fetch_denied` if blocked

## C2 Log Auto-Creation

When a C2 message is delivered (C2_MESSAGE_RX), the fabric can automatically
create a `c2_log` DataItem referencing the message. This is handled by
`FabricEventHandler.createC2LogItem()` and wired through
`DataFabricController.onC2MessageDelivered()`.

## Integration Notes

- **ICAM layer**: FabricEventHandler checks access via `icam.ICAMController.checkSend`
  using message type `"data_item:<CLASSIFICATION>"` and the item's enclave.
- **Replication**: On successful ingest, ReplicationEngine evaluates the source
  DataStore's replicationPolicy and schedules `DATA_REPLICATE` events to peers.
- **Agent integration**: Requires extending `+agent/AgentRegistry` action parsing
  to recognize `publish_data`, `query_data`, and `fetch_data` actions and convert
  them into the appropriate event payloads. This is a **future task** and not yet
  implemented.
- **Statistics**: Both FabricEventHandler and ReplicationEngine maintain `.stats`
  structs for reporting (total ingested, failed, retries, dropped, fetch/query counts).
