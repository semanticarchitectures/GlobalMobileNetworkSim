classdef LinkRegistryTest < matlab.unittest.TestCase
    % LinkRegistryTest  Unit tests for network.LinkRegistry.
    %
    % Covers:
    %   1. GEO_Satellite latency floor enforced (>= 270 ms)
    %   2. Fiber latency computed from geographic distance
    %   3. LEO_Satellite latency used as-is
    %   4. Unknown node reference throws netsim:link:unknownNode
    %   5. setOutage / isLinkActive transitions
    %   6. setLOSActive / isLinkActive transitions
    %   7. refreshBackground updates effectiveBwBps and isCongested
    %   8. getEffectiveLatency adds congestion penalty when congested
    %   9. getEffectiveBandwidth returns correct value
    %  10. indexOf returns correct index; throws for unknown ID
    %  11. count() returns number of links
    %
    % Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 3.2, 3.3

    % ======================================================================
    % Shared helpers
    % ======================================================================
    methods (Access = private)

        function nr = makeTwoNodeRegistry(~)
            % Two stationary nodes: A at (0,0,0) and B at (0,1,0).
            nd(1).id            = 'A';
            nd(1).type          = 'Stationary';
            nd(1).lat           = 0;
            nd(1).lon           = 0;
            nd(1).altM          = 0;
            nd(1).trajectory    = [];
            nd(1).keplerElements = [];

            nd(2).id            = 'B';
            nd(2).type          = 'Stationary';
            nd(2).lat           = 0;
            nd(2).lon           = 1;   % ~111 km east at equator
            nd(2).altM          = 0;
            nd(2).trajectory    = [];
            nd(2).keplerElements = [];

            nr = network.NodeRegistry(nd);
        end

        function lk = makeLink(~, id, type, srcId, dstId, latencyMs, bwBps)
            lk.id               = id;
            lk.type             = type;
            lk.srcNodeId        = srcId;
            lk.dstNodeId        = dstId;
            lk.nominalLatencyMs = latencyMs;
            lk.bandwidthBps     = bwBps;
            lk.outageRate       = 0.001;
            lk.outageDuration   = struct('distribution', 'exponential', 'mean', 60);
            lk.backgroundTraffic = struct('distribution', 'uniform', 'min', 0.1, 'max', 0.3);
            lk.coverageRadiusM  = NaN;
            lk.congestionPenaltyMs = 50;
        end

    end

    % ======================================================================
    % Tests
    % ======================================================================
    methods (Test)

        % ------------------------------------------------------------------
        % Test 1: GEO_Satellite latency floor >= 270 ms
        % ------------------------------------------------------------------

        function testGEOLatencyFloorEnforced(testCase)
            % A GEO link with nominalLatencyMs < 270 should be clamped to 270.
            % Requirements: 2.2
            nr = testCase.makeTwoNodeRegistry();
            lk = testCase.makeLink('L1', 'GEO_Satellite', 'A', 'B', 100, 1e9);
            lr = network.LinkRegistry(lk, nr);

            lat = lr.getEffectiveLatency('L1');
            testCase.verifyGreaterThanOrEqual(lat, 270, ...
                'GEO_Satellite latency should be >= 270 ms (floor enforced).');
        end

        function testGEOLatencyAboveFloorUnchanged(testCase)
            % A GEO link with nominalLatencyMs >= 270 should not be changed.
            % Requirements: 2.2
            nr = testCase.makeTwoNodeRegistry();
            lk = testCase.makeLink('L1', 'GEO_Satellite', 'A', 'B', 300, 1e9);
            lr = network.LinkRegistry(lk, nr);

            lat = lr.getEffectiveLatency('L1');
            testCase.verifyEqual(lat, 300, 'AbsTol', 1e-9, ...
                'GEO_Satellite latency above 270 ms should be stored as-is.');
        end

        % ------------------------------------------------------------------
        % Test 2: Fiber latency computed from geographic distance
        % ------------------------------------------------------------------

        function testFiberLatencyFromDistance(testCase)
            % Fiber link between A(0,0) and B(0,1): distance ~111,319 m.
            % Expected latency = 111319 / 200,000,000 * 1000 ms ≈ 0.5566 ms.
            % Requirements: 2.4
            nr = testCase.makeTwoNodeRegistry();
            lk = testCase.makeLink('L_fiber', 'Fiber', 'A', 'B', 999, 1e9);
            lr = network.LinkRegistry(lk, nr);

            % Compute expected latency from vincenty distance
            distM    = network.GeoUtils.vincenty(0, 0, 0, 1);
            expected = distM / 200000000 * 1000;   % ms

            lat = lr.getEffectiveLatency('L_fiber');
            testCase.verifyEqual(lat, expected, 'RelTol', 1e-6, ...
                'Fiber latency should equal vincenty_distance / 200000 km/s.');
        end

        function testFiberLatencyIgnoresInputLatency(testCase)
            % The nominalLatencyMs field in the link definition should be
            % ignored for Fiber links — distance is used instead.
            % Requirements: 2.4
            nr = testCase.makeTwoNodeRegistry();
            lk1 = testCase.makeLink('L1', 'Fiber', 'A', 'B', 1,    1e9);
            lk2 = testCase.makeLink('L2', 'Fiber', 'A', 'B', 9999, 1e9);
            lr1 = network.LinkRegistry(lk1, nr);
            lr2 = network.LinkRegistry(lk2, nr);

            testCase.verifyEqual(lr1.getEffectiveLatency('L1'), ...
                                 lr2.getEffectiveLatency('L2'), 'AbsTol', 1e-9, ...
                'Fiber latency should be the same regardless of input nominalLatencyMs.');
        end

        % ------------------------------------------------------------------
        % Test 3: LEO_Satellite latency used as-is
        % ------------------------------------------------------------------

        function testLEOLatencyUsedAsIs(testCase)
            % LEO link latency should be stored exactly as provided.
            % Requirements: 2.3
            nr = testCase.makeTwoNodeRegistry();
            lk = testCase.makeLink('L_leo', 'LEO_Satellite', 'A', 'B', 25, 1e9);
            lr = network.LinkRegistry(lk, nr);

            lat = lr.getEffectiveLatency('L_leo');
            testCase.verifyEqual(lat, 25, 'AbsTol', 1e-9, ...
                'LEO_Satellite latency should be stored as-is (25 ms).');
        end

        % ------------------------------------------------------------------
        % Test 4: Unknown node reference throws netsim:link:unknownNode
        % ------------------------------------------------------------------

        function testUnknownSrcNodeThrows(testCase)
            % A link referencing a non-existent source node should throw.
            % Requirements: 2.7
            nr = testCase.makeTwoNodeRegistry();
            lk = testCase.makeLink('L_bad', 'Fiber', 'NONEXISTENT', 'B', 0, 1e9);

            testCase.verifyError(@() network.LinkRegistry(lk, nr), ...
                'netsim:link:unknownNode', ...
                'Unknown srcNodeId should throw netsim:link:unknownNode.');
        end

        function testUnknownDstNodeThrows(testCase)
            % A link referencing a non-existent destination node should throw.
            % Requirements: 2.7
            nr = testCase.makeTwoNodeRegistry();
            lk = testCase.makeLink('L_bad', 'Fiber', 'A', 'NONEXISTENT', 0, 1e9);

            testCase.verifyError(@() network.LinkRegistry(lk, nr), ...
                'netsim:link:unknownNode', ...
                'Unknown dstNodeId should throw netsim:link:unknownNode.');
        end

        % ------------------------------------------------------------------
        % Test 5: setOutage / isLinkActive transitions
        % ------------------------------------------------------------------

        function testSetOutageMakesLinkInactive(testCase)
            % setOutage(id, true) should make the link inactive.
            % Requirements: 4.1
            nr = testCase.makeTwoNodeRegistry();
            lk = testCase.makeLink('L1', 'LEO_Satellite', 'A', 'B', 20, 1e9);
            lr = network.LinkRegistry(lk, nr);

            testCase.verifyTrue(lr.isLinkActive('L1'), ...
                'Link should be active initially.');

            lr.setOutage('L1', true);
            testCase.verifyFalse(lr.isLinkActive('L1'), ...
                'Link should be inactive after setOutage(true).');
        end

        function testClearOutageMakesLinkActive(testCase)
            % setOutage(id, false) should restore the link to active.
            % Requirements: 4.3
            nr = testCase.makeTwoNodeRegistry();
            lk = testCase.makeLink('L1', 'LEO_Satellite', 'A', 'B', 20, 1e9);
            lr = network.LinkRegistry(lk, nr);

            lr.setOutage('L1', true);
            lr.setOutage('L1', false);
            testCase.verifyTrue(lr.isLinkActive('L1'), ...
                'Link should be active after setOutage(false).');
        end

        % ------------------------------------------------------------------
        % Test 6: setLOSActive / isLinkActive transitions
        % ------------------------------------------------------------------

        function testSetLOSActiveFalse(testCase)
            % setLOSActive(id, false) should make the LOS link inactive.
            % Requirements: 2.5, 2.6
            nr = testCase.makeTwoNodeRegistry();
            lk = testCase.makeLink('L_los', 'Line_Of_Sight', 'A', 'B', 5, 1e8);
            lk.coverageRadiusM = 200000;
            lr = network.LinkRegistry(lk, nr);

            lr.setLOSActive('L_los', false);
            testCase.verifyFalse(lr.isLinkActive('L_los'), ...
                'LOS link should be inactive after setLOSActive(false).');
        end

        function testSetLOSActiveTrue(testCase)
            % setLOSActive(id, true) should restore the LOS link to active.
            % Requirements: 2.5
            nr = testCase.makeTwoNodeRegistry();
            lk = testCase.makeLink('L_los', 'Line_Of_Sight', 'A', 'B', 5, 1e8);
            lk.coverageRadiusM = 200000;
            lr = network.LinkRegistry(lk, nr);

            lr.setLOSActive('L_los', false);
            lr.setLOSActive('L_los', true);
            testCase.verifyTrue(lr.isLinkActive('L_los'), ...
                'LOS link should be active after setLOSActive(true).');
        end

        % ------------------------------------------------------------------
        % Test 7: refreshBackground updates effectiveBwBps and isCongested
        % ------------------------------------------------------------------

        function testRefreshBackgroundReducesBandwidth(testCase)
            % After refreshBackground, effectiveBwBps should be <= bandwidthBps.
            % Requirements: 3.2
            nr = testCase.makeTwoNodeRegistry();
            lk = testCase.makeLink('L1', 'LEO_Satellite', 'A', 'B', 20, 1e9);
            % Use uniform [0.1, 0.3] — always reduces bandwidth
            lk.backgroundTraffic = struct('distribution', 'uniform', 'min', 0.1, 'max', 0.3);
            lr = network.LinkRegistry(lk, nr);

            lr.refreshBackground('L1');
            bw = lr.getEffectiveBandwidth('L1');

            testCase.verifyLessThanOrEqual(bw, 1e9, ...
                'Effective bandwidth should be <= total bandwidth after refresh.');
            testCase.verifyGreaterThanOrEqual(bw, 0, ...
                'Effective bandwidth should be >= 0.');
        end

        function testRefreshBackgroundCongestedWhenLoadGe1(testCase)
            % When bgLoadFraction >= 1.0, the link should be congested and
            % effectiveBwBps should be 0.
            % Requirements: 3.3
            nr = testCase.makeTwoNodeRegistry();
            lk = testCase.makeLink('L1', 'LEO_Satellite', 'A', 'B', 20, 1e9);
            % Force load = 1.5 (above 1.0) using uniform [1.5, 1.5]
            lk.backgroundTraffic = struct('distribution', 'uniform', 'min', 1.5, 'max', 1.5);
            lr = network.LinkRegistry(lk, nr);

            lr.refreshBackground('L1');
            bw = lr.getEffectiveBandwidth('L1');

            testCase.verifyEqual(bw, 0, 'AbsTol', 1e-9, ...
                'Effective bandwidth should be 0 when load >= 1.0 (congested).');
        end

        % ------------------------------------------------------------------
        % Test 8: getEffectiveLatency adds congestion penalty when congested
        % ------------------------------------------------------------------

        function testEffectiveLatencyAddsPenaltyWhenCongested(testCase)
            % When congested, effective latency = nominalLatencyMs + penalty.
            % Requirements: 3.3
            nr = testCase.makeTwoNodeRegistry();
            lk = testCase.makeLink('L1', 'LEO_Satellite', 'A', 'B', 20, 1e9);
            lk.congestionPenaltyMs = 100;
            % Force congestion
            lk.backgroundTraffic = struct('distribution', 'uniform', 'min', 1.5, 'max', 1.5);
            lr = network.LinkRegistry(lk, nr);

            lr.refreshBackground('L1');
            lat = lr.getEffectiveLatency('L1');

            testCase.verifyEqual(lat, 120, 'AbsTol', 1e-9, ...
                'Effective latency should be 20 + 100 = 120 ms when congested.');
        end

        function testEffectiveLatencyNoPenaltyWhenNotCongested(testCase)
            % When not congested, effective latency = nominalLatencyMs only.
            % Requirements: 3.3
            nr = testCase.makeTwoNodeRegistry();
            lk = testCase.makeLink('L1', 'LEO_Satellite', 'A', 'B', 20, 1e9);
            lk.congestionPenaltyMs = 100;
            % Low load — not congested
            lk.backgroundTraffic = struct('distribution', 'uniform', 'min', 0.1, 'max', 0.2);
            lr = network.LinkRegistry(lk, nr);

            lr.refreshBackground('L1');
            lat = lr.getEffectiveLatency('L1');

            testCase.verifyEqual(lat, 20, 'AbsTol', 1e-9, ...
                'Effective latency should be 20 ms (no penalty) when not congested.');
        end

        % ------------------------------------------------------------------
        % Test 9: getEffectiveBandwidth returns correct value
        % ------------------------------------------------------------------

        function testInitialEffectiveBandwidthEqualsTotalBandwidth(testCase)
            % Before any refreshBackground call, bgLoadFraction = 0, so
            % effectiveBwBps should equal bandwidthBps.
            % Requirements: 3.2
            nr = testCase.makeTwoNodeRegistry();
            lk = testCase.makeLink('L1', 'GEO_Satellite', 'A', 'B', 300, 5e8);
            lr = network.LinkRegistry(lk, nr);

            bw = lr.getEffectiveBandwidth('L1');
            testCase.verifyEqual(bw, 5e8, 'AbsTol', 1, ...
                'Initial effective bandwidth should equal total bandwidth (load=0).');
        end

        % ------------------------------------------------------------------
        % Test 10: indexOf returns correct index; throws for unknown ID
        % ------------------------------------------------------------------

        function testIndexOfReturnsCorrectIndex(testCase)
            nr = testCase.makeTwoNodeRegistry();
            lk(1) = testCase.makeLink('LA', 'LEO_Satellite', 'A', 'B', 20, 1e9);
            lk(2) = testCase.makeLink('LB', 'LEO_Satellite', 'A', 'B', 25, 1e9);
            lr = network.LinkRegistry(lk, nr);

            testCase.verifyEqual(lr.indexOf('LA'), 1, 'indexOf("LA") should be 1.');
            testCase.verifyEqual(lr.indexOf('LB'), 2, 'indexOf("LB") should be 2.');
        end

        function testIndexOfThrowsForUnknownId(testCase)
            nr = testCase.makeTwoNodeRegistry();
            lk = testCase.makeLink('L1', 'LEO_Satellite', 'A', 'B', 20, 1e9);
            lr = network.LinkRegistry(lk, nr);

            testCase.verifyError(@() lr.indexOf('UNKNOWN'), ...
                'netsim:link:notFound', ...
                'indexOf should throw netsim:link:notFound for unknown ID.');
        end

        % ------------------------------------------------------------------
        % Test 11: count() returns number of links
        % ------------------------------------------------------------------

        function testCountReturnsNumberOfLinks(testCase)
            nr = testCase.makeTwoNodeRegistry();
            lk(1) = testCase.makeLink('L1', 'LEO_Satellite', 'A', 'B', 20, 1e9);
            lk(2) = testCase.makeLink('L2', 'GEO_Satellite', 'A', 'B', 300, 1e9);
            lr = network.LinkRegistry(lk, nr);

            testCase.verifyEqual(lr.count(), 2, 'count() should return 2.');
        end

    end % methods (Test)

end % classdef
