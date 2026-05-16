# GlobalMobileNetworkSim

A MATLAB-based discrete-event simulation framework for modeling global-scale heterogeneous communication networks with mobile and stationary nodes, LLM-driven agent behavior emulation, and Identity, Credential, and Access Management (ICAM).

**Repository**: [github.com/semanticarchitectures/GlobalMobileNetworkSim](https://github.com/semanticarchitectures/GlobalMobileNetworkSim)

---

## Overview

GlobalMobileNetworkSim models the communication infrastructure available to entities operating across a global network — from aircraft and ground teams in remote areas to command centers connected via fiber, satellite, and line-of-sight radio. The simulator captures realistic latency, outage behavior, and bandwidth constraints across all link types.

On top of the network layer, the simulator supports two additional layers:

- **Agent Behavior Emulation** — LLM-driven agents emulate the behavior of human personnel (aircrew, ground teams, air traffic management, command staff) based on documented roles and procedures. The purpose is to evaluate how accurately AI agents replicate human behavior under realistic network-constrained conditions.

- **ICAM (Identity, Credential, and Access Management)** — Models authentication exchanges, certificate lifecycle, policy decision points, and access control enforcement as discrete events subject to the same network constraints as operational traffic.

---

## Architecture

The simulator is organized into five MATLAB packages:

```
+sim/       — Discrete-event simulation engine (EventCalendar, SimController)
+network/   — Node/link registries, routing, outage, background traffic, geodesy
+agent/     — LLM agents, role loading, behavior tracing, fidelity evaluation
+icam/      — Entity registry, credentials, authentication, policy enforcement
+io/        — Scenario I/O, report writing, visualization
```

### Key Design Decisions

- **Pure MATLAB, no SimEvents** — Custom binary min-heap DES engine; no Simulink/SimEvents license required.
- **MATLAB `digraph` for routing** — Dijkstra shortest-path meets the 100ms wall-clock requirement for 1,000-node topologies.
- **Vincenty geodesy** — WGS-84 ellipsoid distances with sub-millimeter accuracy.
- **Keplerian orbital mechanics** — Satellite positions propagated from orbital elements.
- **OpenAI-compatible LLM API** — Agents call any OpenAI-compatible endpoint; simulation clock pauses while awaiting LLM responses.
- **Struct-of-arrays storage** — Memory-efficient at scale (1,000+ nodes, 10,000+ entities).

---

## Network Simulation Layer

### Link Types

| Type | Latency | Notes |
|---|---|---|
| GEO_Satellite | ≥270ms one-way | High availability, low bandwidth |
| LEO_Satellite | 10–40ms | Availability depends on constellation coverage |
| Fiber | Distance-computed | 200,000 km/s propagation on WGS-84 ellipsoid |
| Line_Of_Sight | Configurable | Active only when mobile node is within coverage radius |

### Features

- **Stochastic outages** — Poisson arrival process; exponential, log-normal, or fixed duration distributions
- **Background traffic** — Statistical bandwidth consumption per link
- **Mobile nodes** — Waypoint trajectory interpolation or Keplerian orbital propagation
- **Routing** — Dijkstra minimum-latency path selection with incremental cache invalidation
- **C2 message modeling** — Discrete events with explicit latency, delivery time, and failure recording

---

## Agent Behavior Layer

LLM agents are bound to network nodes and communicate exclusively through the network simulation. All agent messages are subject to the same latency, outage, and bandwidth constraints as operational traffic.

### How It Works

1. **Role definitions** — Each agent is assigned a Markdown file describing its role, duties, and communication procedures
2. **LLM prompting** — When a C2 message arrives, the role Markdown is the system prompt and the message is the user prompt
3. **Behavior tracing** — All agent actions are recorded with simulation timestamps
4. **Fidelity evaluation** — Behavior traces compared against reference specifications; Fidelity Score in [0, 1]
5. **Network-constrained annotation** — Actions missed due to outages are annotated as `"network-constrained"` rather than counted as agent failures

---

## ICAM Layer

The ICAM layer models identity management traffic as discrete C2 messages subject to full network constraints.

| Component | Description |
|---|---|
| `EntityRegistry` | Manages entities and sub-entities (human personnel, NPEs, AI agents) |
| `CredentialStore` | Certificate lifecycle — issuance, expiry detection, revocation |
| `AuthenticationManager` | First-contact cryptographic handshakes (AUTH_REQUEST/RESPONSE/TIMEOUT) |
| `PolicyDecisionPoint` | Evaluates access control queries against a JSON policy definition |
| `CredentialCache` | Per-entity TTL-based cache of PDP decisions |
| `PolicyEnforcementPoint` | Gates message send/receive; cache-first, PDP-fallback |
| `ICAMController` | Top-level coordinator wired into SimController |

**Key concepts:** Entities and sub-entities (a platform hosts multiple crew members with independent identities), Non-Person Entities (NPEs) as first-class identity holders, multi-enclave role bindings, and credential caching to reduce PDP query traffic.

---

## Demonstration Scenario: Airdrop Mission

`scenarios/airdrop_mission/` contains a complete 2-hour tactical airdrop mission scenario with 7 nodes and 20 links:

- Aircraft flying mid-Atlantic → Eastern Europe at 7,500m altitude
- Operations Center in New York City (fiber + satellite uplinks)
- Ground team at remote drop zone (portable satellite terminal, high outage rate)
- Air Traffic Management center in Prague
- GEO and LEO satellite relays
- LOS link activates when aircraft descends near the drop zone

**Running the scenario:**

```bash
# Network simulation only (no API key needed)
cd /path/to/GlobalMobileNetworkSim
matlab -nodisplay -nosplash -r "run_airdrop_mission; exit"

# With LLM agents
export NETSIM_LLM_API_KEY=sk-your-key-here
matlab -nodisplay -nosplash -r "run_airdrop_mission; exit"
```

**Outputs** (written to `output/airdrop_mission/`)

| File | Description |
|---|---|
| `AirdropMission_event_log.csv` | Every simulation event with timestamps |
| `AirdropMission_stats.json` | Latency statistics, per-link outage fractions |
| `AirdropMission_latency_histogram.png` | C2 message latency distribution |
| `AirdropMission_outage_gantt.png` | Per-link outage fractions |
| `AirdropMission_mission_map.png` | Geographic node locations and communication links |
| `AirdropMission_eval.json` | Agent fidelity scores (requires API key) |
| `AirdropMission_trace_*.csv` | Per-agent behavior traces (requires API key) |

---

## Running Tests

```matlab
% From the project root in MATLAB
addpath(pwd)

% Run all tests
run_all_tests

% Run a specific package
results = runtests('tests/network');
results = runtests('tests/icam');
results = runtests('tests/integration');
```

**Test suite: 356 tests, 0 failures** across sim, network, agent, icam, io, and integration packages.

---

## Requirements

- **MATLAB R2020b or later** (R2025b recommended)
- No Simulink, SimEvents, or additional toolboxes required
- **LLM API key** (optional) — set `NETSIM_LLM_API_KEY` for agent emulation; any OpenAI-compatible endpoint supported

---

## Project Structure

```
GlobalMobileNetworkSim/
├── +sim/                    # DES engine
├── +network/                # Network simulation layer
├── +agent/                  # Agent behavior layer
├── +icam/                   # ICAM layer
├── +io/                     # I/O and reporting
├── scenarios/
│   └── airdrop_mission/     # Tactical airdrop demonstration scenario
├── tests/                   # Test suite (356 tests)
├── run_airdrop_mission.m    # Headless demo script
├── runBatch.m               # Batch scenario execution
└── .kiro/specs/             # Requirements, design, and task specifications
```

## Specification Documents

Full specification in `.kiro/specs/matlab-network-sim/`:

- **`requirements.md`** — 24 requirements: network simulation (1–10), agent behavior (11–16), ICAM (17–24)
- **`design.md`** — Component interfaces, data models, 26 correctness properties, testing strategy
- **`tasks.md`** — Implementation task history (Tasks 1–36)

---

## License

Copyright © Semantic Architectures. All rights reserved.
