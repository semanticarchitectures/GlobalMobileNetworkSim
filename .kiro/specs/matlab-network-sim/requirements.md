# Requirements Document

## Introduction

This document defines requirements for a MATLAB-based global-scale network simulation application. The simulator models a heterogeneous network composed of stationary and mobile nodes distributed worldwide. Most background network traffic is estimated statistically, while Command and Control (C2) messages and their associated traffic are modeled discretely, capturing realistic latency and outage behavior derived from underlying network statistics. A representative use case is an aircraft operating in a remote region coordinating with a command center in New York, where effective latency and availability depend on the connectivity path (geosynchronous satellite, Low Earth Orbit satellite constellation, or fiber via a ground station within line of sight).

Building on the network simulation layer, the application also supports an agent-based human behavior emulation layer. AI agents are assigned to roles defined by documented human procedures and responsibilities (e.g., aircrew, ground personnel, air traffic management, command staff). These agents communicate exclusively through the network simulation, so their interactions are subject to the same latency, outage, and bandwidth constraints as any other C2 traffic. The primary purpose of this layer is research and evaluation: measuring how accurately AI agents replicate documented human behavior across a range of operationally realistic, network-constrained scenarios.

A fourth layer adds Identity, Credential, and Access Management (ICAM) to the simulation. Each Node may host multiple Sub_Entities (human personnel and Non_Person_Entities such as sensors, platforms, and AI agents), each holding its own Credentials and Role_Bindings across one or more security Enclaves. Authentication exchanges, Policy_Decision_Point queries, and policy synchronization traffic are all modeled as discrete C2_Messages subject to the same network latency and outage constraints as operational traffic. Access control decisions gate what messages Agents can send and receive, making ICAM a first-class participant in the simulation rather than an out-of-band concern.

A fifth layer (Phase 9) adds an operational archive: a persistent HDF5-backed store and run registry that archives every simulation run, enabling cross-run queries, scenario lineage, and export to standard analytics formats.

A sixth layer (Phase 10) adds a simulated enterprise data fabric. Entities generate data items (sensor telemetry, mission reports, C2 message logs, derived products), transmit them to DataStore nodes as discrete C2 events subject to full network constraints, and request data back through the same network with ICAM-enforced access control and per-item provenance returned in every fetch response.

A seventh layer (Phase 11) adds security evaluation capabilities: a `+security/` package with a SecurityOracle, PolicyAnalyzer, CoverageGenerator, adversarial agent model, and NetworkDegradationTester that transform the simulation into a tool for verifying that the implemented security policy matches the intended policy, and validating that the model accurately predicts real-world security behavior before deployment.

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
- **Entity**: A Node or any Sub_Entity hosted by a Node that participates in ICAM operations, holds Credentials, and is subject to access control decisions.
- **Sub_Entity**: A named participant hosted within a Node (e.g., an individual crew member, a sensor, or an AI agent) that holds its own Identity distinct from the Node's platform identity.
- **Identity**: A unique, verifiable identifier bound to an Entity or Sub_Entity, represented by a Certificate issued under the Public_Key_Infrastructure.
- **Credential**: A cryptographic artifact (Certificate or derived token) that proves an Entity's Identity and Role_Bindings to other Entities and to Policy_Decision_Points.
- **Certificate**: A signed data structure issued by a Trust_Anchor that binds a public key to an Identity and a set of Role_Bindings, with a defined validity period.
- **Public_Key_Infrastructure**: The system of Trust_Anchors, certificate authorities, and certificate issuance and revocation services that creates and manages Certificates.
- **Trust_Anchor**: A root certificate authority whose public key is pre-distributed to all Entities and whose signatures are accepted as authoritative.
- **Policy_Decision_Point**: A network Node that evaluates access control queries from Entities and returns permit or deny decisions based on the current Access_Control_Policy.
- **Policy_Enforcement_Point**: The component within an Entity that intercepts resource access attempts, queries the Policy_Decision_Point, and enforces the resulting decision.
- **Access_Control_Policy**: A set of rules that map authenticated Identity and Role_Bindings to permitted operations on specific resources or information types within a given Enclave.
- **Enclave**: A named security domain with its own Access_Control_Policy, Trust_Anchor set, and Role_Binding definitions. An Entity may participate in multiple Enclaves simultaneously.
- **Role_Binding**: An association between an Identity and a named role within a specific Enclave, granting the access rights defined for that role by the Enclave's Access_Control_Policy.
- **Credential_Cache**: A local store maintained by an Entity that holds recently validated Credentials and Policy_Decision_Point responses, reducing repeated network queries.
- **Cache_TTL**: The configurable time-to-live duration after which a Credential_Cache entry is considered stale and must be revalidated with the Policy_Decision_Point.
- **Non_Person_Entity**: An Entity that is not a human participant, including sensors, platforms, autonomous vehicles, and AI agents, that holds its own Identity and Credentials.
- **Authentication_Exchange**: A discrete cryptographic handshake between two Entities consisting of a sequence of C2_Messages that establishes mutual identity verification before communication proceeds.
- **DataItem**: A metadata struct representing a unit of data generated by an Entity in the simulation (sensor telemetry, mission report, C2 log, or derived product). DataItems carry a classification, provenance chain, and size in bytes; they do not store actual data payloads.
- **DataStore**: A Node designated as a data fabric storage point, hosting a DataCatalog and ProvenanceGraph for DataItems ingested from the simulation.
- **IntendedPolicy**: A formal JSON specification of the intended access control outcomes, distinct from the implemented `icam_policy.json`, used by the SecurityOracle to detect discrepancies between design and implementation.
- **SecurityOracle**: A component that evaluates every security-relevant simulation outcome against the IntendedPolicy and classifies each as conformant, violation, over-restriction, or unspecified.

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

---

### Requirement 17: Entity and Sub-Entity Identity Model

**User Story:** As a simulation engineer, I want each node and its hosted sub-entities to hold distinct identities, so that the simulation accurately represents multi-crew platforms and mixed human/NPE environments.

#### Acceptance Criteria

1. THE Simulator SHALL represent each Entity with a unique Identity, a parent Node identifier, an Entity type (human or Non_Person_Entity), and a set of zero or more Role_Bindings across one or more Enclaves.
2. THE Simulator SHALL support multiple Sub_Entities hosted within a single Node, each with an independent Identity and independent Role_Bindings.
3. WHEN a Scenario is loaded, THE Simulator SHALL validate that every Entity identifier is unique across the entire Scenario and that each Entity references an existing Node identifier.
4. IF an Entity definition references a Node identifier that does not exist in the Scenario, THEN THE Simulator SHALL report a descriptive error identifying the Entity and the missing Node, and halt Scenario loading.
5. THE Simulator SHALL support at least 10,000 Entities in a single Scenario, including Non_Person_Entities, without exceeding available MATLAB memory for a system with 16 GB RAM.
6. FOR ALL valid Scenario configurations, saving then loading the Scenario SHALL preserve all Entity definitions, Identity values, and Role_Bindings without loss (round-trip property).

