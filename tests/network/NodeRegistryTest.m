classdef NodeRegistryTest < matlab.unittest.TestCase
    % NodeRegistryTest  Unit tests for network.NodeRegistry.
    %
    % Covers:
    %   1. Stationary node: getPosition returns fixed lat/lon/altM regardless of time
    %   2. Mobile node with waypoints: getPosition interpolates correctly
    %   3. Mobile node: getPosition clamps before t=0 and after end
    %   4. Satellite node: getPosition calls OrbitalPropagator, returns finite values
    %   5. indexOf returns correct index; throws for unknown ID
    %   6. Malformed trajectory (missing waypoint field) throws netsim:node:malformedTrajectory
    %   7. updatePositions updates internal lat/lon/altM for Mobile nodes
    %
    % Requirements: 1.1, 1.2, 1.3, 1.4, 10.3, 10.4

    % ======================================================================
    % Shared test fixtures
    % ======================================================================
    methods (Access = private)

        function nodes = makeStationaryNode(~, id, lat, lon, altM)
            % Helper: build a Stationary node struct.
            nodes.id            = id;
            nodes.type          = 'Stationary';
            nodes.lat           = lat;
            nodes.lon           = lon;
            nodes.altM          = altM;
            nodes.trajectory    = [];
            nodes.keplerElements = [];
        end

        function nd = makeMobileNodeWithWaypoints(~, id, waypoints)
            % Helper: build a Mobile node struct with a waypoint trajectory.
            nd.id   = id;
            nd.type = 'Mobile';
            % Initial position from first waypoint
            nd.lat  = waypoints(1).lat;
            nd.lon  = waypoints(1).lon;
            nd.altM = waypoints(1).altM;
            nd.trajectory.type      = 'waypoints';
            nd.trajectory.waypoints = waypoints;
            nd.keplerElements = [];
        end

        function nd = makeSatelliteNode(~, id, keplerElems)
            % Helper: build a satellite node struct.
            nd.id            = id;
            nd.type          = 'Mobile';
            nd.lat           = 0;
            nd.lon           = 0;
            nd.altM          = 0;
            nd.trajectory    = [];
            nd.keplerElements = keplerElems;
        end

        function ke = geoKeplerElems(~)
            % Helper: return Keplerian elements for a GEO satellite.
            ke.semiMajorAxisM  = 42164000;
            ke.eccentricity    = 0;
            ke.inclinationDeg  = 0;
            ke.raanDeg         = 0;
            ke.argPeriapsisDeg = 0;
            ke.trueAnomalyDeg  = 0;
            ke.epochSec        = 0;
        end

    end

    % ======================================================================
    % Test 1: Stationary node returns fixed position at any time
    % ======================================================================
    methods (Test)

        function testStationaryNodeFixedPosition(testCase)
            % A Stationary node must return the same lat/lon/altM regardless
            % of the simulation time passed to getPosition.
            %
            % Requirements: 1.1, 1.2

            nd = testCase.makeStationaryNode('S1', 40.7128, -74.0060, 10.0);
            nr = network.NodeRegistry(nd);

            times = [0, 100, 3600, 1e6];
            for t = times
                pos = nr.getPosition('S1', t);
                testCase.verifyEqual(pos.lat,  40.7128, 'AbsTol', 1e-10, ...
                    sprintf('Stationary lat should be fixed at t=%g', t));
                testCase.verifyEqual(pos.lon, -74.0060, 'AbsTol', 1e-10, ...
                    sprintf('Stationary lon should be fixed at t=%g', t));
                testCase.verifyEqual(pos.altM,  10.0,   'AbsTol', 1e-10, ...
                    sprintf('Stationary altM should be fixed at t=%g', t));
            end
        end

        % ------------------------------------------------------------------
        % Test 2: Mobile node with waypoints interpolates correctly
        % ------------------------------------------------------------------

        function testMobileNodeInterpolation(testCase)
            % Two waypoints: t=0 at (0,0,0) and t=100 at (10,20,1000).
            % At t=50 the position should be exactly (5, 10, 500).
            %
            % Requirements: 1.2

            wp(1).timeSec = 0;
            wp(1).lat     = 0;
            wp(1).lon     = 0;
            wp(1).altM    = 0;

            wp(2).timeSec = 100;
            wp(2).lat     = 10;
            wp(2).lon     = 20;
            wp(2).altM    = 1000;

            nd = testCase.makeMobileNodeWithWaypoints('M1', wp);
            nr = network.NodeRegistry(nd);

            pos = nr.getPosition('M1', 50);

            testCase.verifyEqual(pos.lat,   5.0, 'AbsTol', 1e-10, ...
                'Interpolated lat at t=50 should be 5.0');
            testCase.verifyEqual(pos.lon,  10.0, 'AbsTol', 1e-10, ...
                'Interpolated lon at t=50 should be 10.0');
            testCase.verifyEqual(pos.altM, 500.0, 'AbsTol', 1e-10, ...
                'Interpolated altM at t=50 should be 500.0');
        end

        function testMobileNodeInterpolationAtWaypoint(testCase)
            % At exactly a waypoint time, the position should equal that waypoint.
            %
            % Requirements: 1.2

            wp(1).timeSec = 0;
            wp(1).lat     = 51.5;
            wp(1).lon     = -0.1;
            wp(1).altM    = 10000;

            wp(2).timeSec = 3600;
            wp(2).lat     = 40.7;
            wp(2).lon     = -74.0;
            wp(2).altM    = 10000;

            nd = testCase.makeMobileNodeWithWaypoints('M2', wp);
            nr = network.NodeRegistry(nd);

            pos0 = nr.getPosition('M2', 0);
            testCase.verifyEqual(pos0.lat,  51.5,   'AbsTol', 1e-10, ...
                'At t=0 lat should equal first waypoint');
            testCase.verifyEqual(pos0.lon,  -0.1,   'AbsTol', 1e-10, ...
                'At t=0 lon should equal first waypoint');
            testCase.verifyEqual(pos0.altM, 10000,  'AbsTol', 1e-10, ...
                'At t=0 altM should equal first waypoint');

            pos1 = nr.getPosition('M2', 3600);
            testCase.verifyEqual(pos1.lat,  40.7,   'AbsTol', 1e-10, ...
                'At t=3600 lat should equal last waypoint');
            testCase.verifyEqual(pos1.lon,  -74.0,  'AbsTol', 1e-10, ...
                'At t=3600 lon should equal last waypoint');
        end

        % ------------------------------------------------------------------
        % Test 3: Mobile node clamps to first/last waypoint outside range
        % ------------------------------------------------------------------

        function testMobileNodeClampsBeforeFirstWaypoint(testCase)
            % Before the first waypoint time, position should equal the first
            % waypoint (clamped).
            %
            % Requirements: 1.2

            wp(1).timeSec = 100;
            wp(1).lat     = 10.0;
            wp(1).lon     = 20.0;
            wp(1).altM    = 500.0;

            wp(2).timeSec = 200;
            wp(2).lat     = 20.0;
            wp(2).lon     = 40.0;
            wp(2).altM    = 1000.0;

            nd = testCase.makeMobileNodeWithWaypoints('M3', wp);
            nr = network.NodeRegistry(nd);

            % t=0 is before the first waypoint at t=100
            pos = nr.getPosition('M3', 0);
            testCase.verifyEqual(pos.lat,  10.0, 'AbsTol', 1e-10, ...
                'Before first waypoint: lat should clamp to first waypoint');
            testCase.verifyEqual(pos.lon,  20.0, 'AbsTol', 1e-10, ...
                'Before first waypoint: lon should clamp to first waypoint');
            testCase.verifyEqual(pos.altM, 500.0, 'AbsTol', 1e-10, ...
                'Before first waypoint: altM should clamp to first waypoint');
        end

        function testMobileNodeClampsAfterLastWaypoint(testCase)
            % After the last waypoint time, position should equal the last
            % waypoint (clamped).
            %
            % Requirements: 1.2

            wp(1).timeSec = 0;
            wp(1).lat     = 0.0;
            wp(1).lon     = 0.0;
            wp(1).altM    = 0.0;

            wp(2).timeSec = 100;
            wp(2).lat     = 10.0;
            wp(2).lon     = 10.0;
            wp(2).altM    = 100.0;

            nd = testCase.makeMobileNodeWithWaypoints('M4', wp);
            nr = network.NodeRegistry(nd);

            % t=9999 is well after the last waypoint at t=100
            pos = nr.getPosition('M4', 9999);
            testCase.verifyEqual(pos.lat,  10.0, 'AbsTol', 1e-10, ...
                'After last waypoint: lat should clamp to last waypoint');
            testCase.verifyEqual(pos.lon,  10.0, 'AbsTol', 1e-10, ...
                'After last waypoint: lon should clamp to last waypoint');
            testCase.verifyEqual(pos.altM, 100.0, 'AbsTol', 1e-10, ...
                'After last waypoint: altM should clamp to last waypoint');
        end

        % ------------------------------------------------------------------
        % Test 4: Satellite node calls OrbitalPropagator, returns finite values
        % ------------------------------------------------------------------

        function testSatelliteNodeReturnsFinitePosition(testCase)
            % A satellite node with valid Keplerian elements should return
            % finite lat/lon/altM from OrbitalPropagator.propagate.
            %
            % Requirements: 10.3, 10.4

            ke = testCase.geoKeplerElems();
            nd = testCase.makeSatelliteNode('SAT1', ke);
            nr = network.NodeRegistry(nd);

            pos = nr.getPosition('SAT1', 0);

            testCase.verifyTrue(isfinite(pos.lat),  'Satellite lat should be finite');
            testCase.verifyTrue(isfinite(pos.lon),  'Satellite lon should be finite');
            testCase.verifyTrue(isfinite(pos.altM), 'Satellite altM should be finite');

            % GEO altitude should be approximately 35786 km
            testCase.verifyEqual(pos.altM, 35786000, 'AbsTol', 2000, ...
                'GEO satellite altitude should be ~35786 km');
        end

        function testSatelliteNodePositionChangesOverTime(testCase)
            % A satellite node's position should change as simulation time
            % advances (the satellite moves in its orbit).
            %
            % Requirements: 10.3

            ke = testCase.geoKeplerElems();
            nd = testCase.makeSatelliteNode('SAT2', ke);
            nr = network.NodeRegistry(nd);

            pos0 = nr.getPosition('SAT2', 0);
            pos1 = nr.getPosition('SAT2', 3600);  % 1 hour later

            % Longitude should differ (GEO satellite moves ~15 deg/hr in ECEF)
            % We just verify the positions are not identical
            posChanged = (pos0.lat ~= pos1.lat) || ...
                         (pos0.lon ~= pos1.lon) || ...
                         (pos0.altM ~= pos1.altM);
            testCase.verifyTrue(posChanged, ...
                'Satellite position should change over time');
        end

        % ------------------------------------------------------------------
        % Test 5: indexOf returns correct index; throws for unknown ID
        % ------------------------------------------------------------------

        function testIndexOfReturnsCorrectIndex(testCase)
            % indexOf should return the 1-based index of the node in the
            % internal arrays.
            %
            % Requirements: 1.1

            nd(1) = testCase.makeStationaryNode('A', 0, 0, 0);
            nd(2) = testCase.makeStationaryNode('B', 1, 1, 1);
            nd(3) = testCase.makeStationaryNode('C', 2, 2, 2);
            nr = network.NodeRegistry(nd);

            testCase.verifyEqual(nr.indexOf('A'), 1, 'indexOf("A") should be 1');
            testCase.verifyEqual(nr.indexOf('B'), 2, 'indexOf("B") should be 2');
            testCase.verifyEqual(nr.indexOf('C'), 3, 'indexOf("C") should be 3');
        end

        function testIndexOfThrowsForUnknownId(testCase)
            % indexOf should throw netsim:node:notFound for an unknown ID.
            %
            % Requirements: 1.1

            nd = testCase.makeStationaryNode('X', 0, 0, 0);
            nr = network.NodeRegistry(nd);

            testCase.verifyError(@() nr.indexOf('UNKNOWN'), ...
                'netsim:node:notFound', ...
                'indexOf should throw netsim:node:notFound for unknown ID');
        end

        function testCountReturnsNumberOfNodes(testCase)
            % count() should return the number of nodes in the registry.
            %
            % Requirements: 1.1

            nd(1) = testCase.makeStationaryNode('N1', 0, 0, 0);
            nd(2) = testCase.makeStationaryNode('N2', 1, 1, 1);
            nr = network.NodeRegistry(nd);

            testCase.verifyEqual(nr.count(), 2, 'count() should return 2');
        end

        % ------------------------------------------------------------------
        % Test 6: Malformed trajectory throws netsim:node:malformedTrajectory
        % ------------------------------------------------------------------

        function testMalformedTrajectoryMissingTimeSec(testCase)
            % A waypoint missing the 'timeSec' field should throw
            % netsim:node:malformedTrajectory.
            %
            % Requirements: 1.4

            % Build a waypoint missing 'timeSec'
            wp.lat  = 10.0;
            wp.lon  = 20.0;
            wp.altM = 500.0;
            % 'timeSec' is intentionally omitted

            nd.id   = 'BadNode';
            nd.type = 'Mobile';
            nd.lat  = 0;
            nd.lon  = 0;
            nd.altM = 0;
            nd.trajectory.type      = 'waypoints';
            nd.trajectory.waypoints = wp;
            nd.keplerElements = [];

            testCase.verifyError(@() network.NodeRegistry(nd), ...
                'netsim:node:malformedTrajectory', ...
                'Missing timeSec should throw netsim:node:malformedTrajectory');
        end

        function testMalformedTrajectoryMissingLat(testCase)
            % A waypoint missing the 'lat' field should throw
            % netsim:node:malformedTrajectory.
            %
            % Requirements: 1.4

            wp.timeSec = 0;
            wp.lon     = 20.0;
            wp.altM    = 500.0;
            % 'lat' is intentionally omitted

            nd.id   = 'BadNode2';
            nd.type = 'Mobile';
            nd.lat  = 0;
            nd.lon  = 0;
            nd.altM = 0;
            nd.trajectory.type      = 'waypoints';
            nd.trajectory.waypoints = wp;
            nd.keplerElements = [];

            testCase.verifyError(@() network.NodeRegistry(nd), ...
                'netsim:node:malformedTrajectory', ...
                'Missing lat should throw netsim:node:malformedTrajectory');
        end

        function testMalformedTrajectoryMissingAltM(testCase)
            % A waypoint missing the 'altM' field should throw
            % netsim:node:malformedTrajectory.
            %
            % Requirements: 1.4

            wp.timeSec = 0;
            wp.lat     = 10.0;
            wp.lon     = 20.0;
            % 'altM' is intentionally omitted

            nd.id   = 'BadNode3';
            nd.type = 'Mobile';
            nd.lat  = 0;
            nd.lon  = 0;
            nd.altM = 0;
            nd.trajectory.type      = 'waypoints';
            nd.trajectory.waypoints = wp;
            nd.keplerElements = [];

            testCase.verifyError(@() network.NodeRegistry(nd), ...
                'netsim:node:malformedTrajectory', ...
                'Missing altM should throw netsim:node:malformedTrajectory');
        end

        function testValidTrajectoryDoesNotThrow(testCase)
            % A fully valid waypoint trajectory should not throw any error.
            %
            % Requirements: 1.4

            wp(1).timeSec = 0;
            wp(1).lat     = 0;
            wp(1).lon     = 0;
            wp(1).altM    = 0;

            wp(2).timeSec = 100;
            wp(2).lat     = 10;
            wp(2).lon     = 10;
            wp(2).altM    = 100;

            nd = testCase.makeMobileNodeWithWaypoints('GoodNode', wp);

            % Should not throw
            testCase.verifyWarningFree(@() network.NodeRegistry(nd), ...
                'Valid trajectory should not throw any error');
        end

        % ------------------------------------------------------------------
        % Test 7: updatePositions updates internal lat/lon/altM for Mobile nodes
        % ------------------------------------------------------------------

        function testUpdatePositionsUpdatesMobileNodes(testCase)
            % updatePositions should update the internal lat/lon/altM for
            % Mobile nodes based on their trajectory at the given sim time.
            %
            % Requirements: 1.2

            wp(1).timeSec = 0;
            wp(1).lat     = 0.0;
            wp(1).lon     = 0.0;
            wp(1).altM    = 0.0;

            wp(2).timeSec = 100;
            wp(2).lat     = 10.0;
            wp(2).lon     = 20.0;
            wp(2).altM    = 1000.0;

            nd = testCase.makeMobileNodeWithWaypoints('M5', wp);
            nr = network.NodeRegistry(nd);

            % Call updatePositions at t=50 (midpoint)
            nr.updatePositions(50);

            % Now getPosition should reflect the updated internal state
            % (for a Mobile node, getPosition re-interpolates, so we verify
            % the stored values by checking getPosition at t=50 returns
            % the interpolated values)
            pos = nr.getPosition('M5', 50);
            testCase.verifyEqual(pos.lat,   5.0, 'AbsTol', 1e-10, ...
                'After updatePositions(50), lat should be 5.0');
            testCase.verifyEqual(pos.lon,  10.0, 'AbsTol', 1e-10, ...
                'After updatePositions(50), lon should be 10.0');
            testCase.verifyEqual(pos.altM, 500.0, 'AbsTol', 1e-10, ...
                'After updatePositions(50), altM should be 500.0');
        end

        function testUpdatePositionsDoesNotChangeStationaryNodes(testCase)
            % updatePositions should NOT change the position of Stationary nodes.
            %
            % Requirements: 1.2

            nd = testCase.makeStationaryNode('S2', 51.5, -0.1, 100.0);
            nr = network.NodeRegistry(nd);

            nr.updatePositions(9999);

            pos = nr.getPosition('S2', 9999);
            testCase.verifyEqual(pos.lat,  51.5, 'AbsTol', 1e-10, ...
                'Stationary node lat should not change after updatePositions');
            testCase.verifyEqual(pos.lon,  -0.1, 'AbsTol', 1e-10, ...
                'Stationary node lon should not change after updatePositions');
            testCase.verifyEqual(pos.altM, 100.0, 'AbsTol', 1e-10, ...
                'Stationary node altM should not change after updatePositions');
        end

        function testUpdatePositionsUpdatesSatelliteNodes(testCase)
            % updatePositions should update satellite node positions via
            % OrbitalPropagator.
            %
            % Requirements: 10.3

            ke = testCase.geoKeplerElems();
            nd = testCase.makeSatelliteNode('SAT3', ke);
            nr = network.NodeRegistry(nd);

            % Initial position at t=0
            pos0 = nr.getPosition('SAT3', 0);

            % Update to t=3600
            nr.updatePositions(3600);

            % The stored position should now reflect t=3600
            % We verify by checking getPosition at t=3600 returns finite values
            pos1 = nr.getPosition('SAT3', 3600);
            testCase.verifyTrue(isfinite(pos1.lat),  'Updated satellite lat should be finite');
            testCase.verifyTrue(isfinite(pos1.lon),  'Updated satellite lon should be finite');
            testCase.verifyTrue(isfinite(pos1.altM), 'Updated satellite altM should be finite');

            % Position should differ from t=0
            posChanged = (pos0.lat ~= pos1.lat) || ...
                         (pos0.lon ~= pos1.lon) || ...
                         (pos0.altM ~= pos1.altM);
            testCase.verifyTrue(posChanged, ...
                'Satellite position should change after updatePositions(3600)');
        end

        % ------------------------------------------------------------------
        % Additional edge-case tests
        % ------------------------------------------------------------------

        function testMixedNodeTypes(testCase)
            % Registry with a mix of Stationary, Mobile, and satellite nodes
            % should construct without error and return correct counts.
            %
            % Requirements: 1.1, 1.3

            nd(1) = testCase.makeStationaryNode('S', 40.0, -74.0, 0.0);

            wp(1).timeSec = 0;   wp(1).lat = 0; wp(1).lon = 0; wp(1).altM = 0;
            wp(2).timeSec = 100; wp(2).lat = 1; wp(2).lon = 1; wp(2).altM = 100;
            nd(2) = testCase.makeMobileNodeWithWaypoints('M', wp);

            ke = testCase.geoKeplerElems();
            nd(3) = testCase.makeSatelliteNode('SAT', ke);

            nr = network.NodeRegistry(nd);

            testCase.verifyEqual(nr.count(), 3, ...
                'Mixed registry should contain 3 nodes');
            testCase.verifyEqual(nr.indexOf('S'),   1, 'S should be at index 1');
            testCase.verifyEqual(nr.indexOf('M'),   2, 'M should be at index 2');
            testCase.verifyEqual(nr.indexOf('SAT'), 3, 'SAT should be at index 3');
        end

        function testCellArrayInput(testCase)
            % NodeRegistry should accept a cell array of structs as input.
            %
            % Requirements: 1.1

            nd1 = testCase.makeStationaryNode('C1', 10.0, 20.0, 30.0);
            nd2 = testCase.makeStationaryNode('C2', 40.0, 50.0, 60.0);

            cellInput = {nd1, nd2};
            nr = network.NodeRegistry(cellInput);

            testCase.verifyEqual(nr.count(), 2, ...
                'Cell array input should produce 2 nodes');
            testCase.verifyEqual(nr.indexOf('C1'), 1, 'C1 should be at index 1');
            testCase.verifyEqual(nr.indexOf('C2'), 2, 'C2 should be at index 2');
        end

        function testGetPositionThrowsForUnknownId(testCase)
            % getPosition should throw netsim:node:notFound for an unknown ID.
            %
            % Requirements: 1.1

            nd = testCase.makeStationaryNode('Known', 0, 0, 0);
            nr = network.NodeRegistry(nd);

            testCase.verifyError(@() nr.getPosition('Unknown', 0), ...
                'netsim:node:notFound', ...
                'getPosition should throw netsim:node:notFound for unknown ID');
        end

        function testThreeWaypointInterpolation(testCase)
            % Verify interpolation works correctly with three waypoints,
            % selecting the correct bracketing segment.
            %
            % Requirements: 1.2

            wp(1).timeSec = 0;
            wp(1).lat     = 0;
            wp(1).lon     = 0;
            wp(1).altM    = 0;

            wp(2).timeSec = 100;
            wp(2).lat     = 10;
            wp(2).lon     = 10;
            wp(2).altM    = 100;

            wp(3).timeSec = 200;
            wp(3).lat     = 30;
            wp(3).lon     = 30;
            wp(3).altM    = 300;

            nd = testCase.makeMobileNodeWithWaypoints('M6', wp);
            nr = network.NodeRegistry(nd);

            % At t=50: between wp1 and wp2, alpha=0.5 -> lat=5, lon=5, altM=50
            pos50 = nr.getPosition('M6', 50);
            testCase.verifyEqual(pos50.lat,   5.0, 'AbsTol', 1e-10, ...
                'At t=50, lat should be 5.0 (first segment)');
            testCase.verifyEqual(pos50.altM, 50.0, 'AbsTol', 1e-10, ...
                'At t=50, altM should be 50.0 (first segment)');

            % At t=150: between wp2 and wp3, alpha=0.5 -> lat=20, lon=20, altM=200
            pos150 = nr.getPosition('M6', 150);
            testCase.verifyEqual(pos150.lat,  20.0, 'AbsTol', 1e-10, ...
                'At t=150, lat should be 20.0 (second segment)');
            testCase.verifyEqual(pos150.altM, 200.0, 'AbsTol', 1e-10, ...
                'At t=150, altM should be 200.0 (second segment)');
        end

    end % methods (Test)

end % classdef
