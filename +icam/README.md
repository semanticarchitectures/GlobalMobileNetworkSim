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

## Requirements

Requirements 17–24 (ICAM layer).