---

### Requirement 18: Credential Management and PKI

**User Story:** As a simulation engineer, I want the simulator to model certificate issuance and a public key infrastructure, so that entity credentials are grounded in realistic cryptographic trust relationships.

#### Acceptance Criteria

1. THE Simulator SHALL represent each Certificate with an issuing Trust_Anchor identifier, a subject Entity identifier, a public key value, a set of Role_Bindings, an issuance simulation time, and an expiry simulation time.
2. WHEN a Scenario is loaded, THE Simulator SHALL initialize each Entity's Credential from a pre-configured Certificate defined in the Scenario_File or generate a synthetic Certificate signed by the designated Trust_Anchor.
3. WHEN a Certificate's expiry simulation time is reached, THE Simulator SHALL mark the Certificate as expired, record a credential-expiry event in the Event_Log, and trigger a certificate renewal exchange modeled as a sequence of C2_Messages to the issuing Trust_Anchor Node.
4. THE Simulator SHALL model certificate issuance as a discrete C2_Message exchange between the requesting Entity's Node and the Trust_Anchor Node, subject to the network's Latency and Outage constraints.
5. IF a Trust_Anchor Node is unreachable due to an Outage when a certificate renewal is required, THEN THE Simulator SHALL record a credential-renewal-failure event in the Event_Log and retain the expired Certificate until renewal succeeds.
6. THE Simulator SHALL support configuring the certificate validity period per Trust_Anchor, with a minimum granularity of one simulation second.

---

### Requirement 19: Authentication Exchange Protocol

**User Story:** As a simulation engineer, I want first-contact authentication between entities to be modeled as a discrete cryptographic handshake, so that authentication latency and failure modes are captured in the simulation.

#### Acceptance Criteria

1. WHEN two Entities communicate for the first time within a Scenario run, THE Simulator SHALL initiate an Authentication_Exchange consisting of a public key exchange request C2_Message followed by an identity verification response C2_Message before delivering the original message.
2. WHEN an Authentication_Exchange is initiated, THE Simulator SHALL model each message in the exchange as a discrete C2_Message routed through the network simulation, subject to the full Latency and Outage constraints of the Path between the two Entities' Nodes.
3. WHEN an Authentication_Exchange completes successfully, THE Simulator SHALL record the authenticated peer Identity in the initiating Entity's local trust store and skip the Authentication_Exchange for subsequent communications between the same pair of Entities within the same Scenario run.
4. IF an Authentication_Exchange message is undeliverable due to a network Outage, THEN THE Simulator SHALL record an authentication-failure event in the Event_Log and withhold the original message until the Authentication_Exchange completes successfully or a configurable retry limit is reached.
5. WHEN the retry limit for an Authentication_Exchange is reached without success, THE Simulator SHALL record an authentication-timeout event in the Event_Log and discard the original message, recording a delivery-failure event with the reason "authentication-timeout".
6. THE Simulator SHALL record the total Authentication_Exchange Latency (sum of all handshake message latencies) in the Event_Log for each completed exchange.

---

### Requirement 20: Policy Decision Points

**User Story:** As a simulation engineer, I want distributed policy decision points modeled as network nodes, so that access control queries are subject to the same connectivity constraints as operational traffic.

#### Acceptance Criteria

1. THE Simulator SHALL represent each Policy_Decision_Point as a designated Node in the Scenario with an associated Access_Control_Policy and a list of Enclaves it serves.
2. WHEN an Entity's Policy_Enforcement_Point requires an access control decision and no valid Credential_Cache entry exists, THE Simulator SHALL model the query as a C2_Message from the Entity's Node to the nearest reachable Policy_Decision_Point Node, subject to network Latency and Outage constraints.
3. WHEN a Policy_Decision_Point receives a query C2_Message, THE Simulator SHALL evaluate the requesting Entity's Identity and Role_Bindings against the Access_Control_Policy and return a permit or deny decision as a C2_Message response.
4. THE Simulator SHALL model policy synchronization between Policy_Decision_Point Nodes as periodic C2_Messages exchanged at a configurable synchronization interval, contributing to Background_Traffic load on the Links between those Nodes.
5. IF a Policy_Decision_Point Node is unreachable due to an Outage when an access control decision is required, THEN THE Simulator SHALL apply a configurable fail-open or fail-closed policy and record a pdp-unreachable event in the Event_Log.
6. THE Simulator SHALL record per-Policy_Decision_Point statistics in the Statistics_Report, including total queries received, total permit decisions, total deny decisions, and mean query response Latency.

---

### Requirement 21: Access Control Enforcement

**User Story:** As a simulation engineer, I want access control decisions to gate what messages agents can send and receive, so that information flow restrictions are enforced within the simulation.

#### Acceptance Criteria

1. WHEN an Agent attempts to send a C2_Message to a destination Entity, THE Simulator SHALL invoke the Policy_Enforcement_Point to obtain an access control decision before routing the message.
2. WHEN the Policy_Enforcement_Point returns a deny decision for a C2_Message, THE Simulator SHALL discard the message, record an access-denied event in the Event_Log with the requesting Entity identifier, destination Entity identifier, and the denying Policy_Decision_Point identifier, and notify the sending Agent.
3. WHEN the Policy_Enforcement_Point returns a permit decision for a C2_Message, THE Simulator SHALL route the message through the network simulation without additional access control delay beyond the Policy_Decision_Point query Latency already incurred.
4. WHEN a C2_Message is delivered to a receiving Entity, THE Simulator SHALL verify that the receiving Entity holds a Role_Binding permitting receipt of that message type in the relevant Enclave before making the message content available to the Agent.
5. THE Simulator SHALL include access-denied event counts per Entity and per Enclave in the Statistics_Report.
6. WHERE an Agent's Behavior_Trace includes an Agent_Action that was blocked by an access-denied decision, THE Simulator SHALL annotate the corresponding entry in the Evaluation_Report with the reason "access-denied" rather than counting it as an Agent fidelity failure.

---

### Requirement 22: Multi-Enclave Role Management

**User Story:** As a simulation engineer, I want entities to hold different roles in different security enclaves, so that the simulation reflects realistic multi-domain access control environments.

#### Acceptance Criteria

1. THE Simulator SHALL support assigning each Entity zero or more Role_Bindings, where each Role_Binding specifies an Enclave identifier and a role name defined in that Enclave's Access_Control_Policy.
2. WHEN evaluating an access control decision, THE Simulator SHALL apply only the Role_Bindings associated with the Enclave relevant to the resource or message type being accessed.
3. THE Simulator SHALL support a single Entity holding different role names in different Enclaves simultaneously (e.g., "pilot" in one Enclave and "mission-commander" in another), with independent access rights in each.
4. WHEN an Entity's Role_Binding in a given Enclave changes during a simulation run (e.g., due to a role-change event defined in the Scenario), THE Simulator SHALL update the Entity's Credential_Cache entries for that Enclave and record a role-change event in the Event_Log.
5. IF a Role_Binding references an Enclave identifier or role name that is not defined in the Scenario, THEN THE Simulator SHALL report a descriptive error identifying the Entity and the undefined reference, and halt Scenario loading.
6. THE Simulator SHALL include per-Enclave Role_Binding counts in the Statistics_Report.

