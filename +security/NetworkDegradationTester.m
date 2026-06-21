classdef NetworkDegradationTester < handle
    % security.NetworkDegradationTester  Define and evaluate network degradation scenarios.
    %
    % Generates degradation scenarios (node/link outages at specified times)
    % and evaluates security outcomes during degraded conditions. Produces a
    % DegradationSecurityMatrix summarizing which security properties hold
    % under each degradation scenario.
    %
    % Requirements: R47

    properties (SetAccess = private)
        % Degradation configuration struct
        %   Fields: scenarios (struct array), securityProperties (cell array)
        config

        % Struct array of generated degradation scenarios
        %   Fields: name, targetNodes, targetLinks, outageDurationSec,
        %           startTimeSec, type
        scenarios

        % DegradationSecurityMatrix — table with rows=scenarios, cols=properties
        matrix
    end

    methods

        function obj = NetworkDegradationTester(degradationConfig)
            % NetworkDegradationTester  Construct tester from degradation config.
            %
            %   tester = security.NetworkDegradationTester(degradationConfig)
            %
            %   degradationConfig — struct with fields:
            %     scenarios (optional) — struct array of scenario definitions:
            %       name             — string identifier
            %       targetNodes      — cell array of node IDs to take offline
            %       targetLinks      — cell array of link IDs to take offline
            %       outageDurationSec— duration of the outage in seconds
            %       startTimeSec     — when the outage begins in simulation time
            %       type             — 'pdp_outage' | 'trust_anchor_outage' |
            %                          'link_outage' | 'node_outage'
            %     securityProperties (optional) — cell array of property names
            %       default: {'PDP availability', 'credential freshness',
            %                 'replication consistency', 'access control enforcement'}
            %
            % Requirements: R47

            if nargin < 1 || isempty(degradationConfig)
                degradationConfig = struct();
            end

            obj.config = degradationConfig;
            obj.scenarios = struct('name', {}, 'targetNodes', {}, ...
                'targetLinks', {}, 'outageDurationSec', {}, ...
                'startTimeSec', {}, 'type', {});
            obj.matrix = table();

            % If config already has scenario definitions, load them
            if isfield(degradationConfig, 'scenarios') && ~isempty(degradationConfig.scenarios)
                obj.loadScenariosFromConfig(degradationConfig.scenarios);
            end
        end

        function scenarios = generateScenarios(obj)
            % generateScenarios  Generate degradation scenarios from config.
            %
            %   scenarios = tester.generateScenarios()
            %
            %   If no pre-defined scenarios exist in the config, generates
            %   default degradation scenarios based on config parameters.
            %
            %   Returns struct array of degradation scenarios with fields:
            %     name, targetNodes, targetLinks, outageDurationSec,
            %     startTimeSec, type
            %
            % Requirements: R47

            if ~isempty(obj.scenarios)
                scenarios = obj.scenarios;
                return;
            end

            % Generate default scenarios from config parameters
            defaultDuration = 60;
            defaultStart = 300;
            if isfield(obj.config, 'outageDurationSec')
                defaultDuration = obj.config.outageDurationSec;
            end
            if isfield(obj.config, 'startTimeSec')
                defaultStart = obj.config.startTimeSec;
            end

            % Extract target nodes/links from config
            targetNodes = {};
            if isfield(obj.config, 'targetNodes')
                targetNodes = obj.config.targetNodes;
                if ischar(targetNodes)
                    targetNodes = {targetNodes};
                end
            end
            targetLinks = {};
            if isfield(obj.config, 'targetLinks')
                targetLinks = obj.config.targetLinks;
                if ischar(targetLinks)
                    targetLinks = {targetLinks};
                end
            end

            % Generate PDP outage scenario
            s1.name = 'pdp_outage';
            s1.targetNodes = targetNodes;
            s1.targetLinks = {};
            s1.outageDurationSec = defaultDuration;
            s1.startTimeSec = defaultStart;
            s1.type = 'pdp_outage';
            obj.scenarios(end+1) = s1;

            % Generate trust anchor outage scenario
            s2.name = 'trust_anchor_outage';
            s2.targetNodes = targetNodes;
            s2.targetLinks = {};
            s2.outageDurationSec = defaultDuration * 5;
            s2.startTimeSec = defaultStart;
            s2.type = 'trust_anchor_outage';
            obj.scenarios(end+1) = s2;

            % Generate link outage if links specified
            if ~isempty(targetLinks)
                s3.name = 'link_outage';
                s3.targetNodes = {};
                s3.targetLinks = targetLinks;
                s3.outageDurationSec = defaultDuration;
                s3.startTimeSec = defaultStart;
                s3.type = 'link_outage';
                obj.scenarios(end+1) = s3;
            end

            scenarios = obj.scenarios;
        end

        function matrix = evaluateOutcomes(obj, securityOracle, scenarios)
            % evaluateOutcomes  Evaluate security outcomes during degradation.
            %
            %   matrix = tester.evaluateOutcomes(securityOracle, scenarios)
            %
            %   securityOracle — security.SecurityOracle handle with evaluated results
            %   scenarios      — struct array of degradation scenarios (from generateScenarios)
            %
            %   Produces DegradationSecurityMatrix: for each scenario, checks
            %   which security properties held during the degradation window.
            %
            %   Returns a struct with:
            %     scenarioNames  — cell array of scenario names
            %     properties     — cell array of security property names
            %     results        — logical matrix (nScenarios x nProperties)
            %
            % Requirements: R47

            if nargin < 3 || isempty(scenarios)
                scenarios = obj.scenarios;
            end

            % Get security properties to evaluate
            properties = obj.getSecurityProperties();
            nScenarios = numel(scenarios);
            nProperties = numel(properties);

            % Initialize results matrix
            results = true(nScenarios, nProperties);
            scenarioNames = cell(1, nScenarios);

            for iS = 1:nScenarios
                scen = scenarios(iS);
                scenarioNames{iS} = scen.name;

                % Get degraded condition outcomes from oracle that fall within
                % this scenario's time window
                startT = scen.startTimeSec;
                endT = startT + scen.outageDurationSec;

                degradedEvents = obj.filterDegradedEvents(...
                    securityOracle.degradedConditionOutcomes, startT, endT);

                % Also check violations during the window
                windowViolations = obj.filterViolationsByTime(...
                    securityOracle.violations, startT, endT);

                % Evaluate each security property
                for iP = 1:nProperties
                    propName = properties{iP};
                    results(iS, iP) = obj.evaluateProperty(...
                        propName, scen, degradedEvents, windowViolations);
                end
            end

            % Build output struct
            matrix.scenarioNames = scenarioNames;
            matrix.properties = properties;
            matrix.results = results;

            % Store internally
            obj.matrix = obj.buildMatrixTable(matrix);
        end

        function tbl = buildMatrix(obj)
            % buildMatrix  Return DegradationSecurityMatrix as a MATLAB table.
            %
            %   tbl = tester.buildMatrix()
            %
            %   Rows = degradation scenarios, Columns = security properties.
            %   Values are logical (true = property held, false = property violated).
            %
            % Requirements: R47

            if isempty(obj.matrix)
                % Return empty table with property columns
                properties = obj.getSecurityProperties();
                tbl = table();
                for k = 1:numel(properties)
                    tbl.(matlab.lang.makeValidName(properties{k})) = logical([]);
                end
                return;
            end

            tbl = obj.matrix;
        end

    end

    methods (Access = private)

        function loadScenariosFromConfig(obj, scenarioDefs)
            % loadScenariosFromConfig  Load scenario definitions from config.

            for k = 1:numel(scenarioDefs)
                s = scenarioDefs(k);

                scen.name = '';
                if isfield(s, 'name')
                    scen.name = char(s.name);
                else
                    scen.name = sprintf('scenario_%d', k);
                end

                scen.targetNodes = {};
                if isfield(s, 'targetNodes')
                    tn = s.targetNodes;
                    if ischar(tn)
                        scen.targetNodes = {tn};
                    elseif iscell(tn)
                        scen.targetNodes = tn;
                    end
                end

                scen.targetLinks = {};
                if isfield(s, 'targetLinks')
                    tl = s.targetLinks;
                    if ischar(tl)
                        scen.targetLinks = {tl};
                    elseif iscell(tl)
                        scen.targetLinks = tl;
                    end
                end

                scen.outageDurationSec = 60;
                if isfield(s, 'outageDurationSec')
                    scen.outageDurationSec = double(s.outageDurationSec);
                end

                scen.startTimeSec = 0;
                if isfield(s, 'startTimeSec')
                    scen.startTimeSec = double(s.startTimeSec);
                end

                scen.type = 'node_outage';
                if isfield(s, 'type')
                    scen.type = char(s.type);
                end

                obj.scenarios(end+1) = scen;
            end
        end

        function properties = getSecurityProperties(obj)
            % getSecurityProperties  Get the list of security properties to evaluate.

            if isfield(obj.config, 'securityProperties') && ...
                    ~isempty(obj.config.securityProperties)
                properties = obj.config.securityProperties;
            else
                properties = {'PDP availability', 'credential freshness', ...
                    'replication consistency', 'access control enforcement'};
            end
        end

        function filtered = filterDegradedEvents(~, degradedOutcomes, startT, endT)
            % filterDegradedEvents  Filter degraded outcomes by time window.

            filtered = struct('entityId', {}, 'operation', {}, ...
                'outcome', {}, 'reason', {}, 'degradedOnly', {}, ...
                'simTimeSec', {});

            for k = 1:numel(degradedOutcomes)
                evt = degradedOutcomes(k);
                if evt.simTimeSec >= startT && evt.simTimeSec <= endT
                    filtered(end+1) = evt; %#ok<AGROW>
                end
            end
        end

        function filtered = filterViolationsByTime(~, violations, startT, endT)
            % filterViolationsByTime  Filter violations by time window.

            filtered = struct('entityId', {}, 'resourceId', {}, ...
                'enclave', {}, 'operation', {}, 'actualOutcome', {}, ...
                'intendedOutcome', {}, 'simTimeSec', {}, 'adversarialSource', {});

            for k = 1:numel(violations)
                v = violations(k);
                if v.simTimeSec >= startT && v.simTimeSec <= endT
                    filtered(end+1) = v; %#ok<AGROW>
                end
            end
        end

        function holds = evaluateProperty(~, propertyName, scenario, ...
                degradedEvents, windowViolations)
            % evaluateProperty  Check if a security property holds during degradation.
            %
            %   Returns true if property held, false if violated.

            switch propertyName
                case 'PDP availability'
                    % Property holds if scenario type is not pdp_outage
                    % or no violations occurred during outage
                    if strcmp(scenario.type, 'pdp_outage')
                        holds = isempty(windowViolations);
                    else
                        holds = true;
                    end

                case 'credential freshness'
                    % Property holds if no expired credential access succeeded
                    if strcmp(scenario.type, 'trust_anchor_outage')
                        % Check if any degraded events show permit with expired creds
                        holds = true;
                        for k = 1:numel(degradedEvents)
                            if strcmp(degradedEvents(k).outcome, 'permit')
                                holds = false;
                                break;
                            end
                        end
                    else
                        holds = true;
                    end

                case 'replication consistency'
                    % Property holds if no data inconsistency during outage
                    % (simplified: true unless we have degraded events indicating issues)
                    holds = numel(degradedEvents) < 3;

                case 'access control enforcement'
                    % Property holds if no violations during degraded window
                    holds = isempty(windowViolations);

                otherwise
                    % Unknown property — assume holds
                    holds = true;
            end
        end

        function tbl = buildMatrixTable(~, matrixStruct)
            % buildMatrixTable  Convert matrix struct to MATLAB table.

            nScenarios = numel(matrixStruct.scenarioNames);
            nProperties = numel(matrixStruct.properties);

            if nScenarios == 0
                tbl = table();
                return;
            end

            % Build table with scenario names as row names
            varNames = cell(1, nProperties);
            for k = 1:nProperties
                varNames{k} = matlab.lang.makeValidName(matrixStruct.properties{k});
            end

            tbl = array2table(matrixStruct.results, ...
                'VariableNames', varNames, ...
                'RowNames', matrixStruct.scenarioNames);
        end

    end

end
