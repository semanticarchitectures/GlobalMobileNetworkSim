classdef RunRegistry < handle
    % RUNREGISTRY JSON flat-file run catalog for simulation runs.
    %
    % Persists run records as a JSON array in a flat file. Supports CRUD
    % operations, filtering, annotation, and UUID v4 generation.
    %
    % Usage:
    %   reg = data.RunRegistry();                    % default path
    %   reg = data.RunRegistry('my_registry.json');  % custom path
    %   reg.addRun(record);
    %   tbl = reg.list();
    %   tbl = reg.list(struct('scenarioName', "Airdrop*"));
    %   reg.annotate(runId, 'note', 'baseline run');
    %   rec = reg.getRecord(runId);
    %   reg.removeRun(runId);
    %   n = reg.count();
    %
    % Requirements: R25

    properties (SetAccess = private)
        RegistryPath (1,1) string
    end

    properties (Access = private)
        Records (:,1) cell = {}
    end

    methods
        function obj = RunRegistry(registryPath)
            % RUNREGISTRY Construct a RunRegistry instance.
            %
            % Args:
            %   registryPath (string, optional): Path to the JSON registry
            %       file. Defaults to fullfile('data', 'run_registry.json').
            %
            % Loads existing records from the file. If the file is missing
            % or corrupted, creates an empty registry and logs a warning.

            arguments
                registryPath (1,1) string = string(fullfile('data', 'run_registry.json'))
            end

            obj.RegistryPath = registryPath;
            obj.loadRegistry();
        end

        function addRun(obj, record)
            % ADDRUN Append a run record to the registry and save to disk.
            %
            % Args:
            %   record (struct): Run record struct with fields:
            %       runId, scenarioName, scenarioFilePath, simStartTime,
            %       simEndTime, wallClockDurationSec, nodeCount, linkCount,
            %       c2MessagesScheduled, c2MessagesDelivered,
            %       c2MessagesFailed, archiveStorePath, metadata

            arguments
                obj
                record (1,1) struct
            end

            % Ensure metadata field exists
            if ~isfield(record, 'metadata')
                record.metadata = struct();
            end

            obj.Records{end+1, 1} = record;
            obj.saveRegistry();
        end

        function tbl = list(obj, filters)
            % LIST Return a MATLAB table of records matching filters.
            %
            % Args:
            %   filters (struct, optional): Filter criteria with fields:
            %       scenarioName - pattern match (supports wildcards via contains/matches)
            %       dateRange    - [startDatetime, endDatetime] (datetime array)
            %       minFidelityScore - minimum fidelity score (double)
            %       Additional fields are treated as metadata key-value matches.
            %
            % Returns:
            %   tbl (table): Table of matching run records.

            arguments
                obj
                filters (1,1) struct = struct()
            end

            if isempty(obj.Records)
                tbl = table();
                return;
            end

            % Determine which records match the filters
            nRecs = numel(obj.Records);
            mask = true(nRecs, 1);

            filterFields = fieldnames(filters);

            for i = 1:nRecs
                rec = obj.Records{i};

                for f = 1:numel(filterFields)
                    fname = filterFields{f};

                    if strcmp(fname, 'scenarioName')
                        % Pattern match on scenario name
                        pattern = string(filters.scenarioName);
                        if isfield(rec, 'scenarioName')
                            recName = string(rec.scenarioName);
                            % Support wildcard patterns using regexp
                            regexPattern = regexptranslate('wildcard', pattern);
                            if isempty(regexp(recName, regexPattern, 'once'))
                                mask(i) = false;
                            end
                        else
                            mask(i) = false;
                        end

                    elseif strcmp(fname, 'dateRange')
                        % Date range filter on simStartTime
                        dateRange = filters.dateRange;
                        if isfield(rec, 'simStartTime')
                            try
                                recTime = datetime(rec.simStartTime, 'InputFormat', 'yyyy-MM-dd''T''HH:mm:ss.SSS''Z''', 'TimeZone', 'UTC');
                            catch
                                try
                                    recTime = datetime(rec.simStartTime, 'InputFormat', 'yyyy-MM-dd''T''HH:mm:ss''Z''', 'TimeZone', 'UTC');
                                catch
                                    recTime = datetime(rec.simStartTime, 'TimeZone', 'UTC');
                                end
                            end
                            startDt = dateRange(1);
                            endDt = dateRange(2);
                            if recTime < startDt || recTime > endDt
                                mask(i) = false;
                            end
                        else
                            mask(i) = false;
                        end

                    elseif strcmp(fname, 'minFidelityScore')
                        % Minimum fidelity score filter (in metadata)
                        minScore = filters.minFidelityScore;
                        if isfield(rec, 'metadata') && isfield(rec.metadata, 'fidelityScore')
                            if rec.metadata.fidelityScore < minScore
                                mask(i) = false;
                            end
                        else
                            mask(i) = false;
                        end

                    else
                        % Treat as metadata key-value match
                        if isfield(rec, 'metadata') && isfield(rec.metadata, fname)
                            if ~isequal(rec.metadata.(fname), filters.(fname))
                                mask(i) = false;
                            end
                        else
                            mask(i) = false;
                        end
                    end
                end
            end

            % Build table from matching records
            matchingRecs = obj.Records(mask);
            if isempty(matchingRecs)
                tbl = table();
                return;
            end

            tbl = obj.recordsToTable(matchingRecs);
        end

        function annotate(obj, runId, key, value)
            % ANNOTATE Add/update a metadata key-value pair on a run record.
            %
            % Args:
            %   runId (string): Run identifier
            %   key (string): Metadata key name
            %   value: Metadata value (any type)

            arguments
                obj
                runId (1,1) string
                key (1,1) string
                value
            end

            idx = obj.findRecordIndex(runId);
            if isempty(idx)
                error('netsim:data:unknownRunId', ...
                    'Run ID "%s" not found in the registry.', runId);
            end

            if ~isfield(obj.Records{idx}, 'metadata')
                obj.Records{idx}.metadata = struct();
            end
            obj.Records{idx}.metadata.(key) = value;
            obj.saveRegistry();
        end

        function rec = getRecord(obj, runId)
            % GETRECORD Return the record struct for a specific run ID.
            %
            % Args:
            %   runId (string): Run identifier
            %
            % Returns:
            %   rec (struct): The run record struct

            arguments
                obj
                runId (1,1) string
            end

            idx = obj.findRecordIndex(runId);
            if isempty(idx)
                error('netsim:data:unknownRunId', ...
                    'Run ID "%s" not found in the registry.', runId);
            end

            rec = obj.Records{idx};
        end

        function removeRun(obj, runId)
            % REMOVERUN Remove a run record from the registry and save.
            %
            % Args:
            %   runId (string): Run identifier to remove

            arguments
                obj
                runId (1,1) string
            end

            idx = obj.findRecordIndex(runId);
            if isempty(idx)
                error('netsim:data:unknownRunId', ...
                    'Run ID "%s" not found in the registry.', runId);
            end

            obj.Records(idx) = [];
            obj.saveRegistry();
        end

        function n = count(obj)
            % COUNT Return the number of runs in the registry.
            %
            % Returns:
            %   n (double): Number of run records

            n = numel(obj.Records);
        end
    end

    methods (Static)
        function id = generateRunId()
            % GENERATERUNID Generate a UUID v4 string.
            %
            % Uses java.util.UUID for random UUID generation.
            %
            % Returns:
            %   id (string): UUID v4 string (e.g., "550e8400-e29b-41d4-a716-446655440000")

            javaUUID = java.util.UUID.randomUUID();
            id = string(javaUUID.toString());
        end
    end

    methods (Access = private)
        function loadRegistry(obj)
            % LOADREGISTRY Load records from the JSON file.
            % If the file is missing or corrupted, creates an empty
            % registry and logs a warning (never errors).

            if ~isfile(obj.RegistryPath)
                % File doesn't exist — start with empty registry
                obj.Records = {};
                warning('netsim:data:registryMissing', ...
                    'Registry file "%s" not found. Starting with empty registry.', ...
                    obj.RegistryPath);
                return;
            end

            try
                jsonText = fileread(char(obj.RegistryPath));
                if isempty(strtrim(jsonText))
                    obj.Records = {};
                    return;
                end
                decoded = jsondecode(jsonText);

                % Convert struct array to cell array of structs
                if isstruct(decoded)
                    nRecs = numel(decoded);
                    obj.Records = cell(nRecs, 1);
                    for i = 1:nRecs
                        obj.Records{i} = decoded(i);
                    end
                elseif isempty(decoded)
                    obj.Records = {};
                else
                    obj.Records = {};
                end
            catch ME
                % Corrupted file — start with empty registry
                obj.Records = {};
                warning('netsim:data:registryCorrupted', ...
                    'Registry file "%s" is corrupted (%s). Starting with empty registry.', ...
                    obj.RegistryPath, ME.message);
            end
        end

        function saveRegistry(obj)
            % SAVEREGISTRY Persist records to the JSON file.

            % Ensure parent directory exists
            parentDir = fileparts(char(obj.RegistryPath));
            if ~isempty(parentDir) && ~isfolder(parentDir)
                mkdir(parentDir);
            end

            % Convert cell array to struct array for JSON encoding
            if isempty(obj.Records)
                jsonText = '[]';
            else
                recArray = [obj.Records{:}];
                jsonText = jsonencode(recArray, 'PrettyPrint', true);
            end

            fid = fopen(char(obj.RegistryPath), 'w');
            if fid == -1
                warning('netsim:data:registrySaveFailed', ...
                    'Could not write registry file "%s".', obj.RegistryPath);
                return;
            end
            fprintf(fid, '%s', jsonText);
            fclose(fid);
        end

        function idx = findRecordIndex(obj, runId)
            % FINDRECORDINDEX Find the index of a record by runId.
            %
            % Returns:
            %   idx (double or empty): Index into Records cell array, or []

            idx = [];
            for i = 1:numel(obj.Records)
                if isfield(obj.Records{i}, 'runId') && ...
                        strcmp(string(obj.Records{i}.runId), runId)
                    idx = i;
                    return;
                end
            end
        end

        function tbl = recordsToTable(~, records)
            % RECORDSTOTABLE Convert a cell array of record structs to a table.

            n = numel(records);

            runId = strings(n, 1);
            scenarioName = strings(n, 1);
            scenarioFilePath = strings(n, 1);
            simStartTime = strings(n, 1);
            simEndTime = strings(n, 1);
            wallClockDurationSec = zeros(n, 1);
            nodeCount = zeros(n, 1);
            linkCount = zeros(n, 1);
            c2MessagesScheduled = zeros(n, 1);
            c2MessagesDelivered = zeros(n, 1);
            c2MessagesFailed = zeros(n, 1);
            archiveStorePath = strings(n, 1);

            for i = 1:n
                rec = records{i};
                if isfield(rec, 'runId'), runId(i) = string(rec.runId); end
                if isfield(rec, 'scenarioName'), scenarioName(i) = string(rec.scenarioName); end
                if isfield(rec, 'scenarioFilePath'), scenarioFilePath(i) = string(rec.scenarioFilePath); end
                if isfield(rec, 'simStartTime'), simStartTime(i) = string(rec.simStartTime); end
                if isfield(rec, 'simEndTime'), simEndTime(i) = string(rec.simEndTime); end
                if isfield(rec, 'wallClockDurationSec'), wallClockDurationSec(i) = rec.wallClockDurationSec; end
                if isfield(rec, 'nodeCount'), nodeCount(i) = rec.nodeCount; end
                if isfield(rec, 'linkCount'), linkCount(i) = rec.linkCount; end
                if isfield(rec, 'c2MessagesScheduled'), c2MessagesScheduled(i) = rec.c2MessagesScheduled; end
                if isfield(rec, 'c2MessagesDelivered'), c2MessagesDelivered(i) = rec.c2MessagesDelivered; end
                if isfield(rec, 'c2MessagesFailed'), c2MessagesFailed(i) = rec.c2MessagesFailed; end
                if isfield(rec, 'archiveStorePath'), archiveStorePath(i) = string(rec.archiveStorePath); end
            end

            tbl = table(runId, scenarioName, scenarioFilePath, simStartTime, ...
                simEndTime, wallClockDurationSec, nodeCount, linkCount, ...
                c2MessagesScheduled, c2MessagesDelivered, c2MessagesFailed, ...
                archiveStorePath);
        end
    end
end