---

### Requirement 23: Credential Caching

**User Story:** As a simulation engineer, I want entities to cache credentials and policy decisions locally, so that the simulation accurately models the reduction in PDP query traffic that caching provides.

#### Acceptance Criteria

1. THE Simulator SHALL maintain a Credential_Cache for each Entity that stores permit and deny decisions returned by Policy_Decision_Points, keyed by the queried resource or message type and the requesting Entity's Identity.
2. WHEN a Credential_Cache entry exists and has not exceeded its Cache_TTL, THE Simulator SHALL use the cached decision without generating a Policy_Decision_Point query C2_Message.
3. WHEN a Credential_Cache entry's age exceeds the Cache_TTL, THE Simulator SHALL mark the entry as stale, generate a Policy_Decision_Point query C2_Message to revalidate the entry, and apply the fail-open or fail-closed policy configured for the relevant Enclave until the revalidation response is received.
4. THE Simulator SHALL support configuring Cache_TTL independently per Enclave, with a minimum granularity of one simulation second and a value of zero indicating that caching is disabled for that Enclave.
5. WHEN a Policy_Decision_Point broadcasts a policy-update C2_Message, THE Simulator SHALL invalidate all Credential_Cache entries for the affected Enclave on all Entities that receive the broadcast, regardless of remaining Cache_TTL.
6. THE Simulator SHALL record Credential_Cache hit rate, miss rate, and invalidation count per Entity in the Statistics_Report.
7. FOR ALL sequences of access control queries with identical inputs, the sequence of permit/deny decisions SHALL be identical whether the Credential_Cache is enabled or disabled, provided no policy changes occur between queries (cache consistency property).

---

### Requirement 24: Non-Person Entity Identity Support

**User Story:** As a simulation engineer, I want non-person entities such as sensors, platforms, and AI agents to be first-class identity holders, so that automated systems are subject to the same authentication and access control as human participants.

#### Acceptance Criteria

1. THE Simulator SHALL treat Non_Person_Entities as first-class Entities with their own Identity, Certificate, and Role_Bindings, subject to all authentication and access control requirements defined in Requirements 17 through 23.
2. THE Simulator SHALL support assigning a Non_Person_Entity as the operator of an Agent, so that the Agent's C2_Messages are attributed to the Non_Person_Entity's Identity rather than a human Sub_Entity's Identity.
3. WHEN a Non_Person_Entity's Certificate expires, THE Simulator SHALL model the certificate renewal exchange as a C2_Message sequence to the Trust_Anchor Node, identical in structure to the renewal process for human Entities defined in Requirement 18.
4. THE Simulator SHALL support Scenarios containing at least 10,000 Non_Person_Entities without exceeding available MATLAB memory for a system with 16 GB RAM.
5. THE Simulator SHALL include Non_Person_Entity counts, authentication event counts, and access-denied event counts as distinct categories in the Statistics_Report, separate from human Entity statistics.
6. IF a Non_Person_Entity is assigned a Role_Binding that is restricted to human Entities by the Enclave's Access_Control_Policy, THEN THE Simulator SHALL record a policy-violation event in the Event_Log and deny the Role_Binding assignment.

---

## Phase 9: Operational Archive Layer

### Requirement 25: Run Registry

**User Story:** As a simulation engineer, I want every simulation run catalogued automatically with metadata, so that I can discover, filter, and retrieve past runs without manually tracking output directories.

#### Acceptance Criteria

1. THE Simulator SHALL assign a universally unique run identifier (UUID v4) to every simulation run at the time `SimController.run()` is called.
2. WHEN a simulation run completes, THE Simulator SHALL write a run record to the RunRegistry containing: run identifier, scenario name, scenario file path, simulation start time (ISO-8601), simulation end time (ISO-8601), wall-clock duration in seconds, node count, link count, C2 message counts (scheduled/delivered/failed), and archive store path.
3. THE RunRegistry SHALL persist run records across MATLAB sessions and SHALL be readable by subsequent MATLAB sessions without reloading the simulator.
4. THE Simulator SHALL provide a function `data.RunRegistry.list(filters)` that returns a MATLAB table of run records matching the supplied filter criteria (scenario name pattern, date range, minimum fidelity score, custom metadata key-value pairs).
5. IF a RunRegistry file is missing or corrupted on load, THE Simulator SHALL create a new empty registry and log a warning; it SHALL NOT halt or error.
6. THE RunRegistry SHALL support user-defined metadata key-value pairs attached to any run record, set via `data.RunRegistry.annotate(runId, key, value)`.

---

### Requirement 26: Event Stream Archiving

**User Story:** As a simulation engineer, I want simulation events archived to a persistent store during the run, so that complete event histories survive beyond the current MATLAB session and are available for post-run analysis without re-running the simulation.

#### Acceptance Criteria

1. THE Simulator SHALL stream all `EventCalendar` events to the `EventArchiver` at the point of dispatch in the DES main loop, without adding more than 1 ms of wall-clock overhead per event on a system meeting the minimum hardware specification.
2. THE `EventArchiver` SHALL buffer events in memory and flush to the `SimulationStore` at a configurable flush interval (default: every 1,000 events or every 60 simulation seconds, whichever comes first).
3. WHEN the simulation completes or is stopped, THE `EventArchiver` SHALL flush all remaining buffered events to the `SimulationStore` before returning control to the caller.
4. THE archived event log SHALL contain all fields defined in the existing Event Log schema (§4.2 of the design document) plus the run identifier.
5. IF a flush to the `SimulationStore` fails (e.g., disk full), THE `EventArchiver` SHALL log a warning with the run identifier and the number of events lost, and SHALL continue buffering subsequent events; it SHALL NOT halt the simulation.
6. THE Simulator SHALL also archive the complete scenario configuration (as a JSON snapshot) at run start, so that each archived run is self-contained.

---

### Requirement 27: Cross-Run Query API

**User Story:** As a simulation engineer, I want to query simulation data across multiple runs using a structured API, so that I can analyse performance trends, compare scenarios, and detect regressions without manually parsing output files.

#### Acceptance Criteria

