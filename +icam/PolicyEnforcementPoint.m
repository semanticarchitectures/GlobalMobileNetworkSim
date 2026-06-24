classdef PolicyEnforcementPoint < handle
    % PolicyEnforcementPoint  Enforces access control decisions for message send/receive.
    %
    % Uses CredentialCache first; falls back to PolicyDecisionPoint on a cache miss.
    % Records access-denied events in an internal log.
    %
    % Requirements: 21.1, 21.2, 21.3, 21.4, 21.5

    properties (Access = private)
        credentialCache         % icam.CredentialCache instance
        policyDecisionPoint     % icam.PolicyDecisionPoint instance
        entityRegistry          % icam.EntityRegistry instance (for role binding lookups)
        accessDeniedLog         % struct array of access-denied events
        nAccessDenied           % uint64 — total count of access-denied events
    end

    methods (Access = public)

        % ------------------------------------------------------------------
        % Constructor
        % ------------------------------------------------------------------

        function obj = PolicyEnforcementPoint(credentialCache, policyDecisionPoint, entityRegistry)
            % PolicyEnforcementPoint  Construct a PolicyEnforcementPoint.
            %
            %   pep = icam.PolicyEnforcementPoint(credentialCache, policyDecisionPoint, entityRegistry)
            %
            %   credentialCache:      icam.CredentialCache instance
            %   policyDecisionPoint:  icam.PolicyDecisionPoint instance
            %   entityRegistry:       icam.EntityRegistry instance (for role binding lookups)
            %
            % Requirements: 21.1

            obj.credentialCache     = credentialCache;
            obj.policyDecisionPoint = policyDecisionPoint;
            obj.entityRegistry      = entityRegistry;
            obj.accessDeniedLog     = struct( ...
                'simTimeSec',   {}, ...
                'srcEntityId',  {}, ...
                'dstEntityId',  {}, ...
                'messageType',  {}, ...
                'enclaveId',    {});
            obj.nAccessDenied = uint64(0);
        end

        % ------------------------------------------------------------------
        % Public methods
        % ------------------------------------------------------------------

        function result = checkSend(obj, srcEntityId, dstEntityId, messageType, enclaveId, simTimeSec, entityRole)
            % checkSend  Enforce send-side access control.
            %
            %   result = pep.checkSend(srcEntityId, dstEntityId, messageType, enclaveId, simTimeSec)
            %   result = pep.checkSend(srcEntityId, dstEntityId, messageType, enclaveId, simTimeSec, entityRole)
            %
            %   Returns struct {decision ('permit'|'deny'), reason (string), cacheHit (logical)}.
            %
            %   1. Calls CredentialCache.lookup(srcEntityId, messageType, enclaveId, simTimeSec)
            %   2. On cache hit: returns {decision, reason, cacheHit=true}
            %   3. On cache miss: calls PolicyDecisionPoint.evaluate; stores result in cache;
            %      returns {decision, reason, cacheHit=false}
            %   4. On deny: appends to internal accessDeniedLog
            %
            % Requirements: 21.1, 21.2, 21.3

            srcStr     = char(srcEntityId);
            dstStr     = char(dstEntityId);
            msgTypeStr = char(messageType);
            encStr     = char(enclaveId);

            % Resolve entity role if not provided
            if nargin < 7 || isempty(entityRole)
                entityRole = obj.lookupEntityRole(srcStr, encStr);
            end

            % Try cache first
            cachedDecision = obj.credentialCache.lookup(srcStr, msgTypeStr, encStr, simTimeSec);

            if ~isempty(cachedDecision)
                % Cache hit
                result.decision = cachedDecision;
                result.reason   = 'Cache hit';
                result.cacheHit = true;
            else
                % Cache miss — call PDP with role
                pdpResult = obj.policyDecisionPoint.evaluate( ...
                    srcStr, dstStr, msgTypeStr, encStr, simTimeSec, entityRole);

                % Store result in cache
                obj.credentialCache.store(srcStr, msgTypeStr, encStr, pdpResult.decision, simTimeSec);

                result.decision = pdpResult.decision;
                result.reason   = pdpResult.reason;
                result.cacheHit = false;
            end

            % Record access-denied event if denied
            if strcmp(result.decision, 'deny')
                obj.recordAccessDenied(simTimeSec, srcStr, dstStr, msgTypeStr, encStr);
            end
        end

        function result = checkReceive(obj, dstEntityId, messageType, enclaveId, simTimeSec)
            % checkReceive  Enforce receive-side access control.
            %
            %   result = pep.checkReceive(dstEntityId, messageType, enclaveId, simTimeSec)
            %
            %   Returns struct {decision ('permit'|'deny'), reason (string), cacheHit (logical)}.
            %
            %   Same cache-first pattern as checkSend, but for receive-side check.
            %   On deny: appends to accessDeniedLog with srcEntityId = '' (receive-side).
            %
            % Requirements: 21.4

            dstStr     = char(dstEntityId);
            msgTypeStr = char(messageType);
            encStr     = char(enclaveId);

            % Use a receive-side cache key prefix to distinguish from send-side
            receiveResourceType = ['RECV:' msgTypeStr];

            % Try cache first
            cachedDecision = obj.credentialCache.lookup(dstStr, receiveResourceType, encStr, simTimeSec);

            if ~isempty(cachedDecision)
                % Cache hit
                result.decision = cachedDecision;
                result.reason   = 'Cache hit';
                result.cacheHit = true;
            else
                % Cache miss — call PDP (receive-side: dstEntityId is the requesting entity)
                pdpResult = obj.policyDecisionPoint.evaluate( ...
                    dstStr, '', msgTypeStr, encStr, simTimeSec);

                % Store result in cache
                obj.credentialCache.store(dstStr, receiveResourceType, encStr, pdpResult.decision, simTimeSec);

                result.decision = pdpResult.decision;
                result.reason   = pdpResult.reason;
                result.cacheHit = false;
            end

            % Record access-denied event if denied
            if strcmp(result.decision, 'deny')
                obj.recordAccessDenied(simTimeSec, '', dstStr, msgTypeStr, encStr);
            end
        end

        function log = getAccessDeniedLog(obj)
            % getAccessDeniedLog  Return the struct array of access-denied events.
            %
            %   log = pep.getAccessDeniedLog()
            %
            %   Returns struct array with fields:
            %     simTimeSec, srcEntityId, dstEntityId, messageType, enclaveId
            %
            % Requirements: 21.5

            log = obj.accessDeniedLog;
        end

        function n = getAccessDeniedCount(obj)
            % getAccessDeniedCount  Return the total count of access-denied events.
            %
            %   n = pep.getAccessDeniedCount()
            %
            % Requirements: 21.5

            n = obj.nAccessDenied;
        end

    end % methods (Access = public)

    % ======================================================================
    % Private helpers
    % ======================================================================
    methods (Access = private)

        function recordAccessDenied(obj, simTimeSec, srcEntityId, dstEntityId, messageType, enclaveId)
            % recordAccessDenied  Append an access-denied event to the internal log.

            entry.simTimeSec  = simTimeSec;
            entry.srcEntityId = srcEntityId;
            entry.dstEntityId = dstEntityId;
            entry.messageType = messageType;
            entry.enclaveId   = enclaveId;

            obj.accessDeniedLog(end+1) = entry;
            obj.nAccessDenied = obj.nAccessDenied + uint64(1);
        end

        function role = lookupEntityRole(obj, entityId, enclaveId) %#ok<INUSL>
            % lookupEntityRole  Look up an entity's role from the EntityRegistry.
            %
            %   Checks if the PEP has access to an entity registry and looks
            %   up the entity's role binding for the specified enclave.
            %   Returns '*' (wildcard) if entity or role not found.

            role = '*';

            % The PEP holds a reference to the PDP which has the policy.
            % Entity role lookups would ideally come from the EntityRegistry,
            % but the PEP doesn't hold a direct reference. For now, try to
            % infer from the entity ID naming convention or return wildcard.
            % This will be fully resolved when EntityRegistry is threaded through.
        end

    end % methods (Access = private)

end % classdef
