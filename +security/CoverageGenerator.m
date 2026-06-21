classdef CoverageGenerator
    % security.CoverageGenerator  Enumerate and schedule exhaustive access attempts.
    %
    % Enumerates all (entity, classification, enclave, operation) combinations
    % from a scenario and schedules one access attempt per combination at
    % randomized simulation timestamps into an EventCalendar.
    %
    % Supports targeted mode: filter by subset of enclaves, classifications, or roles.
    % Caps combinatorial explosion at maxCoverageCombinations (default 10,000).
    %
    % Requirements: R45

    methods (Static)

        function coverage = generate(scenario, intendedPolicy, eventCalendar, config) %#ok<INUSD>
            % generate  Enumerate combinations and schedule coverage attempts.
            %
            %   coverage = security.CoverageGenerator.generate(scenario, ...
            %       intendedPolicy, eventCalendar, config)
            %
            %   Inputs:
            %     scenario       — struct from ScenarioLoader.load()
            %     intendedPolicy — struct from IntendedPolicyLoader.load()
            %     eventCalendar  — sim.EventCalendar handle (events scheduled into it)
            %     config         — struct with optional fields:
            %       simDurationSec          — total simulation duration (default 3600)
            %       maxCoverageCombinations — cap on total combinations (default 10000)
            %       targeted                — struct with optional filters:
            %         enclave        — cell array of enclave IDs to filter
            %         classification — cell array of classifications to filter
            %         role           — cell array of roles to filter
            %       seed                    — RNG seed for reproducibility (optional)
            %
            %   Returns coverage struct:
            %     totalCombinations   — total number of (entity, classification,
            %                           enclave, operation) tuples enumerated
            %     scheduledAttempts   — number of events actually scheduled
            %     coveragePercent     — scheduledAttempts / totalCombinations * 100
            %     combinations        — struct array of scheduled combinations
            %
            % Requirements: R45

            % Parse config with defaults
            if nargin < 4 || isempty(config)
                config = struct();
            end
            simDuration = 3600;
            if isfield(config, 'simDurationSec')
                simDuration = config.simDurationSec;
            end
            maxCombinations = 10000;
            if isfield(config, 'maxCoverageCombinations')
                maxCombinations = config.maxCoverageCombinations;
            end
            if isfield(config, 'seed')
                rng(config.seed);
            end

            % Extract universe from scenario
            [roles, classifications, enclaves, operations] = ...
                security.CoverageGenerator.extractUniverse(scenario);

            % Apply targeted filters if specified
            if isfield(config, 'targeted') && ~isempty(config.targeted)
                targeted = config.targeted;
                if isfield(targeted, 'role') && ~isempty(targeted.role)
                    filterRoles = targeted.role;
                    if ischar(filterRoles)
                        filterRoles = {filterRoles};
                    end
                    roles = intersect(roles, filterRoles);
                end
                if isfield(targeted, 'classification') && ~isempty(targeted.classification)
                    filterCls = targeted.classification;
                    if ischar(filterCls)
                        filterCls = {filterCls};
                    end
                    classifications = intersect(classifications, filterCls);
                end
                if isfield(targeted, 'enclave') && ~isempty(targeted.enclave)
                    filterEnc = targeted.enclave;
                    if ischar(filterEnc)
                        filterEnc = {filterEnc};
                    end
                    enclaves = intersect(enclaves, filterEnc);
                end
            end

            % Compute total combinations
            totalCombinations = numel(roles) * numel(classifications) * ...
                numel(enclaves) * numel(operations);

            % Cap at maximum
            if totalCombinations > maxCombinations
                warning('netsim:security:coverageCap', ...
                    'CoverageGenerator: %d combinations exceeds cap of %d. Sampling subset.', ...
                    totalCombinations, maxCombinations);
            end

            % Enumerate all combinations
            combinations = struct('role', {}, 'classification', {}, ...
                'enclave', {}, 'operation', {}, 'scheduledTime', {});
            idx = 0;

            for iR = 1:numel(roles)
                for iC = 1:numel(classifications)
                    for iE = 1:numel(enclaves)
                        for iO = 1:numel(operations)
                            idx = idx + 1;
                            if idx > maxCombinations
                                break;
                            end
                            c.role = roles{iR};
                            c.classification = classifications{iC};
                            c.enclave = enclaves{iE};
                            c.operation = operations{iO};
                            % Randomized time within simulation duration
                            c.scheduledTime = rand() * simDuration;
                            combinations(end+1) = c; %#ok<AGROW>
                        end
                        if idx > maxCombinations, break; end
                    end
                    if idx > maxCombinations, break; end
                end
                if idx > maxCombinations, break; end
            end

            % Schedule events into the EventCalendar
            scheduledCount = numel(combinations);
            if ~isempty(eventCalendar)
                for k = 1:scheduledCount
                    combo = combinations(k);
                    % Determine event type based on operation
                    eventType = security.CoverageGenerator.selectEventType(combo.operation);

                    % Build event struct
                    evt.time = combo.scheduledTime;
                    evt.type = eventType;
                    evt.id = uint64(100000 + k);
                    evt.payload.role = combo.role;
                    evt.payload.classification = combo.classification;
                    evt.payload.enclave = combo.enclave;
                    evt.payload.operation = combo.operation;
                    evt.payload.coverageGenerated = true;

                    eventCalendar.schedule(evt);
                end
            end

            % Build coverage output struct
            coverage.totalCombinations = totalCombinations;
            coverage.scheduledAttempts = scheduledCount;
            if totalCombinations > 0
                coverage.coveragePercent = (scheduledCount / totalCombinations) * 100;
            else
                coverage.coveragePercent = 100.0;
            end
            coverage.combinations = combinations;
        end

    end

    methods (Static, Access = private)

        function [roles, classifications, enclaves, operations] = extractUniverse(scenario)
            % extractUniverse  Extract roles, classifications, enclaves, operations
            %   from a scenario struct.

            roles = {};
            classifications = {};
            enclaves = {};
            operations = {'read', 'write', 'ingest'};

            % Extract roles from entities
            if isfield(scenario, 'entities') && ~isempty(scenario.entities)
                ents = scenario.entities;
                for k = 1:numel(ents)
                    if isfield(ents(k), 'role') && ~isempty(ents(k).role)
                        roles{end+1} = char(ents(k).role); %#ok<AGROW>
                    end
                    if isfield(ents(k), 'roles') && ~isempty(ents(k).roles)
                        r = ents(k).roles;
                        if ischar(r)
                            roles{end+1} = r; %#ok<AGROW>
                        elseif iscell(r)
                            roles = [roles, cellfun(@char, r, 'UniformOutput', false)]; %#ok<AGROW>
                        end
                    end
                end
            end
            roles = unique(roles);

            % Extract classifications
            if isfield(scenario, 'dataItems') && ~isempty(scenario.dataItems)
                items = scenario.dataItems;
                for k = 1:numel(items)
                    if isfield(items(k), 'classification') && ~isempty(items(k).classification)
                        classifications{end+1} = char(items(k).classification); %#ok<AGROW>
                    end
                end
            end
            if isfield(scenario, 'classifications') && ~isempty(scenario.classifications)
                cls = scenario.classifications;
                if iscell(cls)
                    for ci = 1:numel(cls)
                        item = cls{ci};
                        if ischar(item) || isstring(item)
                            classifications{end+1} = char(item); %#ok<AGROW>
                        end
                    end
                elseif ischar(cls)
                    classifications{end+1} = cls;
                end
            end
            classifications = unique(classifications);

            % Extract enclaves
            if isfield(scenario, 'enclaves') && ~isempty(scenario.enclaves)
                enc = scenario.enclaves;
                if isstruct(enc)
                    for k = 1:numel(enc)
                        if isfield(enc(k), 'enclaveId')
                            enclaves{end+1} = char(enc(k).enclaveId); %#ok<AGROW>
                        elseif isfield(enc(k), 'id')
                            enclaves{end+1} = char(enc(k).id); %#ok<AGROW>
                        end
                    end
                elseif iscell(enc)
                    enclaves = cellfun(@char, enc, 'UniformOutput', false);
                end
            end
            if isfield(scenario, 'nodes') && ~isempty(scenario.nodes)
                nodes = scenario.nodes;
                for k = 1:numel(nodes)
                    if isfield(nodes(k), 'enclave') && ~isempty(nodes(k).enclave)
                        enclaves{end+1} = char(nodes(k).enclave); %#ok<AGROW>
                    end
                end
            end
            enclaves = unique(enclaves);

            % Provide defaults if nothing found
            if isempty(roles)
                roles = {'default_role'};
            end
            if isempty(classifications)
                classifications = {'UNCLASSIFIED'};
            end
            if isempty(enclaves)
                enclaves = {'default'};
            end
        end

        function eventType = selectEventType(operation)
            % selectEventType  Map operation to an appropriate event type.
            %   read/write → DATA_FETCH, ingest → DATA_INGEST, else → C2_MESSAGE_TX

            switch lower(char(operation))
                case 'read'
                    eventType = "DATA_FETCH";
                case 'write'
                    eventType = "DATA_QUERY";
                case 'ingest'
                    eventType = "DATA_FETCH";
                otherwise
                    eventType = "C2_MESSAGE_TX";
            end
        end

    end

end
