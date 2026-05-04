classdef OrbitalPropagatorTest < matlab.unittest.TestCase
    % OrbitalPropagatorTest  Unit tests for network.OrbitalPropagator.
    %
    % Covers:
    %   - GEO orbit altitude check: propagate at t=0 should return ~35786 km
    %   - Circular orbit period: propagate at t=T should return same position
    %   - Equatorial circular orbit: lat ≈ 0 at t=0 for equatorial orbit
    %
    % Requirements: 10.3, 10.4

    methods (Test)

        % -----------------------------------------------------------------
        % Test 1: GEO orbit altitude check
        % -----------------------------------------------------------------

        function testGEOAltitude(testCase)
            % A satellite at GEO semi-major axis (42164 km) with zero
            % eccentricity should be at approximately 35786 km altitude
            % above the WGS-84 ellipsoid.
            %
            % GEO altitude = a - R_earth ≈ 42164000 - 6378137 ≈ 35785863 m
            % Tolerance: ±1000 m as specified in the task.

            elems.semiMajorAxisM   = 42164000;   % GEO semi-major axis (m)
            elems.eccentricity     = 0;
            elems.inclinationDeg   = 0;
            elems.raanDeg          = 0;
            elems.argPeriapsisDeg  = 0;
            elems.trueAnomalyDeg   = 0;
            elems.epochSec         = 0;

            [~, ~, altM] = network.OrbitalPropagator.propagate(elems, 0, 0);

            expectedAlt = 35786000;   % metres (nominal GEO altitude)
            testCase.verifyEqual(altM, expectedAlt, 'AbsTol', 1000, ...
                sprintf('GEO altitude should be ~35786 km (±1000 m), got %.1f m.', altM));
        end

        % -----------------------------------------------------------------
        % Test 2: Circular orbit period round-trip (LEO at 400 km)
        % -----------------------------------------------------------------

        function testCircularOrbitPeriod(testCase)
            % A circular LEO orbit at 400 km altitude.
            % After exactly one orbital period T = 2*pi*sqrt(a^3/mu),
            % the satellite should return to within 1 km of its initial
            % orbital position (ECI frame).
            %
            % Note: geodetic lat/lon will differ because Earth rotates during
            % the period, but the orbital radius and altitude must be the same,
            % and the ECI position vector must be within 1 km of the start.

            mu = 3.986004418e14;   % Earth gravitational parameter (m^3/s^2)
            R_earth = 6378137.0;   % WGS-84 semi-major axis (m)
            altKm   = 400e3;       % 400 km altitude (m)
            a       = R_earth + altKm;   % semi-major axis (m)

            % Orbital period
            T = 2 * pi * sqrt(a^3 / mu);   % seconds

            elems.semiMajorAxisM   = a;
            elems.eccentricity     = 0;
            elems.inclinationDeg   = 51.6;   % ISS-like inclination
            elems.raanDeg          = 45;
            elems.argPeriapsisDeg  = 0;
            elems.trueAnomalyDeg   = 0;
            elems.epochSec         = 0;

            % Position at t=0
            [lat0, lon0, alt0] = network.OrbitalPropagator.propagate(elems, 0, 0);

            % Position at t=T (one full period)
            [lat1, lon1, alt1] = network.OrbitalPropagator.propagate(elems, 0, T);

            % The altitude (orbital radius) must be the same for a circular orbit.
            testCase.verifyEqual(alt1, alt0, 'AbsTol', 1000, ...
                sprintf(['After one orbital period, altitude should match start. ' ...
                         'alt0=%.1f m, alt1=%.1f m.'], alt0, alt1));

            % Convert geodetic back to ECI to compare orbital positions.
            % At t=0 and t=T the satellite is at the same ECI position.
            % We undo the GMST rotation to get ECI from ECEF.
            eci0 = network.OrbitalPropagatorTest.geodetic2eci(lat0, lon0, alt0, 0);
            eci1 = network.OrbitalPropagatorTest.geodetic2eci(lat1, lon1, alt1, T);

            dist3D = norm(eci1 - eci0);

            testCase.verifyLessThan(dist3D, 1000, ...
                sprintf(['After one orbital period, ECI position should be ' ...
                         'within 1 km of start. Distance: %.2f m.'], dist3D));
        end

        % -----------------------------------------------------------------
        % Test 3: Equatorial circular orbit — latitude ≈ 0 at t=0
        % -----------------------------------------------------------------

        function testEquatorialOrbitLatitude(testCase)
            % An equatorial circular orbit (inclination=0, RAAN=0,
            % argPeriapsis=0, trueAnomaly=0) should place the satellite
            % on the equator (lat ≈ 0 degrees) at t=0.
            % Tolerance: ±0.01 degrees as specified in the task.

            R_earth = 6378137.0;
            a       = R_earth + 500e3;   % 500 km altitude

            elems.semiMajorAxisM   = a;
            elems.eccentricity     = 0;
            elems.inclinationDeg   = 0;
            elems.raanDeg          = 0;
            elems.argPeriapsisDeg  = 0;
            elems.trueAnomalyDeg   = 0;
            elems.epochSec         = 0;

            [lat, ~, ~] = network.OrbitalPropagator.propagate(elems, 0, 0);

            testCase.verifyEqual(lat, 0, 'AbsTol', 0.01, ...
                sprintf(['Equatorial orbit at t=0 should have lat ≈ 0 degrees ' ...
                         '(±0.01 deg), got %.6f deg.'], lat));
        end

        % -----------------------------------------------------------------
        % Test 4: Eccentric orbit — Kepler's equation convergence
        % -----------------------------------------------------------------

        function testEccentricOrbitConverges(testCase)
            % Verify that propagation completes without error for a
            % moderately eccentric orbit (e=0.3) and returns finite values.

            elems.semiMajorAxisM   = 8000e3;   % 8000 km semi-major axis
            elems.eccentricity     = 0.3;
            elems.inclinationDeg   = 28.5;
            elems.raanDeg          = 90;
            elems.argPeriapsisDeg  = 45;
            elems.trueAnomalyDeg   = 120;
            elems.epochSec         = 0;

            [lat, lon, altM] = network.OrbitalPropagator.propagate(elems, 0, 1000);

            testCase.verifyTrue(isfinite(lat),  'lat should be finite.');
            testCase.verifyTrue(isfinite(lon),  'lon should be finite.');
            testCase.verifyTrue(isfinite(altM), 'altM should be finite.');
            testCase.verifyGreaterThan(altM, 0, 'altM should be positive.');
            testCase.verifyGreaterThanOrEqual(lat, -90, 'lat >= -90 deg.');
            testCase.verifyLessThanOrEqual(lat,    90, 'lat <= 90 deg.');
            testCase.verifyGreaterThanOrEqual(lon, -180, 'lon >= -180 deg.');
            testCase.verifyLessThanOrEqual(lon,    180, 'lon <= 180 deg.');
        end

        % -----------------------------------------------------------------
        % Test 5: Non-zero epoch — elapsed time computed correctly
        % -----------------------------------------------------------------

        function testNonZeroEpoch(testCase)
            % Propagating from a non-zero epoch should give the same result
            % as propagating from epoch=0 with the same elapsed time.

            mu = 3.986004418e14;
            R_earth = 6378137.0;
            a = R_earth + 600e3;

            elems.semiMajorAxisM   = a;
            elems.eccentricity     = 0;
            elems.inclinationDeg   = 30;
            elems.raanDeg          = 60;
            elems.argPeriapsisDeg  = 0;
            elems.trueAnomalyDeg   = 45;
            elems.epochSec         = 0;

            % Propagate 500 s from epoch=0
            [lat_a, lon_a, alt_a] = network.OrbitalPropagator.propagate(elems, 0, 500);

            % Same orbit but epoch shifted by 1000 s; simTime also shifted
            elems2 = elems;
            elems2.epochSec = 1000;
            [lat_b, lon_b, alt_b] = network.OrbitalPropagator.propagate(elems2, 1000, 1500);

            testCase.verifyEqual(lat_b,  lat_a,  'AbsTol', 1e-6, ...
                'Latitude should be identical regardless of epoch offset.');
            testCase.verifyEqual(lon_b,  lon_a,  'AbsTol', 1e-6, ...
                'Longitude should be identical regardless of epoch offset.');
            testCase.verifyEqual(alt_b,  alt_a,  'AbsTol', 1e-3, ...
                'Altitude should be identical regardless of epoch offset.');
        end

    end % methods (Test)

    % ======================================================================
    % Private helper methods
    % ======================================================================
    methods (Static, Access = private)

        function dist = geodetic2ecefDist(lat1, lon1, alt1, lat2, lon2, alt2)
            % Convert two geodetic positions to ECEF and return 3D distance.
            a_wgs = 6378137.0;
            f_wgs = 1 / 298.257223563;
            e2    = 2*f_wgs - f_wgs^2;

            xyz1 = network.OrbitalPropagatorTest.geodetic2ecef( ...
                lat1, lon1, alt1, a_wgs, e2);
            xyz2 = network.OrbitalPropagatorTest.geodetic2ecef( ...
                lat2, lon2, alt2, a_wgs, e2);

            dist = norm(xyz1 - xyz2);
        end

        function xyz = geodetic2ecef(latDeg, lonDeg, altM, a, e2)
            lat = deg2rad(latDeg);
            lon = deg2rad(lonDeg);
            N   = a / sqrt(1 - e2 * sin(lat)^2);
            xyz = [(N + altM) * cos(lat) * cos(lon); ...
                   (N + altM) * cos(lat) * sin(lon); ...
                   (N * (1 - e2) + altM) * sin(lat)];
        end

        function r_eci = geodetic2eci(latDeg, lonDeg, altM, timeSec)
            % Convert geodetic position to ECI by undoing the GMST rotation.
            a_wgs = 6378137.0;
            f_wgs = 1 / 298.257223563;
            e2    = 2*f_wgs - f_wgs^2;

            % Geodetic -> ECEF
            r_ecef = network.OrbitalPropagatorTest.geodetic2ecef( ...
                latDeg, lonDeg, altM, a_wgs, e2);

            % GMST at timeSec (same formula as OrbitalPropagator)
            theta_GMST_deg = 280.46061837 + 360.98564736629 * (timeSec / 86400);
            theta_GMST     = deg2rad(mod(theta_GMST_deg, 360));

            % Inverse of R3(-theta_GMST) is R3(+theta_GMST)
            cosG = cos(theta_GMST);
            sinG = sin(theta_GMST);
            R3_inv = [cosG, -sinG, 0; ...
                      sinG,  cosG, 0; ...
                      0,     0,    1];

            r_eci = R3_inv * r_ecef;
        end

    end % methods (Static, Access = private)

end % classdef