1. THE `data.QueryEngine` SHALL provide a `getEvents(runId, filters)` function that returns a MATLAB table of events for the specified run, filtered by event type, simulation time range, node identifier, or link identifier.
2. THE `data.QueryEngine` SHALL provide a `getStats(runIds)` function that returns a MATLAB table with one row per run, containing all top-level fields from the Statistics_Report schema (latency statistics, C2 message counts, per-link outage fractions, agent fidelity summary where present).
3. THE `data.QueryEngine` SHALL provide a `compareRuns(runId1, runId2)` function that returns a struct containing the per-field difference between the two runs' statistics, using absolute difference for numeric fields and a text diff summary for string fields.
4. THE `data.QueryEngine` SHALL provide an `aggregateStats(runIds)` function that returns a struct containing mean, median, standard deviation, min, and max for each numeric statistics field across the supplied run set.
5. ALL query functions SHALL complete within 5 seconds of wall-clock time for a result set of up to 1,000,000 events or 10,000 runs on a system with a conventional SSD.
6. IF a `runId` supplied to any query function does not exist in the store, THE `QueryEngine` SHALL throw `netsim:data:unknownRunId` with the missing identifier; it SHALL NOT silently return empty results.

---

### Requirement 28: Scenario Lineage

**User Story:** As a simulation engineer, I want each archived run to embed the complete scenario configuration that produced it, so that I can reproduce any past run exactly without relying on external file references.

#### Acceptance Criteria

1. WHEN a simulation run starts, THE `DataFabricController` SHALL snapshot the fully resolved scenario struct (including all node definitions, link definitions, agent definitions, and ICAM entity/policy definitions if present) and write it to the archive store under the run's identifier.
2. THE Simulator SHALL provide a `data.QueryEngine.getScenario(runId)` function that returns the scenario struct exactly as it was at run start, loadable directly into `SimController` for replay.
3. FOR ALL archived runs, calling `getScenario(runId)` and using the returned scenario to construct a new `SimController` SHALL produce an equivalent simulation run (same network topology, same trajectory, same agent role files referenced) when re-executed with the same random seed.
4. THE scenario snapshot SHALL be stored as a JSON document within the run's HDF5 group, readable by any HDF5-compatible tool without MATLAB.
5. IF the scenario includes file references (role definition Markdown files, policy JSON files, reference behavior files), THE archive SHALL embed the file contents inline in the scenario snapshot rather than storing the file path alone.

---

### Requirement 29: Standard Export

**User Story:** As a data engineer, I want simulation outputs exported in open standard formats, so that downstream analytics tools (Python, R, Julia, Tableau, etc.) can consume them without a MATLAB license.

#### Acceptance Criteria

1. THE Simulator SHALL provide a `data.QueryEngine.exportRun(runId, outputDir, format)` function that exports all data for a specified run (events, statistics, scenario snapshot, agent traces if present, ICAM report if present) to the specified directory in the specified format.
2. THE supported export formats SHALL include `'csv'` (one CSV file per data table) and `'json'` (one JSON file per data object); HDF5 is always available natively via the store.
3. ALL exported CSV files SHALL include a header row with column names matching the field names in the corresponding data model schema.
4. ALL exported JSON files SHALL be valid JSON (parseable by `jsondecode` and by standard JSON parsers) with no MATLAB-specific encoding artefacts.
5. THE Simulator SHALL provide a `data.QueryEngine.exportBatch(runIds, outputDir, format)` function that exports multiple runs in a single call, placing each run's files in a subdirectory named by the run identifier.

---

### Requirement 30: Schema Versioning

**User Story:** As a simulation engineer, I want the archive schema versioned, so that data written by an older version of the simulator remains readable after the data models evolve.

#### Acceptance Criteria

1. THE `SimulationStore` SHALL write a `schemaVersion` attribute to the root of every HDF5 archive file, set to the current schema version string in the form `"MAJOR.MINOR"`.
2. WHEN the `SimulationStore` opens an existing archive file, it SHALL read the `schemaVersion` attribute and compare it to the current schema version; if the major version differs, THE Simulator SHALL throw `netsim:data:schemaMajorVersionMismatch` with the file path and both version strings.
3. WHEN the minor version of an existing archive is older than the current minor version, THE `SimulationStore` SHALL apply any registered migration functions in order before returning data to the caller.
4. THE Simulator SHALL provide a `data.SimulationStore.registerMigration(fromVersion, toVersion, migrationFn)` function that registers a migration function to be called when upgrading data from `fromVersion` to `toVersion`.
5. FOR ALL archives written by the current schema version, opening and reading all run data SHALL produce byte-for-byte identical results to the data as written (read-back fidelity).

---

### Requirement 31: Retention Policy

**User Story:** As a simulation engineer, I want a configurable retention policy for archived runs, so that the archive does not grow unboundedly during large batch campaigns.

#### Acceptance Criteria

1. THE `DataFabricController` SHALL accept a `retentionPolicy` configuration struct with fields: `maxRuns` (maximum number of runs to retain; default: unlimited), `maxAgeDays` (maximum age of runs to retain; default: unlimited), `keepTagged` (logical; default: `true` — runs annotated with any user metadata are exempt from retention limits).
2. WHEN a retention policy is configured, THE `DataFabricController` SHALL apply the policy after each completed run: runs exceeding `maxRuns` (oldest first) or older than `maxAgeDays` are removed from the archive unless `keepTagged` is `true` and the run has user metadata.
3. WHEN a run is removed by the retention policy, THE Simulator SHALL delete the run's HDF5 group from the archive store and remove its record from the RunRegistry, and SHALL log an informational message identifying the removed run identifier.
4. THE Simulator SHALL provide a `data.DataFabricController.applyRetention()` function that applies the current policy on demand, independently of a simulation run.
5. IF `maxRuns` is set to zero, THE retention policy SHALL be disabled entirely (no runs are removed automatically).

---

### Requirement 32: External Accessibility

**User Story:** As a data engineer, I want the archive readable by standard HDF5 tools without MATLAB, so that I can integrate simulation outputs into Python/Pandas/Spark pipelines directly.

#### Acceptance Criteria

1. ALL datasets in the archive SHALL use HDF5 standard numeric datatypes (float64, int64, uint8 for strings encoded as UTF-8 bytes) with no MATLAB-specific metadata required for interpretation.
2. ALL string-valued fields SHALL be stored as fixed-length or variable-length UTF-8 strings using the HDF5 string datatype, readable by h5py, HDFView, and the HDF5 C library.
3. THE archive SHALL include a `README` attribute at the root group documenting the schema version, the meaning of each top-level group, and a reference to the schema definition document.
4. FOR ALL archive files, the Python expression `import h5py; f = h5py.File(archivePath, 'r'); list(f.keys())` SHALL return the expected top-level group names without error (verified in the integration test).

---

## Phase 10: Simulated Data Fabric Layer

### Requirement 33: Data Item Model

**User Story:** As a simulation engineer, I want data items to be first-class simulation entities with typed metadata and provenance, so that the simulation can model realistic data generation and lineage without storing actual data payloads.

#### Acceptance Criteria

