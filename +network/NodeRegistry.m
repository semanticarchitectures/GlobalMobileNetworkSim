classdef NodeRegistry < handle
    % NodeRegistry  Stores and manages all node state for the simulation.
    %
    % Uses struct-of-arrays storage for memory efficiency, supporting up to
    % 1,000 nodes without exceeding 16 GB RAM constraints.
    %
    % Supported node types:
    %   'Stationary' — fixed geographic position
    %   'Mobile'     — position changes over time via waypoint trajectory
    %   Satellite    — Mobile node with keplerElements; position propagated
    %                  via network.OrbitalPropagator
    %
    % Requirements: 1.1, 1.2, 1.3, 1.4, 10.3, 10.4

    properties (Access = private)
        % Struct-of-arrays internal storage
        nodes   % struct with fields: id, type, lat, lon, altM,
                %   trajectory (cell), keplerElements (cell)
        n       % number of nodes (scalar double)
    end

    methods (Access = public)

        % ------------------------------------------------------------------
        % Constructor
        % ------------------------------------------------------------------

        function obj = NodeRegistry(nodeStructArray)
            % NodeRegistry  Construct a NodeRegistry from an array of node
            %               definition structs.
            %
            %   nr = network.NodeRegistry(nodeStructArray)
            %
            %   nodeStructArray may be:
            %     - A struct array (one element per node)
            %     - A cell array of structs (one cell per node)
            %
            %   Each element must have fields:
            %     id          (string)  — unique node identifier
            %     type        (string)  — 'Stationary' or 'Mobile'
            %     lat         (double)  — initial latitude  (degrees, WGS-84)
            %     lon         (double)  — initial longitude (degrees, WGS-84)
            %     altM        (double)  — initial altitude  (metres)
            %     trajectory  (struct or empty) — waypoint trajectory for
            %                   Mobile nodes; empty for Stationary
            %     keplerElements (struct or empty) — Keplerian elements for
            %                   satellite nodes; empty otherwise
            %
            % Requirements: 1.1, 1.4, 10.4

            % Normalise input to a cell array of structs
            if isstruct(nodeStructArray)
                % Convert struct array to cell array
                nNodes = numel(nodeStructArray);
                cellNodes = cell(nNodes, 1);
                for k = 1:nNodes
                    cellNodes{k} = nodeStructArray(k);
                end
            elseif iscell(nodeStructArray)
                cellNodes = nodeStructArray(:);
                nNodes = numel(cellNodes);
            else
                error('netsim:node:invalidInput', ...
                    'nodeStructArray must be a struct array or cell array of structs.');
            end

            obj.n = nNodes;

            % Pre-allocate struct-of-arrays
            obj.nodes.id            = strings(nNodes, 1);
            obj.nodes.type          = strings(nNodes, 1);
            obj.nodes.lat           = zeros(nNodes, 1);
            obj.nodes.lon           = zeros(nNodes, 1);
            obj.nodes.altM          = zeros(nNodes, 1);
            obj.nodes.trajectory    = cell(nNodes, 1);
            obj.nodes.keplerElements = cell(nNodes, 1);

            % Populate arrays and validate
            for k = 1:nNodes
                nd = cellNodes{k};

                obj.nodes.id(k)   = string(nd.id);
                obj.nodes.type(k) = string(nd.type);
                obj.nodes.lat(k)  = nd.lat;
                obj.nodes.lon(k)  = nd.lon;
                obj.nodes.altM(k) = nd.altM;

                % Trajectory
                if isfield(nd, 'trajectory') && ~isempty(nd.trajectory)
                    obj.nodes.trajectory{k} = nd.trajectory;
                    % Validate waypoint trajectory for Mobile nodes
                    if strcmpi(nd.type, 'Mobile') && ...
                            isfield(nd.trajectory, 'type') && ...
                            strcmpi(nd.trajectory.type, 'waypoints')
                        network.NodeRegistry.validateWaypoints( ...
                            nd.trajectory.waypoints, nd.id);
                    end
                else
                    obj.nodes.trajectory{k} = {};
                end

                % Keplerian elements
                if isfield(nd, 'keplerElements') && ~isempty(nd.keplerElements)
                    obj.nodes.keplerElements{k} = nd.keplerElements;
                else
                    obj.nodes.keplerElements{k} = {};
                end
            end
        end

        % ------------------------------------------------------------------
        % Public methods
        % ------------------------------------------------------------------

        function pos = getPosition(obj, nodeId, simTimeSec)
            % getPosition  Return the position of a node at a given sim time.
            %
            %   pos = nr.getPosition(nodeId, simTimeSec)
            %
            %   Returns a struct with fields:
            %     lat   — latitude  (degrees, WGS-84)
            %     lon   — longitude (degrees, WGS-84)
            %     altM  — altitude  (metres)
            %
            %   For Stationary nodes: returns the fixed position.
            %   For Mobile nodes with waypoint trajectory: linearly
            %     interpolates between waypoints; clamps to first/last
            %     waypoint if outside the trajectory time range.
            %   For satellite nodes (keplerElements non-empty): calls
            %     network.OrbitalPropagator.propagate.
            %
            % Requirements: 1.2, 10.3, 10.4

            idx = obj.indexOf(nodeId);

            kepElems = obj.nodes.keplerElements{idx};
            traj     = obj.nodes.trajectory{idx};
            nodeType = obj.nodes.type(idx);

            % Satellite node: use orbital propagator
            if ~isempty(kepElems)
                epochSec = kepElems.epochSec;
                [lat, lon, altM] = network.OrbitalPropagator.propagate( ...
                    kepElems, epochSec, simTimeSec);
                pos = struct('lat', lat, 'lon', lon, 'altM', altM);
                return;
            end

            % Mobile node with waypoint trajectory
            if strcmpi(nodeType, 'Mobile') && ~isempty(traj)
                pos = network.NodeRegistry.interpolateWaypoints( ...
                    traj.waypoints, simTimeSec);
                return;
            end

            % Stationary node (or Mobile with no trajectory): fixed position
            pos = struct( ...
                'lat',  obj.nodes.lat(idx), ...
                'lon',  obj.nodes.lon(idx), ...
                'altM', obj.nodes.altM(idx));
        end

        function updatePositions(obj, simTimeSec)
            % updatePositions  Batch-update lat/lon/altM for all Mobile nodes.
            %
            %   nr.updatePositions(simTimeSec)
            %
            %   Iterates over all nodes; for each Mobile node (or satellite
            %   node) calls getPosition and stores the result back into the
            %   internal struct-of-arrays.
            %
            % Requirements: 1.2, 10.3

            for k = 1:obj.n
                nodeType = obj.nodes.type(k);
                kepElems = obj.nodes.keplerElements{k};

                isMobile    = strcmpi(nodeType, 'Mobile');
                isSatellite = ~isempty(kepElems);

                if isMobile || isSatellite
                    nodeId = obj.nodes.id(k);
                    pos = obj.getPosition(nodeId, simTimeSec);
                    obj.nodes.lat(k)  = pos.lat;
                    obj.nodes.lon(k)  = pos.lon;
                    obj.nodes.altM(k) = pos.altM;
                end
            end
        end

        function idx = indexOf(obj, nodeId)
            % indexOf  Return the integer index of a node in the internal arrays.
            %
            %   idx = nr.indexOf(nodeId)
            %
            %   Throws error('netsim:node:notFound', ...) if nodeId is not
            %   found in the registry.
            %
            % Requirements: 1.1

            nodeIdStr = string(nodeId);
            matches = find(obj.nodes.id == nodeIdStr, 1);

            if isempty(matches)
                error('netsim:node:notFound', ...
                    'Node with ID "%s" was not found in the NodeRegistry.', ...
                    nodeIdStr);
            end

            idx = matches;
        end

        function n = count(obj)
            % count  Return the number of nodes in the registry.
            %
            %   n = nr.count()
            %
            % Requirements: 1.1

            n = obj.n;
        end

        function id = getIdByIndex(obj, idx)
            % getIdByIndex  Return the node ID string at the given index.
            %
            %   id = nr.getIdByIndex(idx)
            %
            %   Returns the node ID string at position idx in the internal
            %   struct-of-arrays.  Used by RoutingEngine to enumerate all
            %   node names when building the routing digraph.
            %
            % Requirements: 1.1

            if idx < 1 || idx > obj.n
                error('netsim:node:indexOutOfRange', ...
                    'Index %d is out of range [1, %d].', idx, obj.n);
            end
            id = obj.nodes.id(idx);
        end

        function ids = getAllIds(obj)
            % getAllIds  Return all node IDs as a string array.
            %
            %   ids = nr.getAllIds()
            %
            % Requirements: 1.1

            ids = obj.nodes.id;
        end

    end % methods (Access = public)

    % ======================================================================
    % Private static helpers
    % ======================================================================
    methods (Static, Access = private)

        function validateWaypoints(waypoints, nodeId)
            % validateWaypoints  Validate that each waypoint has required fields.
            %
            %   Throws error('netsim:node:malformedTrajectory', ...) with the
            %   node ID and the first missing field name if any waypoint is
            %   missing a required field.
            %
            % Requirements: 1.4

            requiredFields = {'timeSec', 'lat', 'lon', 'altM'};

            if isstruct(waypoints)
                nWp = numel(waypoints);
                for w = 1:nWp
                    for f = 1:numel(requiredFields)
                        fieldName = requiredFields{f};
                        if ~isfield(waypoints(w), fieldName)
                            error('netsim:node:malformedTrajectory', ...
                                ['Node "%s": waypoint %d is missing required ' ...
                                 'field "%s".'], ...
                                string(nodeId), w, fieldName);
                        end
                    end
                end
            elseif iscell(waypoints)
                nWp = numel(waypoints);
                for w = 1:nWp
                    wp = waypoints{w};
                    for f = 1:numel(requiredFields)
                        fieldName = requiredFields{f};
                        if ~isfield(wp, fieldName)
                            error('netsim:node:malformedTrajectory', ...
                                ['Node "%s": waypoint %d is missing required ' ...
                                 'field "%s".'], ...
                                string(nodeId), w, fieldName);
                        end
                    end
                end
            end
        end

        function pos = interpolateWaypoints(waypoints, simTimeSec)
            % interpolateWaypoints  Linearly interpolate position from waypoints.
            %
            %   pos = interpolateWaypoints(waypoints, simTimeSec)
            %
            %   waypoints is a struct array with fields: timeSec, lat, lon, altM.
            %   Clamps to the first waypoint before the first time and to the
            %   last waypoint after the last time.
            %
            % Requirements: 1.2

            if isstruct(waypoints)
                nWp = numel(waypoints);
                times = zeros(nWp, 1);
                lats  = zeros(nWp, 1);
                lons  = zeros(nWp, 1);
                alts  = zeros(nWp, 1);
                for w = 1:nWp
                    times(w) = waypoints(w).timeSec;
                    lats(w)  = waypoints(w).lat;
                    lons(w)  = waypoints(w).lon;
                    alts(w)  = waypoints(w).altM;
                end
            elseif iscell(waypoints)
                nWp = numel(waypoints);
                times = zeros(nWp, 1);
                lats  = zeros(nWp, 1);
                lons  = zeros(nWp, 1);
                alts  = zeros(nWp, 1);
                for w = 1:nWp
                    times(w) = waypoints{w}.timeSec;
                    lats(w)  = waypoints{w}.lat;
                    lons(w)  = waypoints{w}.lon;
                    alts(w)  = waypoints{w}.altM;
                end
            else
                error('netsim:node:malformedTrajectory', ...
                    'Waypoints must be a struct array or cell array.');
            end

            % Clamp before first waypoint
            if simTimeSec <= times(1)
                pos = struct('lat', lats(1), 'lon', lons(1), 'altM', alts(1));
                return;
            end

            % Clamp after last waypoint
            if simTimeSec >= times(end)
                pos = struct('lat', lats(end), 'lon', lons(end), 'altM', alts(end));
                return;
            end

            % Find the bracketing waypoints and interpolate
            for w = 1:(nWp - 1)
                if simTimeSec >= times(w) && simTimeSec <= times(w + 1)
                    t0 = times(w);
                    t1 = times(w + 1);
                    alpha = (simTimeSec - t0) / (t1 - t0);

                    lat  = lats(w)  + alpha * (lats(w+1)  - lats(w));
                    lon  = lons(w)  + alpha * (lons(w+1)  - lons(w));
                    altM = alts(w)  + alpha * (alts(w+1)  - alts(w));

                    pos = struct('lat', lat, 'lon', lon, 'altM', altM);
                    return;
                end
            end

            % Fallback (should not reach here)
            pos = struct('lat', lats(end), 'lon', lons(end), 'altM', alts(end));
        end

    end % methods (Static, Access = private)

end % classdef
