# Requirements Document

## Introduction

This document defines requirements for a MATLAB-based global-scale network simulation application. The simulator models a heterogeneous network composed of stationary and mobile nodes distributed worldwide. Most background network traffic is estimated statistically, while Command and Control (C2) messages and their associated traffic are modeled discretely, capturing realistic latency and outage behavior derived from underlying network statistics. A representative use case is an aircraft operating in a remote region coordinating with a command center in New York, where effective latency and availability depend on the connectivity path (geosynchronous satellite, Low Earth Orbit satellite constellation, or fiber via a ground station within line of sight).

Building on the network simulation layer, the application also supports an agent-based human behavior emulation layer. AI agents are assigned to roles defined by documented human procedures and responsibilities (e.g., aircrew, ground personnel, air traffic management, command staff). These agents communicate exclusively through the network simulation, so their interactions are subject to the same latency, outage, and bandwidth constraints as any other C2 traffic. The primary purpose of this layer is research and evaluation: measuring how accurately AI agents replicate documented human behavior across a range of operationally realistic, network-constrained scenarios.

## Glossary

- **Simulator**: The top-level MATLAB application that orchestrates the simulation.
- **Node**: A network endpoint, either stationary or mobile, participating in the simulated network.
- **Stationary_Node**: A Node with a fixed geographic position (e.g., a ground station, data center, or command center).
- **Mobile_Node**: A Node whose geographic position changes over time (e.g., an aircraft, ship, or ground vehicle).
- **Link**: A directed or bidirectional communication path between two Nodes.
- **Link_Type**: The category of a Link, one of: GEO_Satellite, LEO_Satellite, Fiber, or Line_Of_Sight.
- **GEO_Satellite**: A geosynchronous Earth orbit satellite link with high latency (~600 ms round-trip) and high availability.
- **LEO_Satellite**: A Low Earth Orbit satellite network link with lower latency than GEO and availability dependent on constellation coverage.
- **Fiber**: A terrestrial fiber-optic link with low latency and high availability.
- **Line_Of_Sight**: A direct radio-frequency link between a Mobile_Node and a ground station, available only when the Mobile_Node is within the coverage radius of the ground station.
- **C2_Message**: A discrete Command and Control message exchanged between two Nodes, modeled individually with explicit latency and delivery outcome.
- **Background_Traffic**: Aggregate network traffic that is not modeled discretely; its volume and load are estimated statistically.
- **Latency**: The one-way propagation and queuing delay experienced by a C2_Message traversing a Link, measured in milliseconds.
- **Outage**: A period during which a Link is unavailable and C2_Messages cannot be delivered.
- **Outage_Rate**: The statistical frequency of Outages on a Link, expressed as a probability per unit time.
- **Outage_Duration**: The statistical duration of an Outage on a Link, expressed as a probability distribution.
- **Bandwidth**: The maximum data throughput of a Link, measured in bits per second.
- **Effective_Bandwidth**: The available Bandwidth on a Link after accounting for Background_Traffic load.
- **Path**: An ordered sequence of Links connecting a source Node to a destination Node.
- **Routing_Engine**: The Simulator component responsible for selecting the active Path between two Nodes.
- **Scenario**: A complete simulation configuration including Node positions, Link definitions, traffic parameters, and simulation time span.
- **Scenario_File**: A file that encodes a Scenario in a defined format.
- **Event_Log**: A time-ordered record of discrete simulation events (C2_Message transmissions, deliveries, outage starts, outage ends).
- **Statistics_Report**: A summary of aggregate simulation results including latency distributions, outage statistics, and throughput estimates.
- **Agent**: An LLM_Agent assigned to a specific Role that generates and responds to C2_Messages on behalf of a simulated human participant.
- **LLM_Agent**: An Agent whose behavior is driven by a Large Language Model (LLM). The LLM interprets incoming C2_Messages and the associated Role_Definition to generate responses and Agent_Actions.
- **Role**: A named set of documented duties, decision authorities, and communication procedures that an Agent is configured to emulate (e.g., Aircrew, Ground_Personnel, Air_Traffic_Management, Command_Staff).
- **Role_Definition**: A Markdown file that describes the duties, decision authorities, communication procedures, and behavioral expectations of a Role in prose and structured text, derived from authoritative source documentation. The Role_Definition is provided as context when prompting the LLM_Agent.
- **Agent_Action**: A discrete output produced by an Agent, such as sending a C2_Message, updating a shared situational awareness record, or logging a decision.
- **Reference_Behavior**: The expected sequence or set of Agent_Actions prescribed by the Role_Definition for a given Scenario context, used as the ground truth for evaluation.
- **Behavior_Trace**: A time-ordered record of all Agent_Actions produced by an Agent during a simulation run.
- **Fidelity_Score**: A quantitative measure of how closely an Agent's Behavior_Trace matches the Reference_Behavior for the same Scenario context.
- **Evaluation_Report**: A structured summary of Fidelity_Scores and behavioral deviations produced after a simulation run that includes Agent emulation.
- **Mission_Scenario**: A Scenario that includes at least one Agent assignment and a defined operational context (e.g., airdrop coordination) against which Agent behavior is evaluated.

