# Airdrop Mission Scenario

## Overview

This scenario models a tactical airdrop mission where an aircraft flying from the mid-Atlantic toward Eastern Europe must coordinate with ground personnel at a remote drop zone, air traffic management, and a command center in New York. It exercises all four agent roles and all four link types.

## Scenario Timeline (2-hour simulation)

| Time (s) | Event |
|---|---|
| 0 | Mission start — aircraft departs staging area over mid-Atlantic |
| 60 | Operations Center transmits mission authorization to aircraft |
| 120 | Aircraft transmits departure report; ATM acknowledges flight plan |
| 300 | Ground team arrives at drop zone, transmits on-station report |
| 900–4020 | Aircraft transmits position reports every ~15 minutes |
| 4800 | Aircraft transmits 30-minute advisory; requests DZ status and airspace clearance |
| 4900 | Ground team responds with DZ status; ATM issues airspace clearance |
| 5000 | Operations Center transmits go/no-go decision |
| 5100 | Aircraft confirms go/no-go with Operations Center |
| 5400 | Aircraft executes airdrop — "Payload away" transmitted |
| 5700 | Aircraft transmits 10-minute advisory (post-drop departure) |
| 6100 | Ground team confirms payload received |
| 6300 | Aircraft transmits post-drop assessment |
| 6600 | Ground team confirms recovery complete; aircraft transmits mission complete |
| 7200 | Simulation ends — aircraft en route to recovery base |

## Network Topology

### Nodes (7)
| Node | Type | Location | Role |
|---|---|---|---|
| AIRCRAFT | Mobile (waypoint) | Mid-Atlantic → Eastern Europe, 7500m alt | Aircrew agent |
| OPS_CENTER | Stationary | New York City | Command Staff agent |
| GROUND_TEAM | Stationary | Drop zone (50.6°N, 28.0°E, ~Ukraine border area) | Ground Personnel agent |
| ATM_CENTER | Stationary | Prague (regional ATM hub) | Air Traffic Management agent |
| GEO_SAT | Mobile (Keplerian) | GEO orbit, 0° longitude | Relay node |
| LEO_SAT_1 | Mobile (Keplerian) | LEO 550km, 53° inclination | Relay node |
| LEO_SAT_2 | Mobile (Keplerian) | LEO 550km, 53° inclination, offset plane | Relay node |

### Links (10)
| Link | Type | From → To | Latency | Notes |
|---|---|---|---|---|
| AIRCRAFT_GEO | GEO_Satellite | AIRCRAFT → GEO_SAT | 280ms | Primary long-haul, low bandwidth (512 kbps) |
| AIRCRAFT_LEO1 | LEO_Satellite | AIRCRAFT → LEO_SAT_1 | 30ms | Secondary, higher bandwidth (2 Mbps) |
| AIRCRAFT_LEO2 | LEO_Satellite | AIRCRAFT → LEO_SAT_2 | 35ms | Tertiary LEO path |
| OPS_GEO | GEO_Satellite | OPS_CENTER → GEO_SAT | 275ms | Ops Center satellite uplink |
| OPS_LEO1 | LEO_Satellite | OPS_CENTER → LEO_SAT_1 | 28ms | Ops Center LEO uplink |
| OPS_FIBER_ATM | Fiber | OPS_CENTER → ATM_CENTER | ~45ms | Transatlantic fiber (distance-computed) |
| GROUND_SAT_TERMINAL | LEO_Satellite | GROUND_TEAM → LEO_SAT_2 | 40ms | Portable terminal, low bandwidth (256 kbps), high outage rate |
| GROUND_OPS_FIBER | Fiber | OPS_CENTER → GROUND_TEAM | ~55ms | Fiber path (distance-computed) |
| AIRCRAFT_LOS_GROUND | Line_Of_Sight | AIRCRAFT → GROUND_TEAM | 2ms | Active only when aircraft within 500km of drop zone |
| ATM_LEO1 | LEO_Satellite | ATM_CENTER → LEO_SAT_1 | 32ms | ATM satellite link |

### Key Network Characteristics
- **Aircraft in remote area**: primary connectivity via GEO satellite (high latency, low bandwidth) or LEO (lower latency but intermittent)
- **Ground team**: most constrained node — portable satellite terminal with 256 kbps, high outage rate (lognormal duration distribution)
- **LOS link**: only active when aircraft descends to drop zone altitude and is within 500km — creates a brief high-quality direct link during the drop
- **Ops Center**: well-connected via fiber to ATM and multiple satellite uplinks

## Agent Configuration

Four LLM agents are bound to network nodes:

| Agent | Node | Role | Idle Timeout |
|---|---|---|---|
| aircrew_agent | AIRCRAFT | Aircrew | 15 min |
| ground_agent | GROUND_TEAM | Ground_Personnel | 20 min |
| atm_agent | ATM_CENTER | Air_Traffic_Management | 30 min |
| command_agent | OPS_CENTER | Command_Staff | 10 min |

## Reference Behavior

The `reference_behavior.json` file defines expected agent actions:
- **Aircrew**: strict ordering — 13 required actions from departure report through mission complete
- **Ground Personnel**: strict ordering — 6 required actions from on-station through recovery complete
- **Air Traffic Management**: unordered — 5 required actions (clearances and acknowledgments)
- **Command Staff**: unordered — 6 required actions (authorization through mission complete acknowledgment)

## Running the Scenario

### Network simulation only (no agents)
```matlab
addpath('/path/to/GlobalMobileNetworkSim');
scenario = io.ScenarioLoader.load('scenarios/airdrop_mission/airdrop_mission.json');
sc = sim.SimController(scenario);
sc.run();
report = sc.buildStatsReport();
rw = io.ReportWriter('output/airdrop', 'AirdropMission');
rw.writeEventLog(sc.eventLog);
rw.writeStatisticsReport(report);
```

### With LLM agents
```matlab
addpath('/path/to/GlobalMobileNetworkSim');
config.baseUrl = 'https://api.openai.com/v1';
config.model   = 'gpt-4o';
llm = agent.LLMClient(config);  % reads NETSIM_LLM_API_KEY from environment

scenario = io.ScenarioLoader.load('scenarios/airdrop_mission/airdrop_mission.json');
sc = sim.SimController(scenario, llm);
sc.run();

rw = io.ReportWriter('output/airdrop', 'AirdropMission');
rw.writeEventLog(sc.eventLog);
rw.writeStatisticsReport(sc.buildStatsReport());
rw.writeEvaluationReport(sc.buildEvalReport());
rw.writeBehaviorTraces(sc.agentRegistry.getAllTracers());
```

### Batch runs (compare network conditions)
```matlab
addpath('/path/to/GlobalMobileNetworkSim');
scenarioFiles = {'scenarios/airdrop_mission/airdrop_mission.json'};
combinedReport = runBatch(scenarioFiles, 'output/airdrop_batch');
```

## Visualization
```matlab
report = sc.buildStatsReport();
io.PlotFunctions.latencyHistogram(report, sc.deliveredLatenciesMs);
io.PlotFunctions.outageGantt(report);
```
