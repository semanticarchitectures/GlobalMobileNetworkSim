classdef PolicyDecisionPoint < handle
    % PolicyDecisionPoint  Evaluates access control queries against a policy.
    %
    % The policy is loaded from a JSON file at construction time. Rules are
    % evaluated in order; the first matching rule wins. Supports '*' wildcard
    % in the messageType field of a rule.
    %
    % Policy JSON schema (§6.3):
    %   enclaves    — array of {enclaveId, cacheTtlSec, failPolicy}
    %   trustAnchors — array of {trustAnchorId, nodeId, certificateValidityPeriodSec}
    %   rules       — array of {enclave, role, messageType, decision}
    %
    % Requirements: 20.1, 20.3, 20.5, 22.1, 22.2, 22.5

    properties (Access = private)
        policy          % struct decoded from policy JSON
        enclaveMap      % containers.Map: enclaveId → enclave struct
    end

    methods (Access = public)

        % ------------------------------------------------------------------
        % Constructor
        % ------------------------------------------------------------------

        function obj = PolicyDecisionPoint(policyFilePath)
            % PolicyDecisionPoint  Load and validate a policy JSON file.
            %
            %   pdp = icam.PolicyDecisionPoint(policyFilePath)
            %
            %   Throws netsim:icam:policyJsonError on JSON parse failure.
            %
            % Requirements: 20.1

            try
                rawText = fileread(policyFilePath);
                obj.policy = jsondecode(rawText);
            catch ME
                error('netsim:icam:policyJsonError', ...
                    'Policy file: %s — %s', policyFilePath, ME.message);
            end

            % Build enclave lookup map
            obj.enclaveMap = containers.Map('KeyType', 'char', 'ValueType', 'any');
            if isfield(obj.policy, 'enclaves') && ~isempty(obj.policy.enclaves)
                enclaves = obj.policy.enclaves;
                % jsondecode returns struct array or single struct
                if isstruct(enclaves)
                    n = numel(enclaves);
                    for k = 1:n
                        enc = enclaves(k);
                        obj.enclaveMap(char(enc.enclaveId)) = enc;
                    end
                end
            end
        end

        % ------------------------------------------------------------------
        % Public methods
        % ------------------------------------------------------------------

        function result = evaluate(obj, requestingEntityId, targetEntityId, ...
                messageType, enclaveId, simTimeSec, entityRole) %#ok<INUSL>
            % evaluate  Apply policy rules and return a decision.
            %
            %   result = pdp.evaluate(requestingEntityId, targetEntityId, ...
            %                         messageType, enclaveId, simTimeSec)
            %   result = pdp.evaluate(requestingEntityId, targetEntityId, ...
            %                         messageType, enclaveId, simTimeSec, entityRole)
            %
            %   Returns struct {decision ('permit'|'deny'), reason (string)}.
            %   Rules are applied in order; first matching rule wins.
            %   '*' in a rule's enclave, role, or messageType field matches any value.
            %   Falls back to the enclave's failPolicy when no rule matches.
            %
            %   entityRole (optional) — the requesting entity's role in the
            %   relevant enclave. When omitted, role matching uses '*' (any).
            %
            % Requirements: 20.3, 20.5

            msgTypeStr  = char(messageType);
            enclaveStr  = char(enclaveId);

            % Resolve entity role (default '*' for backwards compatibility)
            if nargin < 7 || isempty(entityRole)
                roleStr = '*';
            else
                roleStr = char(entityRole);
            end

            % Walk rules in order
            if isfield(obj.policy, 'rules') && ~isempty(obj.policy.rules)
                rules = obj.policy.rules;
                n = numel(rules);
                for k = 1:n
                    rule = rules(k);

                    % Match enclave ('*' or exact)
                    ruleEnclave = char(rule.enclave);
                    if ~strcmp(ruleEnclave, '*') && ~strcmp(ruleEnclave, enclaveStr)
                        continue;
                    end

                    % Match role ('*' or exact)
                    if isfield(rule, 'role')
                        ruleRole = char(rule.role);
                        if ~strcmp(ruleRole, '*') && ~strcmp(roleStr, '*') && ...
                                ~strcmp(ruleRole, roleStr)
                            continue;
                        end
                    end

                    % Match messageType ('*' or exact)
                    ruleType = char(rule.messageType);
                    if ~strcmp(ruleType, '*') && ~strcmp(ruleType, msgTypeStr)
                        continue;
                    end

                    % Rule matched
                    result.decision = char(rule.decision);
                    result.reason   = sprintf('Matched rule %d (role=%s, enclave=%s, msgType=%s)', ...
                        k, ruleRole, ruleEnclave, ruleType);
                    return;
                end
            end

            % No rule matched — apply failPolicy
            result = obj.evaluateWithPdpUnreachable(enclaveId);
            result.reason = 'No matching rule; applied failPolicy';
        end

        function result = evaluateWithPdpUnreachable(obj, enclaveId)
            % evaluateWithPdpUnreachable  Return decision based on failPolicy.
            %
            %   result = pdp.evaluateWithPdpUnreachable(enclaveId)
            %
            %   Returns permit for fail-open, deny for fail-closed.
            %
            % Requirements: 20.5

            fp = obj.getFailPolicy(enclaveId);
            if strcmp(fp, 'open')
                result.decision = 'permit';
            else
                result.decision = 'deny';
            end
            result.reason = sprintf('PDP unreachable; failPolicy=%s', fp);
        end

        function ttl = getCacheTtl(obj, enclaveId)
            % getCacheTtl  Return cacheTtlSec for the enclave (default 300).
            %
            %   ttl = pdp.getCacheTtl(enclaveId)
            %
            % Requirements: 20.1

            key = char(enclaveId);
            if obj.enclaveMap.isKey(key)
                enc = obj.enclaveMap(key);
                ttl = enc.cacheTtlSec;
            else
                ttl = 300;
            end
        end

        function fp = getFailPolicy(obj, enclaveId)
            % getFailPolicy  Return 'open' or 'closed' for the enclave (default 'closed').
            %
            %   fp = pdp.getFailPolicy(enclaveId)
            %
            % Requirements: 20.5

            key = char(enclaveId);
            if obj.enclaveMap.isKey(key)
                enc = obj.enclaveMap(key);
                fp = char(enc.failPolicy);
            else
                fp = 'closed';
            end
        end

    end % methods (Access = public)

end % classdef