1. THE Simulator SHALL represent each DataItem with: a unique identifier, a DataItem_Type (one of `sensor_telemetry`, `mission_report`, `c2_log`, `derived`), a creator Entity identifier, a creator Node identifier, a creation simulation timestamp, a payload size in bytes, a classification label (string, defined per-scenario), an owning Enclave identifier, and a provenance chain.
2. THE provenance chain SHALL be an ordered list of zero or more ProvenanceEntry structs, each containing: a source DataItem identifier, the identifier of the DataStore that held the source item, a transformation type string, and the simulation timestamp at which the transformation occurred.
3. THE Simulator SHALL assign a unique DataItem identifier to every DataItem at creation time; no two DataItems in the same simulation run SHALL share an identifier.
4. THE Simulator SHALL support at least 1,000,000 DataItems in a single Scenario without exceeding available MATLAB memory for a system with 16 GB RAM, using struct-of-arrays storage.
5. WHEN an Agent produces a `publish_data` Agent_Action, THE Simulator SHALL create a DataItem from the action's metadata fields and schedule a DATA_INGEST event.
6. WHEN a `c2_log` DataItem is created, THE Simulator SHALL populate its provenance chain with a single ProvenanceEntry referencing the C2_Message identifier that triggered the log.

---

### Requirement 34: Data Ingest Events

**User Story:** As a simulation engineer, I want data ingestion to be modeled as a discrete network event, so that the cost of publishing data to the fabric — including latency and the possibility of failure — is captured in the simulation.

#### Acceptance Criteria

1. WHEN a DataItem is created by an entity, THE Simulator SHALL schedule a DATA_INGEST event: a C2_Message from the creator entity's Node to the designated primary DataStore Node, with size equal to the DataItem's `sizeBytes`.
2. WHEN a DATA_INGEST event is successfully delivered to the DataStore Node, THE Simulator SHALL add the DataItem to the DataStore's DataCatalog and record a `data_ingest_complete` event in the Event_Log with the DataItem identifier, DataStore node identifier, and delivery simulation time.
3. WHEN a DATA_INGEST delivery fails (no path available or link outage), THE Simulator SHALL record a `data_ingest_failed` event in the Event_Log with the DataItem identifier and reason, and SHALL schedule a retry at a configurable retry interval (default: 60 simulation seconds) until a configurable maximum retry count is reached.
4. WHEN the maximum retry count for a DATA_INGEST is reached without success, THE Simulator SHALL record a `data_ingest_dropped` event in the Event_Log with the DataItem identifier, and the DataItem SHALL not be added to any DataStore's DataCatalog.
5. THE Simulator SHALL record the DATA_INGEST latency (from DataItem creation time to DataCatalog insertion time) for each successfully ingested DataItem, and SHALL include the mean, median, and 95th-percentile ingest latency in the Statistics_Report.

---

### Requirement 35: Data Store Nodes

**User Story:** As a simulation engineer, I want specific nodes designated as Data Store nodes that host the fabric's catalogs, so that data ingestion and retrieval are subject to the same geographic and network constraints as operational C2 traffic.

#### Acceptance Criteria

1. THE Simulator SHALL support designating any Node in a Scenario as a DataStore by setting a `"dataStore": true` flag in the Node's definition in the Scenario JSON.
2. WHEN a Node is designated a DataStore, THE Simulator SHALL initialize a DataCatalog for that Node and register it in the DataStoreRegistry.
3. THE Simulator SHALL support a Scenario containing zero DataStore nodes (fabric layer inactive), one DataStore node, or multiple DataStore nodes simultaneously.
4. EACH DataStore node SHALL maintain a DataCatalog implemented as a struct-of-arrays with fields for DataItem identifier, DataItem_Type, creator Entity identifier, creator Node identifier, creation simulation time, `sizeBytes`, classification, owning Enclave identifier, and provenance chain reference.
5. THE DataCatalog SHALL support lookup by DataItem identifier in O(1) average time using MATLAB `containers.Map`.
6. IF a DATA_INGEST or DATA_FETCH event is routed to a Node that is not designated a DataStore, THE Simulator SHALL record a `data_routing_error` event in the Event_Log and discard the message.

---

### Requirement 36: Data Access Control via ICAM Extension

**User Story:** As a simulation engineer, I want data access control enforced through the existing ICAM layer, so that the fabric inherits the same enclave and role model without duplicating policy infrastructure.

#### Acceptance Criteria

