classdef ICAMController < handle
    % ICAMController  Top-level coordinator for the ICAM layer.
    %
    % Wired into SimController as an optional property. Holds references to
    % all ICAM subsystems and dispatches ICAM-related events from the EventCalendar.
    %
    % Requirements: 17.1, 18.3, 18.4, 18.5, 19.1, 19.2, 19.5, 20.1, 20.6,
    %               21.1, 21.5, 23.6, 24.1, 24.5

    properties (Access = public)
        entityRegistry      % icam.EntityRegistry instance
        credentialStore     % icam.CredentialStore instance
        authManager         % icam.AuthenticationManager instance
        pdp                 % icam.PolicyDecisionPoint instance
        credentialCache     % icam.CredentialCache instance
        pep                 % icam.PolicyEnforcementPoint instance
        eventCalendar       % sim.EventCalendar reference
    end

    properties (Access = private)
        % Auth exchange tracking
        nAuthTotal          % uint64
        nAuthSuccessful     % uint64
        nAuthFailed         % uint64
        nAuthTimedOut       % uint64

        % Scenario reference for entity role lookups
        scenario            % struct (stored on initialize)

        % Certificate renewal tracking
        nCertRenewalsTotal      % uint64
        nCertRenewalsSuccessful % uint64
        nCertRenewalsFailed     % uint64

        % Next event id counter (for scheduling events)
        nextEventId         % uint64
    end

    methods (Access = public)

        % ------------------------------------------------------------------
        % Constructor
        % ------------------------------------------------------------------

        function obj = ICAMController()
            % ICAMController  Construct an empty ICAMController.
            %
            %   ic = icam.ICAMController()
            %
            %   All subsystems are null until initialize() is called.
            %
            % Requirements: 21.1

            obj.entityRegistry  = [];
            obj.credentialStore = [];
            obj.authManager     = [];
            obj.pdp             = [];
            obj.credentialCache = [];
            obj.pep             = [];
            obj.eventCalendar   = [];

            obj.nAuthTotal              = uint64(0);
            obj.nAuthSuccessful         = uint64(0);
            obj.nAuthFailed             = uint64(0);
            obj.nAuthTimedOut           = uint64(0);
            obj.nCertRenewalsTotal      = uint64(0);
            obj.nCertRenewalsSuccessful = uint64(0);
            obj.nCertRenewalsFailed     = uint64(0);
            obj.nextEventId             = uint64(1);
        end

        % ------------------------------------------------------------------
        % initialize
        % ------------------------------------------------------------------

        function initialize(obj, scenario, nodeRegistry, eventCalendar)
            % initialize  Construct all ICAM subsystems from the scenario.
            %
            %   ic.initialize(scenario, nodeRegistry, eventCalendar)
            %
            %   - If scenario has 'entities' field: construct EntityRegistry
            %   - If scenario has 'policyDefinitionFile' field: construct PDP
            %     from that file; otherwise create a default permissive PDP
            %   - Build ttlConfigMap from PDP enclave definitions
            %   - Construct CredentialCache, AuthenticationManager, PEP
            %   - Issue initial certificates for all entities
            %   - Store eventCalendar reference
            %
            % Requirements: 17.1, 18.1, 19.1, 20.1, 21.1, 23.1

            obj.eventCalendar = eventCalendar;
            obj.scenario = scenario;  % Store for entity role lookups

            % ---- EntityRegistry ----
            if isfield(scenario, 'entities') && ~isempty(scenario.entities)
                obj.entityRegistry = icam.EntityRegistry(scenario.entities, nodeRegistry);
            else
                % Empty registry
                obj.entityRegistry = icam.EntityRegistry([], nodeRegistry);
            end

            % ---- PolicyDecisionPoint ----
            if isfield(scenario, 'policyDefinitionFile') && ...
                    ~isempty(scenario.policyDefinitionFile)
                policyFilePath = char(scenario.policyDefinitionFile);

                % Resolve path relative to scenario file if needed
                if isfield(scenario, 'scenarioFilePath') && ...
                        ~isempty(scenario.scenarioFilePath) && ...
                        ~java.io.File(policyFilePath).isAbsolute()
                    scenarioDir = fileparts(char(scenario.scenarioFilePath));
                    policyFilePath = fullfile(scenarioDir, policyFilePath);
                end

                obj.pdp = icam.PolicyDecisionPoint(policyFilePath);
            else
                % Default permissive PDP (allow all) — write a temp policy file
                obj.pdp = obj.makeDefaultPermissivePdp(scenario);
            end

            % ---- CredentialCache ----
            ttlConfigMap = obj.buildTtlConfigMap(obj.pdp, scenario);
            obj.credentialCache = icam.CredentialCache(ttlConfigMap);

            % ---- AuthenticationManager ----
            obj.authManager = icam.AuthenticationManager();

            % ---- CredentialStore ----
            obj.credentialStore = icam.CredentialStore();

            % ---- PolicyEnforcementPoint ----
            obj.pep = icam.PolicyEnforcementPoint( ...
                obj.credentialCache, obj.pdp, obj.entityRegistry);

            % ---- Issue initial certificates for all entities ----
            obj.issueInitialCertificates(scenario);
        end

        % ------------------------------------------------------------------
        % checkSend
        % ------------------------------------------------------------------

        function decision = checkSend(obj, srcEntityId, dstEntityId, messageType, enclaveId, simTimeSec)
            % checkSend  Check whether a message send is permitted.
            %
            %   decision = ic.checkSend(srcEntityId, dstEntityId, messageType, enclaveId, simTimeSec)
            %
            %   Returns 'permit', 'deny', or 'pending'.
            %
            %   - If not authenticated: call authManager.initiateExchange and return 'pending'
            %   - Call pep.checkSend with entity role; return 'permit' or 'deny'
            %
            % Requirements: 19.1, 21.1, 21.5

            srcStr = char(srcEntityId);
            dstStr = char(dstEntityId);

            % Check authentication
            if ~obj.authManager.isAuthenticated(srcStr, dstStr)
                obj.nAuthTotal = obj.nAuthTotal + uint64(1);
                obj.authManager.initiateExchange(srcStr, dstStr, simTimeSec, obj.eventCalendar);
                decision = 'pending';
                return;
            end

            % Resolve entity role for RBAC
            entityRole = obj.resolveEntityRole(srcStr);

            % Enforce policy with role
            result = obj.pep.checkSend(srcStr, dstStr, char(messageType), char(enclaveId), simTimeSec, entityRole);
            decision = result.decision;
        end

        % ------------------------------------------------------------------
        % Event handlers
        % ------------------------------------------------------------------

        function handleAuthRequest(obj, event) %#ok<INUSD>
            % handleAuthRequest  No-op for now (auth is simulated).
            %
            %   ic.handleAuthRequest(event)
            %
            % Requirements: 19.2
        end

        function handleAuthResponse(obj, event)
            % handleAuthResponse  Record successful authentication.
            %
            %   ic.handleAuthResponse(event)
            %
            %   Calls authManager.recordSuccess(srcEntityId, dstEntityId, simTimeSec).
            %
            % Requirements: 19.3, 19.4

            srcEntityId = char(event.payload.srcEntityId);
            dstEntityId = char(event.payload.dstEntityId);
            simTimeSec  = event.time;

            obj.authManager.recordSuccess(srcEntityId, dstEntityId, simTimeSec);
            obj.nAuthSuccessful = obj.nAuthSuccessful + uint64(1);
        end

        function handleAuthTimeout(obj, event)
            % handleAuthTimeout  Record authentication timeout failure.
            %
            %   ic.handleAuthTimeout(event)
            %
            %   Calls authManager.recordFailure(srcEntityId, dstEntityId, 'timeout', simTimeSec, eventCalendar).
            %
            % Requirements: 19.5, 19.6

            srcEntityId = char(event.payload.srcEntityId);
            dstEntityId = char(event.payload.dstEntityId);
            simTimeSec  = event.time;

            obj.authManager.recordFailure(srcEntityId, dstEntityId, 'timeout', simTimeSec, obj.eventCalendar);
            obj.nAuthTimedOut = obj.nAuthTimedOut + uint64(1);
        end

        function handleCertRenewal(obj, event)
            % handleCertRenewal  Renew a certificate for an entity.
            %
            %   ic.handleCertRenewal(event)
            %
            %   Calls credentialStore.issueCertificate to renew.
            %
            % Requirements: 18.4, 18.5

            entityId    = char(event.payload.entityId);
            simTimeSec  = event.time;

            obj.nCertRenewalsTotal = obj.nCertRenewalsTotal + uint64(1);

            try
                % Retrieve existing cert to get trust anchor and role bindings
                cert = obj.credentialStore.getCertificate(entityId);
                trustAnchorId    = char(cert.issuer);
                roleBindings     = cert.roleBindings;
                validityPeriodSec = cert.expirySec - cert.issuedTimeSec;

                obj.credentialStore.issueCertificate( ...
                    entityId, trustAnchorId, roleBindings, validityPeriodSec, simTimeSec);

                obj.nCertRenewalsSuccessful = obj.nCertRenewalsSuccessful + uint64(1);
            catch
                obj.nCertRenewalsFailed = obj.nCertRenewalsFailed + uint64(1);
            end
        end

        % ------------------------------------------------------------------
        % checkExpiredCredentials
        % ------------------------------------------------------------------

        function checkExpiredCredentials(obj, simTimeSec)
            % checkExpiredCredentials  Check for expired credentials and schedule renewals.
            %
            %   ic.checkExpiredCredentials(simTimeSec)
            %
            %   Calls credentialStore.checkExpiry; schedules CERT_RENEWAL_REQUEST
            %   for each expired entity.
            %
            % Requirements: 18.3

            if isempty(obj.credentialStore)
                return;
            end

            expiredIds = obj.credentialStore.checkExpiry(simTimeSec);

            for k = 1:numel(expiredIds)
                entityId = expiredIds{k};

                % Try to get trust anchor from existing cert
                try
                    cert = obj.credentialStore.getCertificate(entityId);
                    trustAnchorId = char(cert.issuer);
                catch
                    trustAnchorId = '';
                end

                % Schedule CERT_RENEWAL_REQUEST event
                renewalEvent.time              = simTimeSec;
                renewalEvent.type              = sim.EventCalendar.CERT_RENEWAL_REQUEST;
                renewalEvent.id                = obj.nextEventId;
                renewalEvent.payload.entityId  = entityId;
                renewalEvent.payload.trustAnchorId = trustAnchorId;
                obj.nextEventId = obj.nextEventId + uint64(1);

                if ~isempty(obj.eventCalendar)
                    obj.eventCalendar.schedule(renewalEvent);
                end
            end
        end

        % ------------------------------------------------------------------
        % buildICAMReport
        % ------------------------------------------------------------------

        function report = buildICAMReport(obj)
            % buildICAMReport  Return ICAM statistics struct.
            %
            %   report = ic.buildICAMReport()
            %
            %   Returns struct with fields matching §6.4 schema:
            %     authExchanges: {total, successful, failed, timedOut}
            %     cacheHitRate: from credentialCache.getStats()
            %     accessDeniedCount: {total, perEntity, perEnclave}
            %     certRenewals: {total, successful, failed}
            %     entityCounts: {human, npe}
            %     pdpStats: [] (placeholder)
            %     perEnclaveRoleBindingCounts: {} (placeholder)
            %
            % Requirements: 20.6, 21.5, 23.6, 24.5

            % Auth exchanges
            report.authExchanges.total      = obj.nAuthTotal;
            report.authExchanges.successful = obj.nAuthSuccessful;
            report.authExchanges.failed     = obj.nAuthFailed;
            report.authExchanges.timedOut   = obj.nAuthTimedOut;

            % Cache hit rate
            if ~isempty(obj.credentialCache)
                stats = obj.credentialCache.getStats();
                totalLookups = double(stats.hits) + double(stats.misses);
                if totalLookups > 0
                    report.cacheHitRate = double(stats.hits) / totalLookups;
                else
                    report.cacheHitRate = 0.0;
                end
            else
                report.cacheHitRate = 0.0;
            end

            % Access denied count
            if ~isempty(obj.pep)
                deniedCount = double(obj.pep.getAccessDeniedCount());
                deniedLog   = obj.pep.getAccessDeniedLog();
            else
                deniedCount = 0;
                deniedLog   = struct('srcEntityId', {}, 'dstEntityId', {}, ...
                                     'messageType', {}, 'enclaveId', {}, 'simTimeSec', {});
            end

            report.accessDeniedCount.total     = deniedCount;
            report.accessDeniedCount.perEntity = obj.buildPerEntityDeniedMap(deniedLog);
            report.accessDeniedCount.perEnclave = obj.buildPerEnclaveDeniedMap(deniedLog);

            % Certificate renewals
            report.certRenewals.total      = obj.nCertRenewalsTotal;
            report.certRenewals.successful = obj.nCertRenewalsSuccessful;
            report.certRenewals.failed     = obj.nCertRenewalsFailed;

            % Entity counts
            report.entityCounts = obj.buildEntityCounts();

            % Placeholders
            report.pdpStats                    = [];
            report.perEnclaveRoleBindingCounts = struct();
        end

    end % methods (Access = public)

    % ======================================================================
    % Private helpers
    % ======================================================================
    methods (Access = private)

        function pdp = makeDefaultPermissivePdp(~, scenario)
            % makeDefaultPermissivePdp  Create a PDP that permits everything.
            %
            % Writes a minimal fail-open policy to a temp file and loads it.
            % Includes all enclaves referenced in the scenario with fail-open policy.

            if nargin < 2
                scenario = struct();
            end

            % Collect all enclave IDs from scenario entities
            enclaveIds = {'default'};
            if isfield(scenario, 'entities') && ~isempty(scenario.entities)
                entities = scenario.entities;
                if isstruct(entities)
                    for k = 1:numel(entities)
                        ent = entities(k);
                        if isfield(ent, 'enclaveIds') && ~isempty(ent.enclaveIds)
                            ids = ent.enclaveIds;
                            if iscell(ids)
                                for j = 1:numel(ids)
                                    enclaveIds{end+1} = char(ids{j}); %#ok<AGROW>
                                end
                            end
                        end
                        if isfield(ent, 'roleBindings') && ~isempty(ent.roleBindings)
                            rb = ent.roleBindings;
                            if isstruct(rb)
                                for j = 1:numel(rb)
                                    if isfield(rb(j), 'enclaveId')
                                        enclaveIds{end+1} = char(rb(j).enclaveId); %#ok<AGROW>
                                    end
                                end
                            end
                        end
                    end
                end
            end
            enclaveIds = unique(enclaveIds);

            % Build enclave array with fail-open policy for all enclaves
            nEnclaves = numel(enclaveIds);
            enclaves(nEnclaves) = struct('enclaveId', '', 'cacheTtlSec', 300, 'failPolicy', 'open');
            for k = 1:nEnclaves
                enclaves(k).enclaveId   = enclaveIds{k};
                enclaves(k).cacheTtlSec = 300;
                enclaves(k).failPolicy  = 'open';
            end

            policy.enclaves     = enclaves;
            policy.trustAnchors = struct('trustAnchorId', 'default-ta', ...
                                          'nodeId', 'default-node', ...
                                          'certificateValidityPeriodSec', 3600);
            policy.rules = struct.empty(0, 1);

            tmpFile = [tempname() '.json'];
            fid = fopen(tmpFile, 'w');
            fprintf(fid, '%s', jsonencode(policy));
            fclose(fid);

            pdp = icam.PolicyDecisionPoint(tmpFile);
            delete(tmpFile);
        end

        function ttlMap = buildTtlConfigMap(obj, pdp, scenario)
            % buildTtlConfigMap  Build a TTL config map from PDP enclave definitions
            % and scenario entity enclave memberships.
            %
            % Queries the PDP for known enclaves and their cache TTLs.
            % Also adds entries for any enclaves referenced in scenario entities.

            if nargin < 3
                scenario = struct();
            end

            ttlMap = containers.Map('KeyType', 'char', 'ValueType', 'double');

            % Add default enclave
            ttlMap('default') = pdp.getCacheTtl('default');

            % Collect all enclave IDs referenced in scenario entities
            enclaveIds = obj.collectEnclaveIds(scenario);
            for k = 1:numel(enclaveIds)
                encId = enclaveIds{k};
                if ~ttlMap.isKey(encId)
                    % Use PDP's configured TTL (defaults to 300 for unknown enclaves)
                    ttlMap(encId) = pdp.getCacheTtl(encId);
                end
            end
        end

        function enclaveIds = collectEnclaveIds(~, scenario)
            % collectEnclaveIds  Collect all unique enclave IDs from scenario entities.

            enclaveIds = {};
            if ~isfield(scenario, 'entities') || isempty(scenario.entities)
                return;
            end

            entities = scenario.entities;
            if ~isstruct(entities)
                return;
            end

            for k = 1:numel(entities)
                ent = entities(k);
                if isfield(ent, 'enclaveIds') && ~isempty(ent.enclaveIds)
                    ids = ent.enclaveIds;
                    if iscell(ids)
                        for j = 1:numel(ids)
                            enclaveIds{end+1} = char(ids{j}); %#ok<AGROW>
                        end
                    end
                end
                if isfield(ent, 'roleBindings') && ~isempty(ent.roleBindings)
                    rb = ent.roleBindings;
                    if isstruct(rb)
                        for j = 1:numel(rb)
                            if isfield(rb(j), 'enclaveId')
                                enclaveIds{end+1} = char(rb(j).enclaveId); %#ok<AGROW>
                            end
                        end
                    end
                end
            end

            % Deduplicate
            enclaveIds = unique(enclaveIds);
        end

        function issueInitialCertificates(obj, scenario)
            % issueInitialCertificates  Issue certificates for all entities.
            %
            % For each entity in the EntityRegistry, issue a certificate using
            % values from the entity's certificate config in the scenario.
            % Default validityPeriodSec = 3600 if not specified.

            if isempty(obj.entityRegistry) || obj.entityRegistry.count() == 0
                return;
            end

            entityIds = obj.entityRegistry.getEntityIds();

            % Build a lookup map from entityId to scenario entity def
            entityDefMap = containers.Map('KeyType', 'char', 'ValueType', 'any');
            if isfield(scenario, 'entities') && ~isempty(scenario.entities)
                entities = scenario.entities;
                if isstruct(entities)
                    for k = 1:numel(entities)
                        ent = entities(k);
                        if isfield(ent, 'entityId')
                            entityDefMap(char(ent.entityId)) = ent;
                        elseif isfield(ent, 'id')
                            entityDefMap(char(ent.id)) = ent;
                        end
                    end
                end
            end

            for k = 1:numel(entityIds)
                entityId = char(entityIds(k));

                % Defaults
                trustAnchorId     = 'default-ta';
                roleBindings      = struct('enclaveId', 'default', 'roleName', 'default');
                validityPeriodSec = 3600;

                % Override with scenario-provided values if available
                if entityDefMap.isKey(entityId)
                    def = entityDefMap(entityId);

                    if isfield(def, 'certificate') && ~isempty(def.certificate)
                        certCfg = def.certificate;
                        if isfield(certCfg, 'trustAnchorId') && ~isempty(certCfg.trustAnchorId)
                            trustAnchorId = char(certCfg.trustAnchorId);
                        end
                        if isfield(certCfg, 'validityPeriodSec') && ~isempty(certCfg.validityPeriodSec)
                            validityPeriodSec = certCfg.validityPeriodSec;
                        end
                    end

                    if isfield(def, 'roleBindings') && ~isempty(def.roleBindings)
                        roleBindings = def.roleBindings;
                    end
                end

                obj.credentialStore.issueCertificate( ...
                    entityId, trustAnchorId, roleBindings, validityPeriodSec, 0);
            end
        end

        function perEntityMap = buildPerEntityDeniedMap(~, deniedLog)
            % buildPerEntityDeniedMap  Build per-entity access-denied count map.

            perEntityMap = containers.Map('KeyType', 'char', 'ValueType', 'double');
            for k = 1:numel(deniedLog)
                src = char(deniedLog(k).srcEntityId);
                if ~isempty(src)
                    if perEntityMap.isKey(src)
                        perEntityMap(src) = perEntityMap(src) + 1;
                    else
                        perEntityMap(src) = 1;
                    end
                end
            end
        end

        function perEnclaveMap = buildPerEnclaveDeniedMap(~, deniedLog)
            % buildPerEnclaveDeniedMap  Build per-enclave access-denied count map.

            perEnclaveMap = containers.Map('KeyType', 'char', 'ValueType', 'double');
            for k = 1:numel(deniedLog)
                enc = char(deniedLog(k).enclaveId);
                if ~isempty(enc)
                    if perEnclaveMap.isKey(enc)
                        perEnclaveMap(enc) = perEnclaveMap(enc) + 1;
                    else
                        perEnclaveMap(enc) = 1;
                    end
                end
            end
        end

        function counts = buildEntityCounts(obj)
            % buildEntityCounts  Count human and NPE entities.

            counts.human = 0;
            counts.npe   = 0;

            if isempty(obj.entityRegistry) || obj.entityRegistry.count() == 0
                return;
            end

            entityIds = obj.entityRegistry.getEntityIds();
            for k = 1:numel(entityIds)
                try
                    entity = obj.entityRegistry.getEntity(entityIds(k));
                    typeStr = lower(char(entity.entityType));
                    if strcmp(typeStr, 'human')
                        counts.human = counts.human + 1;
                    elseif strcmp(typeStr, 'npe')
                        counts.npe = counts.npe + 1;
                    end
                catch
                    % Skip entities that can't be retrieved
                end
            end
        end

        function role = resolveEntityRole(obj, entityId)
            % resolveEntityRole  Look up the role for an entity from the EntityRegistry.
            %
            %   role = ic.resolveEntityRole(entityId)
            %
            %   Returns the entity's type/role string (e.g., 'pilot', 'aircraft').
            %   Falls back to '*' if entity not found or has no role.

            role = '*';

            % Try EntityRegistry if available
            if ~isempty(obj.entityRegistry)
                try
                    entityData = obj.entityRegistry.getEntity(entityId);
                    if isfield(entityData, 'type') && ~isempty(entityData.type)
                        role = char(entityData.type);
                    end
                catch
                    % Entity not found in registry — fall through
                end
            end

            % If still wildcard, try scenario entities for a role/type field
            if strcmp(role, '*') && ~isempty(obj.scenario) && ...
                    isfield(obj.scenario, 'entities') && ~isempty(obj.scenario.entities)
                ents = obj.scenario.entities;
                for k = 1:numel(ents)
                    if isstruct(ents)
                        ent = ents(k);
                    elseif iscell(ents)
                        ent = ents{k};
                    else
                        break;
                    end
                    if isfield(ent, 'id') && strcmp(char(ent.id), entityId)
                        if isfield(ent, 'role') && ~isempty(ent.role)
                            role = char(ent.role);
                        elseif isfield(ent, 'type') && ~isempty(ent.type) && ...
                                ~ismember(char(ent.type), {'human', 'npe'})
                            % Only use type as role if it's a meaningful role name
                            role = char(ent.type);
                        end
                        return;
                    end
                end
            end
        end

    end % methods (Access = private)

end % classdef
