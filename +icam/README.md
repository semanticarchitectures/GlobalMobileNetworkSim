# `+icam/` — Identity, Credential, and Access Management Package

## Overview

The `+icam/` package implements the ICAM layer of the MATLAB Network Simulator. It models authentication exchanges, certificate lifecycle, policy decision points, credential caching, and access control enforcement as first-class discrete-event participants.

All ICAM traffic (authentication handshakes, PDP queries, certificate renewals, policy synchronization) is modeled as C2_Messages routed through the existing network simulation, making ICAM latency and failure modes subject to the same outage and congestion constraints as operational traffic.

## Components

| Class | Description |
|---|---|
| `icam.EntityRegistry` | Manages all entities and sub-entities using struct-of-arrays storage |
| `icam.CredentialStore` | Manages certificates and their lifecycle per entity |
| `icam.AuthenticationManager` | Tracks authentication state between entity pairs |
| `icam.PolicyDecisionPoint` | Evaluates access control queries against a loaded policy |
| `icam.CredentialCache` | Per-entity cache of PDP decisions with configurable TTL |
| `icam.PolicyEnforcementPoint` | Intercepts message operations and enforces access control |
| `icam.ICAMController` | Top-level coordinator wired into `SimController` |

## Design Principles

- **Struct-of-arrays storage**: `EntityRegistry` uses the same memory-efficient pattern as `NodeRegistry` and `LinkRegistry`, supporting 10,000+ entities within the 16 GB RAM constraint.
- **Discrete-event integration**: All ICAM operations that involve network communication are modeled as C2_Messages scheduled into the `EventCalendar`.
- **Optional integration**: `SimController` gains an optional `icamController` property (default: `[]`). When absent, the simulator runs without ICAM enforcement.

## Error Identifiers

All ICAM errors follow the `netsim:icam:<errorType>` convention:

| Identifier | Condition |
|---|---|
| `netsim:icam:unknownNode` | Entity references a non-existent node |
| `netsim:icam:duplicateEntityId` | Duplicate entity identifier detected |
| `netsim:icam:unknownEnclave` | Role binding references undefined enclave |
| `netsim:icam:unknownRole` | Role binding references undefined role name |
| `netsim:icam:policyViolation` | NPE assigned human-restricted role binding |
| `netsim:icam:noCertificate` | Certificate not found for entity |
| `netsim:icam:policyJsonError` | Policy definition JSON syntax error |

## Data Item Access Control (Phase 10 Extension)

The `PolicyDecisionPoint` supports data-item-level access control using the `messageType` field convention `'data_item:<classification>'`. Because the PDP already supports wildcard (`'*'`) matching in rule `messageType` fields, no code changes are required — the existing wildcard logic naturally extends to data fabric access control.

### Policy Rule Examples

```json
{
  "rules": [
    {"enclave": "enclave-alpha", "role": "pilot", "messageType": "data_item:UNCLASSIFIED", "decision": "permit"},
    {"enclave": "enclave-bravo", "role": "mission-commander", "messageType": "data_item:*", "decision": "permit"},
    {"enclave": "enclave-alpha", "role": "sensor-operator", "messageType": "data_item:SECRET", "decision": "deny"}
  ]
}
```

### How It Works

1. When a `DATA_FETCH` or `DATA_QUERY` event is processed, the `FabricEventHandler` constructs a `messageType` string of the form `'data_item:<classification>'` (e.g., `'data_item:SECRET'`, `'data_item:UNCLASSIFIED'`).
2. This `messageType` is passed to `ICAMController.checkSend` (or the PEP directly), which evaluates it against the policy rules.
3. The PDP's existing rule-matching logic handles these patterns:
   - **Exact match**: `"messageType": "data_item:SECRET"` matches only requests for SECRET-classified items.
   - **Wildcard match**: `"messageType": "data_item:*"` matches requests for items of _any_ classification (via the existing `'*'` wildcard in the PDP's `evaluate` method).
   - **Global wildcard**: `"messageType": "*"` matches all message types including data item requests.

### Scenario Loader Validation

The `ScenarioLoader` accepts any string in the `messageType` field of policy rules. The `data_item:<classification>` pattern is a naming convention enforced by the fabric layer's usage of the PDP — no additional schema validation is required. The PDP's `evaluate` method performs string comparison (exact or wildcard) regardless of the messageType format.

### Default Behavior

If no ICAM layer is configured in the scenario (i.e., `icamController` is empty), the data fabric applies a default **permit-all** policy for all `DATA_FETCH` and `DATA_QUERY` requests, with a warning logged once at runtime that data access control is unenforced.

## Requirements

Requirements 17–24 (ICAM layer), R36 (data item access control).