---

## Requirements

### Requirement 1: Node Modeling

**User Story:** As a simulation engineer, I want to define stationary and mobile nodes with geographic positions, so that I can represent real-world network endpoints at global scale.

#### Acceptance Criteria

1. THE Simulator SHALL represent each Node with a unique identifier, a Node type (Stationary_Node or Mobile_Node), and an initial geographic position expressed as WGS-84 latitude, longitude, and altitude.
2. WHEN a Simulation time step advances, THE Simulator SHALL update the geographic position of each Mobile_Node according to its defined trajectory.
3. THE Simulator SHALL support at least 1,000 Nodes in a single Scenario without exceeding available MATLAB memory for a system with 16 GB RAM.
4. IF a Mobile_Node trajectory definition is missing or malformed, THEN THE Simulator SHALL report a descriptive error identifying the Node and the malformed field, and halt Scenario loading.

---

### Requirement 2: Link Modeling

**User Story:** As a simulation engineer, I want to define communication links between nodes with realistic latency and outage statistics, so that the simulation reflects real-world connectivity constraints.

#### Acceptance Criteria

1. THE Simulator SHALL represent each Link with a Link_Type, a source Node identifier, a destination Node identifier, a nominal Latency value, a Bandwidth value, an Outage_Rate, and an Outage_Duration distribution.
2. WHEN a Link_Type is GEO_Satellite, THE Simulator SHALL apply a baseline one-way Latency of no less than 270 ms.
3. WHEN a Link_Type is LEO_Satellite, THE Simulator SHALL apply a baseline one-way Latency between 10 ms and 40 ms, configurable per Link.
4. WHEN a Link_Type is Fiber, THE Simulator SHALL compute Latency from the geographic distance between the two endpoint Nodes using a propagation speed of 200,000 km/s.
5. WHEN a Link_Type is Line_Of_Sight, THE Simulator SHALL mark the Link as active only while the Mobile_Node is within the configured coverage radius of the Stationary_Node endpoint.
6. WHEN a Link_Type is Line_Of_Sight and the Mobile_Node moves outside the coverage radius, THE Simulator SHALL transition the Link to an Outage state and record an outage-start event in the Event_Log.
7. IF a Link definition references a Node identifier that does not exist in the Scenario, THEN THE Simulator SHALL report a descriptive error and halt Scenario loading.

---

### Requirement 3: Background Traffic Statistical Modeling

**User Story:** As a simulation engineer, I want background network traffic to be estimated statistically, so that the simulation runs efficiently without modeling every individual packet.

#### Acceptance Criteria

1. THE Simulator SHALL model Background_Traffic on each Link as a statistical load expressed as a fraction of Bandwidth consumed, drawn from a configurable probability distribution (uniform, normal, or log-normal).
2. WHEN computing Effective_Bandwidth for a Link, THE Simulator SHALL subtract the Background_Traffic load from the total Bandwidth of that Link.
3. WHILE Effective_Bandwidth on a Link is less than or equal to zero, THE Simulator SHALL treat that Link as congested and apply a configurable congestion Latency penalty to C2_Messages traversing it.
4. THE Simulator SHALL update Background_Traffic load values at a configurable statistical refresh interval, with a default of 60 simulation seconds.
5. IF a Background_Traffic distribution parameter is outside a valid range (e.g., negative mean or standard deviation), THEN THE Simulator SHALL report a descriptive error identifying the Link and the invalid parameter.

---

### Requirement 4: Outage Modeling

**User Story:** As a simulation engineer, I want link outages to be modeled stochastically, so that the simulation captures realistic network availability behavior.

#### Acceptance Criteria

