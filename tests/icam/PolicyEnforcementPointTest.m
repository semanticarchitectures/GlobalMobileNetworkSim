classdef PolicyEnforcementPointTest < matlab.unittest.TestCase
    % PolicyEnforcementPointTest  Unit tests for icam.PolicyEnforcementPoint.
    %
    % Covers:
    %   1. Cache hit path: lookup returns decision without calling PDP
    %   2. Cache miss path: PDP is called and result stored in cache
    %   3. Deny path: access-denied event recorded in log
    %   4. checkReceive enforces receive-side independently of checkSend
    %   5. getAccessDeniedCount returns correct count
    %
    % Requirements: 21.1, 21.2, 21.3, 21.4, 21.5

    % ======================================================================
    % Helper methods
    % ======================================================================
    methods (Access = private)

        function ttlMap = makePermissiveTtlMap(~)
            % Build a TTL map with a 300-second TTL for enc-alpha.
            ttlMap = containers.Map('KeyType', 'char', 'ValueType', 'double');
            ttlMap('enc-alpha') = 300;
            ttlMap('enc-bravo') = 300;
        end

        function pdp = makePermitPdp(testCase)
            % Build a PDP that always permits (fail-open, no rules).
            policy.enclaves = struct('enclaveId', 'enc-alpha', ...
                                     'cacheTtlSec', 300, ...
                                     'failPolicy', 'open');
            policy.trustAnchors = struct('trustAnchorId', 'TA1', ...
                                         'nodeId', 'n1', ...
                                         'certificateValidityPeriodSec', 3600);
            policy.rules = struct.empty(0, 1);
            pdp = testCase.makePdpFromStruct(policy);
        end

        function pdp = makeDenyPdp(testCase)
            % Build a PDP that always denies (fail-closed, no rules).
            policy.enclaves = struct('enclaveId', 'enc-alpha', ...
                                     'cacheTtlSec', 300, ...
                                     'failPolicy', 'closed');
            policy.trustAnchors = struct('trustAnchorId', 'TA1', ...
                                         'nodeId', 'n1', ...
                                         'certificateValidityPeriodSec', 3600);
            policy.rules = struct.empty(0, 1);
            pdp = testCase.makePdpFromStruct(policy);
        end

        function pdp = makePdpFromStruct(~, policyStruct)
            % Serialize policyStruct to a temp JSON file and build a PDP.
            tmpFile = [tempname() '.json'];
            fid = fopen(tmpFile, 'w');
            fprintf(fid, '%s', jsonencode(policyStruct));
            fclose(fid);
            pdp = icam.PolicyDecisionPoint(tmpFile);
            delete(tmpFile);
        end

        function er = makeEmptyEntityRegistry(~)
            % Build an empty EntityRegistry (no entities needed for PEP tests).
            % We pass an empty struct array and a minimal NodeRegistry stub.
            % Since EntityRegistry requires a nodeRegistry, we use a real one
            % with a dummy node.
            nodeDef.id    = 'node1';
            nodeDef.type  = 'Stationary';
            nodeDef.lat   = 0.0;
            nodeDef.lon   = 0.0;
            nodeDef.altM  = 0.0;
            nr = network.NodeRegistry(nodeDef);
            er = icam.EntityRegistry([], nr);
        end

    end

    % ======================================================================
    % Test 1: Cache hit path — lookup returns decision without calling PDP
    % ======================================================================
    methods (Test)

        function testCacheHitReturnsDecisionWithoutCallingPdp(testCase)
            % When the cache has a valid entry, the result should come from
            % the cache (cacheHit=true) and the PDP should not be consulted.
            %
            % We verify this by pre-populating the cache with 'permit' and
            % using a deny-all PDP. If the cache is consulted, result is 'permit'.
            % If the PDP were called, result would be 'deny'.
            %
            % Requirements: 21.2

            ttlMap = testCase.makePermissiveTtlMap();
            cc  = icam.CredentialCache(ttlMap);
            pdp = testCase.makeDenyPdp();
            er  = testCase.makeEmptyEntityRegistry();

            % Pre-populate cache with a permit decision
            cc.store('entity-src', 'MSG_TYPE', 'enc-alpha', 'permit', 0.0);

            pep = icam.PolicyEnforcementPoint(cc, pdp, er);
            result = pep.checkSend('entity-src', 'entity-dst', 'MSG_TYPE', 'enc-alpha', 50.0);

            testCase.verifyEqual(result.decision, 'permit', ...
                'Cache hit should return the cached permit decision');
            testCase.verifyTrue(result.cacheHit, ...
                'cacheHit should be true when decision comes from cache');
        end

        function testCacheHitReturnsDenyFromCache(testCase)
            % Cache hit with a 'deny' entry should return deny with cacheHit=true.
            %
            % Requirements: 21.2

            ttlMap = testCase.makePermissiveTtlMap();
            cc  = icam.CredentialCache(ttlMap);
            pdp = testCase.makePermitPdp();  % PDP would permit, but cache has deny
            er  = testCase.makeEmptyEntityRegistry();

            % Pre-populate cache with a deny decision
            cc.store('entity-src', 'MSG_TYPE', 'enc-alpha', 'deny', 0.0);

            pep = icam.PolicyEnforcementPoint(cc, pdp, er);
            result = pep.checkSend('entity-src', 'entity-dst', 'MSG_TYPE', 'enc-alpha', 50.0);

            testCase.verifyEqual(result.decision, 'deny', ...
                'Cache hit should return the cached deny decision');
            testCase.verifyTrue(result.cacheHit, ...
                'cacheHit should be true when decision comes from cache');
        end

        % ======================================================================
        % Test 2: Cache miss path — PDP is called and result stored in cache
        % ======================================================================

        function testCacheMissCallsPdpAndStoresResult(testCase)
            % On a cache miss, the PDP should be called and the result stored
            % in the cache for subsequent lookups.
            %
            % Requirements: 21.3

            ttlMap = testCase.makePermissiveTtlMap();
            cc  = icam.CredentialCache(ttlMap);
            pdp = testCase.makePermitPdp();
            er  = testCase.makeEmptyEntityRegistry();

            pep = icam.PolicyEnforcementPoint(cc, pdp, er);

            % First call — cache miss, PDP consulted
            result1 = pep.checkSend('entity-src', 'entity-dst', 'MSG_TYPE', 'enc-alpha', 0.0);

            testCase.verifyEqual(result1.decision, 'permit', ...
                'Cache miss should return PDP decision (permit)');
            testCase.verifyFalse(result1.cacheHit, ...
                'cacheHit should be false on first call (cache miss)');

            % Second call — should now be a cache hit
            result2 = pep.checkSend('entity-src', 'entity-dst', 'MSG_TYPE', 'enc-alpha', 10.0);

            testCase.verifyEqual(result2.decision, 'permit', ...
                'Second call should return same decision from cache');
            testCase.verifyTrue(result2.cacheHit, ...
                'cacheHit should be true on second call (cache hit)');
        end

        function testCacheMissDenyCallsPdpAndStoresResult(testCase)
            % On a cache miss with a deny PDP, the deny should be stored in cache.
            %
            % Requirements: 21.3

            ttlMap = testCase.makePermissiveTtlMap();
            cc  = icam.CredentialCache(ttlMap);
            pdp = testCase.makeDenyPdp();
            er  = testCase.makeEmptyEntityRegistry();

            pep = icam.PolicyEnforcementPoint(cc, pdp, er);

            % First call — cache miss, PDP consulted
            result1 = pep.checkSend('entity-src', 'entity-dst', 'MSG_TYPE', 'enc-alpha', 0.0);

            testCase.verifyEqual(result1.decision, 'deny', ...
                'Cache miss should return PDP decision (deny)');
            testCase.verifyFalse(result1.cacheHit, ...
                'cacheHit should be false on first call (cache miss)');

            % Second call — should now be a cache hit with deny
            result2 = pep.checkSend('entity-src', 'entity-dst', 'MSG_TYPE', 'enc-alpha', 10.0);

            testCase.verifyEqual(result2.decision, 'deny', ...
                'Second call should return cached deny decision');
            testCase.verifyTrue(result2.cacheHit, ...
                'cacheHit should be true on second call (cache hit)');
        end

        function testResultStructHasRequiredFields(testCase)
            % checkSend result should have decision, reason, and cacheHit fields.
            %
            % Requirements: 21.1

            ttlMap = testCase.makePermissiveTtlMap();
            cc  = icam.CredentialCache(ttlMap);
            pdp = testCase.makePermitPdp();
            er  = testCase.makeEmptyEntityRegistry();

            pep = icam.PolicyEnforcementPoint(cc, pdp, er);
            result = pep.checkSend('src', 'dst', 'MSG', 'enc-alpha', 0.0);

            testCase.verifyTrue(isfield(result, 'decision'), ...
                'Result should have decision field');
            testCase.verifyTrue(isfield(result, 'reason'), ...
                'Result should have reason field');
            testCase.verifyTrue(isfield(result, 'cacheHit'), ...
                'Result should have cacheHit field');
        end

        % ======================================================================
        % Test 3: Deny path — access-denied event recorded in log
        % ======================================================================

        function testDenyPathRecordsAccessDeniedEvent(testCase)
            % When checkSend returns deny, an access-denied event should be
            % recorded in the internal log.
            %
            % Requirements: 21.5

            ttlMap = testCase.makePermissiveTtlMap();
            cc  = icam.CredentialCache(ttlMap);
            pdp = testCase.makeDenyPdp();
            er  = testCase.makeEmptyEntityRegistry();

            pep = icam.PolicyEnforcementPoint(cc, pdp, er);
            pep.checkSend('entity-src', 'entity-dst', 'MSG_TYPE', 'enc-alpha', 100.0);

            log = pep.getAccessDeniedLog();
            testCase.verifyEqual(numel(log), 1, ...
                'One access-denied event should be recorded');
            testCase.verifyEqual(log(1).srcEntityId, 'entity-src', ...
                'Access-denied log should record srcEntityId');
            testCase.verifyEqual(log(1).dstEntityId, 'entity-dst', ...
                'Access-denied log should record dstEntityId');
            testCase.verifyEqual(log(1).messageType, 'MSG_TYPE', ...
                'Access-denied log should record messageType');
            testCase.verifyEqual(log(1).enclaveId, 'enc-alpha', ...
                'Access-denied log should record enclaveId');
            testCase.verifyEqual(log(1).simTimeSec, 100.0, ...
                'Access-denied log should record simTimeSec');
        end

        function testPermitPathDoesNotRecordAccessDeniedEvent(testCase)
            % When checkSend returns permit, no access-denied event should be recorded.
            %
            % Requirements: 21.5

            ttlMap = testCase.makePermissiveTtlMap();
            cc  = icam.CredentialCache(ttlMap);
            pdp = testCase.makePermitPdp();
            er  = testCase.makeEmptyEntityRegistry();

            pep = icam.PolicyEnforcementPoint(cc, pdp, er);
            pep.checkSend('entity-src', 'entity-dst', 'MSG_TYPE', 'enc-alpha', 0.0);

            testCase.verifyEqual(pep.getAccessDeniedCount(), uint64(0), ...
                'No access-denied events should be recorded for permit decisions');
        end

        function testMultipleDeniesAccumulateInLog(testCase)
            % Multiple deny decisions should accumulate in the access-denied log.
            %
            % Requirements: 21.5

            ttlMap = containers.Map('KeyType', 'char', 'ValueType', 'double');
            ttlMap('enc-alpha') = 0;  % TTL=0 disables caching so each call hits PDP

            cc  = icam.CredentialCache(ttlMap);
            pdp = testCase.makeDenyPdp();
            er  = testCase.makeEmptyEntityRegistry();

            pep = icam.PolicyEnforcementPoint(cc, pdp, er);
            pep.checkSend('src1', 'dst1', 'MSG', 'enc-alpha', 1.0);
            pep.checkSend('src2', 'dst2', 'MSG', 'enc-alpha', 2.0);
            pep.checkSend('src3', 'dst3', 'MSG', 'enc-alpha', 3.0);

            testCase.verifyEqual(pep.getAccessDeniedCount(), uint64(3), ...
                'Three deny decisions should produce three access-denied log entries');
        end

        % ======================================================================
        % Test 4: checkReceive enforces receive-side independently of checkSend
        % ======================================================================

        function testCheckReceiveEnforcesReceiveSideIndependently(testCase)
            % checkReceive should enforce access control independently of checkSend.
            % A cache hit for checkSend should not affect checkReceive.
            %
            % Requirements: 21.4

            ttlMap = testCase.makePermissiveTtlMap();
            cc  = icam.CredentialCache(ttlMap);
            pdp = testCase.makePermitPdp();
            er  = testCase.makeEmptyEntityRegistry();

            pep = icam.PolicyEnforcementPoint(cc, pdp, er);

            % checkSend populates cache for send-side
            sendResult = pep.checkSend('entity-src', 'entity-dst', 'MSG_TYPE', 'enc-alpha', 0.0);
            testCase.verifyFalse(sendResult.cacheHit, 'First checkSend should be cache miss');

            % checkReceive should be a separate cache miss (different key)
            recvResult = pep.checkReceive('entity-dst', 'MSG_TYPE', 'enc-alpha', 0.0);
            testCase.verifyFalse(recvResult.cacheHit, ...
                'checkReceive should be a cache miss independent of checkSend');
        end

        function testCheckReceiveResultHasRequiredFields(testCase)
            % checkReceive result should have decision, reason, and cacheHit fields.
            %
            % Requirements: 21.4

            ttlMap = testCase.makePermissiveTtlMap();
            cc  = icam.CredentialCache(ttlMap);
            pdp = testCase.makePermitPdp();
            er  = testCase.makeEmptyEntityRegistry();

            pep = icam.PolicyEnforcementPoint(cc, pdp, er);
            result = pep.checkReceive('entity-dst', 'MSG_TYPE', 'enc-alpha', 0.0);

            testCase.verifyTrue(isfield(result, 'decision'), ...
                'checkReceive result should have decision field');
            testCase.verifyTrue(isfield(result, 'reason'), ...
                'checkReceive result should have reason field');
            testCase.verifyTrue(isfield(result, 'cacheHit'), ...
                'checkReceive result should have cacheHit field');
        end

        function testCheckReceiveDenyRecordsAccessDeniedEvent(testCase)
            % When checkReceive returns deny, an access-denied event should be recorded.
            %
            % Requirements: 21.4, 21.5

            ttlMap = testCase.makePermissiveTtlMap();
            cc  = icam.CredentialCache(ttlMap);
            pdp = testCase.makeDenyPdp();
            er  = testCase.makeEmptyEntityRegistry();

            pep = icam.PolicyEnforcementPoint(cc, pdp, er);
            result = pep.checkReceive('entity-dst', 'MSG_TYPE', 'enc-alpha', 50.0);

            testCase.verifyEqual(result.decision, 'deny', ...
                'checkReceive should return deny from deny PDP');
            testCase.verifyEqual(pep.getAccessDeniedCount(), uint64(1), ...
                'checkReceive deny should record one access-denied event');
        end

        function testCheckReceiveCacheHitOnSecondCall(testCase)
            % Second checkReceive call with same inputs should be a cache hit.
            %
            % Requirements: 21.4

            ttlMap = testCase.makePermissiveTtlMap();
            cc  = icam.CredentialCache(ttlMap);
            pdp = testCase.makePermitPdp();
            er  = testCase.makeEmptyEntityRegistry();

            pep = icam.PolicyEnforcementPoint(cc, pdp, er);

            % First call — cache miss
            result1 = pep.checkReceive('entity-dst', 'MSG_TYPE', 'enc-alpha', 0.0);
            testCase.verifyFalse(result1.cacheHit, 'First checkReceive should be cache miss');

            % Second call — cache hit
            result2 = pep.checkReceive('entity-dst', 'MSG_TYPE', 'enc-alpha', 10.0);
            testCase.verifyTrue(result2.cacheHit, 'Second checkReceive should be cache hit');
            testCase.verifyEqual(result2.decision, result1.decision, ...
                'Cache hit should return same decision as original PDP call');
        end

        % ======================================================================
        % Test 5: getAccessDeniedCount returns correct count
        % ======================================================================

        function testGetAccessDeniedCountInitiallyZero(testCase)
            % getAccessDeniedCount should return 0 on a fresh PEP.
            %
            % Requirements: 21.5

            ttlMap = testCase.makePermissiveTtlMap();
            cc  = icam.CredentialCache(ttlMap);
            pdp = testCase.makePermitPdp();
            er  = testCase.makeEmptyEntityRegistry();

            pep = icam.PolicyEnforcementPoint(cc, pdp, er);
            testCase.verifyEqual(pep.getAccessDeniedCount(), uint64(0), ...
                'getAccessDeniedCount should be 0 initially');
        end

        function testGetAccessDeniedCountIncrementsOnDeny(testCase)
            % getAccessDeniedCount should increment for each deny decision.
            %
            % Requirements: 21.5

            % Use TTL=0 to disable caching so each call hits PDP
            ttlMap = containers.Map('KeyType', 'char', 'ValueType', 'double');
            ttlMap('enc-alpha') = 0;

            cc  = icam.CredentialCache(ttlMap);
            pdp = testCase.makeDenyPdp();
            er  = testCase.makeEmptyEntityRegistry();

            pep = icam.PolicyEnforcementPoint(cc, pdp, er);

            pep.checkSend('src', 'dst', 'MSG', 'enc-alpha', 1.0);
            testCase.verifyEqual(pep.getAccessDeniedCount(), uint64(1), ...
                'Count should be 1 after one deny');

            pep.checkSend('src', 'dst', 'MSG', 'enc-alpha', 2.0);
            testCase.verifyEqual(pep.getAccessDeniedCount(), uint64(2), ...
                'Count should be 2 after two denies');

            pep.checkReceive('dst', 'MSG', 'enc-alpha', 3.0);
            testCase.verifyEqual(pep.getAccessDeniedCount(), uint64(3), ...
                'Count should be 3 after checkReceive deny');
        end

        function testGetAccessDeniedCountDoesNotIncrementOnPermit(testCase)
            % getAccessDeniedCount should not increment for permit decisions.
            %
            % Requirements: 21.5

            ttlMap = testCase.makePermissiveTtlMap();
            cc  = icam.CredentialCache(ttlMap);
            pdp = testCase.makePermitPdp();
            er  = testCase.makeEmptyEntityRegistry();

            pep = icam.PolicyEnforcementPoint(cc, pdp, er);

            pep.checkSend('src', 'dst', 'MSG', 'enc-alpha', 0.0);
            pep.checkReceive('dst', 'MSG', 'enc-alpha', 0.0);

            testCase.verifyEqual(pep.getAccessDeniedCount(), uint64(0), ...
                'Count should remain 0 after permit decisions');
        end

        function testGetAccessDeniedLogIsEmptyInitially(testCase)
            % getAccessDeniedLog should return empty struct array initially.
            %
            % Requirements: 21.5

            ttlMap = testCase.makePermissiveTtlMap();
            cc  = icam.CredentialCache(ttlMap);
            pdp = testCase.makePermitPdp();
            er  = testCase.makeEmptyEntityRegistry();

            pep = icam.PolicyEnforcementPoint(cc, pdp, er);
            log = pep.getAccessDeniedLog();

            testCase.verifyEmpty(log, 'Access-denied log should be empty initially');
        end

    end % methods (Test)

end % classdef
