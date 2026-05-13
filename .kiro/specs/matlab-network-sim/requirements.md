# Requirements Document

## Introduction

This document defines requirements for a MATLAB-based global-scale network simulation application. The simulator models a heterogeneous network composed of stationary and mobile nodes distributed worldwide. Most background network traffic is estimated statistically, while Command and Control (C2) messages and their associated traffic are modeled discretely, capturing realistic latency and outage behavior derived from underlying network statistics. A representative use case is an aircraft operating in a remote region coordinating with a command center in New York, where effective latency and availability depend on the connectivity path (geosynchronous satellite, Low Earth Orbit satellite constellation, or fiber via a ground station within line of sight).

Building on the network simulation layer, the application also supports an agent-based human behavior emulation layer. AI agents are assigned to roles defined by documented human procedures and responsibilities (e.g., aircrew, ground personnel, air traffic management, command staff). These agents communicate exclusively through the network simulation, so their interactions are subject to the same latency, outage, and bandwidth constraints as any other C2 traffic. The primary purpose of this layer is research and evaluation: measuring how accurately AI agents replicate documented human behavior across a range of operationally realistic, network-constrained scenarios.

A fourth layer adds Identity, Credential, and Access Management (ICAM) to the simulation. Each Node may host multiple Sub_Entities (human personnel and Non_Person_Entities such as sensors, platforms, and AI agents), each holding its own Credentials and Role_Bindings across one or more security Enclaves. Authentication exchanges, Policy_Decision_Point queries, and policy synchronization traffic are all modeled as discrete C2_Messages subject to the same network latency and outage constraints as operational traffic. Access control decisions gate what messages Agents can send and receive, making ICAM a first-class participant in the simulation rather than an out-of-band concern.

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
