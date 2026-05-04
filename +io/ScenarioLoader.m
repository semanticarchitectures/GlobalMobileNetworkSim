classdef ScenarioLoader
    % ScenarioLoader  Loads and saves simulation scenario files in JSON format.
    %
    % All methods are static; no instance is required.
    %
    % Usage:
    %   scenario = io.ScenarioLoader.load(filePath)
    %   io.ScenarioLoader.save(scenario, filePath)
    %
    % Requirements: 7.1, 7.2, 7.3, 7.4, 1.4, 2.7, 3.5, 10.4

    methods (Static)

        % ------------------------------------------------------------------
        % load
        % ------------------------------------------------------------------

        function scenario = load(filePath)
            % load  Read and validate a JSON scenario file.
            %
            %   scenario = io.ScenarioLoader.load(filePath)
            %
            %   Reads the file at filePath, decodes the JSON, validates all
            %   required top-level fields, node definitions, link definitions,
            %   and C2 message definitions.  Returns the validated scenario
            %   struct on success.
            %
            %   Throws structured errors per the design error-handling table:
            %     netsim:io:jsonSyntaxError         — JSON parse failure
            %     netsim:io:missingField            — missing required top-level field
            %     netsim:node:malformedTrajectory   — missing/invalid waypoint field
            %     netsim:node:invalidKeplerElements — missing/invalid orbital element
            %     netsim:link:missingField          — missing required link field
            %     netsim:link:unknownNode           — link references non-existent node
            %     netsim:c2:missingField            — missing required C2 message field
            %
            % Requirements: 7.1, 7.2, 7.3, 1.4, 2.7, 10.4

            % --- Read and parse JSON ---
            try
                rawText = fileread(filePath);
                scenario = jsondecode(rawText);
            catch ME
                error('netsim:io:jsonSyntaxError', ...
                    'File: %s — %s', filePath, ME.message);
            end

            % --- Validate required top-level fields ---
            requiredTopFields = {'scenarioName', 'simulationDurationSec'};
            for fi = 1:numel(requiredTopFields)
                fn = requiredTopFields{fi};
                if ~isfield(scenario, fn)
                    error('netsim:io:missingField', ...
                        'Missing required field: %s', fn);
                end
            end

            % --- Validate nodes (optional array) ---
            if isfield(scenario, 'nodes') && ~isempty(scenario.nodes) && ...
                    ~(isnumeric(scenario.nodes) && isempty(scenario.nodes))
                nodes = scenario.nodes;
                % jsondecode may return a struct array or cell array
                if isstruct(nodes)
                    nNodes = numel(nodes);
                    getNode = @(k) nodes(k);
                elseif iscell(nodes)
                    nNodes = numel(nodes);
                    getNode = @(k) nodes{k};
                else
                    nNodes = 0;
                    getNode = @(k) [];
                end

                % Collect node IDs for link validation
                nodeIds = strings(nNodes, 1);

                for k = 1:nNodes
                    nd = getNode(k);
                    io.ScenarioLoader.validateNode(nd);
                    nodeIds(k) = string(nd.id);
                end
            else
                nodeIds = strings(0, 1);
            end

            % --- Validate links (optional array) ---
            if isfield(scenario, 'links') && ~isempty(scenario.links) && ...
                    ~(isnumeric(scenario.links) && isempty(scenario.links))
                links = scenario.links;
                if isstruct(links)
                    nLinks = numel(links);
                    getLink = @(k) links(k);
                elseif iscell(links)
                    nLinks = numel(links);
                    getLink = @(k) links{k};
                else
                    nLinks = 0;
                    getLink = @(k) [];
                end

                for k = 1:nLinks
                    lk = getLink(k);
                    io.ScenarioLoader.validateLink(lk, nodeIds);
                end
            end

            % --- Validate c2Messages (optional array) ---
            if isfield(scenario, 'c2Messages') && ~isempty(scenario.c2Messages) && ...
                    ~(isnumeric(scenario.c2Messages) && isempty(scenario.c2Messages))
                msgs = scenario.c2Messages;
                if isstruct(msgs)
                    nMsgs = numel(msgs);
                    getMsg = @(k) msgs(k);
                elseif iscell(msgs)
                    nMsgs = numel(msgs);
                    getMsg = @(k) msgs{k};
                else
                    nMsgs = 0;
                    getMsg = @(k) [];
                end

                for k = 1:nMsgs
                    msg = getMsg(k);
                    io.ScenarioLoader.validateC2Message(msg);
                end
            end
        end

        % ------------------------------------------------------------------
        % save
        % ------------------------------------------------------------------

        function save(scenario, filePath)
            % save  Serialize a scenario struct to a JSON file.
            %
            %   io.ScenarioLoader.save(scenario, filePath)
            %
            %   Encodes the scenario struct as JSON and writes it to filePath.
            %   Uses pretty-printing when supported (MATLAB R2021a+).
            %
            % Requirements: 7.4

            % Try pretty-print first (R2021a+), fall back to plain jsonencode
            try
                jsonText = jsonencode(scenario, 'PrettyPrint', true);
            catch
                jsonText = jsonencode(scenario);
            end

            fid = fopen(filePath, 'w');
            if fid == -1
                error('netsim:io:fileWriteError', ...
                    'Cannot open file for writing: %s', filePath);
            end
            try
                fwrite(fid, jsonText, 'char');
            catch ME
                fclose(fid);
                rethrow(ME);
            end
            fclose(fid);
        end

    end % methods (Static)

    % ======================================================================
    % Private static helpers
    % ======================================================================
    methods (Static, Access = private)

        function validateNode(nd)
            % validateNode  Validate a single node definition struct.
            %
            %   Required fields: id, type, lat, lon, altM
            %   If type is 'Mobile' and trajectory is present with type=='waypoints',
            %   validate each waypoint has timeSec/lat/lon/altM.
            %   If keplerElements is present, validate required orbital fields.
            %
            % Requirements: 1.4, 10.4

            requiredNodeFields = {'id', 'type', 'lat', 'lon', 'altM'};
            for f = 1:numel(requiredNodeFields)
                fn = requiredNodeFields{f};
                if ~isfield(nd, fn)
                    error('netsim:node:malformedTrajectory', ...
                        'Node is missing required field "%s".', fn);
                end
            end

            nodeId = string(nd.id);

            % Validate trajectory waypoints for Mobile nodes
            if isfield(nd, 'trajectory') && ~isempty(nd.trajectory) && ...
                    isstruct(nd.trajectory)
                traj = nd.trajectory;
                if isfield(traj, 'type') && strcmp(string(traj.type), 'waypoints')
                    if isfield(traj, 'waypoints') && ~isempty(traj.waypoints)
                        io.ScenarioLoader.validateWaypoints(traj.waypoints, nodeId);
                    end
                end
            end

            % Validate Keplerian elements if present and non-null
            if isfield(nd, 'keplerElements') && ~isempty(nd.keplerElements) && ...
                    isstruct(nd.keplerElements)
                io.ScenarioLoader.validateKeplerElements(nd.keplerElements, nodeId);
            end
        end

        function validateWaypoints(waypoints, nodeId)
            % validateWaypoints  Validate that each waypoint has required fields.
            %
            %   Required waypoint fields: timeSec, lat, lon, altM
            %
            % Requirements: 1.4

            requiredWpFields = {'timeSec', 'lat', 'lon', 'altM'};

            if isstruct(waypoints)
                nWp = numel(waypoints);
                for w = 1:nWp
                    for f = 1:numel(requiredWpFields)
                        fn = requiredWpFields{f};
                        if ~isfield(waypoints(w), fn)
                            error('netsim:node:malformedTrajectory', ...
                                'Node "%s": waypoint %d is missing required field "%s".', ...
                                nodeId, w, fn);
                        end
                    end
                end
            elseif iscell(waypoints)
                nWp = numel(waypoints);
                for w = 1:nWp
                    wp = waypoints{w};
                    for f = 1:numel(requiredWpFields)
                        fn = requiredWpFields{f};
                        if ~isfield(wp, fn)
                            error('netsim:node:malformedTrajectory', ...
                                'Node "%s": waypoint %d is missing required field "%s".', ...
                                nodeId, w, fn);
                        end
                    end
                end
            end
        end

        function validateKeplerElements(ke, nodeId)
            % validateKeplerElements  Validate required Keplerian orbital element fields.
            %
            %   Required fields: semiMajorAxisM, eccentricity, inclinationDeg,
            %                    raanDeg, argPeriapsisDeg, trueAnomalyDeg, epochSec
            %
            % Requirements: 10.4

            requiredKeplerFields = { ...
                'semiMajorAxisM', ...
                'eccentricity', ...
                'inclinationDeg', ...
                'raanDeg', ...
                'argPeriapsisDeg', ...
                'trueAnomalyDeg', ...
                'epochSec' ...
            };

            for f = 1:numel(requiredKeplerFields)
                fn = requiredKeplerFields{f};
                if ~isfield(ke, fn)
                    error('netsim:node:invalidKeplerElements', ...
                        'Node "%s": missing keplerElements field "%s"', ...
                        nodeId, fn);
                end
            end
        end

        function validateLink(lk, nodeIds)
            % validateLink  Validate a single link definition struct.
            %
            %   Required fields: id, type, srcNodeId, dstNodeId,
            %                    nominalLatencyMs, bandwidthBps, outageRate,
            %                    outageDuration, backgroundTraffic
            %   Also validates that srcNodeId and dstNodeId exist in nodeIds.
            %
            % Requirements: 2.7

            requiredLinkFields = { ...
                'id', 'type', 'srcNodeId', 'dstNodeId', ...
                'nominalLatencyMs', 'bandwidthBps', 'outageRate', ...
                'outageDuration', 'backgroundTraffic' ...
            };

            % Get link ID for error messages (may not exist yet)
            if isfield(lk, 'id')
                linkId = string(lk.id);
            else
                linkId = '<unknown>';
            end

            for f = 1:numel(requiredLinkFields)
                fn = requiredLinkFields{f};
                if ~isfield(lk, fn)
                    error('netsim:link:missingField', ...
                        'Link "%s": missing required field "%s"', ...
                        linkId, fn);
                end
            end

            linkId = string(lk.id);

            % Validate node references
            srcId = string(lk.srcNodeId);
            dstId = string(lk.dstNodeId);

            if ~isempty(nodeIds) && ~any(nodeIds == srcId)
                error('netsim:link:unknownNode', ...
                    'Link "%s": source node "%s" was not found in the scenario nodes.', ...
                    linkId, srcId);
            end

            if ~isempty(nodeIds) && ~any(nodeIds == dstId)
                error('netsim:link:unknownNode', ...
                    'Link "%s": destination node "%s" was not found in the scenario nodes.', ...
                    linkId, dstId);
            end
        end

        function validateC2Message(msg)
            % validateC2Message  Validate a single C2 message definition struct.
            %
            %   Required fields: id, srcNodeId, dstNodeId, sizeBytes, scheduledTimeSec
            %
            % Requirements: 5.1

            % Get message ID for error messages (may not exist yet)
            if isfield(msg, 'id')
                msgId = string(msg.id);
            else
                msgId = '<unknown>';
            end

            requiredMsgFields = { ...
                'id', 'srcNodeId', 'dstNodeId', 'sizeBytes', 'scheduledTimeSec' ...
            };

            for f = 1:numel(requiredMsgFields)
                fn = requiredMsgFields{f};
                if ~isfield(msg, fn)
                    error('netsim:c2:missingField', ...
                        'C2 message "%s": missing required field "%s"', ...
                        msgId, fn);
                end
            end
        end

    end % methods (Static, Access = private)

end % classdef
