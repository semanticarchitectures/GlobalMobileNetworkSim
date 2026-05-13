classdef CredentialCacheTest < matlab.unittest.TestCase
    % CredentialCacheTest  Unit tests for icam.CredentialCache.
    %
    % Covers:
    %   1. Cache hit within TTL returns stored decision
    %   2. Cache miss after TTL expiry returns ''
    %   3. TTL=0 always returns '' (caching disabled)
    %   4. invalidateEnclave removes only entries for specified enclave
    %   5. getStats returns correct hit/miss/invalidation counts
    %
    % Requirements: 23.1, 23.2, 23.3, 23.4, 23.5, 23.6

    % ======================================================================
    % Helper: build a ttlConfigMap
    % ======================================================================
    methods (Access = private)

        function m = makeTtlMap(~, enclaveIds, ttlValues)
            % Build a containers.Map from enclaveId strings to ttlSec values.
            m = containers.Map('KeyType', 'char', 'ValueType', 'double');
            for k = 1:numel(enclaveIds)
                m(enclaveIds{k}) = ttlValues(k);
            end
        end

    end

    % ======================================================================
    % Test 1: Cache hit within TTL returns stored decision
    % ======================================================================
    methods (Test)

        function testCacheHitWithinTtlReturnsPermit(testCase)
            % A lookup within TTL should return the stored 'permit' decision.
            %
            % Requirements: 23.2

            ttlMap = testCase.makeTtlMap({'enc1'}, [300]);
            cc = icam.CredentialCache(ttlMap);

            cc.store('entity1', 'MSG_TYPE', 'enc1', 'permit', 0.0);
            result = cc.lookup('entity1', 'MSG_TYPE', 'enc1', 100.0);  % age=100 < TTL=300

            testCase.verifyEqual(result, 'permit', ...
                'Cache hit within TTL should return permit');
        end

        function testCacheHitWithinTtlReturnsDeny(testCase)
            % A lookup within TTL should return the stored 'deny' decision.
            %
            % Requirements: 23.2

            ttlMap = testCase.makeTtlMap({'enc1'}, [300]);
            cc = icam.CredentialCache(ttlMap);

            cc.store('entity1', 'MSG_TYPE', 'enc1', 'deny', 0.0);
            result = cc.lookup('entity1', 'MSG_TYPE', 'enc1', 50.0);  % age=50 < TTL=300

            testCase.verifyEqual(result, 'deny', ...
                'Cache hit within TTL should return deny');
        end

        function testCacheHitAtExactTtlBoundary(testCase)
            % A lookup at exactly TTL age should be a miss (age > TTL is miss,
            % age == TTL is still a hit since condition is age > ttl).
            %
            % Requirements: 23.2

            ttlMap = testCase.makeTtlMap({'enc1'}, [100]);
            cc = icam.CredentialCache(ttlMap);

            cc.store('entity1', 'MSG_TYPE', 'enc1', 'permit', 0.0);
            % age = 100 == TTL = 100 → age > ttl is false → hit
            result = cc.lookup('entity1', 'MSG_TYPE', 'enc1', 100.0);

            testCase.verifyEqual(result, 'permit', ...
                'Lookup at exactly TTL age should be a hit (age > ttl is false)');
        end

        % ======================================================================
        % Test 2: Cache miss after TTL expiry returns ''
        % ======================================================================

        function testCacheMissAfterTtlExpiry(testCase)
            % A lookup after TTL expiry should return ''.
            %
            % Requirements: 23.3

            ttlMap = testCase.makeTtlMap({'enc1'}, [100]);
            cc = icam.CredentialCache(ttlMap);

            cc.store('entity1', 'MSG_TYPE', 'enc1', 'permit', 0.0);
            result = cc.lookup('entity1', 'MSG_TYPE', 'enc1', 200.0);  % age=200 > TTL=100

            testCase.verifyEqual(result, '', ...
                'Cache miss after TTL expiry should return empty string');
        end

        function testCacheMissForNonExistentKey(testCase)
            % A lookup for a key that was never stored should return ''.
            %
            % Requirements: 23.2

            ttlMap = testCase.makeTtlMap({'enc1'}, [300]);
            cc = icam.CredentialCache(ttlMap);

            result = cc.lookup('entity1', 'MSG_TYPE', 'enc1', 0.0);

            testCase.verifyEqual(result, '', ...
                'Lookup for non-existent key should return empty string');
        end

        % ======================================================================
        % Test 3: TTL=0 always returns '' (caching disabled)
        % ======================================================================

        function testTtlZeroAlwaysReturnsMiss(testCase)
            % When TTL=0 for an enclave, lookup should always return ''.
            %
            % Requirements: 23.3

            ttlMap = testCase.makeTtlMap({'enc-disabled'}, [0]);
            cc = icam.CredentialCache(ttlMap);

            % store should be a no-op
            cc.store('entity1', 'MSG_TYPE', 'enc-disabled', 'permit', 0.0);

            % lookup should always miss
            result = cc.lookup('entity1', 'MSG_TYPE', 'enc-disabled', 0.0);

            testCase.verifyEqual(result, '', ...
                'TTL=0 should always return empty string (caching disabled)');
        end

        function testTtlZeroStoreIsNoOp(testCase)
            % store with TTL=0 should not add any entry to the cache.
            %
            % Requirements: 23.4

            ttlMap = testCase.makeTtlMap({'enc-disabled'}, [0]);
            cc = icam.CredentialCache(ttlMap);

            cc.store('entity1', 'MSG_TYPE', 'enc-disabled', 'permit', 0.0);
            cc.store('entity1', 'MSG_TYPE', 'enc-disabled', 'deny', 0.0);

            % Both lookups should miss
            r1 = cc.lookup('entity1', 'MSG_TYPE', 'enc-disabled', 0.0);
            r2 = cc.lookup('entity1', 'MSG_TYPE', 'enc-disabled', 1000.0);

            testCase.verifyEqual(r1, '', 'store with TTL=0 should be no-op (lookup 1)');
            testCase.verifyEqual(r2, '', 'store with TTL=0 should be no-op (lookup 2)');
        end

        function testUnknownEnclaveDefaultsToTtlZero(testCase)
            % An enclave not in ttlConfigMap should default to TTL=0 (disabled).
            %
            % Requirements: 23.3

            ttlMap = testCase.makeTtlMap({'enc-known'}, [300]);
            cc = icam.CredentialCache(ttlMap);

            % enc-unknown is not in the map
            cc.store('entity1', 'MSG_TYPE', 'enc-unknown', 'permit', 0.0);
            result = cc.lookup('entity1', 'MSG_TYPE', 'enc-unknown', 0.0);

            testCase.verifyEqual(result, '', ...
                'Unknown enclave should default to TTL=0 (caching disabled)');
        end

        % ======================================================================
        % Test 4: invalidateEnclave removes only entries for specified enclave
        % ======================================================================

        function testInvalidateEnclaveRemovesOnlyTargetEnclave(testCase)
            % invalidateEnclave should remove entries for the specified enclave
            % and leave entries for other enclaves intact.
            %
            % Requirements: 23.5

            ttlMap = testCase.makeTtlMap({'enc-alpha', 'enc-bravo'}, [300, 300]);
            cc = icam.CredentialCache(ttlMap);

            cc.store('entity1', 'MSG', 'enc-alpha', 'permit', 0.0);
            cc.store('entity2', 'MSG', 'enc-alpha', 'deny',   0.0);
            cc.store('entity1', 'MSG', 'enc-bravo', 'permit', 0.0);

            cc.invalidateEnclave('enc-alpha');

            % enc-alpha entries should be gone
            r1 = cc.lookup('entity1', 'MSG', 'enc-alpha', 0.0);
            r2 = cc.lookup('entity2', 'MSG', 'enc-alpha', 0.0);
            % enc-bravo entry should remain
            r3 = cc.lookup('entity1', 'MSG', 'enc-bravo', 0.0);

            testCase.verifyEqual(r1, '', 'entity1/enc-alpha should be invalidated');
            testCase.verifyEqual(r2, '', 'entity2/enc-alpha should be invalidated');
            testCase.verifyEqual(r3, 'permit', 'entity1/enc-bravo should be unaffected');
        end

        function testInvalidateEnclaveOnEmptyCacheIsNoOp(testCase)
            % invalidateEnclave on an empty cache should not error.
            %
            % Requirements: 23.5

            ttlMap = testCase.makeTtlMap({'enc1'}, [300]);
            cc = icam.CredentialCache(ttlMap);

            % Should not throw
            testCase.verifyWarningFree(@() cc.invalidateEnclave('enc1'), ...
                'invalidateEnclave on empty cache should not error');
        end

        function testInvalidateEnclaveOnNonExistentEnclaveIsNoOp(testCase)
            % invalidateEnclave for an enclave with no entries should not error.
            %
            % Requirements: 23.5

            ttlMap = testCase.makeTtlMap({'enc1'}, [300]);
            cc = icam.CredentialCache(ttlMap);

            cc.store('entity1', 'MSG', 'enc1', 'permit', 0.0);

            % Invalidate a different enclave
            testCase.verifyWarningFree(@() cc.invalidateEnclave('enc-other'), ...
                'invalidateEnclave for non-existent enclave should not error');

            % enc1 entry should still be there
            result = cc.lookup('entity1', 'MSG', 'enc1', 0.0);
            testCase.verifyEqual(result, 'permit', ...
                'enc1 entry should be unaffected by invalidating enc-other');
        end

        % ======================================================================
        % Test 5: getStats returns correct hit/miss/invalidation counts
        % ======================================================================

        function testGetStatsInitiallyZero(testCase)
            % getStats should return all zeros on a fresh cache.
            %
            % Requirements: 23.6

            ttlMap = testCase.makeTtlMap({'enc1'}, [300]);
            cc = icam.CredentialCache(ttlMap);

            stats = cc.getStats();
            testCase.verifyEqual(stats.hits,          uint64(0), 'Initial hits should be 0');
            testCase.verifyEqual(stats.misses,        uint64(0), 'Initial misses should be 0');
            testCase.verifyEqual(stats.invalidations, uint64(0), 'Initial invalidations should be 0');
        end

        function testGetStatsCountsHits(testCase)
            % getStats should count cache hits correctly.
            %
            % Requirements: 23.6

            ttlMap = testCase.makeTtlMap({'enc1'}, [300]);
            cc = icam.CredentialCache(ttlMap);

            cc.store('entity1', 'MSG', 'enc1', 'permit', 0.0);
            cc.lookup('entity1', 'MSG', 'enc1', 10.0);  % hit
            cc.lookup('entity1', 'MSG', 'enc1', 20.0);  % hit

            stats = cc.getStats();
            testCase.verifyEqual(stats.hits, uint64(2), 'Should count 2 hits');
        end

        function testGetStatsCountsMisses(testCase)
            % getStats should count cache misses correctly.
            %
            % Requirements: 23.6

            ttlMap = testCase.makeTtlMap({'enc1'}, [300]);
            cc = icam.CredentialCache(ttlMap);

            cc.lookup('entity1', 'MSG', 'enc1', 0.0);  % miss (no entry)
            cc.lookup('entity2', 'MSG', 'enc1', 0.0);  % miss (no entry)

            stats = cc.getStats();
            testCase.verifyEqual(stats.misses, uint64(2), 'Should count 2 misses');
        end

        function testGetStatsCountsInvalidations(testCase)
            % getStats should count invalidated entries correctly.
            %
            % Requirements: 23.6

            ttlMap = testCase.makeTtlMap({'enc-alpha', 'enc-bravo'}, [300, 300]);
            cc = icam.CredentialCache(ttlMap);

            cc.store('entity1', 'MSG', 'enc-alpha', 'permit', 0.0);
            cc.store('entity2', 'MSG', 'enc-alpha', 'deny',   0.0);
            cc.store('entity1', 'MSG', 'enc-bravo', 'permit', 0.0);

            cc.invalidateEnclave('enc-alpha');  % removes 2 entries

            stats = cc.getStats();
            testCase.verifyEqual(stats.invalidations, uint64(2), ...
                'Should count 2 invalidations after removing 2 enc-alpha entries');
        end

        function testGetStatsCountsAllTogether(testCase)
            % getStats should correctly track hits, misses, and invalidations
            % across a mixed sequence of operations.
            %
            % Requirements: 23.6

            ttlMap = testCase.makeTtlMap({'enc1', 'enc2'}, [300, 300]);
            cc = icam.CredentialCache(ttlMap);

            cc.store('e1', 'MSG', 'enc1', 'permit', 0.0);
            cc.store('e2', 'MSG', 'enc1', 'deny',   0.0);
            cc.store('e1', 'MSG', 'enc2', 'permit', 0.0);

            cc.lookup('e1', 'MSG', 'enc1', 10.0);   % hit
            cc.lookup('e2', 'MSG', 'enc1', 10.0);   % hit
            cc.lookup('e3', 'MSG', 'enc1', 10.0);   % miss (no entry)
            cc.lookup('e1', 'MSG', 'enc1', 500.0);  % miss (expired, TTL=300)

            cc.invalidateEnclave('enc2');  % removes 1 entry

            stats = cc.getStats();
            testCase.verifyEqual(stats.hits,          uint64(2), 'Should have 2 hits');
            testCase.verifyEqual(stats.misses,        uint64(2), 'Should have 2 misses');
            testCase.verifyEqual(stats.invalidations, uint64(1), 'Should have 1 invalidation');
        end

        function testGetStatsCountsTtlZeroMisses(testCase)
            % Lookups on TTL=0 enclaves should count as misses.
            %
            % Requirements: 23.6

            ttlMap = testCase.makeTtlMap({'enc-disabled'}, [0]);
            cc = icam.CredentialCache(ttlMap);

            cc.lookup('e1', 'MSG', 'enc-disabled', 0.0);  % miss (TTL=0)
            cc.lookup('e1', 'MSG', 'enc-disabled', 0.0);  % miss (TTL=0)

            stats = cc.getStats();
            testCase.verifyEqual(stats.misses, uint64(2), ...
                'TTL=0 lookups should count as misses');
        end

    end % methods (Test)

end % classdef