1. THE Simulator SHALL generate Outage events on each Link using a Poisson arrival process parameterized by the Link's configured Outage_Rate.
2. WHEN an Outage begins on a Link, THE Simulator SHALL sample an Outage_Duration from the Link's configured Outage_Duration distribution and record an outage-start event in the Event_Log.
3. WHEN an Outage ends on a Link, THE Simulator SHALL restore the Link to active state and record an outage-end event in the Event_Log.
4. WHILE a Link is in Outage state, THE Simulator SHALL treat any C2_Message routed over that Link as undeliverable and record a delivery-failure event in the Event_Log.
5. THE Simulator SHALL support configuring Outage_Duration as an exponential, log-normal, or fixed-duration distribution per Link.

---

### Requirement 5: C2 Message Discrete Modeling

**User Story:** As a simulation engineer, I want Command and Control messages to be modeled individually with explicit latency and delivery outcomes, so that I can analyze C2 communication performance in detail.

#### Acceptance Criteria

1. THE Simulator SHALL model each C2_Message as a discrete event with a source Node, destination Node, message size in bytes, and scheduled transmission time.
2. WHEN a C2_Message is transmitted, THE Routing_Engine SHALL select the active Path with the lowest total Latency among all available Paths between the source and destination Nodes.
3. WHEN a C2_Message traverses a Path, THE Simulator SHALL compute the total Latency as the sum of the nominal Latency values of all Links on the Path plus any congestion Latency penalties.
4. WHEN a C2_Message is successfully delivered, THE Simulator SHALL record the message identifier, source Node, destination Node, transmission time, delivery time, and total Latency in the Event_Log.
5. IF no active Path exists between the source and destination Nodes at the scheduled transmission time, THEN THE Simulator SHALL record a delivery-failure event in the Event_Log with the reason "no available path".
6. THE Simulator SHALL support scheduling at least 100,000 C2_Messages in a single Scenario.

---

### Requirement 6: Routing Engine

**User Story:** As a simulation engineer, I want the simulator to automatically select the best available path between nodes, so that C2 messages are routed realistically based on current network conditions.

#### Acceptance Criteria

1. WHEN the Routing_Engine selects a Path, THE Routing_Engine SHALL consider only Links that are currently active (not in Outage state and not Line_Of_Sight links whose Mobile_Node is out of coverage).
2. WHEN multiple Paths exist between a source and destination Node, THE Routing_Engine SHALL select the Path with the minimum total Latency.
3. WHEN a Link transitions to or from Outage state, THE Routing_Engine SHALL recompute affected Paths before processing the next C2_Message scheduled after the transition time.
4. THE Routing_Engine SHALL complete Path selection for a single C2_Message in no more than 100 ms of wall-clock time for a Scenario with up to 1,000 Nodes and 10,000 Links.
5. WHERE a user-defined routing policy is configured, THE Routing_Engine SHALL apply that policy to filter or rank candidate Paths before selecting the minimum-latency Path.

---

### Requirement 7: Scenario Definition and Loading

**User Story:** As a simulation engineer, I want to define and load simulation scenarios from files, so that I can reproduce and share simulation configurations.

#### Acceptance Criteria

1. THE Simulator SHALL load a Scenario from a Scenario_File encoded in JSON format.
2. WHEN a Scenario_File is loaded, THE Simulator SHALL validate all Node definitions, Link definitions, and traffic parameters before beginning simulation execution.
3. IF a Scenario_File contains a JSON syntax error, THEN THE Simulator SHALL report the file path, line number, and a descriptive error message, and halt loading.
4. THE Simulator SHALL support saving the current Scenario configuration to a Scenario_File in JSON format.
5. FOR ALL valid Scenario_Files, loading then saving then loading SHALL produce a Scenario equivalent to the original (round-trip property).

---

### Requirement 8: Simulation Execution Control

**User Story:** As a simulation engineer, I want to control simulation execution including start, pause, and step-through, so that I can inspect simulation state at specific points in time.

#### Acceptance Criteria

1. THE Simulator SHALL execute a Scenario in discrete event simulation mode, advancing simulation time to the next scheduled event.
2. THE Simulator SHALL provide functions to start, pause, resume, and stop a simulation run.
3. WHEN the simulation is paused, THE Simulator SHALL allow inspection of the current state of all Nodes, Links, and queued C2_Messages.
4. THE Simulator SHALL support a configurable simulation time limit, after which execution stops automatically and a Statistics_Report is generated.
5. WHEN simulation execution completes, THE Simulator SHALL write the Event_Log to a file in CSV format and generate a Statistics_Report in JSON format.

