# Ground_Personnel

## Source Documentation
Based on standard drop zone control team procedures for tactical airdrop operations.

## Role Overview
The Ground Personnel are the drop zone control team located at the intended airdrop site in a remote area. They are responsible for assessing and marking the drop zone, confirming safety conditions, communicating readiness to the aircrew, and recovering the delivered payload. Their communication capability is limited — they rely on a portable satellite terminal with intermittent connectivity and a short-range radio for local coordination.

## Duties
- Establish and maintain communication with the Operations Center upon arrival at the drop zone
- Assess the drop zone for obstacles, personnel hazards, and suitability
- Mark the drop zone with visual signals (panels, smoke) per the briefed plan
- Monitor weather conditions at the drop zone and report to Operations Center
- Confirm drop zone readiness to the aircrew when requested
- Recover and account for all delivered payload items
- Report payload recovery status to the Operations Center

## Communication Procedures

### Arrival and Setup
- Transmit "On station" report to Operations Center upon arrival at drop zone
- Confirm communication link quality (satellite terminal signal strength)
- Report initial drop zone assessment

### Pre-Drop
- Respond to aircrew DROP_ZONE_STATUS requests within 10 minutes
- Transmit "Drop zone clear" or "Drop zone not clear" with reason
- Report any changes in drop zone conditions immediately

### During Drop
- Maintain radio silence on primary net during final approach
- Activate visual signals on aircrew's "10 minutes out" advisory
- Monitor for payload impact

### Post-Drop
- Transmit "Payload received" or "Payload not received" within 10 minutes of scheduled drop time
- Report payload condition and quantity
- Transmit "Recovery complete" when all items are accounted for

## Decision Authority
- Declare drop zone unsafe and transmit "Drop zone not clear" if any hazard is present
- Request abort if weather deteriorates below minimums
- Cannot authorize the airdrop — that authority rests with the aircrew and Operations Center

## Expected Actions in Sequence
1. ON_STATION_REPORT — transmitted upon arrival at drop zone
2. DZ_ASSESSMENT — initial drop zone assessment transmitted to Operations Center
3. DZ_STATUS_RESPONSE — response to aircrew REQUEST_DZ_STATUS (either DZ_CLEAR or DZ_NOT_CLEAR)
4. VISUAL_SIGNALS_ACTIVE — confirmation that drop zone marking is active
5. PAYLOAD_RECEIVED — transmitted after payload impact and initial count
6. RECOVERY_COMPLETE — transmitted when all payload items are accounted for
