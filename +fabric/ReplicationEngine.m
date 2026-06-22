classdef ReplicationEngine < handle
    % REPLICATIONENGINE Handle class for managing data replication across DataStores.
    %
    % Evaluates replication policies on successful ingest and schedules
    % DATA_REPLICATE events to peer DataStores. Handles incoming replicate
    % events by adding items to target catalogs with provenance tracking.
    %
    % Usage:
    %   reg = fabric.DataStoreRegistry();
    %   ec = sim.EventCalendar();
    %   engine = fabric.ReplicationEngine(reg, ec);
    %   engine.onIngestComplete(dataItem, "node_1", 10.0);
    %   logEntry = engine.handleReplicate(event, 20.0);
    %
    % Requirements: R39

    properties (SetAccess = private)
        stats (1,1) struct
    end

    properties (Access = private)
        Registry        % fabric.DataStoreRegistry handle
        EventCalendar   % sim.EventCalendar handle
    end

    methods
        function obj = ReplicationEngine(registry, eventCalendar)
            % REPLICATIONENGINE Construct a ReplicationEngine.
            %
            % Args:
            %   registry (fabric.DataStoreRegistry): Handle to the DataStore registry.
            %   eventCalendar (sim.EventCalendar): Handle to the event calendar.

            arguments
                registry (1,1) fabric.DataStoreRegistry
                eventCalendar (1,1) sim.EventCalendar
            end

            obj.Registry = registry;
            obj.EventCalendar = eventCalendar;

            % Initialize stats
            obj.stats = struct( ...
                'totalReplicated', 0, ...
                'totalReplicationFailed', 0);
        end

        function onIngestComplete(obj, dataItem, sourceDataStoreId, simTimeSec)
            % ONINGESTCOMPLETE Evaluate replication policy and schedule replicate events.
            %
            % Called after a successful DATA_INGEST. Checks the source
            % DataStore's replicationPolicy and schedules DATA_REPLICATE
            % events for qualifying peer DataStores.
            %
            % Args:
            %   dataItem (fabric.DataItem): The ingested data item.
            %   sourceDataStoreId (string): The DataStore that received the ingest.
            %   simTimeSec (double): Current simulation time in seconds.

            arguments
                obj
                dataItem (1,1) fabric.DataItem
                sourceDataStoreId (1,1) string
                simTimeSec (1,1) double
            end

            % Get config for the source DataStore
            if ~obj.Registry.isDataStore(sourceDataStoreId)
                return;
            end

            cfg = obj.Registry.getConfig(sourceDataStoreId);

            % Check if a replication policy is defined
            if ~isfield(cfg, 'replicationPolicy') || isempty(cfg.replicationPolicy)
                return;
            end

            policy = string(cfg.replicationPolicy);

            % Determine target peers based on policy
            allStores = obj.Registry.listDataStores();
            % Remove source from list
            peers = allStores(allStores ~= sourceDataStoreId);

            if isempty(peers)
                return;
            end

            targets = string.empty(1, 0);

            if policy == "all"
                % Replicate to all other registered DataStores
                targets = peers;
            elseif startsWith(policy, "by_classification:")
                % Replicate only if dataItem.classification matches label
                label = extractAfter(policy, "by_classification:");
                if dataItem.classification == label
                    targets = peers;
                end
            elseif startsWith(policy, "by_enclave:")
                % Replicate only if dataItem.enclaveId matches id
                enclaveMatch = extractAfter(policy, "by_enclave:");
                if dataItem.enclaveId == enclaveMatch
                    targets = peers;
                end
            end

            % Schedule DATA_REPLICATE events for each target
            dataItemStruct = dataItem.toStruct();

            for i = 1:numel(targets)
                replicateEvent.time = simTimeSec;
                replicateEvent.type = sim.EventCalendar.DATA_REPLICATE;
                replicateEvent.id = uint64(randi([1, intmax('uint32')]));
                replicateEvent.payload = struct( ...
                    'dataItemId', dataItem.id, ...
                    'dataItemStruct', dataItemStruct, ...
                    'sourceDataStoreId', sourceDataStoreId, ...
                    'targetDataStoreId', targets(i));

                obj.EventCalendar.schedule(replicateEvent);
            end
        end

        function logEntry = handleReplicate(obj, event, simTimeSec)
            % HANDLEREPLICATE Process a DATA_REPLICATE event.
            %
            % Extracts the DataItem struct from the event payload and adds
            % it to the target DataStore's DataCatalog and ProvenanceGraph
            % with a 'replication' derivation edge from the original.
            %
            % Args:
            %   event (struct): Event struct with payload containing:
            %       dataItemStruct (struct), targetDataStoreId (string),
            %       dataItemId (string), sourceDataStoreId (string).
            %   simTimeSec (double): Current simulation time in seconds.
            %
            % Returns:
            %   logEntry (struct): Log entry with type 'data_replicated'
            %       or 'data_replication_failed'.

            payload = event.payload;
            targetId = string(payload.targetDataStoreId);

            % Check if target is a registered DataStore
            if ~obj.Registry.isDataStore(targetId)
                logEntry = struct( ...
                    'type', "data_replication_failed", ...
                    'dataItemId', string(payload.dataItemId), ...
                    'targetDataStoreId', targetId, ...
                    'simTimeSec', simTimeSec, ...
                    'message', "Target is not a registered DataStore");
                obj.stats.totalReplicationFailed = obj.stats.totalReplicationFailed + 1;
                return;
            end

            % Create DataItem from struct
            dataItem = fabric.DataItem(payload.dataItemStruct);

            % Add to target DataStore's DataCatalog
            catalog = obj.Registry.getCatalog(targetId);
            catalog.add(dataItem);

            % Add to ProvenanceGraph with a 'replication' derivation edge
            pg = obj.Registry.getProvenanceGraph(targetId);
            pg.addItem(dataItem.id);
            pg.addDerivation(dataItem.id, dataItem.id, "replication", simTimeSec);

            % Update stats
            obj.stats.totalReplicated = obj.stats.totalReplicated + 1;

            % Return success log entry
            logEntry = struct( ...
                'type', "data_replicated", ...
                'dataItemId', string(dataItem.id), ...
                'sourceDataStoreId', string(payload.sourceDataStoreId), ...
                'targetDataStoreId', targetId, ...
                'simTimeSec', simTimeSec);
        end
    end
end
