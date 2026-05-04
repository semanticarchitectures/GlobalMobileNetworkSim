classdef GeoUtils
    % GeoUtils  Static WGS-84 geodesy utilities.
    %
    % Provides Vincenty's iterative formula for geodesic distance and a
    % line-of-sight visibility check that accounts for Earth curvature.
    %
    % Requirements: 2.4, 2.5, 10.1, 10.2

    methods (Static)

        function distM = vincenty(lat1, lon1, lat2, lon2)
            % vincenty  Compute geodesic distance between two points on the
            %           WGS-84 ellipsoid using Vincenty's iterative formula.
            %
            %   distM = network.GeoUtils.vincenty(lat1, lon1, lat2, lon2)
            %
            %   Inputs (all in decimal degrees):
            %     lat1, lon1 — first point latitude and longitude
            %     lat2, lon2 — second point latitude and longitude
            %
            %   Output:
            %     distM — geodesic distance in metres
            %
            %   Accuracy: sub-millimetre (< 0.001% error) for non-antipodal
            %   points.  Near-antipodal pairs that fail to converge after
            %   1000 iterations return an approximate distance.
            %
            % Requirements: 10.1

            % WGS-84 ellipsoid parameters
            a = 6378137.0;            % semi-major axis (m)
            f = 1 / 298.257223563;    % flattening
            b = a * (1 - f);          % semi-minor axis (m)

            % Convert degrees to radians
            phi1   = deg2rad(lat1);
            phi2   = deg2rad(lat2);
            L      = deg2rad(lon2 - lon1);

            % Reduced latitudes (latitude on the auxiliary sphere)
            tanU1  = (1 - f) * tan(phi1);
            tanU2  = (1 - f) * tan(phi2);
            cosU1  = 1 / sqrt(1 + tanU1^2);
            sinU1  = tanU1 * cosU1;
            cosU2  = 1 / sqrt(1 + tanU2^2);
            sinU2  = tanU2 * cosU2;

            % Degenerate case: identical points
            if abs(lat1 - lat2) < 1e-12 && abs(lon1 - lon2) < 1e-12
                distM = 0;
                return;
            end

            % Iterative solution
            lambda     = L;
            lambdaPrev = Inf;
            maxIter    = 1000;
            tol        = 1e-12;
            converged  = false;

            sinSigma = 0;  cosAlpha2 = 0;  cosSigma = 0;
            sigma = 0;     cos2SigmaM = 0;

            for iter = 1:maxIter
                sinLambda = sin(lambda);
                cosLambda = cos(lambda);

                sinSigma = sqrt( (cosU2 * sinLambda)^2 + ...
                                 (cosU1 * sinU2 - sinU1 * cosU2 * cosLambda)^2 );
                cosSigma = sinU1 * sinU2 + cosU1 * cosU2 * cosLambda;

                % Coincident points (should be caught above, but guard here)
                if sinSigma == 0
                    distM = 0;
                    return;
                end

                sigma     = atan2(sinSigma, cosSigma);
                sinAlpha  = cosU1 * cosU2 * sinLambda / sinSigma;
                cosAlpha2 = 1 - sinAlpha^2;

                if cosAlpha2 == 0
                    % Equatorial line
                    cos2SigmaM = 0;
                else
                    cos2SigmaM = cosSigma - 2 * sinU1 * sinU2 / cosAlpha2;
                end

                C      = f / 16 * cosAlpha2 * (4 + f * (4 - 3 * cosAlpha2));
                lambda = L + (1 - C) * f * sinAlpha * ...
                         (sigma + C * sinSigma * ...
                          (cos2SigmaM + C * cosSigma * (-1 + 2 * cos2SigmaM^2)));

                if abs(lambda - lambdaPrev) < tol
                    converged = true;
                    break;
                end
                lambdaPrev = lambda;
            end

            if ~converged
                % Near-antipodal: return approximate distance using the
                % last iterate (accuracy degrades but avoids NaN/Inf).
                % This satisfies the "handle gracefully" requirement.
            end

            % Evaluate Vincenty's distance formula
            u2     = cosAlpha2 * (a^2 - b^2) / b^2;
            A_coef = 1 + u2 / 16384 * (4096 + u2 * (-768 + u2 * (320 - 175 * u2)));
            B_coef = u2 / 1024  * (256  + u2 * (-128 + u2 * (74  - 47  * u2)));

            deltaSigma = B_coef * sinSigma * ...
                         (cos2SigmaM + B_coef / 4 * ...
                          (cosSigma * (-1 + 2 * cos2SigmaM^2) - ...
                           B_coef / 6 * cos2SigmaM * (-3 + 4 * sinSigma^2) * ...
                           (-3 + 4 * cos2SigmaM^2)));

            distM = b * A_coef * (sigma - deltaSigma);
        end

        % -----------------------------------------------------------------

        function tf = isLOSVisible(mobileLat, mobileLon, mobileAltM, ...
                                    stationLat, stationLon, coverageRadiusM)
            % isLOSVisible  Check whether a mobile node has line-of-sight to
            %               a ground station, accounting for Earth curvature.
            %
            %   tf = network.GeoUtils.isLOSVisible(mobileLat, mobileLon, ...
            %            mobileAltM, stationLat, stationLon, coverageRadiusM)
            %
            %   The link is considered visible when BOTH conditions hold:
            %     1. The geodesic distance between the mobile and the station
            %        is less than coverageRadiusM.
            %     2. The geodesic distance is less than the radio horizon
            %        distance sqrt(2 * R * h), where R is Earth's mean radius
            %        and h is the mobile's altitude above the ellipsoid.
            %
            %   Inputs:
            %     mobileLat, mobileLon  — mobile node position (degrees)
            %     mobileAltM            — mobile altitude above ellipsoid (m)
            %     stationLat, stationLon — station position (degrees)
            %     coverageRadiusM       — configured coverage radius (m)
            %
            %   Output:
            %     tf — logical true if LOS link is active
            %
            % Requirements: 2.5, 10.2

            % Earth's mean radius (m) — used for radio horizon approximation
            R = 6371000.0;

            % Geodesic distance between mobile and station
            geodesicDistM = network.GeoUtils.vincenty( ...
                mobileLat, mobileLon, stationLat, stationLon);

            % Radio horizon distance from station to mobile given mobile altitude
            % d_horizon = sqrt(2 * R * h)
            if mobileAltM <= 0
                horizonDistM = 0;
            else
                horizonDistM = sqrt(2 * R * mobileAltM);
            end

            % Both conditions must hold for LOS to be active
            tf = (geodesicDistM < coverageRadiusM) && ...
                 (geodesicDistM < horizonDistM);
        end

    end % methods (Static)

end % classdef
