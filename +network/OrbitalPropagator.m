classdef OrbitalPropagator
    % OrbitalPropagator  Static orbital mechanics utilities.
    %
    % Propagates satellite positions from Keplerian elements to geodetic
    % coordinates (WGS-84 latitude, longitude, altitude).
    %
    % The propagation pipeline is:
    %   1. Advance mean anomaly by elapsed time
    %   2. Solve Kepler's equation (Newton-Raphson) for eccentric anomaly
    %   3. Convert eccentric anomaly -> true anomaly
    %   4. Compute position in perifocal (PQW) frame
    %   5. Rotate PQW -> ECI via three Euler rotations
    %   6. Rotate ECI -> ECEF via Greenwich Mean Sidereal Time
    %   7. Convert ECEF (X,Y,Z) -> geodetic (lat, lon, alt) via Bowring method
    %
    % Requirements: 10.3, 10.4

    methods (Static)

        function [lat, lon, altM] = propagate(keplerElems, epochSec, simTimeSec)
            % propagate  Compute geodetic position of a satellite at simTimeSec.
            %
            %   [lat, lon, altM] = network.OrbitalPropagator.propagate( ...
            %       keplerElems, epochSec, simTimeSec)
            %
            %   Inputs:
            %     keplerElems  — struct with fields:
            %       semiMajorAxisM   : semi-major axis (m)
            %       eccentricity     : orbital eccentricity [0, 1)
            %       inclinationDeg   : inclination (degrees)
            %       raanDeg          : right ascension of ascending node (degrees)
            %       argPeriapsisDeg  : argument of periapsis (degrees)
            %       trueAnomalyDeg   : true anomaly at epoch (degrees)
            %                          (treated as mean anomaly at epoch)
            %       epochSec         : reference epoch (simulation seconds)
            %     epochSec     — epoch reference time (simulation seconds)
            %     simTimeSec   — current simulation time (seconds)
            %
            %   Outputs:
            %     lat   — geodetic latitude  (degrees, WGS-84)
            %     lon   — geodetic longitude (degrees, WGS-84)
            %     altM  — altitude above WGS-84 ellipsoid (metres)
            %
            % Requirements: 10.3, 10.4

            % ---- Constants -----------------------------------------------
            mu    = 3.986004418e14;   % Earth gravitational parameter (m^3/s^2)

            % ---- Unpack Keplerian elements --------------------------------
            a    = keplerElems.semiMajorAxisM;
            e    = keplerElems.eccentricity;
            iDeg = keplerElems.inclinationDeg;
            Om   = deg2rad(keplerElems.raanDeg);          % RAAN (rad)
            w    = deg2rad(keplerElems.argPeriapsisDeg);  % arg periapsis (rad)
            M0   = deg2rad(keplerElems.trueAnomalyDeg);   % mean anomaly at epoch (rad)

            % ---- Step 1: Elapsed time and mean anomaly --------------------
            dt = simTimeSec - epochSec;
            n  = sqrt(mu / a^3);          % mean motion (rad/s)
            M  = M0 + n * dt;             % mean anomaly at simTimeSec (rad)
            M  = mod(M, 2*pi);            % wrap to [0, 2*pi)

            % ---- Step 2: Solve Kepler's equation via Newton-Raphson ------
            E = network.OrbitalPropagator.solveKepler(M, e);

            % ---- Step 3: Eccentric anomaly -> true anomaly ---------------
            % nu = 2 * atan2(sqrt(1+e)*sin(E/2), sqrt(1-e)*cos(E/2))
            nu = 2 * atan2(sqrt(1 + e) * sin(E / 2), sqrt(1 - e) * cos(E / 2));

            % ---- Step 4: Position in perifocal (PQW) frame ---------------
            p = a * (1 - e^2);                  % semi-latus rectum (m)
            r = p / (1 + e * cos(nu));          % orbital radius (m)
            P_pqw = r * cos(nu);
            Q_pqw = r * sin(nu);
            W_pqw = 0;

            % ---- Step 5: Rotate PQW -> ECI --------------------------------
            % R_ECI_PQW = R3(-RAAN) * R1(-i) * R3(-argPeriapsis)
            % where R3 and R1 are rotation matrices about Z and X axes.
            i = deg2rad(iDeg);

            % Standard rotation matrices for PQW -> ECI transformation.
            % The transformation is: r_ECI = R3(-Om) * R1(-i) * R3(-w) * r_PQW
            %
            % R3(theta) rotates about Z:  [cos t, -sin t, 0; sin t, cos t, 0; 0,0,1]
            % R1(theta) rotates about X:  [1,0,0; 0, cos t, -sin t; 0, sin t, cos t]
            %
            % We need R3(-w), R1(-i), R3(-Om) — i.e. negative-angle rotations.

            % R3(-w): rotation about Z by -argPeriapsis
            R3_neg_w = [ cos(w),  sin(w), 0; ...
                        -sin(w),  cos(w), 0; ...
                         0,       0,      1];

            % R1(-i): rotation about X by -inclination
            R1_neg_i = [1,  0,       0;      ...
                        0,  cos(i),  sin(i); ...
                        0, -sin(i),  cos(i)];

            % R3(-Om): rotation about Z by -RAAN
            R3_neg_Om = [ cos(Om),  sin(Om), 0; ...
                         -sin(Om),  cos(Om), 0; ...
                          0,        0,       1];

            % Combined rotation: PQW -> ECI
            % r_ECI = R3(-Om) * R1(-i) * R3(-w) * r_PQW
            R_ECI = R3_neg_Om * R1_neg_i * R3_neg_w;

            r_pqw  = [P_pqw; Q_pqw; W_pqw];
            r_eci  = R_ECI * r_pqw;

            % ---- Step 6: Rotate ECI -> ECEF via GMST ----------------------
            % Simplified GMST (degrees):
            %   theta_GMST = 280.46061837 + 360.98564736629 * (simTimeSec / 86400)
            theta_GMST_deg = 280.46061837 + 360.98564736629 * (simTimeSec / 86400);
            theta_GMST     = deg2rad(mod(theta_GMST_deg, 360));

            % R3(-theta_GMST): rotate ECI to ECEF
            cosG = cos(theta_GMST);
            sinG = sin(theta_GMST);
            R3_GMST = [ cosG,  sinG, 0; ...
                       -sinG,  cosG, 0; ...
                        0,     0,    1];

            r_ecef = R3_GMST * r_eci;
            X = r_ecef(1);
            Y = r_ecef(2);
            Z = r_ecef(3);

            % ---- Step 7: ECEF -> geodetic (Bowring iterative method) ------
            [lat, lon, altM] = network.OrbitalPropagator.ecef2geodetic(X, Y, Z);
        end

    end % methods (Static)

    % ======================================================================
    % Private helper methods
    % ======================================================================
    methods (Static, Access = private)

        function E = solveKepler(M, e)
            % solveKepler  Solve Kepler's equation M = E - e*sin(E) for E.
            %
            %   Uses Newton-Raphson iteration with tolerance 1e-10 rad and
            %   a maximum of 100 iterations.
            %
            %   Inputs:
            %     M — mean anomaly (radians)
            %     e — eccentricity
            %
            %   Output:
            %     E — eccentric anomaly (radians)

            tol     = 1e-10;   % convergence tolerance (rad)
            maxIter = 100;

            % Initial guess: Kepler's equation linearised around e=0
            E = M;

            for k = 1:maxIter
                f  = E - e * sin(E) - M;   % residual
                fp = 1 - e * cos(E);        % derivative
                dE = -f / fp;
                E  = E + dE;
                if abs(dE) < tol
                    break;
                end
            end
        end

        function [lat, lon, altM] = ecef2geodetic(X, Y, Z)
            % ecef2geodetic  Convert ECEF Cartesian to WGS-84 geodetic.
            %
            %   Uses the iterative Bowring method.
            %
            %   Inputs:
            %     X, Y, Z — ECEF coordinates (metres)
            %
            %   Outputs:
            %     lat  — geodetic latitude  (degrees)
            %     lon  — geodetic longitude (degrees)
            %     altM — altitude above WGS-84 ellipsoid (metres)

            % WGS-84 parameters
            a_wgs = 6378137.0;              % semi-major axis (m)
            f_wgs = 1 / 298.257223563;      % flattening
            b_wgs = a_wgs * (1 - f_wgs);   % semi-minor axis (m)
            e2    = 2*f_wgs - f_wgs^2;     % first eccentricity squared
            ep2   = e2 / (1 - e2);         % second eccentricity squared

            % Longitude (exact)
            lon = atan2(Y, X);   % radians

            % Distance from Z-axis
            p = sqrt(X^2 + Y^2);

            % Bowring iterative method for latitude
            % Initial estimate using parametric latitude
            theta = atan2(Z * a_wgs, p * b_wgs);

            lat = atan2(Z + ep2 * b_wgs * sin(theta)^3, ...
                        p - e2  * a_wgs * cos(theta)^3);

            for iter = 1:10
                lat_prev = lat;
                sinLat   = sin(lat);
                N        = a_wgs / sqrt(1 - e2 * sinLat^2);   % prime vertical radius
                lat      = atan2(Z + e2 * N * sinLat, p);
                if abs(lat - lat_prev) < 1e-12
                    break;
                end
            end

            % Altitude
            sinLat = sin(lat);
            cosLat = cos(lat);
            N      = a_wgs / sqrt(1 - e2 * sinLat^2);

            if abs(cosLat) > 1e-10
                altM = p / cosLat - N;
            else
                % Near the poles use Z component
                altM = abs(Z) / abs(sinLat) - N * (1 - e2);
            end

            % Convert to degrees
            lat = rad2deg(lat);
            lon = rad2deg(lon);
        end

    end % methods (Static, Access = private)

end % classdef
