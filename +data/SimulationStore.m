classdef SimulationStore < handle
    % SIMULATIONSTORE HDF5-backed archive for simulation runs.
    %
    % Provides create/read/write/delete operations on an HDF5 archive file
    % organized with a group-per-run layout:
    %   /runs/<runId>/events   — event log datasets
    %   /runs/<runId>/stats    — statistics JSON
    %   /runs/<runId>/scenario — scenario JSON snapshot
    %   /runs/<runId>/agent    — agent behavior data
    %   /runs/<runId>/icam     — ICAM audit data
    %
    % The archive root carries a 'schemaVersion' attribute and a 'README'
    % attribute describing the schema layout.
    %
    % Requirements: R30, R32

    properties (SetAccess = private)
        ArchivePath (1,1) string
    end

    methods
        function obj = SimulationStore(archivePath)
            % SIMULATIONSTORE Construct a SimulationStore instance.
            %
            % Args:
            %   archivePath (string, optional): Path to the HDF5 archive file.
            %       Defaults to fullfile('data', 'simulation_archive.h5').
            %
            % Creates the HDF5 file if it does not exist, writing the
            % schemaVersion and README attributes at the root group.
            % Opens an existing file and validates the schema version.

            arguments
                archivePath (1,1) string = string(fullfile('data', 'simulation_archive.h5'))
            end

            obj.ArchivePath = archivePath;

            if ~isfile(archivePath)
                % Create parent directory if needed
                parentDir = fileparts(char(archivePath));
                if ~isempty(parentDir) && ~isfolder(parentDir)
                    mkdir(parentDir);
                end

                % Create new HDF5 file with a small placeholder dataset
                % (HDF5 files need at least one dataset to be created via h5create)
                h5create(char(archivePath), '/__placeholder', 1);
                h5write(char(archivePath), '/__placeholder', int8(0));

                % Write root attributes
                h5writeatt(char(archivePath), '/', 'schemaVersion', char(data.SchemaVersion.CURRENT));
                h5writeatt(char(archivePath), '/', 'README', ...
                    'SimulationStore HDF5 Archive. Schema version stored in schemaVersion attribute. Layout: /runs/<runId>/{events,stats,scenario,agent,icam}. See design documentation for full schema definition.');
            else
                % Open existing file — validate schema version
                fileVersion = string(h5readatt(char(archivePath), '/', 'schemaVersion'));
                if ~data.SchemaVersion.isCompatible(fileVersion, data.SchemaVersion.CURRENT)
                    [fileMajor, ~] = data.SchemaVersion.parse(fileVersion);
                    [curMajor, ~] = data.SchemaVersion.parse(data.SchemaVersion.CURRENT);
                    error('netsim:data:schemaMajorVersionMismatch', ...
                        'Archive "%s" has schema major version %d but current is %d (file: %s, current: %s).', ...
                        archivePath, fileMajor, curMajor, fileVersion, data.SchemaVersion.CURRENT);
                end

                % Apply migrations if minor version is older
                data.SchemaVersion.applyMigrations(obj, fileVersion);
            end
        end

        function createRun(obj, runId)
            % CREATERUN Create a new run group with standard subgroups.
            %
            % Args:
            %   runId (string): Unique run identifier (e.g., UUID)

            arguments
                obj
                runId (1,1) string
            end

            basePath = "/runs/" + runId;
            subgroups = ["events", "stats", "scenario", "agent", "icam"];

            for i = 1:numel(subgroups)
                dsPath = basePath + "/" + subgroups(i) + "/__init";
                h5create(char(obj.ArchivePath), char(dsPath), 1);
                h5write(char(obj.ArchivePath), char(dsPath), int8(0));
            end
        end

        function writeEvents(obj, runId, eventLog)
            % WRITEEVENTS Write event struct array fields as datasets.
            %
            % Each field of the eventLog struct array is stored as a
            % separate dataset under /runs/<runId>/events/.
            %
            % Args:
            %   runId (string): Run identifier
            %   eventLog (struct array): Event log with fields like
            %       eventId, simTimeSec, eventType, linkId, msgId, etc.

            arguments
                obj
                runId (1,1) string
                eventLog struct
            end

            basePath = "/runs/" + runId + "/events";
            fields = fieldnames(eventLog);
            nEvents = numel(eventLog);

            for i = 1:numel(fields)
                fname = fields{i};
                dsPath = char(basePath + "/" + fname);
                values = {eventLog.(fname)};

                % Determine data type and write appropriately
                if nEvents == 0
                    continue;
                end

                sample = values{1};
                if isnumeric(sample)
                    numData = cellfun(@double, values);
                    obj.createAndWrite(dsPath, numData);
                elseif ischar(sample) || isstring(sample)
                    strData = string(values);
                    obj.writeStringDataset(dsPath, strData);
                else
                    % Fallback: convert to string
                    strData = string(cellfun(@char, values, 'UniformOutput', false));
                    obj.writeStringDataset(dsPath, strData);
                end
            end
        end

        function eventLog = readEvents(obj, runId)
            % READEVENTS Read event data back as a struct array.
            %
            % Args:
            %   runId (string): Run identifier
            %
            % Returns:
            %   eventLog (struct array): Reconstructed event struct array

            arguments
                obj
                runId (1,1) string
            end

            basePath = "/runs/" + runId + "/events";
            info = h5info(char(obj.ArchivePath), char(basePath));

            % Get dataset names (exclude __init placeholder)
            dsNames = {};
            if ~isempty(info.Datasets)
                for i = 1:numel(info.Datasets)
                    name = info.Datasets(i).Name;
                    if ~strcmp(name, '__init')
                        dsNames{end+1} = name; %#ok<AGROW>
                    end
                end
            end

            if isempty(dsNames)
                eventLog = struct([]);
                return;
            end

            % Read each dataset
            eventLog = struct();
            nEvents = 0;
            for i = 1:numel(dsNames)
                dsPath = char(basePath + "/" + dsNames{i});
                rawData = h5read(char(obj.ArchivePath), dsPath);

                if isnumeric(rawData)
                    nEvents = numel(rawData);
                    for j = 1:nEvents
                        eventLog(j).(dsNames{i}) = rawData(j);
                    end
                elseif iscell(rawData)
                    nEvents = numel(rawData);
                    for j = 1:nEvents
                        eventLog(j).(dsNames{i}) = string(rawData{j});
                    end
                elseif isstring(rawData)
                    nEvents = numel(rawData);
                    for j = 1:nEvents
                        eventLog(j).(dsNames{i}) = rawData(j);
                    end
                end
            end
        end

        function writeStats(obj, runId, statsStruct)
            % WRITESTATS Write statistics as a JSON string dataset.
            %
            % Args:
            %   runId (string): Run identifier
            %   statsStruct (struct): Statistics structure to encode as JSON

            arguments
                obj
                runId (1,1) string
                statsStruct struct
            end

            jsonStr = jsonencode(statsStruct);
            dsPath = char("/runs/" + runId + "/stats/json");
            obj.writeStringDataset(dsPath, string(jsonStr));
        end

        function statsStruct = readStats(obj, runId)
            % READSTATS Read and decode statistics JSON.
            %
            % Args:
            %   runId (string): Run identifier
            %
            % Returns:
            %   statsStruct (struct): Decoded statistics structure

            arguments
                obj
                runId (1,1) string
            end

            dsPath = char("/runs/" + runId + "/stats/json");
            rawData = h5read(char(obj.ArchivePath), dsPath);
            if iscell(rawData)
                jsonStr = rawData{1};
            else
                jsonStr = rawData;
            end
            statsStruct = jsondecode(char(jsonStr));
        end

        function writeScenario(obj, runId, jsonStr)
            % WRITESCENARIO Write scenario JSON string to the archive.
            %
            % Args:
            %   runId (string): Run identifier
            %   jsonStr (string): Scenario JSON string

            arguments
                obj
                runId (1,1) string
                jsonStr (1,1) string
            end

            dsPath = char("/runs/" + runId + "/scenario/json");
            obj.writeStringDataset(dsPath, jsonStr);
        end

        function jsonStr = readScenario(obj, runId)
            % READSCENARIO Read scenario JSON string from the archive.
            %
            % Args:
            %   runId (string): Run identifier
            %
            % Returns:
            %   jsonStr (string): Scenario JSON string

            arguments
                obj
                runId (1,1) string
            end

            dsPath = char("/runs/" + runId + "/scenario/json");
            rawData = h5read(char(obj.ArchivePath), dsPath);
            if iscell(rawData)
                jsonStr = string(rawData{1});
            else
                jsonStr = string(rawData);
            end
        end

        function runIds = listRuns(obj)
            % LISTRUNS Return cell array of run IDs in the archive.
            %
            % Returns:
            %   runIds (cell array of char): Run identifiers

            arguments
                obj
            end

            runIds = {};
            try
                info = h5info(char(obj.ArchivePath), '/runs');
                if ~isempty(info.Groups)
                    for i = 1:numel(info.Groups)
                        [~, name] = fileparts(info.Groups(i).Name);
                        runIds{end+1} = char(name); %#ok<AGROW>
                    end
                end
            catch
                % /runs group doesn't exist yet
                runIds = {};
            end
        end

        function deleteRun(obj, runId)
            % DELETERUN Remove a run group from the archive.
            %
            % Uses low-level HDF5 API (H5F/H5G) since MATLAB does not
            % provide a high-level h5delete function.
            %
            % Args:
            %   runId (string): Run identifier to delete

            arguments
                obj
                runId (1,1) string
            end

            groupPath = "/runs/" + runId;

            % Use low-level HDF5 API to unlink the group
            fileId = H5F.open(char(obj.ArchivePath), 'H5F_ACC_RDWR', 'H5P_DEFAULT');
            try
                H5L.delete(fileId, char(groupPath), 'H5P_DEFAULT');
            catch ME
                H5F.close(fileId);
                rethrow(ME);
            end
            H5F.close(fileId);
        end

        function tf = runExists(obj, runId)
            % RUNEXISTS Check if a run group exists in the archive.
            %
            % Args:
            %   runId (string): Run identifier to check
            %
            % Returns:
            %   tf (logical): true if the run group exists

            arguments
                obj
                runId (1,1) string
            end

            groupPath = "/runs/" + runId;
            try
                h5info(char(obj.ArchivePath), char(groupPath));
                tf = true;
            catch
                tf = false;
            end
        end
    end

    methods (Access = private)
        function createAndWrite(obj, dsPath, numData)
            % CREATEANDWRITE Create/overwrite a numeric dataset.
            %
            % Deletes any existing dataset at dsPath, then creates a new
            % one with the correct size and writes the data.
            %
            % Args:
            %   dsPath (char): HDF5 dataset path
            %   numData (double array): Numeric data to write

            filePath = char(obj.ArchivePath);
            n = numel(numData);

            % Delete existing dataset if present (handles size mismatch)
            fileId = H5F.open(filePath, 'H5F_ACC_RDWR', 'H5P_DEFAULT');
            try
                H5L.delete(fileId, dsPath, 'H5P_DEFAULT');
            catch
                % Dataset doesn't exist yet — fine
            end
            H5F.close(fileId);

            % Create with correct size and write
            h5create(filePath, dsPath, n, 'Datatype', 'double');
            h5write(filePath, dsPath, numData);
        end

        function writeStringDataset(obj, dsPath, strData)
            % WRITESTRINGDATASET Write string data as a variable-length
            % UTF-8 string dataset using the low-level HDF5 API.
            %
            % Args:
            %   dsPath (char): HDF5 dataset path
            %   strData (string array): String data to write

            filePath = char(obj.ArchivePath);

            % Ensure strData is a cell array of char vectors
            if isstring(strData)
                cellData = cellstr(strData);
            else
                cellData = {char(strData)};
            end

            n = numel(cellData);

            % Use low-level API for variable-length strings
            fileId = H5F.open(filePath, 'H5F_ACC_RDWR', 'H5P_DEFAULT');
            try
                % Check if dataset already exists and delete it first
                try
                    H5L.delete(fileId, dsPath, 'H5P_DEFAULT');
                catch
                    % Dataset doesn't exist yet, that's fine
                end

                % Create variable-length string type
                typeId = H5T.copy('H5T_C_S1');
                H5T.set_size(typeId, 'H5T_VARIABLE');
                H5T.set_cset(typeId, H5ML.get_constant_value('H5T_CSET_UTF8'));

                % Create dataspace
                if n == 1
                    spaceId = H5S.create_simple(1, 1, 1);
                else
                    spaceId = H5S.create_simple(1, n, n);
                end

                % Create dataset
                dsetId = H5D.create(fileId, dsPath, typeId, spaceId, 'H5P_DEFAULT');

                % Write data
                H5D.write(dsetId, typeId, 'H5S_ALL', 'H5S_ALL', 'H5P_DEFAULT', cellData);

                % Cleanup
                H5D.close(dsetId);
                H5S.close(spaceId);
                H5T.close(typeId);
            catch ME
                H5F.close(fileId);
                rethrow(ME);
            end
            H5F.close(fileId);
        end
    end
end
