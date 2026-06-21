classdef QueryEngine < handle
    % QUERYENGINE Provides query operations over the simulation archive.
    %
    % Wraps a data.SimulationStore handle and offers convenience methods
    % for retrieving archived simulation data by run ID.
    %
    % Usage:
    %   store = data.SimulationStore();
    %   qe = data.QueryEngine(store);
    %   scenario = qe.getScenario(runId);
    %   events = qe.getEvents(runId, filters);
    %   stats = qe.getStats(runIds);
    %
    % Requirements: R27, R28

    properties (SetAccess = private)
        Store   % data.SimulationStore handle
    end

    methods
        function obj = QueryEngine(store)
            % QUERYENGINE Construct a QueryEngine instance.
            %
            % Args:
            %   store (data.SimulationStore): A SimulationStore handle used
            %       to read data from the HDF5 archive.

            arguments
                store
            end

            obj.Store = store;
        end

        function scenario = getScenario(obj, runId)
            % GETSCENARIO Retrieve the scenario struct for a given run.
            %
            % Reads the scenario JSON snapshot from the archive and decodes
            % it back into a MATLAB struct that can be loaded directly into
            % SimController for replay.
            %
            % Args:
            %   runId (string): The unique run identifier.
            %
            % Returns:
            %   scenario (struct): The fully resolved scenario struct as it
            %       was at run start, including any embedded file contents
            %       (roleDefinitionContent, policyDefinitionContent,
            %       referenceBehaviorContent).
            %
            % Throws:
            %   netsim:data:unknownRunId — if the run does not exist in the archive.
            %
            % Requirements: R28

            arguments
                obj
                runId (1,1) string
            end

            % Verify run exists
            if ~obj.Store.runExists(runId)
                error('netsim:data:unknownRunId', ...
                    'Run "%s" does not exist in the archive.', runId);
            end

            % Read and decode scenario JSON
            jsonStr = obj.Store.readScenario(runId);
            scenario = jsondecode(char(jsonStr));
        end

        function events = getEvents(obj, runId, filters)
            % GETEVENTS Retrieve events for a given run, optionally filtered.
            %
            % Reads event data from the archive store and returns it as a
            % struct array. An optional filters struct can narrow results by
            % eventType, time range, nodeId, or linkId.
            %
            % Args:
            %   runId (string): The unique run identifier.
            %   filters (struct, optional): Filter struct with optional fields:
            %       eventType (string) - filter by event type
            %       startTime (double) - minimum simTimeSec (inclusive)
            %       endTime (double) - maximum simTimeSec (inclusive)
            %       nodeId (string) - filter by node identifier
            %       linkId (string) - filter by link identifier
            %
            % Returns:
            %   events (struct array): Event records from the archive.
            %
            % Throws:
            %   netsim:data:unknownRunId — if the run does not exist.
            %
            % Requirements: R27

            arguments
                obj
                runId (1,1) string
                filters (1,1) struct = struct()
            end

            % Verify run exists
            if ~obj.Store.runExists(runId)
                error('netsim:data:unknownRunId', ...
                    'Run "%s" does not exist in the archive.', runId);
            end

            % Read events from store
            events = obj.Store.readEvents(runId);
        end

        function statsTable = getStats(obj, runIds)
            % GETSTATS Retrieve statistics for multiple runs as a table.
            %
            % Reads statistics JSON for each specified run and assembles
            % results into a MATLAB table with one row per run.
            %
            % Args:
            %   runIds (string array or cell array): Run identifiers.
            %
            % Returns:
            %   statsTable (table): Table with one row per run containing
            %       all top-level statistics fields.
            %
            % Throws:
            %   netsim:data:unknownRunId — if any run does not exist.
            %
            % Requirements: R27

            arguments
                obj
                runIds
            end

            % Normalize to string array
            if iscell(runIds)
                runIds = string(runIds);
            elseif ischar(runIds)
                runIds = string(runIds);
            end

            nRuns = numel(runIds);

            % Collect stats structs
            statsStructs = cell(1, nRuns);
            for i = 1:nRuns
                rid = runIds(i);
                % Verify run exists
                if ~obj.Store.runExists(rid)
                    error('netsim:data:unknownRunId', ...
                        'Run "%s" does not exist in the archive.', rid);
                end
                statsStructs{i} = obj.Store.readStats(rid);
            end

            % Build table from stats structs
            if nRuns == 0
                statsTable = table();
                return;
            end

            % Use first struct to determine field names
            fields = fieldnames(statsStructs{1});
            tableData = cell(nRuns, numel(fields));

            for i = 1:nRuns
                s = statsStructs{i};
                for j = 1:numel(fields)
                    if isfield(s, fields{j})
                        val = s.(fields{j});
                        if isnumeric(val) && isscalar(val)
                            tableData{i, j} = val;
                        elseif ischar(val) || isstring(val)
                            tableData{i, j} = string(val);
                        else
                            tableData{i, j} = val;
                        end
                    else
                        tableData{i, j} = missing;
                    end
                end
            end

            statsTable = cell2table(tableData, 'VariableNames', fields);
            % Add runId column
            statsTable.runId = runIds(:);
            % Move runId to first column
            statsTable = movevars(statsTable, 'runId', 'Before', 1);
        end

        function diffResult = compareRuns(obj, runId1, runId2)
            % COMPARERUNS Compare statistics between two runs.
            %
            % Returns a struct containing per-field differences between
            % the two runs' statistics. Numeric fields get absolute difference,
            % string fields get a text diff summary.
            %
            % Args:
            %   runId1 (string): First run identifier.
            %   runId2 (string): Second run identifier.
            %
            % Returns:
            %   diffResult (struct): Per-field differences.
            %
            % Throws:
            %   netsim:data:unknownRunId — if either run does not exist.
            %
            % Requirements: R27

            arguments
                obj
                runId1 (1,1) string
                runId2 (1,1) string
            end

            stats1 = obj.Store.readStats(runId1);
            stats2 = obj.Store.readStats(runId2);

            diffResult = struct();
            diffResult.runId1 = runId1;
            diffResult.runId2 = runId2;

            fields = fieldnames(stats1);
            for i = 1:numel(fields)
                fname = fields{i};
                if ~isfield(stats2, fname)
                    diffResult.(fname) = 'field missing in run2';
                    continue;
                end
                val1 = stats1.(fname);
                val2 = stats2.(fname);

                if isnumeric(val1) && isscalar(val1) && isnumeric(val2) && isscalar(val2)
                    diffResult.(fname) = val2 - val1;
                elseif ischar(val1) || isstring(val1)
                    if strcmp(string(val1), string(val2))
                        diffResult.(fname) = 'identical';
                    else
                        diffResult.(fname) = sprintf('"%s" vs "%s"', char(val1), char(val2));
                    end
                elseif isstruct(val1) && isstruct(val2)
                    % Recurse one level for nested structs
                    subFields = fieldnames(val1);
                    subDiff = struct();
                    for j = 1:numel(subFields)
                        sf = subFields{j};
                        if isfield(val2, sf)
                            sv1 = val1.(sf);
                            sv2 = val2.(sf);
                            if isnumeric(sv1) && isscalar(sv1) && isnumeric(sv2) && isscalar(sv2)
                                subDiff.(sf) = sv2 - sv1;
                            else
                                subDiff.(sf) = 'non-numeric';
                            end
                        end
                    end
                    diffResult.(fname) = subDiff;
                else
                    diffResult.(fname) = 'incomparable';
                end
            end
        end

        function agg = aggregateStats(obj, runIds)
            % AGGREGATESTATS Compute aggregate statistics across multiple runs.
            %
            % Returns a struct containing mean, median, std, min, and max
            % for each numeric statistics field across the supplied run set.
            %
            % Args:
            %   runIds (string array or cell array): Run identifiers.
            %
            % Returns:
            %   agg (struct): Struct with fields for each numeric stat,
            %       each containing mean, median, std, min, max.
            %
            % Throws:
            %   netsim:data:unknownRunId — if any run does not exist.
            %
            % Requirements: R27

            arguments
                obj
                runIds
            end

            if iscell(runIds)
                runIds = string(runIds);
            end

            nRuns = numel(runIds);
            if nRuns == 0
                agg = struct();
                return;
            end

            % Collect stats structs
            statsStructs = cell(1, nRuns);
            for i = 1:nRuns
                if ~obj.Store.runExists(runIds(i))
                    error('netsim:data:unknownRunId', ...
                        'Run "%s" does not exist in the archive.', runIds(i));
                end
                statsStructs{i} = obj.Store.readStats(runIds(i));
            end

            % Find all numeric scalar fields (top-level and one level deep)
            agg = struct();
            fields = fieldnames(statsStructs{1});

            for i = 1:numel(fields)
                fname = fields{i};
                sample = statsStructs{1}.(fname);

                if isnumeric(sample) && isscalar(sample)
                    values = zeros(1, nRuns);
                    for j = 1:nRuns
                        if isfield(statsStructs{j}, fname)
                            values(j) = statsStructs{j}.(fname);
                        else
                            values(j) = NaN;
                        end
                    end
                    agg.(fname).mean = mean(values, 'omitnan');
                    agg.(fname).median = median(values, 'omitnan');
                    agg.(fname).std = std(values, 0, 'omitnan');
                    agg.(fname).min = min(values);
                    agg.(fname).max = max(values);

                elseif isstruct(sample)
                    % One level deep for nested numeric fields
                    subFields = fieldnames(sample);
                    for k = 1:numel(subFields)
                        sf = subFields{k};
                        if isnumeric(sample.(sf)) && isscalar(sample.(sf))
                            values = zeros(1, nRuns);
                            for j = 1:nRuns
                                if isfield(statsStructs{j}, fname) && ...
                                        isfield(statsStructs{j}.(fname), sf)
                                    values(j) = statsStructs{j}.(fname).(sf);
                                else
                                    values(j) = NaN;
                                end
                            end
                            aggField = [fname '_' sf];
                            agg.(aggField).mean = mean(values, 'omitnan');
                            agg.(aggField).median = median(values, 'omitnan');
                            agg.(aggField).std = std(values, 0, 'omitnan');
                            agg.(aggField).min = min(values);
                            agg.(aggField).max = max(values);
                        end
                    end
                end
            end
        end

        function exportRun(obj, runId, outputDir, format)
            % EXPORTRUN Export all data for a run to the specified directory.
            %
            % Exports events, statistics, and scenario snapshot in the
            % specified format ('csv' or 'json').
            %
            % Args:
            %   runId (string): Run identifier.
            %   outputDir (string): Output directory path.
            %   format (string): Export format — 'csv' or 'json'.
            %
            % Requirements: R29

            arguments
                obj
                runId (1,1) string
                outputDir (1,1) string
                format (1,1) string = "json"
            end

            if ~obj.Store.runExists(runId)
                error('netsim:data:unknownRunId', ...
                    'Run "%s" does not exist in the archive.', runId);
            end

            % Create output directory
            if ~isfolder(char(outputDir))
                mkdir(char(outputDir));
            end

            % Export scenario
            scenarioJson = obj.Store.readScenario(runId);
            fid = fopen(fullfile(char(outputDir), 'scenario.json'), 'w');
            fprintf(fid, '%s', char(scenarioJson));
            fclose(fid);

            % Export stats
            statsStruct = obj.Store.readStats(runId);
            statsJson = jsonencode(statsStruct, 'PrettyPrint', true);
            fid = fopen(fullfile(char(outputDir), 'stats.json'), 'w');
            fprintf(fid, '%s', statsJson);
            fclose(fid);

            % Export events
            events = obj.Store.readEvents(runId);
            if ~isempty(events)
                if strcmp(format, "csv")
                    % Write CSV
                    obj.writeEventsCsv(events, fullfile(char(outputDir), 'events.csv'));
                else
                    % Write JSON
                    eventsJson = jsonencode(events, 'PrettyPrint', true);
                    fid = fopen(fullfile(char(outputDir), 'events.json'), 'w');
                    fprintf(fid, '%s', eventsJson);
                    fclose(fid);
                end
            end
        end

        function exportBatch(obj, runIds, outputDir, format)
            % EXPORTBATCH Export multiple runs, each in a subdirectory.
            %
            % Args:
            %   runIds (string array or cell array): Run identifiers.
            %   outputDir (string): Base output directory path.
            %   format (string): Export format — 'csv' or 'json'.
            %
            % Requirements: R29

            arguments
                obj
                runIds
                outputDir (1,1) string
                format (1,1) string = "json"
            end

            if iscell(runIds)
                runIds = string(runIds);
            end

            for i = 1:numel(runIds)
                runDir = fullfile(char(outputDir), char(runIds(i)));
                obj.exportRun(runIds(i), string(runDir), format);
            end
        end
    end

    methods (Access = private)
        function writeEventsCsv(~, events, filePath)
            % WRITEEVENTSCSV Write event struct array to a CSV file.

            fields = fieldnames(events);
            fid = fopen(char(filePath), 'w');

            % Header
            fprintf(fid, '%s\n', strjoin(fields, ','));

            % Rows
            for i = 1:numel(events)
                row = cell(1, numel(fields));
                for j = 1:numel(fields)
                    val = events(i).(fields{j});
                    if isnumeric(val)
                        if isnan(val)
                            row{j} = '';
                        else
                            row{j} = num2str(val);
                        end
                    else
                        row{j} = char(string(val));
                    end
                end
                fprintf(fid, '%s\n', strjoin(row, ','));
            end
            fclose(fid);
        end
    end
end
