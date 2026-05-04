classdef GeoUtilsTest < matlab.unittest.TestCase
    % GeoUtilsTest  Unit tests for network.GeoUtils.
    %
    % Covers:
    %   - vincenty: same-point returns 0
    %   - vincenty: known equatorial distance (1 degree longitude at equator)
    %   - vincenty: known polar distance (1 degree latitude near pole)
    %   - isLOSVisible: returns true when within range and altitude
    %   - isLOSVisible: returns false when beyond coverage radius
    %   - isLOSVisible: returns false when beyond radio horizon
    %
    % Requirements: 10.1, 10.2

    methods (Test)

        % -----------------------------------------------------------------
        % vincenty tests
        % -----------------------------------------------------------------

        function testSamePointReturnsZero(testCase)
            % Identical coordinates must return exactly 0 m.
            dist = network.GeoUtils.vincenty(40.0, -74.0, 40.0, -74.0);
            testCase.verifyEqual(dist, 0, ...
                'vincenty should return 0 for identical points.');
        end

        function testSamePointAtOriginReturnsZero(testCase)
            % Degenerate case at (0, 0).
            dist = network.GeoUtils.vincenty(0.0, 0.0, 0.0, 0.0);
            testCase.verifyEqual(dist, 0, ...
                'vincenty should return 0 for identical points at origin.');
        end

        function testEquatorialOneDegreeOfLongitude(testCase)
            % 1 degree of longitude at the equator.
            % Reference: 2*pi*a/360 where a = 6378137.0 m (WGS-84 semi-major axis)
            % = 111319.49... m
            % Tolerance: 0.1% per Requirement 10.1
            a = 6378137.0;
            expected = 2 * pi * a / 360;   % ~111319.49 m
            dist = network.GeoUtils.vincenty(0.0, 0.0, 0.0, 1.0);
            testCase.verifyEqual(dist, expected, 'RelTol', 0.001, ...
                'Equatorial 1-degree longitude distance should be ~111319 m (±0.1%).');
        end

        function testEquatorialOneDegreeOfLatitude(testCase)
            % 1 degree of latitude along the prime meridian near the equator.
            % At the equator the meridional arc for 1 degree is approximately
            % 110574 m on WGS-84 (slightly shorter than the equatorial degree).
            % We verify within 0.1% of the accepted value.
            expected = 110574.0;   % metres (standard reference value)
            dist = network.GeoUtils.vincenty(0.0, 0.0, 1.0, 0.0);
            testCase.verifyEqual(dist, expected, 'RelTol', 0.001, ...
                '1-degree latitude arc near equator should be ~110574 m (±0.1%).');
        end

        function testKnownPolarDistance(testCase)
            % Distance from the North Pole to 89 N along the prime meridian.
            % 1 degree of latitude near the pole ≈ 111694 m on WGS-84.
            expected = 111694.0;   % metres (standard reference value)
            dist = network.GeoUtils.vincenty(90.0, 0.0, 89.0, 0.0);
            testCase.verifyEqual(dist, expected, 'RelTol', 0.001, ...
                '1-degree latitude arc near the pole should be ~111694 m (±0.1%).');
        end

        function testSymmetry(testCase)
            % vincenty(A, B) should equal vincenty(B, A).
            d1 = network.GeoUtils.vincenty(51.5, -0.1, 40.7, -74.0);
            d2 = network.GeoUtils.vincenty(40.7, -74.0, 51.5, -0.1);
            testCase.verifyEqual(d1, d2, 'RelTol', 1e-9, ...
                'vincenty should be symmetric.');
        end

        function testLondonToNewYorkApproximate(testCase)
            % London (51.5074 N, 0.1278 W) to New York (40.7128 N, 74.0060 W).
            % Known geodesic distance ≈ 5,570,538 m.
            expected = 5570538;
            dist = network.GeoUtils.vincenty(51.5074, -0.1278, 40.7128, -74.0060);
            testCase.verifyEqual(dist, expected, 'RelTol', 0.001, ...
                'London-to-New-York distance should be ~5,570,538 m (±0.1%).');
        end

        % -----------------------------------------------------------------
        % isLOSVisible tests
        % -----------------------------------------------------------------

        function testLOSVisibleWithinRangeAndAltitude(testCase)
            % Mobile at 10,000 m altitude, 50 km from station.
            % Radio horizon = sqrt(2 * 6371000 * 10000) ≈ 356,936 m >> 50 km.
            % Coverage radius = 200 km >> 50 km.  Should be visible.
            stationLat = 0.0;
            stationLon = 0.0;
            % ~50 km north of station
            mobileLat  = 0.45;   % ~50 km at equator
            mobileLon  = 0.0;
            mobileAlt  = 10000;  % 10 km altitude
            coverageR  = 200000; % 200 km

            tf = network.GeoUtils.isLOSVisible( ...
                mobileLat, mobileLon, mobileAlt, ...
                stationLat, stationLon, coverageR);
            testCase.verifyTrue(tf, ...
                'Mobile within coverage radius and above horizon should be visible.');
        end

        function testLOSNotVisibleBeyondCoverageRadius(testCase)
            % Mobile at 10,000 m altitude but 500 km from station.
            % Coverage radius = 200 km.  Should NOT be visible.
            stationLat = 0.0;
            stationLon = 0.0;
            % ~500 km east of station
            mobileLat  = 0.0;
            mobileLon  = 4.5;    % ~500 km at equator
            mobileAlt  = 10000;  % 10 km altitude
            coverageR  = 200000; % 200 km

            tf = network.GeoUtils.isLOSVisible( ...
                mobileLat, mobileLon, mobileAlt, ...
                stationLat, stationLon, coverageR);
            testCase.verifyFalse(tf, ...
                'Mobile beyond coverage radius should not be visible.');
        end

        function testLOSNotVisibleBeyondRadioHorizon(testCase)
            % Mobile at very low altitude (100 m) but 100 km from station.
            % Radio horizon = sqrt(2 * 6371000 * 100) ≈ 35,693 m ≈ 35.7 km.
            % Geodesic distance ~100 km > 35.7 km horizon.
            % Coverage radius = 500 km (large, so coverage is not the constraint).
            stationLat = 0.0;
            stationLon = 0.0;
            % ~100 km east of station
            mobileLat  = 0.0;
            mobileLon  = 0.9;    % ~100 km at equator
            mobileAlt  = 100;    % 100 m altitude
            coverageR  = 500000; % 500 km (not the limiting factor)

            tf = network.GeoUtils.isLOSVisible( ...
                mobileLat, mobileLon, mobileAlt, ...
                stationLat, stationLon, coverageR);
            testCase.verifyFalse(tf, ...
                'Mobile beyond radio horizon should not be visible despite large coverage radius.');
        end

        function testLOSNotVisibleAtZeroAltitude(testCase)
            % Mobile at 0 m altitude: horizon distance = 0, so never visible
            % unless co-located with station.
            stationLat = 0.0;
            stationLon = 0.0;
            mobileLat  = 0.0;
            mobileLon  = 0.1;    % ~11 km away
            mobileAlt  = 0;
            coverageR  = 500000;

            tf = network.GeoUtils.isLOSVisible( ...
                mobileLat, mobileLon, mobileAlt, ...
                stationLat, stationLon, coverageR);
            testCase.verifyFalse(tf, ...
                'Mobile at zero altitude should not be visible (horizon = 0).');
        end

    end

end
