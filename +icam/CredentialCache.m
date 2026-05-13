classdef CredentialCache < handle
    % CredentialCache  Per-entity TTL-based cache of PDP access control decisions.
    %
    % Cache key:   entityId + '|' + resourceType + '|' + enclaveId
    % Cache entry: struct {decision (string), timestamp (double), ttl (double)}
    %
    % Internal storage: containers.Map from cache key (char) to entry struct.
    %
    % Stats tracked: hits (uint64), misses (uint64), invalidations (uint64).
    %
    % Requirements: 23.1, 23.2, 23.3, 23.4, 23.5, 23.6

    properties (Access = private)
        cacheMap        % containers.Map: cache key → entry struct
        ttlConfigMap    % containers.Map: enclaveId → ttlSec (0 = disabled)
        nHits           % uint64
        nMisses         % uint64
        nInvalidations  % uint64
    end

    methods (Access = public)

        % ------------------------------------------------------------------
        % Constructor
        % ------------------------------------------------------------------

        function obj = CredentialCache(ttlConfigMap)
            % CredentialCache  Construct a CredentialCache.
            %
            %   cc = icam.CredentialCache(ttlConfigMap)
            %
            %   ttlConfigMap: containers.Map of enclaveId (char) → ttlSec (double).
            %   A ttlSec of 0 disables caching for that enclave.
            %
            % Requirements: 23.1

            if nargin < 1 || isempty(ttlConfigMap)
                ttlConfigMap = containers.Map('KeyType', 'char', 'ValueType', 'double');
            end

            obj.ttlConfigMap   = ttlConfigMap;
            obj.cacheMap       = containers.Map('KeyType', 'char', 'ValueType', 'any');
            obj.nHits          = uint64(0);
            obj.nMisses        = uint64(0);
            obj.nInvalidations = uint64(0);
        end

        % ------------------------------------------------------------------
        % Public methods
        % ------------------------------------------------------------------

        function result = lookup(obj, entityId, resourceType, enclaveId, simTimeSec)
            % lookup  Return cached decision or '' on miss.
            %
            %   result = cc.lookup(entityId, resourceType, enclaveId, simTimeSec)
            %
            %   Returns 'permit', 'deny', or '' (cache miss).
            %   Returns '' if:
            %     - TTL for the enclave is 0 (caching disabled)
            %     - No entry exists for the key
            %     - Entry age (simTimeSec - entry.timestamp) > entry.ttl
            %
            % Requirements: 23.2, 23.3

            enclaveStr = char(enclaveId);
            ttl = obj.getTtl(enclaveStr);

            % Caching disabled for this enclave
            if ttl == 0
                obj.nMisses = obj.nMisses + uint64(1);
                result = '';
                return;
            end

            key = obj.buildKey(entityId, resourceType, enclaveId);

            if ~obj.cacheMap.isKey(key)
                obj.nMisses = obj.nMisses + uint64(1);
                result = '';
                return;
            end

            entry = obj.cacheMap(key);
            age = simTimeSec - entry.timestamp;

            if age > entry.ttl
                % Expired entry — treat as miss (do not remove; store() will overwrite)
                obj.nMisses = obj.nMisses + uint64(1);
                result = '';
                return;
            end

            % Cache hit
            obj.nHits = obj.nHits + uint64(1);
            result = entry.decision;
        end

        function store(obj, entityId, resourceType, enclaveId, decision, simTimeSec)
            % store  Store a decision in the cache.
            %
            %   cc.store(entityId, resourceType, enclaveId, decision, simTimeSec)
            %
            %   No-op if TTL for the enclave is 0 (caching disabled).
            %
            % Requirements: 23.4

            enclaveStr = char(enclaveId);
            ttl = obj.getTtl(enclaveStr);

            if ttl == 0
                return;  % caching disabled
            end

            key = obj.buildKey(entityId, resourceType, enclaveId);

            entry.decision  = char(decision);
            entry.timestamp = simTimeSec;
            entry.ttl       = ttl;

            obj.cacheMap(key) = entry;
        end

        function invalidateEnclave(obj, enclaveId)
            % invalidateEnclave  Remove all cache entries for the specified enclave.
            %
            %   cc.invalidateEnclave(enclaveId)
            %
            %   Removes all entries whose cache key ends with '|<enclaveId>'.
            %   Increments invalidations by the count of removed entries.
            %
            % Requirements: 23.5

            suffix = ['|' char(enclaveId)];
            allKeys = obj.cacheMap.keys();
            removed = 0;

            for k = 1:numel(allKeys)
                key = allKeys{k};
                % Check if key ends with the enclave suffix
                if numel(key) >= numel(suffix) && ...
                        strcmp(key(end-numel(suffix)+1:end), suffix)
                    obj.cacheMap.remove(key);
                    removed = removed + 1;
                end
            end

            obj.nInvalidations = obj.nInvalidations + uint64(removed);
        end

        function stats = getStats(obj)
            % getStats  Return hit/miss/invalidation counts.
            %
            %   stats = cc.getStats()
            %
            %   Returns struct {hits (uint64), misses (uint64), invalidations (uint64)}.
            %
            % Requirements: 23.6

            stats.hits          = obj.nHits;
            stats.misses        = obj.nMisses;
            stats.invalidations = obj.nInvalidations;
        end

    end % methods (Access = public)

    % ======================================================================
    % Private helpers
    % ======================================================================
    methods (Access = private)

        function key = buildKey(~, entityId, resourceType, enclaveId)
            % buildKey  Build the composite cache key string.
            key = [char(entityId) '|' char(resourceType) '|' char(enclaveId)];
        end

        function ttl = getTtl(obj, enclaveId)
            % getTtl  Return TTL for the enclave, or 0 if not configured.
            key = char(enclaveId);
            if obj.ttlConfigMap.isKey(key)
                ttl = obj.ttlConfigMap(key);
            else
                ttl = 0;  % default: caching disabled for unknown enclaves
            end
        end

    end % methods (Access = private)

end % classdef