1. WHEN a DATA_FETCH request arrives at a DataStore node, THE Simulator SHALL invoke the ICAM `PolicyEnforcementPoint.checkReceive` for the requesting entity with a `messageType` of `'data_item:<classification>'` (where `<classification>` is the DataItem's classification label) before returning the item.
2. WHEN the ICAM policy returns `deny` for a DATA_FETCH, THE Simulator SHALL schedule a DATA_FETCH_DENIED C2_Message back to the requesting entity's Node, record an `access_denied` event in the Event_Log with the DataItem identifier and requesting entity identifier, and SHALL NOT include the DataItem or its provenance in any response.
3. WHEN the ICAM policy returns `permit` for a DATA_FETCH, THE Simulator SHALL proceed with the fetch and include the DataItem metadata and full provenance chain in the DATA_FETCH_RESULT response.
4. THE Scenario's ICAM policy JSON SHALL support wildcard classification rules (e.g., `'data_item:*'` permits access to any DataItem regardless of classification, `'data_item:SECRET'` permits access only to SECRET-classified items).
5. IF no ICAM layer is configured in the Scenario, THE Simulator SHALL apply a default permit-all policy for all DATA_FETCH requests and log a warning at scenario load time that data access control is unenforced.
6. THE Statistics_Report SHALL include a `dataFabric` section with per-entity data access denial counts and per-classification denial counts.

---

### Requirement 37: Data Query and Fetch Events

**User Story:** As a simulation engineer, I want data queries and fetches to be modeled as discrete C2 message exchanges, so that the latency and failure modes of retrieving data from the fabric are captured in the simulation.

#### Acceptance Criteria

1. WHEN an Agent produces a `query_data` Agent_Action, THE Simulator SHALL schedule a DATA_QUERY C2_Message from the agent's Node to the targeted DataStore Node, carrying the query criteria (DataItem_Type filter, creator entity filter, time range filter, classification filter, and/or enclave filter) as payload.
2. WHEN a DATA_QUERY C2_Message is delivered to a DataStore Node, THE Simulator SHALL evaluate the query criteria against the DataCatalog, apply ICAM `PolicyEnforcementPoint.checkReceive` for each matching item, and schedule a DATA_QUERY_RESULT C2_Message back to the requesting entity's Node carrying only the metadata of permitted matching items.
3. WHEN an Agent produces a `fetch_data` Agent_Action specifying a DataItem identifier, THE Simulator SHALL schedule a DATA_FETCH C2_Message from the agent's Node to the DataStore Node holding that item, with `sizeBytes` equal to the fetch request overhead (configurable, default 64 bytes).
4. WHEN a DATA_FETCH C2_Message is delivered to a DataStore Node, THE Simulator SHALL perform the ICAM access control check defined in Requirement 36 and schedule either a DATA_FETCH_RESULT or DATA_FETCH_DENIED C2_Message back to the requesting entity's Node.
5. WHEN a DATA_FETCH_RESULT is scheduled, its `sizeBytes` SHALL equal the DataItem's `sizeBytes`, so that large data items impose a proportionally larger network cost on the return path.
6. THE Simulator SHALL record ingest, query, and fetch latencies separately in the Statistics_Report.
7. IF a DATA_FETCH requests a DataItem identifier that does not exist in the targeted DataStore's DataCatalog, THE Simulator SHALL schedule a DATA_FETCH_DENIED response with reason `'item_not_found'`.

---

### Requirement 38: Data Provenance

**User Story:** As a simulation engineer, I want every data item to carry a provenance chain tracing its lineage, so that the simulation models the ability to audit the origin and transformation history of any data item retrieved from the fabric.

#### Acceptance Criteria

1. WHEN a `derived` DataItem is created from one or more source DataItems, THE Simulator SHALL populate the new DataItem's provenance chain with one ProvenanceEntry per source item, each recording the source DataItem identifier, source DataStore node identifier, transformation type, and transformation simulation timestamp.
2. THE ProvenanceGraph at each DataStore SHALL be a MATLAB `digraph` where each node is a DataItem identifier and each directed edge represents a derivation relationship (source → derived), with edge attributes for transformation type and timestamp.
3. WHEN a DATA_FETCH_RESULT is returned to a requesting entity, THE response SHALL include the full provenance chain of the requested DataItem as a JSON array in the message payload, including recursive provenance (i.e., the provenance chains of all source items, up to a configurable maximum depth, default 5).
4. THE Simulator SHALL provide a `fabric.ProvenanceGraph.getLineage(dataItemId, maxDepth)` function that returns a struct containing all ancestor DataItem identifiers, the directed edge list of the derivation graph, and the transformation types at each step.
5. WHEN a `c2_log` DataItem is created automatically (Requirement 33.6), its provenance chain SHALL reference the originating C2_Message identifier, enabling audit queries that trace from a data item back to the specific C2 traffic that produced it.
6. THE Statistics_Report SHALL include per-DataStore provenance graph statistics: total DataItem nodes, total derivation edges, maximum provenance depth observed, and mean provenance chain length.

---

### Requirement 39: Data Replication

**User Story:** As a simulation engineer, I want data items replicated between Data Store nodes as discrete C2 messages, so that replication traffic competes for bandwidth with operational traffic and replication failures are subject to the same outage constraints as any other link.

#### Acceptance Criteria

1. EACH DataStore node SHALL have a configurable replication target list specifying zero or more peer DataStore node identifiers and a replication policy per peer (`'all'` — replicate all items, `'by_classification:<label>'` — replicate only items with the specified classification, `'by_enclave:<enclaveId>'` — replicate only items belonging to the specified enclave).
2. WHEN a DataItem is successfully ingested by a DataStore (Requirement 34.2), THE Simulator SHALL schedule a DATA_REPLICATE C2_Message to each peer DataStore in the replication target list that matches the item's replication policy, with `sizeBytes` equal to the DataItem's `sizeBytes`.
3. WHEN a DATA_REPLICATE C2_Message is delivered to a peer DataStore, THE Simulator SHALL add the DataItem to the peer's DataCatalog (if not already present) and record a `data_replicated` event in the Event_Log.
4. WHEN a DATA_REPLICATE delivery fails due to network outage or no available path, THE Simulator SHALL schedule a retry after the replication retry interval (default 120 simulation seconds) and record a `data_replication_failed` event in the Event_Log.
5. WHEN the maximum replication retry count is reached without success, THE Simulator SHALL record a `data_replication_dropped` event in the Event_Log; the DataItem SHALL remain in the primary DataStore's catalog and not be counted as lost.
6. DATA_REPLICATE messages SHALL contribute to the Background_Traffic load on the links they traverse, counted separately from operational C2 traffic in per-link statistics.
7. THE Statistics_Report SHALL include per-DataStore replication statistics: total items replicated out, total items replicated in, failed replications, and mean replication latency per peer.

---

### Requirement 40: Agent Data Integration

**User Story:** As a researcher, I want agents to generate and consume data items as part of their role behavior, so that data fabric interactions are driven by the same role-defined procedures as all other agent actions.

#### Acceptance Criteria

1. THE Simulator SHALL support three new Agent_Action types: `publish_data` (creates and ingests a DataItem), `query_data` (sends a DATA_QUERY to a DataStore), and `fetch_data` (sends a DATA_FETCH for a specific DataItem identifier).
2. WHEN an LLM_Agent produces a `publish_data` Agent_Action, THE action SHALL include: DataItem_Type, `sizeBytes`, classification label, owning Enclave identifier, and optionally a list of source DataItem identifiers (for `derived` items).
3. WHEN a DATA_QUERY_RESULT or DATA_FETCH_RESULT C2_Message is delivered to an agent's Node, THE Simulator SHALL make its content available to the agent via `AgentRegistry.deliver` at the computed delivery time, triggering the agent's LLM to process the result as it would any incoming C2_Message.
4. WHEN a DATA_FETCH_DENIED message is delivered to an agent's Node, THE Simulator SHALL make its content available to the agent and SHALL annotate the corresponding `fetch_data` Agent_Action in the Behavior_Trace with reason `'access_denied'`, consistent with the pattern for network-constrained and ICAM-denied actions.
5. THE Reference_Behavior specification SHALL support specifying `publish_data`, `query_data`, and `fetch_data` as expected Agent_Actions, with the same strict/unordered ordering options as other action types.
6. THE FidelityEvaluator SHALL treat `fetch_data` Agent_Actions blocked by an ICAM `access_denied` decision identically to those blocked by network outage: annotating them as `'access_denied'` rather than penalizing the agent's Fidelity_Score.

---

### Requirement 41: Data Fabric Reporting

**User Story:** As a simulation engineer, I want data fabric statistics included in the simulation's standard reports, so that I can analyse data flow performance alongside network and ICAM results.

#### Acceptance Criteria

1. THE Statistics_Report SHALL include a `"dataFabric"` block (present only when at least one DataStore node is configured) with the following sub-fields: total DataItems created, total DataItems successfully ingested, total ingest failures, total ingest retries, total DATA_QUERY requests, total DATA_FETCH requests, total DATA_FETCH_RESULT responses, total DATA_FETCH_DENIED responses.
2. THE `"dataFabric"` block SHALL include per-DataStore statistics: DataCatalog item count, ingest latency distribution (mean, median, p95), replication statistics (per Requirement 39.7), and per-classification item counts.
3. THE `"dataFabric"` block SHALL include provenance statistics per Requirement 38.6.
4. THE `"dataFabric"` block SHALL include per-entity access denial counts and per-classification denial counts per Requirement 36.6.
5. THE Simulator SHALL provide a MATLAB function `io.PlotFunctions.dataFlowDiagram(statsReport)` that plots a directed graph of DataItem flow between nodes (ingest sources → DataStore nodes → fetch destinations) with edge widths proportional to item count.
6. FOR ALL valid Statistics_Report JSON files containing a `"dataFabric"` block, loading the file and re-computing the per-DataStore totals SHALL produce values identical to those recorded in the file (consistency property).

---

## Phase 11: Security Evaluation Layer

### Requirement 42: Intended Policy Specification

**User Story:** As a security engineer, I want to specify the intended security policy independently of its implementation, so that I can compare what the policy was meant to do against what it actually does.

#### Acceptance Criteria

1. THE Simulator SHALL load an IntendedPolicy from a JSON file that maps combinations of requesting entity role, target resource classification, enclave, and operation type (`'read'`, `'write'`, `'ingest'`) to an expected outcome (`'permit'` or `'deny'`).
2. THE IntendedPolicy SHALL support wildcard values (`'*'`) in any field, with more specific rules taking precedence over more general rules in the same way as the existing `PolicyDecisionPoint` rule evaluation.
3. WHEN an IntendedPolicy file is loaded, THE Simulator SHALL validate that all referenced roles, classifications, and enclaves are defined in the Scenario; log warnings (not errors) for any roles, classifications, or enclaves in the IntendedPolicy that are not present in the Scenario.
4. THE Simulator SHALL support saving the current IntendedPolicy to a JSON file, and round-trip loading SHALL produce a specification equivalent to the original.
5. IF an IntendedPolicy file cannot be read or contains a JSON syntax error, THE Simulator SHALL report a descriptive error with the file path and halt security evaluation setup.

---

### Requirement 43: Security Oracle

**User Story:** As a security engineer, I want every security-relevant simulation outcome evaluated against the intended policy automatically, so that I can identify where the implementation diverges from the design.

#### Acceptance Criteria

1. WHEN a simulation run completes, THE `SecurityOracle` SHALL evaluate every DATA_FETCH, DATA_QUERY, AUTH_REQUEST, and C2_MESSAGE_TX outcome in the Event_Log against the IntendedPolicy and classify each as: **Conformant** (outcome matches intended), **Violation** (permit returned when intended policy specifies deny), **Over-restriction** (deny returned when intended policy specifies permit), or **Unspecified** (no IntendedPolicy rule covers this combination).
2. THE SecurityOracle SHALL produce a `SecurityEvaluationReport` containing: total outcomes evaluated, violation count, over-restriction count, unspecified count, conformance rate (conformant / total specified), and a per-event list of all non-conformant outcomes with entity identifier, resource identifier, enclave, operation, actual outcome, intended outcome, and simulation timestamp.
3. WHEN a violation is detected, THE SecurityOracle SHALL record a `security_violation` event in the Event_Log with the full event context, in addition to reporting it in the SecurityEvaluationReport.
4. WHEN a network-degraded condition (PDP unreachability, expired credential, replication lag) causes an outcome that differs from the outcome that would have been produced under normal conditions, THE SecurityOracle SHALL annotate the affected outcomes with reason `'degraded_condition'` and include them in a separate `degradedConditionOutcomes` section of the SecurityEvaluationReport.
5. THE SecurityOracle SHALL compute a **PolicyConformanceScore** in [0.0, 1.0] equal to `conformant / (conformant + violations + over-restrictions)` — unspecified outcomes do not contribute to the denominator.
6. FOR ALL valid SecurityEvaluationReport JSON files, reloading the file and recomputing the PolicyConformanceScore SHALL produce a value identical to the one recorded (consistency property).

---

### Requirement 44: Policy Static Analysis

**User Story:** As a security engineer, I want the security policy analyzed for structural defects before any simulation is run, so that I can fix gaps and conflicts at design time rather than discovering them through test failures.

#### Acceptance Criteria

1. THE `PolicyAnalyzer` SHALL analyze `icam_policy.json` and identify **gaps**: (role, classification, enclave, operation) combinations that no rule explicitly covers, leaving outcome determined by the enclave's `failPolicy` default rather than an explicit rule.
2. THE `PolicyAnalyzer` SHALL identify **conflicts**: pairs of rules that would produce different outcomes for the same (role, classification, enclave, operation) input, where rule ordering determines which fires.
3. THE `PolicyAnalyzer` SHALL identify **dead rules**: rules that are unreachable because an earlier rule with a wildcard always matches the same inputs first.
4. THE `PolicyAnalyzer` SHALL identify **orphaned role bindings**: roles assigned to entities in the Scenario that no rule in `icam_policy.json` references (entities exist with roles that no policy governs).
5. WHEN an IntendedPolicy is provided alongside `icam_policy.json`, THE `PolicyAnalyzer` SHALL additionally identify **intent mismatches**: (role, classification, enclave, operation) combinations where the implementation policy would produce an outcome that differs from the IntendedPolicy.
6. THE `PolicyAnalyzer` SHALL produce a `PolicyAnalysisReport` in JSON format containing counts and details of each finding category, and SHALL return exit code 0 (no findings) or 1 (findings present) for use in automated pipelines.

---

### Requirement 45: Systematic Coverage Generation

**User Story:** As a security engineer, I want the simulation to exercise all entity/resource/enclave combinations systematically, so that I can demonstrate that the security policy has been tested exhaustively rather than only for the access patterns that happen to arise organically.

#### Acceptance Criteria

1. THE `CoverageGenerator` SHALL enumerate all combinations of (requesting entity, target DataItem classification, enclave, operation) that are defined in the Scenario and schedule one access attempt per combination as DATA_FETCH, DATA_QUERY, or C2_MESSAGE_TX events in the simulation.
2. THE `CoverageGenerator` SHALL report a **coverage percentage**: the fraction of combinations explicitly covered by IntendedPolicy rules that were exercised during the simulation run.
3. WHEN the `CoverageGenerator` is active, it SHALL inject access attempts at randomized simulation timestamps distributed across the scenario duration to avoid clustering artifacts.
4. THE Simulator SHALL support running `CoverageGenerator` in **targeted mode**: generating coverage attempts only for a specified subset of enclaves, classifications, or entity roles.
5. IF a Scenario contains no DataStore nodes, THE `CoverageGenerator` SHALL instead generate C2_MESSAGE_TX coverage attempts between all entity pairs across all enclaves, and SHALL log a warning that data-item coverage is not applicable.
6. THE `SecurityEvaluationReport` SHALL include coverage statistics: total combinations enumerated, combinations exercised, combinations producing violations, and combinations unspecified by IntendedPolicy.

---

### Requirement 46: Adversarial Agent Model

**User Story:** As a security engineer, I want to define agents that deliberately attempt unauthorized operations, so that I can verify the security policy holds against a modeled adversary operating within the simulated network.

#### Acceptance Criteria

1. THE Simulator SHALL support a new agent designation `"adversarial": true` in the Scenario agent definitions, with an associated `attackPatterns` list specifying the unauthorized operations the agent will attempt.
2. EACH attack pattern SHALL specify: `attackType` (one of `'unauthorized_data_access'`, `'cross_enclave_access'`, `'expired_credential_access'`, `'pdp_outage_exploitation'`), target resource criteria, target enclave, and attempt timing (simulation timestamp or relative to a trigger event).
3. WHEN a simulation run includes adversarial agents, THE Simulator SHALL execute each attack pattern as a discrete simulation event: scheduling the appropriate DATA_FETCH, DATA_QUERY, or C2_MESSAGE_TX from the adversarial entity's node, subject to full network constraints.
4. THE SecurityOracle SHALL evaluate every adversarial agent access attempt against the IntendedPolicy; a successful adversarial access (permit returned for an operation the IntendedPolicy specifies as deny) SHALL be classified as a **Violation** and flagged with `adversarialSource: true` in the SecurityEvaluationReport.
5. Adversarial agents SHALL be evaluated by the SecurityOracle, not by the FidelityEvaluator; adversarial attack patterns SHALL NOT appear in agent Behavior_Traces or fidelity scores.
6. THE Scenario SHALL support defining an adversarial agent with legitimate credentials (an insider threat model) as well as an adversarial agent with no initial authentication state (an external attacker model).

---

### Requirement 47: Network-Degradation Security Testing

**User Story:** As a security engineer, I want the simulation to systematically test security behavior under degraded network conditions, so that I can identify exploitable windows that only exist when the network is stressed.

#### Acceptance Criteria

1. THE `NetworkDegradationTester` SHALL support defining **degradation scenarios**: named configurations specifying which links or nodes to force into outage, for what duration, and at what simulation time — targeted at specific security-sensitive nodes (PDP nodes, Trust Anchor nodes, primary DataStore nodes).
2. WHEN a degradation scenario targets a PDP node, THE `NetworkDegradationTester` SHALL record the full set of access control outcomes that occurred during the PDP-unreachable window and report them in the SecurityEvaluationReport's `degradedConditionOutcomes` section.
3. WHEN a degradation scenario targets a Trust Anchor node, THE `NetworkDegradationTester` SHALL track entities whose certificates expire during the outage and monitor whether expired-credential access attempts succeed or fail.
4. THE `NetworkDegradationTester` SHALL produce a **DegradationSecurityMatrix**: a table with one row per degradation scenario and one column per security property tested (PDP availability, credential freshness, replication consistency), with pass/fail outcomes and the conditions under which each failure occurs.
5. THE Simulator SHALL support running the complete set of degradation scenarios automatically in a batch, producing a combined DegradationSecurityMatrix across all scenarios.
6. WHEN a security violation is detected only under degraded conditions (not under normal conditions), THE SecurityEvaluationReport SHALL annotate it with `'degraded_only': true` to distinguish exploitable degradation conditions from baseline policy defects.

---

### Requirement 48: Security Reporting and Visualization

**User Story:** As a security engineer, I want security evaluation results in structured reports with supporting visualizations, so that I can communicate findings to policy designers and system owners.

#### Acceptance Criteria

1. THE `SecurityReportWriter` SHALL write a `SecurityEvaluationReport` to JSON format containing all fields specified in Requirement 43, plus the PolicyAnalysisReport (Requirement 44), coverage statistics (Requirement 45), and DegradationSecurityMatrix (Requirement 47).
2. THE `SecurityReportWriter` SHALL write a summary CSV file with one row per non-conformant outcome, suitable for import into spreadsheet tools.
3. THE Simulator SHALL provide `io.PlotFunctions.policyConformanceHeatmap(securityReport)` that plots a heatmap of policy conformance rate by entity role (rows) × data classification (columns), colored by conformance rate.
4. THE Simulator SHALL provide `io.PlotFunctions.attackSurfaceDiagram(securityReport)` that plots the network topology with nodes colored by their security role (normal entity, DataStore, PDP, Trust Anchor, adversarial agent) and edges colored by whether any violation traversed them.
5. THE Simulator SHALL provide `io.PlotFunctions.degradationSecurityPlot(securityReport)` that plots the DegradationSecurityMatrix as a color-coded grid (green = pass, red = fail) with the degradation scenario on one axis and the security property on the other.
6. FOR ALL valid SecurityEvaluationReport JSON files, reloading and recomputing the PolicyConformanceScore SHALL produce a value identical to the recorded value (consistency property).

---

### Requirement 49: Traffic Replay for Validation

**User Story:** As a security engineer, I want to replay real-world network traffic through the simulation, so that I can validate that the simulation accurately predicts the security outcomes observed in the deployed system, and use that validated model to test proposed policy changes before deployment.

#### Acceptance Criteria

1. THE `TrafficReplayLoader` SHALL load a real-world traffic log from a JSON or CSV file and generate a Scenario in which the observed traffic is scheduled as C2_MESSAGE_TX events at the original timestamps, mapped to simulation nodes by entity identifier.
2. THE traffic log format SHALL support the following event types: message transmission (source entity, destination entity, message type, timestamp, size bytes), authentication exchange (initiating entity, target entity, timestamp, outcome), data access attempt (requesting entity, resource identifier, classification, operation, timestamp, observed outcome).
3. WHEN a traffic log contains observed security outcomes (permit/deny decisions from a real system), THE `TrafficReplayLoader` SHALL store these as a **RealWorldOutcomes** reference and pass them to the SecurityOracle for comparison against simulation-predicted outcomes.
4. THE SecurityOracle SHALL produce a **ValidationReport** containing: total events replayed, outcomes where simulation matched real-world, outcomes where simulation differed, and a **ModelAccuracyScore** in [0.0, 1.0] equal to `matched / total`.
5. WHEN simulation and real-world outcomes differ, THE ValidationReport SHALL include the event context, the simulation-predicted outcome, the real-world observed outcome, and the simulation time.
6. THE `TrafficReplayLoader` SHALL support a **topology import** mode where node positions, link types, nominal latencies, and outage parameters are read from a real-world network configuration file rather than specified manually in the Scenario JSON.

---

### Requirement 50: Security Scenario Library

**User Story:** As a security engineer, I want a library of pre-defined attack scenario templates that I can parameterize for any network topology, so that I can apply standard security tests without building each scenario from scratch.

#### Acceptance Criteria

1. THE Simulator SHALL ship with a library of at least five named security scenario templates, each specified as a parameterized JSON file: `insider_data_exfiltration`, `outsider_authentication_bypass`, `pdp_outage_exploitation`, `cross_enclave_escalation`, and `expired_credential_persistence`.
2. EACH scenario template SHALL be instantiable by substituting a target topology (node identifiers, enclave names, role names) without modifying the template itself.
3. THE Simulator SHALL provide a `security.ScenarioLibrary.instantiate(templateName, topology)` function that returns a fully populated Scenario ready for `SimController`.
4. THE SecurityEvaluationReport SHALL identify which library template (if any) was used for the run, for traceability.