---

### Requirement 9: Statistics and Reporting

**User Story:** As a simulation engineer, I want summary statistics and reports generated at the end of a simulation, so that I can evaluate network performance across the scenario.

#### Acceptance Criteria

1. THE Simulator SHALL compute and include in the Statistics_Report: total C2_Messages scheduled, total delivered, total failed, mean Latency, median Latency, 95th-percentile Latency, and per-Link outage fraction.
2. THE Simulator SHALL compute per-Link statistics including mean Effective_Bandwidth, mean Background_Traffic load, total C2_Messages routed, and total outage duration.
3. WHEN a Statistics_Report is generated, THE Simulator SHALL include the Scenario name, simulation start time, simulation end time, and wall-clock execution duration.
4. THE Simulator SHALL provide a MATLAB function that plots the latency distribution of delivered C2_Messages as a histogram.
5. THE Simulator SHALL provide a MATLAB function that plots per-Link outage timelines as a Gantt-style chart over the simulation time span.

---

### Requirement 10: Geographic and Propagation Accuracy

**User Story:** As a simulation engineer, I want geographic distances and propagation delays to be computed accurately at global scale, so that the simulation reflects realistic physics.

#### Acceptance Criteria

1. WHEN computing the distance between two geographic positions, THE Simulator SHALL use the WGS-84 ellipsoid model with an accuracy of no more than 0.1% error relative to the true geodesic distance.
2. WHEN computing Line_Of_Sight coverage, THE Simulator SHALL account for Earth curvature using the WGS-84 ellipsoid model.
3. THE Simulator SHALL compute the orbital position of GEO_Satellite and LEO_Satellite relay nodes using Keplerian orbital elements updated at each simulation time step.
4. IF orbital element parameters for a satellite Node are missing or invalid, THEN THE Simulator SHALL report a descriptive error identifying the Node and halt Scenario loading.

---

### Requirement 11: Agent Role Definition and Loading

**User Story:** As a researcher, I want to define agent roles from authoritative documentation, so that each agent's behavior is grounded in real-world procedures and responsibilities.

#### Acceptance Criteria

1. THE Simulator SHALL load a Role_Definition from a Markdown file that describes the Role name, source documentation reference, duties, decision authorities, communication procedures, and behavioral expectations for that Role.
2. WHEN a Role_Definition file is loaded, THE Simulator SHALL validate that the file is non-empty and that a Role name is identifiable within the document.
3. WHEN a Role_Definition file is loaded, THE Simulator SHALL extract the full Markdown content as the role context string to be supplied to the LLM_Agent when prompting for responses.
4. IF a Role_Definition file cannot be read or is empty, THEN THE Simulator SHALL report a descriptive error identifying the file path and halt Scenario loading.
5. THE Simulator SHALL support at least the following Roles in a single Mission_Scenario: Aircrew, Ground_Personnel, Air_Traffic_Management, and Command_Staff.

---

### Requirement 12: Agent Assignment and Network Binding

**User Story:** As a researcher, I want each agent to be bound to a specific network node, so that all agent communications are subject to the same network constraints as real C2 traffic.

#### Acceptance Criteria

1. THE Simulator SHALL associate each Agent with exactly one Node in the Scenario, representing the physical location from which the Agent communicates.
2. WHEN an Agent generates an Agent_Action that involves sending a message, THE Simulator SHALL route that message as a C2_Message through the network simulation from the Agent's bound Node to the destination Node.
3. WHILE a Link on the Path between two Agents' Nodes is in Outage state, THE Simulator SHALL withhold delivery of C2_Messages between those Agents and record a delivery-failure event in the Event_Log.
4. WHEN a C2_Message sent by an Agent is delivered, THE Simulator SHALL make the message content available to the receiving Agent at the simulation time corresponding to the computed delivery time, not the transmission time.
5. IF an Agent is assigned to a Node identifier that does not exist in the Scenario, THEN THE Simulator SHALL report a descriptive error identifying the Agent and the missing Node, and halt Scenario loading.

---

### Requirement 13: Agent Behavior Execution

**User Story:** As a researcher, I want agents to autonomously generate actions based on their role definitions and incoming messages, so that the simulation produces realistic human-like communication patterns.

#### Acceptance Criteria

