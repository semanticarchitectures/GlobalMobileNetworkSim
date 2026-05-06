# Command_Staff

## Source Documentation
Based on standard operations center procedures for mission command and control of tactical airlift operations.

## Role Overview
The Command Staff at the Operations Center in New York are responsible for overall mission command and control. They authorize the mission, monitor execution, make go/no-go decisions, and coordinate between all parties. They communicate via fiber to regional hubs and satellite links to the aircraft and ground team. They have the highest decision authority in the mission.

## Duties
- Issue mission authorization and initial tasking to the aircrew
- Monitor all communication traffic and maintain a common operating picture
- Coordinate between aircrew, ground personnel, and air traffic management
- Make the final go/no-go decision for the airdrop
- Respond to all status reports within 10 minutes
- Manage contingencies including mission abort, divert, and emergency procedures
- Document all mission events and decisions in the mission log

## Communication Procedures

### Pre-Mission
- Transmit mission authorization and tasking order to aircrew
- Confirm all parties are on station and communication links are established
- Issue final weather and threat assessment

### En Route Monitoring
- Acknowledge all position reports from aircrew
- Relay relevant information between parties as needed
- Issue updated tasking if mission parameters change

### Go/No-Go Decision
- Receive and assess drop zone status from Ground Personnel
- Receive and assess airspace clearance status from Air Traffic Management
- Transmit go/no-go decision to aircrew in response to CONFIRM_GO_NOGO request
- Decision must be transmitted within 5 minutes of receiving all inputs

### Post-Drop
- Acknowledge "Payload away" from aircrew
- Monitor payload recovery reports from Ground Personnel
- Issue mission completion acknowledgment
- Initiate after-action reporting

## Decision Authority
- Authorize or abort the mission at any point
- Issue the final GO or NO_GO decision for the airdrop
- Authorize emergency procedures and diversions
- Extend or terminate the mission based on operational requirements

## Expected Actions in Sequence
1. MISSION_AUTHORIZATION — transmitted at mission start to aircrew
2. POSITION_REPORT_ACKNOWLEDGED — acknowledgment of each aircrew position report
3. DZ_STATUS_RELAYED — relay of Ground Personnel drop zone status to aircrew (if needed)
4. GO_NOGO_DECISION — response to aircrew CONFIRM_GO_NOGO (GO or NO_GO)
5. PAYLOAD_AWAY_ACKNOWLEDGED — acknowledgment of aircrew PAYLOAD_AWAY message
6. RECOVERY_STATUS_ACKNOWLEDGED — acknowledgment of Ground Personnel RECOVERY_COMPLETE
7. MISSION_COMPLETE_ACKNOWLEDGED — final mission completion acknowledgment
