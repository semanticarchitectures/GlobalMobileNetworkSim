classdef AdversarialAgentRegistry < handle
    % security.AdversarialAgentRegistry  Load and schedule adversarial attack events.
    %
    % Scans a scenario struct for entities with "adversarial": true and
    % associated attackPatterns. Schedules attack events into the DES
    % EventCalendar at specified attempt times.
    %
    % Supported attack types:
    %   'unauthorized_data_access'    — access data above entity's clearance
    %   'cross_enclave_access'        — access resources in unauthorized enclave
    %   'expired_credential_access'   — use expired credentials after outage
    %   'pdp_outage_exploitation'     — exploit PDP outage for fail-open access
    %
    % Adversarial agents are excluded from FidelityEvaluator; evaluated only
    % by SecurityOracle with adversarialSource: true flag.
    %
    % Requirements: R46

    properties (SetAccess = private)
        % Struct array of adversarial agent definitions
        %   Fields: id, nodeId, attackPatterns
        adversarialAgents

        % Struct array of scheduled attacks
        %   Fields: agentId, attackType, targetClassification, targetEnclave,
        %           operation, attemptTimeSec, eventId, details
        attackSchedule

        % Supported attack type constants
        supportedAttackTypes
    end

    methods

        function obj = AdversarialAgentRegistry(scenario)
            % AdversarialAgentRegistry  Construct registry from scenario.
            %
            %   registry = security.AdversarialAgentRegistry(scenario)
            %
            %   scenario — struct from ScenarioLoader.load() with entities
            %              that may have adversarial=true and attackPatterns.
            %
            % Requirements: R46

            obj.supportedAttackTypes = {'unauthorized_data_access', ...
                'cross_enclave_access', 'expired_credential_access', ...
                'pdp_outage_exploitation'};

            obj.adversarialAgents = struct('id', {}, 'nodeId', {}, ...
                'attackPatterns', {});
            obj.attackSchedule = struct('agentId', {}, 'attackType', {}, ...
                'targetClassification', {}, 'targetEnclave', {}, ...
                'operation', {}, 'attemptTimeSec', {}, 'eventId', {}, ...
                'details', {});

            % Scan scenario for adversarial entities
            if nargin < 1 || isempty(scenario)
                return;
            end

            obj.scanScenario(scenario);
        end

        function scheduleAttacks(obj, eventCalendar)
            % scheduleAttacks  Schedule attack events into the EventCalendar.
            %
            %   registry.scheduleAttacks(eventCalendar)
            %
            %   Creates DES events for each attack pattern at the specified
            %   attemptTimeSec. Each event has adversarialSource=true in payload.
            %
            % Requirements: R46

            if isempty(obj.adversarialAgents)
                return;
            end

            eventIdBase = uint64(200000);
            scheduleIdx = 0;

            for iAgent = 1:numel(obj.adversarialAgents)
                agent = obj.adversarialAgents(iAgent);
                patterns = agent.attackPatterns;

                for iPat = 1:numel(patterns)
                    pattern = patterns(iPat);
                    scheduleIdx = scheduleIdx + 1;
                    eventId = eventIdBase + uint64(scheduleIdx);

                    % Build event based on attack type
                    attackType = char(pattern.attackType);

                    % Validate attack type
                    if ~ismember(attackType, obj.supportedAttackTypes)
                        warning('netsim:security:unsupportedAttackType', ...
                            'Unsupported attack type: %s (agent %s). Skipping.', ...
                            attackType, agent.id);
                        continue;
                    end

                    % Extract common fields with defaults
                    attemptTime = 0;
                    if isfield(pattern, 'attemptTimeSec')
                        attemptTime = double(pattern.attemptTimeSec);
                    end
                    targetCls = '';
                    if isfield(pattern, 'targetClassification')
                        targetCls = char(pattern.targetClassification);
                    end
                    targetEnclave = '';
                    if isfield(pattern, 'targetEnclaveId')
                        targetEnclave = char(pattern.targetEnclaveId);
                    end
                    operation = 'read';
                    if isfield(pattern, 'operation')
                        operation = char(pattern.operation);
                    end

                    % Build DES event
                    evt.time = attemptTime;
                    evt.type = obj.selectEventType(attackType, operation);
                    evt.id = eventId;
                    evt.payload.role = obj.extractAgentRole(agent, pattern);
                    evt.payload.classification = targetCls;
                    evt.payload.enclave = targetEnclave;
                    evt.payload.operation = operation;
                    evt.payload.entityId = agent.id;
                    evt.payload.adversarialSource = true;
                    evt.payload.attackType = attackType;

                    % Add attack-type-specific payload fields
                    evt.payload = obj.addAttackSpecificPayload(evt.payload, pattern, attackType);

                    % Schedule into EventCalendar
                    eventCalendar.schedule(evt);

                    % Record in attack schedule
                    sched.agentId = agent.id;
                    sched.attackType = attackType;
                    sched.targetClassification = targetCls;
                    sched.targetEnclave = targetEnclave;
                    sched.operation = operation;
                    sched.attemptTimeSec = attemptTime;
                    sched.eventId = eventId;
                    sched.details = pattern;
                    obj.attackSchedule(end+1) = sched;
                end
            end
        end

        function ids = getAdversarialEntityIds(obj)
            % getAdversarialEntityIds  Return cell array of adversarial entity IDs.
            %
            %   ids = registry.getAdversarialEntityIds()
            %
            %   Used by FidelityEvaluator to exclude adversarial agents.

            ids = {};
            for k = 1:numel(obj.adversarialAgents)
                ids{end+1} = obj.adversarialAgents(k).id; %#ok<AGROW>
            end
        end

    end

    methods (Access = private)

        function scanScenario(obj, scenario)
            % scanScenario  Find adversarial entities in scenario.

            if ~isfield(scenario, 'entities') || isempty(scenario.entities)
                return;
            end

            ents = scenario.entities;
            for k = 1:numel(ents)
                entity = ents(k);

                % Check if marked as adversarial
                isAdversarial = false;
                if isfield(entity, 'adversarial')
                    isAdversarial = logical(entity.adversarial);
                end

                if ~isAdversarial
                    continue;
                end

                % Must have attackPatterns
                if ~isfield(entity, 'attackPatterns') || isempty(entity.attackPatterns)
                    continue;
                end

                % Build adversarial agent entry
                a.id = '';
                if isfield(entity, 'id')
                    a.id = char(entity.id);
                end
                a.nodeId = '';
                if isfield(entity, 'nodeId')
                    a.nodeId = char(entity.nodeId);
                end
                a.attackPatterns = entity.attackPatterns;

                obj.adversarialAgents(end+1) = a;
            end
        end

        function eventType = selectEventType(~, attackType, operation)
            % selectEventType  Choose DES event type based on attack type.

            switch attackType
                case {'unauthorized_data_access', 'cross_enclave_access', ...
                        'expired_credential_access'}
                    switch lower(operation)
                        case 'read'
                            eventType = "DATA_FETCH";
                        case 'write'
                            eventType = "DATA_QUERY";
                        otherwise
                            eventType = "DATA_FETCH";
                    end
                case 'pdp_outage_exploitation'
                    eventType = "DATA_FETCH";
                otherwise
                    eventType = "C2_MESSAGE_TX";
            end
        end

        function role = extractAgentRole(~, agent, pattern)
            % extractAgentRole  Extract the role for the adversarial agent.
            %   If pattern specifies a role, use it; otherwise use agent default.

            role = 'adversary';
            if isfield(pattern, 'role')
                role = char(pattern.role);
            elseif isfield(agent, 'role')
                role = char(agent.role);
            end
        end

        function payload = addAttackSpecificPayload(~, payload, pattern, attackType)
            % addAttackSpecificPayload  Add attack-type-specific fields.

            switch attackType
                case 'pdp_outage_exploitation'
                    if isfield(pattern, 'targetPdpNodeId')
                        payload.targetPdpNodeId = char(pattern.targetPdpNodeId);
                    end
                    if isfield(pattern, 'outageDurationSec')
                        payload.outageDurationSec = double(pattern.outageDurationSec);
                    end
                    if isfield(pattern, 'dataFetchAttemptOffsetSec')
                        payload.dataFetchAttemptOffsetSec = double(pattern.dataFetchAttemptOffsetSec);
                    end
                case 'expired_credential_access'
                    payload.expiredCredential = true;
                case 'cross_enclave_access'
                    payload.crossEnclaveAttempt = true;
                otherwise
                    % No extra fields needed
            end
        end

    end

end
