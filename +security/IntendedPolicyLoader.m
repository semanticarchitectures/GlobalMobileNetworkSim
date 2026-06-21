classdef IntendedPolicyLoader
    % IntendedPolicyLoader  Load, save, and evaluate IntendedPolicy specifications.
    %
    % The IntendedPolicy is a JSON file that maps (role, classification, enclave,
    % operation) combinations to expected outcomes ('permit' or 'deny'). It is
    % used by the SecurityOracle and PolicyAnalyzer to compare implemented
    % behaviour against design intent.
    %
    % JSON Schema:
    %   description    — string describing the policy
    %   defaultOutcome — 'permit' or 'deny' (fallback when no rule matches)
    %   rules          — array of {role, classification, enclave, operation, outcome}
    %                    where any field may be '*' (wildcard)
    %
    % Requirements: R42

    methods (Static)

        function policy = load(filePath)
            % load  Read and parse an IntendedPolicy JSON file.
            %
            %   policy = security.IntendedPolicyLoader.load(filePath)
            %
            %   Returns a struct with fields:
            %     description    (char)
            %     defaultOutcome (char: 'permit' | 'deny')
            %     rules          (struct array with role, classification,
            %                     enclave, operation, outcome)
            %
            %   Throws netsim:security:policyLoadError on missing or
            %   malformed file.
            %
            % Requirements: R42

            % Validate file existence
            if ~isfile(filePath)
                error('netsim:security:policyLoadError', ...
                    'IntendedPolicy file not found: %s', filePath);
            end

            % Read and decode JSON
            try
                rawText = fileread(filePath);
                policy = jsondecode(rawText);
            catch ME
                error('netsim:security:policyLoadError', ...
                    'Failed to parse IntendedPolicy file "%s": %s', ...
                    filePath, ME.message);
            end

            % Validate required top-level fields
            if ~isfield(policy, 'description') || ~ischar(policy.description)
                error('netsim:security:policyLoadError', ...
                    'IntendedPolicy file "%s" missing or invalid "description" field.', ...
                    filePath);
            end
            if ~isfield(policy, 'defaultOutcome')
                error('netsim:security:policyLoadError', ...
                    'IntendedPolicy file "%s" missing "defaultOutcome" field.', ...
                    filePath);
            end
            policy.defaultOutcome = char(policy.defaultOutcome);
            if ~ismember(policy.defaultOutcome, {'permit', 'deny'})
                error('netsim:security:policyLoadError', ...
                    'IntendedPolicy file "%s": defaultOutcome must be ''permit'' or ''deny'', got ''%s''.', ...
                    filePath, policy.defaultOutcome);
            end
            if ~isfield(policy, 'rules')
                error('netsim:security:policyLoadError', ...
                    'IntendedPolicy file "%s" missing "rules" field.', ...
                    filePath);
            end

            % Normalize rules to struct array
            if isempty(policy.rules)
                policy.rules = struct('role', {}, 'classification', {}, ...
                    'enclave', {}, 'operation', {}, 'outcome', {});
            else
                % Ensure char for all string fields in rules
                nRules = numel(policy.rules);
                for k = 1:nRules
                    policy.rules(k).role = char(policy.rules(k).role);
                    policy.rules(k).classification = char(policy.rules(k).classification);
                    policy.rules(k).enclave = char(policy.rules(k).enclave);
                    policy.rules(k).operation = char(policy.rules(k).operation);
                    policy.rules(k).outcome = char(policy.rules(k).outcome);
                    % Validate outcome
                    if ~ismember(policy.rules(k).outcome, {'permit', 'deny'})
                        error('netsim:security:policyLoadError', ...
                            'IntendedPolicy file "%s": rule %d has invalid outcome ''%s''.', ...
                            filePath, k, policy.rules(k).outcome);
                    end
                end
            end
        end

        function save(policy, filePath)
            % save  Write an IntendedPolicy struct to a JSON file.
            %
            %   security.IntendedPolicyLoader.save(policy, filePath)
            %
            %   Writes the policy struct as formatted JSON. The output is
            %   compatible with the load() method for round-trip fidelity.
            %
            % Requirements: R42

            jsonText = jsonencode(policy, 'PrettyPrint', true);
            fid = fopen(filePath, 'w');
            if fid == -1
                error('netsim:security:policyLoadError', ...
                    'Cannot open file for writing: %s', filePath);
            end
            cleanupObj = onCleanup(@() fclose(fid));
            fprintf(fid, '%s', jsonText);
        end

        function outcome = evaluate(policy, role, classification, enclave, operation)
            % evaluate  Determine the intended outcome for a given access request.
            %
            %   outcome = security.IntendedPolicyLoader.evaluate(policy, ...
            %       role, classification, enclave, operation)
            %
            %   Searches for the most specific matching rule using
            %   specificity scoring. Exact matches rank higher than
            %   wildcards. If no rule matches, returns policy.defaultOutcome.
            %
            %   Returns 'permit' or 'deny'.
            %
            % Requirements: R42

            role = char(role);
            classification = char(classification);
            enclave = char(enclave);
            operation = char(operation);

            bestScore = -1;
            bestOutcome = '';

            nRules = numel(policy.rules);
            for k = 1:nRules
                rule = policy.rules(k);

                % Check if the rule matches
                if ~security.IntendedPolicyLoader.fieldMatches(rule.role, role)
                    continue;
                end
                if ~security.IntendedPolicyLoader.fieldMatches(rule.classification, classification)
                    continue;
                end
                if ~security.IntendedPolicyLoader.fieldMatches(rule.enclave, enclave)
                    continue;
                end
                if ~security.IntendedPolicyLoader.fieldMatches(rule.operation, operation)
                    continue;
                end

                % Compute specificity score: each exact field = 1, wildcard = 0
                score = 0;
                if ~strcmp(rule.role, '*'), score = score + 1; end
                if ~strcmp(rule.classification, '*'), score = score + 1; end
                if ~strcmp(rule.enclave, '*'), score = score + 1; end
                if ~strcmp(rule.operation, '*'), score = score + 1; end

                if score > bestScore
                    bestScore = score;
                    bestOutcome = rule.outcome;
                end
            end

            if bestScore >= 0
                outcome = bestOutcome;
            else
                outcome = char(policy.defaultOutcome);
            end
        end

    end % methods (Static)

    methods (Static, Access = private)

        function tf = fieldMatches(ruleValue, inputValue)
            % fieldMatches  Check if a rule field matches an input value.
            %   Supports '*' wildcard matching any value.
            tf = strcmp(ruleValue, '*') || strcmp(ruleValue, inputValue);
        end

    end % methods (Static, Access = private)

end % classdef
