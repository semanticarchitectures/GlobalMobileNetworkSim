classdef SecurityOracle < handle
    % security.SecurityOracle  Dynamic security event evaluator.
    %
    % Evaluates security-relevant events against an IntendedPolicy to classify
    % each outcome as conformant, violation, over-restriction, or unspecified.
    %
    % Tracks all evaluation results and provides conformance scoring.
    %
    % Requirements: R43, R45

    properties (SetAccess = private)
        % IntendedPolicy struct (from IntendedPolicyLoader.load)
        intendedPolicy

        % Struct array of all evaluation results
        %   Fields: eventId, classification, reason, simTimeSec, details
        results

        % Struct array of violation events with details
        violations

        % Struct array of events evaluated during degraded conditions
        degradedConditionOutcomes
    end

    properties (Access = private)
        % Counters for conformance score computation
        conformantCount     double = 0
        violationCount      double = 0
        overRestrictionCount double = 0
        unspecifiedCount     double = 0

        % Set of event types we evaluate
        evaluatedEventTypes
    end

    methods

        function obj = SecurityOracle(intendedPolicy)
            % SecurityOracle  Construct a SecurityOracle with a given IntendedPolicy.
            %
            %   oracle = security.SecurityOracle(intendedPolicy)
            %
            %   intendedPolicy — struct from security.IntendedPolicyLoader.load()
            %
            % Requirements: R43

            if nargin < 1 || isempty(intendedPolicy)
                error('netsim:security:invalidArgument', ...
                    'SecurityOracle requires a non-empty IntendedPolicy struct.');
            end

            obj.intendedPolicy = intendedPolicy;
            obj.results = struct('eventId', {}, 'classification', {}, ...
                'reason', {}, 'simTimeSec', {}, 'details', {});
            obj.violations = struct('entityId', {}, 'resourceId', {}, ...
                'enclave', {}, 'operation', {}, 'actualOutcome', {}, ...
                'intendedOutcome', {}, 'simTimeSec', {}, 'adversarialSource', {});
            obj.degradedConditionOutcomes = struct('entityId', {}, ...
                'operation', {}, 'outcome', {}, 'reason', {}, ...
                'degradedOnly', {}, 'simTimeSec', {});
            obj.evaluatedEventTypes = {'DATA_FETCH', 'DATA_QUERY', ...
                'AUTH_REQUEST', 'C2_MESSAGE_TX'};
        end

        function classification = evaluate(obj, event, simTimeSec)
            % evaluate  Classify a security-relevant event against IntendedPolicy.
            %
            %   classification = oracle.evaluate(event, simTimeSec)
            %
            %   event — struct with fields:
            %     type    — event type string
            %     id      — unique event identifier (uint64)
            %     payload — struct with security-relevant fields:
            %       role, classification, enclave, operation, outcome
            %       Optional: entityId, resourceId, adversarialSource,
            %                 degradedCondition
            %
            %   simTimeSec — simulation time in seconds
            %
            %   Returns one of: 'conformant', 'violation', 'over_restriction', 'unspecified'
            %
            % Requirements: R43

            % Extract event type as char
            eventType = char(event.type);

            % Check if this is a security-relevant event type
            if ~ismember(eventType, obj.evaluatedEventTypes)
                classification = 'unspecified';
                obj.unspecifiedCount = obj.unspecifiedCount + 1;
                obj.recordResult(event, classification, ...
                    'Event type not security-relevant', simTimeSec);
                return;
            end

            % Extract payload fields
            payload = event.payload;

            % Get role, classification, enclave, operation from payload
            role = obj.extractField(payload, 'role', '*');
            dataClassification = obj.extractField(payload, 'classification', '*');
            enclave = obj.extractField(payload, 'enclave', '*');
            operation = obj.extractField(payload, 'operation', '*');
            actualOutcome = obj.extractField(payload, 'outcome', '');

            % If no actual outcome recorded, mark as unspecified
            if isempty(actualOutcome)
                classification = 'unspecified';
                obj.unspecifiedCount = obj.unspecifiedCount + 1;
                obj.recordResult(event, classification, ...
                    'No outcome field in payload', simTimeSec);
                return;
            end

            % Evaluate intended outcome from policy
            intendedOutcome = security.IntendedPolicyLoader.evaluate(...
                obj.intendedPolicy, role, dataClassification, enclave, operation);

            % Classify the event
            classification = obj.classifyOutcome(actualOutcome, intendedOutcome);

            % Update counters
            switch classification
                case 'conformant'
                    obj.conformantCount = obj.conformantCount + 1;
                case 'violation'
                    obj.violationCount = obj.violationCount + 1;
                case 'over_restriction'
                    obj.overRestrictionCount = obj.overRestrictionCount + 1;
                otherwise
                    obj.unspecifiedCount = obj.unspecifiedCount + 1;
            end

            % Build reason string
            reason = sprintf('actual=%s, intended=%s', actualOutcome, intendedOutcome);

            % Record result
            obj.recordResult(event, classification, reason, simTimeSec);

            % Record violation details if applicable
            if strcmp(classification, 'violation')
                v.entityId = obj.extractField(payload, 'entityId', '');
                v.resourceId = obj.extractField(payload, 'resourceId', '');
                v.enclave = enclave;
                v.operation = operation;
                v.actualOutcome = actualOutcome;
                v.intendedOutcome = intendedOutcome;
                v.simTimeSec = simTimeSec;
                v.adversarialSource = obj.extractLogicalField(payload, 'adversarialSource', false);
                obj.violations(end+1) = v;
            end

            % Record degraded condition outcome if applicable
            if obj.extractLogicalField(payload, 'degradedCondition', false)
                d.entityId = obj.extractField(payload, 'entityId', '');
                d.operation = operation;
                d.outcome = actualOutcome;
                d.reason = 'degraded_condition';
                d.degradedOnly = true;
                d.simTimeSec = simTimeSec;
                obj.degradedConditionOutcomes(end+1) = d;
            end
        end

        function score = computeConformanceScore(obj)
            % computeConformanceScore  Compute policy conformance score.
            %
            %   score = oracle.computeConformanceScore()
            %
            %   Returns conformant / (conformant + violations + over_restrictions).
            %   Unspecified events are excluded from the denominator.
            %   Returns 1.0 if no evaluations have been performed.
            %
            % Requirements: R43

            denominator = obj.conformantCount + obj.violationCount + ...
                obj.overRestrictionCount;

            if denominator == 0
                score = 1.0;
                return;
            end

            score = obj.conformantCount / denominator;
        end

        function counts = getCounts(obj)
            % getCounts  Return evaluation counts as a struct.
            %
            %   counts = oracle.getCounts()

            counts.conformant = obj.conformantCount;
            counts.violations = obj.violationCount;
            counts.overRestrictions = obj.overRestrictionCount;
            counts.unspecified = obj.unspecifiedCount;
            counts.total = obj.conformantCount + obj.violationCount + ...
                obj.overRestrictionCount + obj.unspecifiedCount;
        end

    end

    methods (Access = private)

        function classification = classifyOutcome(~, actualOutcome, intendedOutcome)
            % classifyOutcome  Determine classification from actual vs intended.
            %
            %   If actual=permit and intended=permit → conformant
            %   If actual=deny and intended=deny → conformant
            %   If actual=permit and intended=deny → violation
            %   If actual=deny and intended=permit → over_restriction
            %   Otherwise → unspecified

            actual = lower(char(actualOutcome));
            intended = lower(char(intendedOutcome));

            if strcmp(actual, intended)
                classification = 'conformant';
            elseif strcmp(actual, 'permit') && strcmp(intended, 'deny')
                classification = 'violation';
            elseif strcmp(actual, 'deny') && strcmp(intended, 'permit')
                classification = 'over_restriction';
            else
                classification = 'unspecified';
            end
        end

        function recordResult(obj, event, classification, reason, simTimeSec)
            % recordResult  Append an evaluation result to the results array.

            r.eventId = event.id;
            r.classification = classification;
            r.reason = reason;
            r.simTimeSec = simTimeSec;
            r.details = struct('type', char(event.type));
            obj.results(end+1) = r;
        end

        function val = extractField(~, s, fieldName, defaultVal)
            % extractField  Safely extract a char field from a struct.
            if isfield(s, fieldName) && ~isempty(s.(fieldName))
                val = char(s.(fieldName));
            else
                val = defaultVal;
            end
        end

        function val = extractLogicalField(~, s, fieldName, defaultVal)
            % extractLogicalField  Safely extract a logical field from a struct.
            if isfield(s, fieldName) && ~isempty(s.(fieldName))
                val = logical(s.(fieldName));
            else
                val = defaultVal;
            end
        end

    end

end
