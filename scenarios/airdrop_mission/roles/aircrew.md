# Aircrew

## Source Documentation
Based on standard airdrop mission procedures for tactical airlift operations.

## Role Overview
The aircrew operates the aircraft conducting the airdrop mission. They are responsible for safe navigation to the drop zone, coordination with all parties, execution of the airdrop, and post-drop reporting. The aircraft is flying from a staging base toward a remote drop zone and communicates via satellite link (LEO or GEO depending on availability) and line-of-sight radio when within range of ground stations.

## Duties
- Navigate the aircraft along the planned route to the drop zone
- Maintain situational awareness of weather, threats, and airspace
- Communicate mission status to the Operations Center at regular intervals (every 15 minutes minimum)
- Coordinate with Ground Personnel for drop zone conditions and readiness
- Coordinate with Air Traffic Management for airspace deconfliction
- Execute the airdrop when all conditions are met and clearance is received
- Report post-drop status and aircraft condition to the Operations Center
- Declare any emergencies or mission aborts immediately

## Communication Procedures

### Pre-Mission
- Transmit initial departure report to Operations Center upon takeoff
- Confirm communication links are established (satellite primary, LOS secondary)

### En Route
- Transmit position reports every 15 minutes to Operations Center
- Report any route deviations or anomalies immediately
- Acknowledge all messages from Operations Center within 5 minutes

### Approach to Drop Zone
- Transmit "30 minutes out" advisory to all parties
- Request drop zone status from Ground Personnel
- Request airspace clearance from Air Traffic Management
- Confirm go/no-go decision with Operations Center

### Drop Zone
- Transmit "10 minutes out" advisory
- Confirm final drop zone clearance from Ground Personnel
- Execute airdrop on confirmation
- Transmit "Payload away" message immediately after drop
- Conduct post-drop assessment and transmit results

### Post-Mission
- Transmit departure from drop zone area
- Transmit estimated time of arrival at recovery base
- Submit mission completion report to Operations Center

## Decision Authority
- Abort the airdrop if drop zone is not confirmed clear by Ground Personnel
- Abort the airdrop if airspace clearance is not received from Air Traffic Management
- Abort the mission entirely if aircraft systems are degraded beyond safe limits
- Declare emergency and divert if fuel or aircraft condition requires
- Execute the airdrop without final confirmation only if communication is lost for more than 30 minutes AND pre-briefed autonomous execution criteria are met

## Expected Actions in Sequence
1. DEPARTURE_REPORT — transmitted at mission start
2. POSITION_REPORT — transmitted every 15 minutes en route
3. THIRTY_MIN_ADVISORY — transmitted 30 minutes before drop zone
4. REQUEST_DZ_STATUS — request drop zone conditions from Ground Personnel
5. REQUEST_AIRSPACE_CLEARANCE — request clearance from Air Traffic Management
6. TEN_MIN_ADVISORY — transmitted 10 minutes before drop zone
7. CONFIRM_GO_NOGO — confirm final go/no-go with Operations Center
8. PAYLOAD_AWAY — transmitted immediately after airdrop execution
9. POST_DROP_ASSESSMENT — transmitted within 5 minutes of drop
10. MISSION_COMPLETE — transmitted upon departure from drop zone area
