classdef RoutingEngineTest < matlab.unittest.TestCase
    % RoutingEngineTest  Unit tests for network.RoutingEngine.
    %
    % Covers:
    %   1. Simple 2-node, 1-link topology: selectPath returns correct path and latency
    %   2. No path (all links in outage): selectPath returns {} and Inf
    %   3. Two parallel paths: selectPath returns the lower-latency path
    %   4. invalidateCache removes outage link from routing
    %   5. invalidateCache restores link when outage ends
    %   6. rebuildGraph reconstructs from current active links
    %   7. Three-node chain: selectPath returns multi-hop path with summed latency
    %
    % Requirements: 5.2, 5.3, 5.5, 6.1, 6.2, 6.3, 6.4, 6.5

    % ======================================================================
    % Shared helpers
    % ======================================================================
    methods (Access = private)

        function nr = makeNodeRegistry(~, nodeIds)
            % Build a NodeRegistry from a cell array of node ID strings.
            % All nodes are stationary at (0, 0, 0).
            nNodes = numel(nodeIds);
            nd = repmat(struct(), nNodes, 1);
            for k = 1:nNodes
                nd(k).id             = nodeIds{k};
                nd(k).type           = 'Stationary';
                nd(k).lat            = 0;
                nd(k).lon            = 0;
                nd(k).altM           = 0;
                nd(k).trajectory     = [];
                nd(k).keplerElements = [];
            end
            nr = network.NodeRegistry(nd);
        end

        function lk = makeLink(~, id, srcId, dstId, latencyMs)
            % Build a minimal LEO_Satellite link definition struct.
            lk.id               = id;
            lk.type             = 'LEO_Satellite';
            lk.srcNodeId        = srcId;
            lk.dstNodeId        = dstId;
            lk.nominalLatencyMs = latencyMs;
            lk.bandwidthBps     = 1e9;
            lk.outageRate       = 0;
            lk.outageDuration   = struct('distribution', 'exponential', 'mean', 60);
            lk.backgroundTraffic = struct('distribution', 'uniform', 'min', 0, 'max', 0);
            lk.coverageRadiusM  = NaN;
            lk.congestionPenaltyMs = 0;
        end

    end

    % ======================================================================
    % Tests
    % ======================================================================
    methods (Test)

        % ------------------------------------------------------------------
        % Test 1: Simple 2-node, 1-link topology
        % ------------------------------------------------------------------

        function testSimpleTwoNodeOneLinkPath(testCase)
            % A → B with 50 ms latency.
            % selectPath('A','B') should return path={'A','B'} and latency=50.
            % Requirements: 5.2, 5.3, 6.2
            nr = testCase.makeNodeRegistry({'A', 'B'});
            lk = testCase.makeLink('L1', 'A', 'B', 50);
            lr = network.LinkRegistry(lk, nr);
            re = network.RoutingEngine(nr, lr);

            [path, latency] = re.selectPath('A', 'B', 0);

            testCase.verifyEqual(numel(path), 2, ...
                'Path should contain 2 nodes (A and B).');
            testCase.verifyEqual(string(path{1}), "A", ...
                'First node in path should be A.');
            testCase.verifyEqual(string(path{2}), "B", ...
                'Last node in path should be B.');
            testCase.verifyEqual(latency, 50, 'AbsTol', 1e-9, ...
                'Total latency should be 50 ms.');
        end

        function testSimpleTwoNodeOneLinkPathReverse(testCase)
            % A → B link; selectPath('B','A') should return {} and Inf
            % because the graph is directed.
            % Requirements: 5.5, 6.1
            nr = testCase.makeNodeRegistry({'A', 'B'});
            lk = testCase.makeLink('L1', 'A', 'B', 50);
            lr = network.LinkRegistry(lk, nr);
            re = network.RoutingEngine(nr, lr);

            [path, latency] = re.selectPath('B', 'A', 0);

            testCase.verifyEmpty(path, ...
                'No reverse path should exist for a directed link A→B.');
            testCase.verifyEqual(latency, Inf, ...
                'Latency should be Inf when no path exists.');
        end

        % ------------------------------------------------------------------
        % Test 2: No path (all links in outage)
        % ------------------------------------------------------------------

        function testNoPathWhenAllLinksInOutage(testCase)
            % A → B link put into outage; selectPath should return {} and Inf.
            % Requirements: 5.5, 6.1
            nr = testCase.makeNodeRegistry({'A', 'B'});
            lk = testCase.makeLink('L1', 'A', 'B', 30);
            lr = network.LinkRegistry(lk, nr);
            re = network.RoutingEngine(nr, lr);

            % Put the link into outage
            lr.setOutage('L1', true);
            re.invalidateCache('L1');

            [path, latency] = re.selectPath('A', 'B', 0);

            testCase.verifyEmpty(path, ...
                'Path should be empty when the only link is in outage.');
            testCase.verifyEqual(latency, Inf, ...
                'Latency should be Inf when no active path exists.');
        end

        % ------------------------------------------------------------------
        % Test 3: Two parallel paths — select lower-latency path
        % ------------------------------------------------------------------

        function testTwoParallelPathsSelectsLowerLatency(testCase)
            % A → B via L1 (100 ms) and A → B via L2 (40 ms).
            % selectPath should choose L2 (40 ms).
            % Requirements: 5.2, 6.2
            nr = testCase.makeNodeRegistry({'A', 'B'});
            lk(1) = testCase.makeLink('L1', 'A', 'B', 100);
            lk(2) = testCase.makeLink('L2', 'A', 'B', 40);
            lr = network.LinkRegistry(lk, nr);
            re = network.RoutingEngine(nr, lr);

            [path, latency] = re.selectPath('A', 'B', 0);

            testCase.verifyEqual(latency, 40, 'AbsTol', 1e-9, ...
                'Should select the lower-latency path (40 ms, not 100 ms).');
            testCase.verifyEqual(numel(path), 2, ...
                'Path should contain 2 nodes.');
        end

        function testTwoParallelPathsSelectsLowerLatencyReversed(testCase)
            % Same as above but link order reversed to ensure it's not
            % just picking the first edge.
            % Requirements: 5.2, 6.2
            nr = testCase.makeNodeRegistry({'A', 'B'});
            lk(1) = testCase.makeLink('L1', 'A', 'B', 40);
            lk(2) = testCase.makeLink('L2', 'A', 'B', 100);
            lr = network.LinkRegistry(lk, nr);
            re = network.RoutingEngine(nr, lr);

            [~, latency] = re.selectPath('A', 'B', 0);

            testCase.verifyEqual(latency, 40, 'AbsTol', 1e-9, ...
                'Should select the lower-latency path (40 ms).');
        end

        % ------------------------------------------------------------------
        % Test 4: invalidateCache removes outage link from routing
        % ------------------------------------------------------------------

        function testInvalidateCacheRemovesOutageLink(testCase)
            % A → B via L1 (20 ms) and A → B via L2 (80 ms).
            % Put L1 into outage; routing should fall back to L2 (80 ms).
            % Requirements: 6.1, 6.3
            nr = testCase.makeNodeRegistry({'A', 'B'});
            lk(1) = testCase.makeLink('L1', 'A', 'B', 20);
            lk(2) = testCase.makeLink('L2', 'A', 'B', 80);
            lr = network.LinkRegistry(lk, nr);
            re = network.RoutingEngine(nr, lr);

            % Verify initial routing uses L1 (20 ms)
            [~, latencyBefore] = re.selectPath('A', 'B', 0);
            testCase.verifyEqual(latencyBefore, 20, 'AbsTol', 1e-9, ...
                'Before outage, should use 20 ms path.');

            % Put L1 into outage and invalidate cache
            lr.setOutage('L1', true);
            re.invalidateCache('L1');

            % Now routing should use L2 (80 ms)
            [path, latency] = re.selectPath('A', 'B', 0);

            testCase.verifyFalse(isempty(path), ...
                'A path should still exist via L2.');
            testCase.verifyEqual(latency, 80, 'AbsTol', 1e-9, ...
                'After L1 outage, should fall back to 80 ms path via L2.');
        end

        function testInvalidateCacheAllLinksOutageNoPath(testCase)
            % A → B via L1 only; put L1 into outage; no path should exist.
            % Requirements: 6.1, 6.3
            nr = testCase.makeNodeRegistry({'A', 'B'});
            lk = testCase.makeLink('L1', 'A', 'B', 20);
            lr = network.LinkRegistry(lk, nr);
            re = network.RoutingEngine(nr, lr);

            lr.setOutage('L1', true);
            re.invalidateCache('L1');

            [path, latency] = re.selectPath('A', 'B', 0);

            testCase.verifyEmpty(path, ...
                'No path should exist after the only link enters outage.');
            testCase.verifyEqual(latency, Inf, ...
                'Latency should be Inf with no active path.');
        end

        % ------------------------------------------------------------------
        % Test 5: invalidateCache restores link when outage ends
        % ------------------------------------------------------------------

        function testInvalidateCacheRestoresLinkAfterOutage(testCase)
            % A → B via L1; put into outage, then restore.
            % After restoration, routing should work again.
            % Requirements: 6.1, 6.3
            nr = testCase.makeNodeRegistry({'A', 'B'});
            lk = testCase.makeLink('L1', 'A', 'B', 35);
            lr = network.LinkRegistry(lk, nr);
            re = network.RoutingEngine(nr, lr);

            % Put into outage
            lr.setOutage('L1', true);
            re.invalidateCache('L1');

            [pathDuring, latencyDuring] = re.selectPath('A', 'B', 0);
            testCase.verifyEmpty(pathDuring, 'No path during outage.');
            testCase.verifyEqual(latencyDuring, Inf, 'Inf latency during outage.');

            % Restore link
            lr.setOutage('L1', false);
            re.invalidateCache('L1');

            [pathAfter, latencyAfter] = re.selectPath('A', 'B', 0);

            testCase.verifyFalse(isempty(pathAfter), ...
                'Path should be restored after outage ends.');
            testCase.verifyEqual(latencyAfter, 35, 'AbsTol', 1e-9, ...
                'Latency should be 35 ms after link is restored.');
        end

        % ------------------------------------------------------------------
        % Test 6: rebuildGraph reconstructs from current active links
        % ------------------------------------------------------------------

        function testRebuildGraphReconstructsActiveLinks(testCase)
            % A → B via L1 (10 ms) and A → B via L2 (60 ms).
            % Put L1 into outage (without invalidateCache), then call
            % rebuildGraph; routing should use L2 (60 ms).
            % Requirements: 6.1, 6.2
            nr = testCase.makeNodeRegistry({'A', 'B'});
            lk(1) = testCase.makeLink('L1', 'A', 'B', 10);
            lk(2) = testCase.makeLink('L2', 'A', 'B', 60);
            lr = network.LinkRegistry(lk, nr);
            re = network.RoutingEngine(nr, lr);

            % Verify initial routing uses L1 (10 ms)
            [~, latencyBefore] = re.selectPath('A', 'B', 0);
            testCase.verifyEqual(latencyBefore, 10, 'AbsTol', 1e-9, ...
                'Before rebuild, should use 10 ms path.');

            % Put L1 into outage and do a full rebuild
            lr.setOutage('L1', true);
            re.rebuildGraph();

            [path, latency] = re.selectPath('A', 'B', 0);

            testCase.verifyFalse(isempty(path), ...
                'Path should exist via L2 after rebuild.');
            testCase.verifyEqual(latency, 60, 'AbsTol', 1e-9, ...
                'After rebuild with L1 in outage, should use 60 ms path via L2.');
        end

        function testRebuildGraphWithNoActiveLinksReturnsNoPath(testCase)
            % All links in outage; rebuildGraph; no path should exist.
            % Requirements: 5.5, 6.1
            nr = testCase.makeNodeRegistry({'A', 'B'});
            lk = testCase.makeLink('L1', 'A', 'B', 10);
            lr = network.LinkRegistry(lk, nr);
            re = network.RoutingEngine(nr, lr);

            lr.setOutage('L1', true);
            re.rebuildGraph();

            [path, latency] = re.selectPath('A', 'B', 0);

            testCase.verifyEmpty(path, ...
                'No path should exist after rebuild with all links in outage.');
            testCase.verifyEqual(latency, Inf, ...
                'Latency should be Inf after rebuild with no active links.');
        end

        % ------------------------------------------------------------------
        % Test 7: Three-node chain — multi-hop path with summed latency
        % ------------------------------------------------------------------

        function testThreeNodeChainMultiHop(testCase)
            % A → B (20 ms) → C (30 ms).
            % selectPath('A','C') should return path={'A','B','C'} and latency=50.
            % Requirements: 5.2, 5.3, 6.2
            nr = testCase.makeNodeRegistry({'A', 'B', 'C'});
            lk(1) = testCase.makeLink('L_AB', 'A', 'B', 20);
            lk(2) = testCase.makeLink('L_BC', 'B', 'C', 30);
            lr = network.LinkRegistry(lk, nr);
            re = network.RoutingEngine(nr, lr);

            [path, latency] = re.selectPath('A', 'C', 0);

            testCase.verifyEqual(numel(path), 3, ...
                'Path should contain 3 nodes (A, B, C).');
            testCase.verifyEqual(string(path{1}), "A", ...
                'First node should be A.');
            testCase.verifyEqual(string(path{2}), "B", ...
                'Middle node should be B.');
            testCase.verifyEqual(string(path{3}), "C", ...
                'Last node should be C.');
            testCase.verifyEqual(latency, 50, 'AbsTol', 1e-9, ...
                'Total latency should be 20 + 30 = 50 ms.');
        end

        function testThreeNodeChainSelectsShortestMultiHop(testCase)
            % A → B (10 ms) → C (10 ms) vs A → C direct (100 ms).
            % selectPath('A','C') should prefer the direct link (100 ms)
            % only if it's shorter — here multi-hop (20 ms) wins.
            % Requirements: 5.2, 6.2
            nr = testCase.makeNodeRegistry({'A', 'B', 'C'});
            lk(1) = testCase.makeLink('L_AB',  'A', 'B', 10);
            lk(2) = testCase.makeLink('L_BC',  'B', 'C', 10);
            lk(3) = testCase.makeLink('L_AC',  'A', 'C', 100);
            lr = network.LinkRegistry(lk, nr);
            re = network.RoutingEngine(nr, lr);

            [~, latency] = re.selectPath('A', 'C', 0);

            testCase.verifyEqual(latency, 20, 'AbsTol', 1e-9, ...
                'Should select multi-hop path (20 ms) over direct link (100 ms).');
        end

        function testThreeNodeChainNoPathWhenMiddleLinkInOutage(testCase)
            % A → B → C; put L_BC into outage; no path from A to C.
            % Requirements: 5.5, 6.1
            nr = testCase.makeNodeRegistry({'A', 'B', 'C'});
            lk(1) = testCase.makeLink('L_AB', 'A', 'B', 20);
            lk(2) = testCase.makeLink('L_BC', 'B', 'C', 30);
            lr = network.LinkRegistry(lk, nr);
            re = network.RoutingEngine(nr, lr);

            lr.setOutage('L_BC', true);
            re.invalidateCache('L_BC');

            [path, latency] = re.selectPath('A', 'C', 0);

            testCase.verifyEmpty(path, ...
                'No path from A to C when L_BC is in outage.');
            testCase.verifyEqual(latency, Inf, ...
                'Latency should be Inf when no path exists.');
        end

        % ------------------------------------------------------------------
        % Additional: unknown node returns empty path
        % ------------------------------------------------------------------

        function testUnknownNodeReturnsEmptyPath(testCase)
            % selectPath with a node ID not in the registry should return
            % {} and Inf gracefully.
            % Requirements: 5.5
            nr = testCase.makeNodeRegistry({'A', 'B'});
            lk = testCase.makeLink('L1', 'A', 'B', 10);
            lr = network.LinkRegistry(lk, nr);
            re = network.RoutingEngine(nr, lr);

            [path, latency] = re.selectPath('A', 'UNKNOWN', 0);

            testCase.verifyEmpty(path, ...
                'Path should be empty for unknown destination node.');
            testCase.verifyEqual(latency, Inf, ...
                'Latency should be Inf for unknown destination node.');
        end

        % ------------------------------------------------------------------
        % Additional: simTimeSec parameter is accepted (ignored for static topo)
        % ------------------------------------------------------------------

        function testSelectPathAcceptsSimTimeSec(testCase)
            % Verify that passing a non-zero simTimeSec does not cause errors.
            % Requirements: 5.2
            nr = testCase.makeNodeRegistry({'A', 'B'});
            lk = testCase.makeLink('L1', 'A', 'B', 15);
            lr = network.LinkRegistry(lk, nr);
            re = network.RoutingEngine(nr, lr);

            [path, latency] = re.selectPath('A', 'B', 3600);

            testCase.verifyFalse(isempty(path), ...
                'Path should exist regardless of simTimeSec value.');
            testCase.verifyEqual(latency, 15, 'AbsTol', 1e-9, ...
                'Latency should be 15 ms.');
        end

    end % methods (Test)

end % classdef