1. WHEN an Agent receives a C2_Message, THE LLM_Agent SHALL submit the message content and its Role_Definition context to the LLM and produce zero or more Agent_Actions based on the LLM response.
2. WHEN an LLM_Agent is awaiting an LLM response, THE Simulator SHALL pause the simulation clock and resume simulation time advancement only after the LLM returns a complete response.
3. WHEN an Agent produces an Agent_Action, THE Simulator SHALL record the action in the Agent's Behavior_Trace with the simulation timestamp, the triggering event, and the action type.
4. WHILE no incoming C2_Message has been received by an Agent within a configurable idle timeout period, THE LLM_Agent SHALL generate a role-appropriate status or check-in Agent_Action as prescribed by its Role_Definition.
5. THE Simulator SHALL execute all Agent behavior logic within the discrete event simulation loop so that Agent_Actions are time-ordered consistently with network events.

---

### Requirement 14: Reference Behavior Specification

**User Story:** As a researcher, I want to specify the expected behavior for each role in a given scenario, so that I have a ground truth against which to evaluate agent fidelity.

#### Acceptance Criteria

1. THE Simulator SHALL load a Reference_Behavior specification from a JSON file that maps Scenario events to the expected sequence of Agent_Actions for each Role.
2. WHEN a Reference_Behavior file is loaded, THE Simulator SHALL validate that all referenced Roles and C2_Message types exist in the current Mission_Scenario.
3. THE Simulator SHALL support specifying Reference_Behavior as either an ordered sequence (strict ordering required) or an unordered set (all actions required but order unconstrained), configurable per Role.
4. IF a Reference_Behavior file references a Role that has no Agent assigned in the Mission_Scenario, THEN THE Simulator SHALL log a warning identifying the unassigned Role and continue loading.
5. THE Simulator SHALL support saving a Reference_Behavior specification to a JSON file, and FOR ALL valid Reference_Behavior files, loading then saving then loading SHALL produce a specification equivalent to the original (round-trip property).

---

### Requirement 15: Agent Fidelity Evaluation

**User Story:** As a researcher, I want the simulator to compute fidelity scores comparing agent behavior to reference behavior, so that I can quantitatively assess how well agents replicate documented human behavior.

#### Acceptance Criteria

1. WHEN a Mission_Scenario simulation run completes, THE Simulator SHALL compare each Agent's Behavior_Trace against the Reference_Behavior for that Agent's Role and compute a Fidelity_Score expressed as a value between 0.0 and 1.0.
2. THE Simulator SHALL compute Fidelity_Score as the fraction of required Reference_Behavior Agent_Actions that appear in the Agent's Behavior_Trace, accounting for ordering constraints where the Reference_Behavior specifies strict ordering.
3. THE Simulator SHALL include in the Evaluation_Report: the Fidelity_Score per Agent, the list of expected Agent_Actions that were not observed, the list of Agent_Actions observed that were not in the Reference_Behavior, and the simulation time of each deviation.
4. WHEN network conditions (Outage or congestion) prevented delivery of a C2_Message that would have triggered a Reference_Behavior action, THE Simulator SHALL annotate the corresponding missing action in the Evaluation_Report with the reason "network-constrained" rather than counting it as an Agent fidelity failure.
5. THE Simulator SHALL provide a MATLAB function that plots per-Agent Fidelity_Scores across multiple simulation runs as a box-and-whisker chart, enabling comparison across network conditions.

---

### Requirement 16: Evaluation Reporting and Export

**User Story:** As a researcher, I want evaluation results exported in standard formats, so that I can analyze agent fidelity data with external tools and share results with collaborators.

#### Acceptance Criteria

1. WHEN a Mission_Scenario simulation run completes, THE Simulator SHALL write the Evaluation_Report to a file in JSON format containing all fields specified in Requirement 15.
2. THE Simulator SHALL write each Agent's Behavior_Trace to a file in CSV format with columns for simulation time, Agent identifier, Role, action type, target Agent identifier, and message identifier.
3. THE Simulator SHALL include Agent fidelity summary statistics in the Statistics_Report generated at the end of each simulation run, including mean Fidelity_Score, minimum Fidelity_Score, and maximum Fidelity_Score across all Agents.
4. FOR ALL valid Evaluation_Report JSON files produced by the Simulator, loading the file and re-computing summary statistics SHALL produce values identical to those recorded in the file (consistency property).
5. WHERE multiple Mission_Scenario runs are executed in a batch, THE Simulator SHALL produce a combined Evaluation_Report aggregating Fidelity_Scores across all runs, with each run identified by a unique run identifier and timestamp.
