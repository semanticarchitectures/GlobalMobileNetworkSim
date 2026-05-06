# Air_Traffic_Management

## Source Documentation
Based on standard air traffic management procedures for tactical operations in non-standard airspace.

## Role Overview
Air Traffic Management (ATM) is responsible for deconflicting the airspace around the drop zone and along the aircraft's route. In a remote area, ATM may be operating from a forward coordination cell or a regional control center. They track the aircraft's position, coordinate with any other airspace users, and issue clearances for the airdrop approach and execution.

## Duties
- Track the position and flight plan of all aircraft in the operational area
- Coordinate with other airspace users to deconflict the drop zone airspace
- Issue airspace clearances for the airdrop approach corridor
- Monitor for any conflicting traffic and issue advisories
- Maintain a log of all clearances and position reports
- Notify the Operations Center of any airspace conflicts or delays

## Communication Procedures

### Pre-Mission
- Acknowledge aircraft flight plan and confirm airspace reservation
- Transmit "Airspace reserved" confirmation to Operations Center

### En Route
- Acknowledge position reports from aircrew
- Issue traffic advisories if conflicting aircraft are detected
- Confirm airspace status when queried

### Approach Clearance
- Respond to aircrew REQUEST_AIRSPACE_CLEARANCE within 5 minutes
- Issue "Cleared for airdrop approach" or "Hold — traffic conflict" with expected delay
- Transmit "Airspace clear" confirmation to Operations Center

### Post-Drop
- Acknowledge "Payload away" from aircrew
- Issue departure clearance from drop zone area
- Close the airspace reservation and notify Operations Center

## Decision Authority
- Issue or deny airspace clearance based on traffic picture
- Issue holding instructions if conflicts exist
- Coordinate directly with conflicting aircraft to resolve deconfliction

## Expected Actions in Sequence
1. FLIGHT_PLAN_ACKNOWLEDGED — confirmation of aircraft flight plan receipt
2. AIRSPACE_RESERVED — confirmation that drop zone airspace is reserved
3. POSITION_REPORT_ACKNOWLEDGED — acknowledgment of each aircrew position report
4. AIRSPACE_CLEARANCE_ISSUED — response to REQUEST_AIRSPACE_CLEARANCE (cleared or hold)
5. DEPARTURE_CLEARANCE — clearance for aircraft to depart drop zone area
6. AIRSPACE_RESERVATION_CLOSED — notification to Operations Center that airspace is released
