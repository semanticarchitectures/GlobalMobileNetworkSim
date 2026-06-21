classdef DataFabricController < handle
    % DATAFABRICCONTROLLER Orchestrates RunRegistry, EventArchiver, and SimulationStore.
    %
    % Provides a unified interface for simulation data archival. When wired
    % into SimController, it automatically archives events, snapshots scenarios,
    % and records run metadata without requiring changes to simulation logic.
    %
    % Usage:
    %   dfc = data.DataFabricController();
    %   sc.dataFabricController = dfc;
    %   sc.run();  % archiving happens automatically
    %
    % Requirements: R25, R26

    properties (SetAccess = private)
        runId (1,1) string = ""
        Store       % data.SimulationStore handle (public read for QueryEngine access)
        Registry    % data.RunRegistry handle (public read)

        % Fabric mode properties (optional, populated by initFabric)
        fabricHandler       % fabric.FabricEventHandler handle (or [])
        replicationEngine   % fabric.ReplicationEngine handle (or [])
        dataStoreRegistry   % fabric.DataStoreRegistry handle (or [])
    end

    properties (Access = private)
        ArchivePath (1,1) string
        RegistryPath (1,1) string
        FlushEventThreshold (1,1) double
        FlushTimeIntervalSec (1,1) double
        RetentionPolicy   % struct with maxRuns, maxAgeDays, keepTagged (or [])
        c2LogDataStoreId (1,1) string = ""  % DataStore for auto C2 log creation

        Archiver    % data.EventArchiver handle (created per-run)
    end

    methods
        function obj = DataFabricController(config)
            % DATAFABRICCONTROLLER Construct a DataFabricController instance.
            %
            % Args:
            %   config (struct, optional): Configuration with fields:
            %       archivePath (string) - HDF5 archive path
            %           (default: fullfile('data', 'simulation_archive.h5'))
            %       registryPath (string) - JSON registry path
            %           (default: fullfile('data', 'run_registry.json'))
            %       flushEventThreshold (double) - flush after N events (default 1000)
            %       flushTimeIntervalSec (double) - flush after N sim seconds (default 60)

            arguments
                config (1,1) struct = struct()
            end

            % Apply defaults
            if isfield(config, 'archivePath')
                obj.ArchivePath = string(config.archivePath);
            else
                obj.ArchivePath = string(fullfile('data', 'simulation_archive.h5'));
            end

            if isfield(config, 'registryPath')
                obj.RegistryPath = string(config.registryPath);
            else
                obj.RegistryPath = string(fullfile('data', 'run_registry.json'));
            end

            if isfield(config, 'flushEventThreshold')
                obj.FlushEventThreshold = config.flushEventThreshold;
            else
                obj.FlushEventThreshold = 1000;
            end

            if isfield(config, 'flushTimeIntervalSec')
                obj.FlushTimeIntervalSec = config.flushTimeIntervalSec;
            else
                obj.FlushTimeIntervalSec = 60;
            end

            % Create/open SimulationStore and RunRegistry on construction
            obj.Store = data.SimulationStore(obj.ArchivePath);
            obj.Registry = data.RunRegistry(obj.RegistryPath);
            obj.Archiver = [];

            % Initialize fabric mode properties as empty
            obj.fabricHandler = [];
            obj.replicationEngine = [];
            obj.dataStoreRegistry = [];

            % Parse c2LogDataStoreId if provided
            if isfield(config, 'c2LogDataStoreId')
                obj.c2LogDataStoreId = string(config.c2LogDataStoreId);
            end

            % Parse retention policy if provided
            if isfield(config, 'retentionPolicy') && isstruct(config.retentionPolicy)
                rp = config.retentionPolicy;
                obj.RetentionPolicy = struct( ...
                    'maxRuns', 0, 'maxAgeDays', 0, 'keepTagged', true);
                if isfield(rp, 'maxRuns')
                    obj.RetentionPolicy.maxRuns = rp.maxRuns;
                end
                if isfield(rp, 'maxAgeDays')
                    obj.RetentionPolicy.maxAgeDays = rp.maxAgeDays;
                end
                if isfield(rp, 'keepTagged')
                    obj.RetentionPolicy.keepTagged = rp.keepTagged;
                end
            else
                obj.RetentionPolicy = [];
            end
        end

        function onSimulationStart(obj, sc)
            % ONSIMULATIONSTART Called at the start of a simulation run.
            %
            % Generates a UUID, creates a run group in the archive, creates
            % an EventArchiver for this run, and snapshots the scenario JSON.
            %
            % Args:
            %   sc (sim.SimController): The simulation controller instance.

            arguments
                obj
                sc
            end

            % Generate UUID via RunRegistry static method
            obj.runId = data.RunRegistry.generateRunId();

            % Create run group in the HDF5 archive
            obj.Store.createRun(obj.runId);

            % Create EventArchiver for this run
            archiverConfig.flushEventThreshold = obj.FlushEventThreshold;
            archiverConfig.flushTimeIntervalSec = obj.FlushTimeIntervalSec;
            obj.Archiver = data.EventArchiver(obj.Store, obj.runId, archiverConfig);

            % Embed referenced file contents inline before snapshotting
            scenarioSnapshot = sc.scenario;
            scenarioSnapshot = data.DataFabricController.embedFileContents(scenarioSnapshot);

            % Snapshot scenario JSON to the archive
            scenarioJson = jsonencode(scenarioSnapshot);
            obj.Store.writeScenario(obj.runId, string(scenarioJson));

            % Initialize fabric mode if scenario has DataStore nodes
            if obj.hasDataStoreNodes(sc.scenario)
                obj.initFabric(sc.scenario, sc.eventCalendar);
            end
        end

        function archiveEvent(obj, event)
            % ARCHIVEEVENT Archive a single event struct.
            %
            % Delegates to the EventArchiver for buffered writing.
            %
            % Args:
            %   event (struct): Event struct with standard log fields.

            arguments
                obj
                event (1,1) struct
            end

            if ~isempty(obj.Archiver)
                obj.Archiver.archive(event);
            end
        end

        function rid = onSimulationComplete(obj, sc)
            % ONSIMULATIONCOMPLETE Called when the simulation finishes.
            %
            % Finalizes the EventArchiver (flushes remaining events), writes
            % stats to the archive, and adds a run record to the RunRegistry.
            %
            % Args:
            %   sc (sim.SimController): The simulation controller instance.
            %
            % Returns:
            %   rid (string): The run ID for this completed run.

            arguments
                obj
                sc
            end

            % Finalize the EventArchiver (flush remaining buffered events)
            if ~isempty(obj.Archiver)
                obj.Archiver.finalize();
            end

            % Write stats report to the archive
            statsReport = sc.buildStatsReport();

            % Include data fabric stats if fabric mode is active
            if ~isempty(obj.fabricHandler)
                statsReport.dataFabric = obj.buildFabricStats();
            end

            obj.Store.writeStats(obj.runId, statsReport);

            % Build run record for the registry
            record = struct();
            record.runId = char(obj.runId);

            if isfield(sc.scenario, 'scenarioName') && ~isempty(sc.scenario.scenarioName)
                record.scenarioName = sc.scenario.scenarioName;
            else
                record.scenarioName = 'unnamed';
            end

            if isfield(sc.scenario, 'scenarioFilePath') && ~isempty(sc.scenario.scenarioFilePath)
                record.scenarioFilePath = sc.scenario.scenarioFilePath;
            else
                record.scenarioFilePath = '';
            end

            record.simStartTime = sc.runTimestamp;
            record.simEndTime = datestr(now, 'yyyy-mm-ddTHH:MM:SS'); %#ok<TNOW1,DATST>
            record.wallClockDurationSec = sc.wallClockDurationSec;

            % Node and link counts
            if ~isempty(sc.nodeRegistry)
                record.nodeCount = sc.nodeRegistry.count();
            else
                record.nodeCount = 0;
            end
            if ~isempty(sc.linkRegistry)
                record.linkCount = sc.linkRegistry.count();
            else
                record.linkCount = 0;
            end

            % C2 message stats
            record.c2MessagesScheduled = double(sc.stats.c2MessagesTx);
            record.c2MessagesDelivered = double(sc.stats.c2MessagesRx);
            record.c2MessagesFailed = double(sc.stats.c2MessagesFail);

            % Archive store path
            record.archiveStorePath = char(obj.ArchivePath);

            % Metadata
            record.metadata = struct();
            if ~isempty(sc.evalResults) && numel(sc.evalResults) > 0
                scores = [sc.evalResults.fidelityScore];
                scores = scores(~isnan(scores));
                if ~isempty(scores)
                    record.metadata.fidelityScore = mean(scores);
                end
            end

            % Add to registry
            obj.Registry.addRun(record);

            % Apply retention policy after each completed run
            if ~isempty(obj.RetentionPolicy)
                obj.applyRetention();
            end

            rid = obj.runId;
        end

        function applyRetention(obj)
            % APPLYRETENTION Apply the configured retention policy.
            %
            % Removes runs from the archive and registry that exceed
            % maxRuns (oldest first) or are older than maxAgeDays.
            % Runs with user metadata are kept if keepTagged is true.
            %
            % Requirements: R31

            if isempty(obj.RetentionPolicy)
                return;
            end

            policy = obj.RetentionPolicy;
            maxRuns = policy.maxRuns;
            maxAgeDays = policy.maxAgeDays;
            keepTagged = policy.keepTagged;

            % maxRuns = 0 means retention is disabled
            if maxRuns == 0 && maxAgeDays == 0
                return;
            end

            % Get all records from registry
            allRecords = obj.Registry.list();
            if isempty(allRecords) || height(allRecords) == 0
                return;
            end

            nRuns = height(allRecords);
            toRemove = {};

            % Age-based removal
            if maxAgeDays > 0
                now_dt = datetime('now', 'TimeZone', 'UTC');
                for i = 1:nRuns
                    recId = char(allRecords.runId(i));
                    rec = obj.Registry.getRecord(string(recId));

                    % Check if tagged and keepTagged
                    if keepTagged && isfield(rec, 'metadata') && ...
                            ~isempty(fieldnames(rec.metadata))
                        continue;
                    end

                    % Parse start time
                    try
                        recTime = datetime(rec.simStartTime, 'TimeZone', 'UTC');
                        ageDays = days(now_dt - recTime);
                        if ageDays > maxAgeDays
                            toRemove{end+1} = recId; %#ok<AGROW>
                        end
                    catch
                        % Can't parse date — skip
                    end
                end
            end

            % Count-based removal (oldest first)
            if maxRuns > 0 && nRuns > maxRuns
                % Remove entries already marked for age removal first
                remainingCount = nRuns - numel(toRemove);
                if remainingCount > maxRuns
                    % Need to remove more — oldest first (by table row order)
                    excess = remainingCount - maxRuns;
                    removed = 0;
                    for i = 1:nRuns
                        if removed >= excess
                            break;
                        end
                        recId = char(allRecords.runId(i));
                        if ismember(recId, toRemove)
                            continue;  % Already marked
                        end

                        rec = obj.Registry.getRecord(string(recId));
                        if keepTagged && isfield(rec, 'metadata') && ...
                                ~isempty(fieldnames(rec.metadata))
                            continue;  % Protected by keepTagged
                        end

                        toRemove{end+1} = recId; %#ok<AGROW>
                        removed = removed + 1;
                    end
                end
            end

            % Execute removals
            for i = 1:numel(toRemove)
                rid = string(toRemove{i});
                try
                    if obj.Store.runExists(rid)
                        obj.Store.deleteRun(rid);
                    end
                    obj.Registry.removeRun(rid);
                    fprintf('[retention] Removed run: %s\n', rid);
                catch ME
                    warning('netsim:data:retentionError', ...
                        'Failed to remove run "%s": %s', rid, ME.message);
                end
            end
        end

        function initFabric(obj, scenario, eventCalendar)
            % INITFABRIC Initialize fabric mode from scenario DataStore nodes.
            %
            % Creates a DataStoreRegistry from the scenario, instantiates a
            % FabricEventHandler and ReplicationEngine, and wires them together.
            %
            % Args:
            %   scenario (struct): Scenario struct (from io.ScenarioLoader.load).
            %   eventCalendar (sim.EventCalendar): The simulation event calendar.
            %
            % Requirements: R33, R35, R39

            arguments
                obj
                scenario (1,1) struct
                eventCalendar (1,1) sim.EventCalendar
            end

            % Create DataStoreRegistry from scenario nodes
            obj.dataStoreRegistry = fabric.DataStoreRegistry.fromScenario(scenario);

            % Create FabricEventHandler with the registry
            obj.fabricHandler = fabric.FabricEventHandler(obj.dataStoreRegistry);

            % Create ReplicationEngine with registry and event calendar
            obj.replicationEngine = fabric.ReplicationEngine(obj.dataStoreRegistry, eventCalendar);

            % Attach replication engine to handler
            obj.fabricHandler.setReplicationEngine(obj.replicationEngine);
        end

        function logEntry = handleDataEvent(obj, event, simTimeSec, eventCalendar, icamController)
            % HANDLEDATAEVENT Dispatch a data fabric event to the appropriate handler.
            %
            % Routes events by type to FabricEventHandler or ReplicationEngine.
            %
            % Args:
            %   event (struct): Event struct with type and payload.
            %   simTimeSec (double): Current simulation time in seconds.
            %   eventCalendar (sim.EventCalendar): The event calendar for scheduling.
            %   icamController: icam.ICAMController handle or [] if not configured.
            %
            % Returns:
            %   logEntry (struct): Log entry from the handler, or empty struct
            %       if fabric mode is not initialized.
            %
            % Requirements: R34, R36, R37, R39

            arguments
                obj
                event (1,1) struct
                simTimeSec (1,1) double
                eventCalendar (1,1) sim.EventCalendar
                icamController = []
            end

            % If fabric mode is not initialized, return empty
            if isempty(obj.fabricHandler)
                logEntry = struct();
                return;
            end

            eventType = string(event.type);

            switch eventType
                case sim.EventCalendar.DATA_INGEST
                    logEntry = obj.fabricHandler.handleIngest(event, simTimeSec, eventCalendar);

                case sim.EventCalendar.DATA_REPLICATE
                    logEntry = obj.replicationEngine.handleReplicate(event, simTimeSec);

                case sim.EventCalendar.DATA_FETCH
                    logEntry = obj.fabricHandler.handleFetch(event, simTimeSec, icamController);

                case sim.EventCalendar.DATA_QUERY
                    logEntry = obj.fabricHandler.handleQuery(event, simTimeSec, icamController);

                otherwise
                    logEntry = struct( ...
                        'type', "data_event_unknown", ...
                        'eventType', eventType, ...
                        'simTimeSec', simTimeSec);
            end
        end

        function payload = onC2MessageDelivered(obj, event, simTimeSec)
            % ONC2MESSAGEDELIVERED Create a c2_log DataItem on C2 message delivery.
            %
            % If fabric mode is active and c2LogDataStoreId is configured,
            % calls createC2LogItem to produce a DATA_INGEST payload. The
            % caller (SimController) is responsible for scheduling the event.
            %
            % Args:
            %   event (struct): The C2_MESSAGE_RX event struct.
            %   simTimeSec (double): Current simulation time in seconds.
            %
            % Returns:
            %   payload (struct): DATA_INGEST payload struct, or empty struct
            %       if fabric handler is not configured or c2LogDataStoreId is empty.
            %
            % Requirements: R34, R38

            arguments
                obj
                event (1,1) struct
                simTimeSec (1,1) double
            end

            % Check that fabric mode is active and c2LogDataStoreId is configured
            if isempty(obj.fabricHandler) || strlength(obj.c2LogDataStoreId) == 0
                payload = struct();
                return;
            end

            % Delegate to FabricEventHandler.createC2LogItem
            payload = obj.fabricHandler.createC2LogItem(event, simTimeSec, obj.c2LogDataStoreId);
        end

        function fabricStats = buildFabricStats(obj)
            % BUILDFABRICSTATS Build the dataFabric block for the Statistics_Report.
            %
            % Returns a struct with aggregate data fabric statistics across
            % all DataStores. Only call when fabricHandler is not empty
            % (i.e., ≥1 DataStore is configured).
            %
            % Returns:
            %   fabricStats (struct): Struct with fields:
            %       totalDataItems, ingest, fetch, query, replication,
            %       perDataStore, provenanceGraph.
            %
            % Requirements: R41

            % --- totalDataItems: sum across all DataStores ---
            storeIds = obj.dataStoreRegistry.listDataStores();
            totalItems = 0;
            for i = 1:numel(storeIds)
                catalog = obj.dataStoreRegistry.getCatalog(storeIds(i));
                totalItems = totalItems + catalog.count();
            end
            fabricStats.totalDataItems = totalItems;

            % --- ingest block ---
            handlerStats = obj.fabricHandler.stats;
            latencies = handlerStats.ingestLatencies;

            if isempty(latencies)
                meanLat = 0;
                medianLat = 0;
                p95Lat = 0;
            else
                meanLat = mean(latencies) * 1000;    % convert sec to ms
                medianLat = median(latencies) * 1000;
                p95Lat = prctile(latencies, 95) * 1000;
            end

            fabricStats.ingest = struct( ...
                'totalIngested', handlerStats.totalIngested, ...
                'totalFailed', handlerStats.totalFailed, ...
                'totalRetries', handlerStats.totalRetries, ...
                'totalDropped', handlerStats.totalDropped, ...
                'meanLatencyMs', meanLat, ...
                'medianLatencyMs', medianLat, ...
                'p95LatencyMs', p95Lat);

            % --- fetch block ---
            fabricStats.fetch = struct( ...
                'totalRequests', handlerStats.totalFetchRequests, ...
                'totalResults', handlerStats.totalFetchResults, ...
                'totalDenied', handlerStats.totalFetchDenied, ...
                'totalItemNotFound', handlerStats.totalItemNotFound);

            % --- query block ---
            fabricStats.query = struct( ...
                'totalRequests', handlerStats.totalQueryRequests, ...
                'totalResults', handlerStats.totalQueryResults);

            % --- replication block ---
            replStats = obj.replicationEngine.stats;
            fabricStats.replication = struct( ...
                'totalReplicated', replStats.totalReplicated, ...
                'totalReplicationFailed', replStats.totalReplicationFailed);

            % --- perDataStore block ---
            nStores = numel(storeIds);
            if nStores == 0
                fabricStats.perDataStore = struct( ...
                    'nodeId', {}, 'itemCount', {}, 'catalogSize', {});
            else
                perStore = struct( ...
                    'nodeId', cell(1, nStores), ...
                    'itemCount', cell(1, nStores), ...
                    'catalogSize', cell(1, nStores));
                for i = 1:nStores
                    catalog = obj.dataStoreRegistry.getCatalog(storeIds(i));
                    itemCount = catalog.count();
                    perStore(i).nodeId = char(storeIds(i));
                    perStore(i).itemCount = itemCount;
                    perStore(i).catalogSize = itemCount;
                end
                fabricStats.perDataStore = perStore;
            end

            % --- provenanceGraph block ---
            totalNodes = 0;
            totalEdges = 0;
            for i = 1:numel(storeIds)
                pg = obj.dataStoreRegistry.getProvenanceGraph(storeIds(i));
                totalNodes = totalNodes + pg.nodeCount();
                totalEdges = totalEdges + pg.edgeCount();
            end
            fabricStats.provenanceGraph = struct( ...
                'totalNodes', totalNodes, ...
                'totalEdges', totalEdges);
        end
    end

    methods (Access = private)
        function tf = hasDataStoreNodes(~, scenario)
            % HASDATASTORENODES Check if scenario contains DataStore nodes.
            %
            % Args:
            %   scenario (struct): The scenario struct.
            %
            % Returns:
            %   tf (logical): true if any node has dataStore = true.

            tf = false;

            if ~isfield(scenario, 'nodes') || isempty(scenario.nodes)
                return;
            end

            nodes = scenario.nodes;
            if isstruct(nodes)
                for k = 1:numel(nodes)
                    if isfield(nodes(k), 'dataStore') && isequal(nodes(k).dataStore, true)
                        tf = true;
                        return;
                    end
                end
            elseif iscell(nodes)
                for k = 1:numel(nodes)
                    nd = nodes{k};
                    if isfield(nd, 'dataStore') && isequal(nd.dataStore, true)
                        tf = true;
                        return;
                    end
                end
            end
        end
    end

    methods (Static, Access = private)
        function scenario = embedFileContents(scenario)
            % EMBEDFILECONTENTS Embed referenced file contents inline in the scenario.
            %
            % Reads the contents of roleDefinitionFile (.md), policyDefinitionFile
            % (.json), and referenceBehaviorFile (.json) and stores them as
            % inline content fields in the scenario struct. Uses try/catch
            % so missing or unreadable files do not crash the archiver.
            %
            % Requirements: R28 (acceptance criterion 5)

            % --- Embed agent roleDefinitionFile contents ---
            if isfield(scenario, 'agents') && ~isempty(scenario.agents)
                agents = scenario.agents;
                if isstruct(agents)
                    for k = 1:numel(agents)
                        if isfield(agents(k), 'roleDefinitionFile') && ...
                                ~isempty(agents(k).roleDefinitionFile)
                            try
                                filePath = char(agents(k).roleDefinitionFile);
                                agents(k).roleDefinitionContent = fileread(filePath);
                            catch
                                agents(k).roleDefinitionContent = '';
                            end
                        end
                    end
                    scenario.agents = agents;
                elseif iscell(agents)
                    for k = 1:numel(agents)
                        if isfield(agents{k}, 'roleDefinitionFile') && ...
                                ~isempty(agents{k}.roleDefinitionFile)
                            try
                                filePath = char(agents{k}.roleDefinitionFile);
                                agents{k}.roleDefinitionContent = fileread(filePath);
                            catch
                                agents{k}.roleDefinitionContent = '';
                            end
                        end
                    end
                    scenario.agents = agents;
                end
            end

            % --- Embed policyDefinitionFile contents ---
            if isfield(scenario, 'policyDefinitionFile') && ...
                    ~isempty(scenario.policyDefinitionFile)
                try
                    filePath = char(scenario.policyDefinitionFile);
                    scenario.policyDefinitionContent = fileread(filePath);
                catch
                    scenario.policyDefinitionContent = '';
                end
            end

            % --- Embed referenceBehaviorFile contents ---
            if isfield(scenario, 'referenceBehaviorFile') && ...
                    ~isempty(scenario.referenceBehaviorFile)
                try
                    filePath = char(scenario.referenceBehaviorFile);
                    scenario.referenceBehaviorContent = fileread(filePath);
                catch
                    scenario.referenceBehaviorContent = '';
                end
            end
        end
    end
end
