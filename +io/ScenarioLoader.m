classdef ScenarioLoader
    % ScenarioLoader  Loads and saves simulation scenario files in JSON format.
    %
    % All methods are static; no instance is required.
    %
    % Usage:
    %   scenario = io.ScenarioLoader.load(filePath)
    %   io.ScenarioLoader.save(scenario, filePath)
    %   refBehavior = io.ScenarioLoader.loadReferenceBehavior(filePath)
    %   io.ScenarioLoader.saveReferenceBehavior(refBehavior, filePath)
    %
    % Requirements: 7.1, 7.2, 7.3, 7.4, 1.4, 2.7, 3.5, 10.4, 14.1, 14.2,
    %               14.3, 14.4, 14.5

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

            % --- Resolve agent roleDefinitionFile paths relative to scenario dir ---
            % Requirements: 11.1
            [scenarioDir, ~, ~] = fileparts(filePath);
            if isfield(scenario, 'agents') && ~isempty(scenario.agents) && ...
                    ~(isnumeric(scenario.agents) && isempty(scenario.agents))
                agents = scenario.agents;
                if isstruct(agents)
                    for k = 1:numel(agents)
                        if isfield(agents(k), 'roleDefinitionFile') && ...
                                ~isempty(agents(k).roleDefinitionFile)
                            agents(k).roleDefinitionFile = ...
                                io.ScenarioLoader.resolveRelativePath( ...
                                    agents(k).roleDefinitionFile, scenarioDir);
                        end
                    end
                    scenario.agents = agents;
                elseif iscell(agents)
                    for k = 1:numel(agents)
                        if isfield(agents{k}, 'roleDefinitionFile') && ...
                                ~isempty(agents{k}.roleDefinitionFile)
                            agents{k}.roleDefinitionFile = ...
                                io.ScenarioLoader.resolveRelativePath( ...
                                    agents{k}.roleDefinitionFile, scenarioDir);
                        end
                    end
                    scenario.agents = agents;
                end
            end

            % --- Load reference behavior (optional) ---
            % Requirements: 14.1, 14.2, 14.4
            if isfield(scenario, 'referenceBehaviorFile') && ...
                    ~isempty(scenario.referenceBehaviorFile) && ...
                    ischar(scenario.referenceBehaviorFile)

                refFilePath = io.ScenarioLoader.resolveRelativePath( ...
                    scenario.referenceBehaviorFile, scenarioDir);

                % Resolve relative path relative to the scenario file's directory
                [scenarioDir, ~, ~] = fileparts(filePath);
                if ~isempty(scenarioDir)
                    % Detect absolute paths: starts with / (Unix) or X: (Windows)
                    isAbsPath = (numel(refFilePath) > 0 && refFilePath(1) == '/') || ...
                                (numel(refFilePath) > 1 && refFilePath(2) == ':');
                    if ~isAbsPath
                        refFilePath = fullfile(scenarioDir, refFilePath);
                    end
                end

                refBehavior = io.ScenarioLoader.loadReferenceBehavior(refFilePath);

                % Validate that referenced roles exist in agent definitions;
                % warn (do not halt) for roles with no assigned agent.
                % Requirements: 14.2, 14.4
                if isfield(scenario, 'agents') && ~isempty(scenario.agents) && ...
                        ~(isnumeric(scenario.agents) && isempty(scenario.agents))
                    agents = scenario.agents;
                    if isstruct(agents)
                        nAgents = numel(agents);
                        getAgent = @(k) agents(k);
                    elseif iscell(agents)
                        nAgents = numel(agents);
                        getAgent = @(k) agents{k};
                    else
                        nAgents = 0;
                        getAgent = @(k) [];
                    end

                    % Collect agent role names
                    agentRoles = strings(nAgents, 1);
                    for k = 1:nAgents
                        ag = getAgent(k);
                        if isfield(ag, 'role')
                            agentRoles(k) = string(ag.role);
                        end
                    end

                    % Check each referenced role
                    roles = refBehavior.roles;
                    if isstruct(roles)
                        nRoles = numel(roles);
                        getRole = @(k) roles(k);
                    elseif iscell(roles)
                        nRoles = numel(roles);
                        getRole = @(k) roles{k};
                    else
                        nRoles = 0;
                        getRole = @(k) [];
                    end

                    for k = 1:nRoles
                        rEntry = getRole(k);
                        roleName = string(rEntry.role);
                        if ~any(agentRoles == roleName)
                            warning('netsim:agent:unassignedRole', ...
                                'Role "%s" has no assigned agent', roleName);
                        end
                    end
                end

                scenario.referenceBehavior = refBehavior;
            else
                scenario.referenceBehavior = [];
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

        % ------------------------------------------------------------------
        % loadReferenceBehavior
        % ------------------------------------------------------------------

        function refBehavior = loadReferenceBehavior(filePath)
            % loadReferenceBehavior  Read and validate a reference behavior JSON file.
            %
            %   refBehavior = io.ScenarioLoader.loadReferenceBehavior(filePath)
            %
            %   Reads the JSON file at filePath, validates the required top-level
            %   fields (scenarioName, roles), and validates each role entry and
            %   its actions.  Returns the validated reference behavior struct.
            %
            %   Throws:
            %     netsim:io:jsonSyntaxError  — JSON parse failure
            %     netsim:io:missingField     — missing required field
            %
            % Requirements: 14.3, 14.5

            % --- Read and parse JSON ---
            try
                rawText = fileread(filePath);
                refBehavior = jsondecode(rawText);
            catch ME
                error('netsim:io:jsonSyntaxError', ...
                    'File: %s — %s', filePath, ME.message);
            end

            % --- Validate required top-level fields ---
            requiredTopFields = {'scenarioName', 'roles'};
            for fi = 1:numel(requiredTopFields)
                fn = requiredTopFields{fi};
                if ~isfield(refBehavior, fn)
                    error('netsim:io:missingField', ...
                        'Reference behavior file "%s": missing required field "%s"', ...
                        filePath, fn);
                end
            end

            % --- Validate each role entry ---
            roles = refBehavior.roles;
            if isstruct(roles)
                nRoles = numel(roles);
                getRole = @(k) roles(k);
            elseif iscell(roles)
                nRoles = numel(roles);
                getRole = @(k) roles{k};
            else
                nRoles = 0;
                getRole = @(k) [];
            end

            for k = 1:nRoles
                rEntry = getRole(k);

                % Validate role-level required fields
                roleRequiredFields = {'role', 'ordering', 'actions'};
                for fi = 1:numel(roleRequiredFields)
                    fn = roleRequiredFields{fi};
                    if ~isfield(rEntry, fn)
                        error('netsim:io:missingField', ...
                            'Reference behavior role %d: missing required field "%s"', ...
                            k, fn);
                    end
                end

                % Validate ordering value
                orderingVal = string(rEntry.ordering);
                if ~any(orderingVal == ["strict", "unordered"])
                    error('netsim:io:missingField', ...
                        'Reference behavior role "%s": ordering must be "strict" or "unordered", got "%s"', ...
                        string(rEntry.role), orderingVal);
                end

                % Validate each action
                actions = rEntry.actions;
                if isstruct(actions)
                    nActions = numel(actions);
                    getAction = @(j) actions(j);
                elseif iscell(actions)
                    nActions = numel(actions);
                    getAction = @(j) actions{j};
                else
                    nActions = 0;
                    getAction = @(j) [];
                end

                for j = 1:nActions
                    act = getAction(j);
                    actionRequiredFields = {'actionType', 'triggerEvent', 'expectedTimeSec'};
                    for fi = 1:numel(actionRequiredFields)
                        fn = actionRequiredFields{fi};
                        if ~isfield(act, fn)
                            error('netsim:io:missingField', ...
                                'Reference behavior role "%s", action %d: missing required field "%s"', ...
                                string(rEntry.role), j, fn);
                        end
                    end
                end
            end
        end

        % ------------------------------------------------------------------
        % saveReferenceBehavior
        % ------------------------------------------------------------------

        function saveReferenceBehavior(refBehavior, filePath)
            % saveReferenceBehavior  Serialize a reference behavior struct to JSON.
            %
            %   io.ScenarioLoader.saveReferenceBehavior(refBehavior, filePath)
            %
            %   Encodes the reference behavior struct as JSON and writes it to
            %   filePath.  Uses pretty-printing when supported (MATLAB R2021a+).
            %
            % Requirements: 14.3, 14.5

            % Try pretty-print first (R2021a+), fall back to plain jsonencode
            try
                jsonText = jsonencode(refBehavior, 'PrettyPrint', true);
            catch
                jsonText = jsonencode(refBehavior);
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

        function resolved = resolveRelativePath(rawPath, baseDir)
            % resolveRelativePath  Resolve a path relative to baseDir unless
            %                      it is already absolute.
            %
            %   resolved = resolveRelativePath(rawPath, baseDir)

            rawPath = char(rawPath);
            if isempty(rawPath)
                resolved = rawPath;
                return;
            end
            % Absolute path detection: starts with / (Unix) or X:\ (Windows)
            isAbsPath = (rawPath(1) == '/') || ...
                        (numel(rawPath) > 1 && rawPath(2) == ':');
            if isAbsPath || isempty(baseDir)
                resolved = rawPath;
            else
                resolved = fullfile(baseDir, rawPath);
            end
        end

    end % methods (Static, Access = private)

end % classdef
