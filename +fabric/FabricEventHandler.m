classdef FabricEventHandler < handle
    % FABRICEVENTHANDLER Handle class for processing data fabric events.
    %
    % Handles DATA_INGEST events by routing DataItems to their target
    % DataStore's DataCatalog and ProvenanceGraph. Manages retry logic
    % for failed ingestions with configurable retry limits.
    %
    % Usage:
    %   reg = fabric.DataStoreRegistry();
    %   reg.register("node_1", struct());
    %   handler = fabric.FabricEventHandler(reg);
    %   logEntry = handler.handleIngest(event, 10.0, eventCalendar);
    %
    % Requirements: R34

    properties (SetAccess = private)
        stats (1,1) struct
    end

    properties (Access = private)
        Registry        % fabric.DataStoreRegistry handle
        Config          % struct with ingestMaxRetries, retryIntervalSec
    end

    methods
        function obj = FabricEventHandler(registry, config)
            % FABRICEVENTHANDLER Construct a FabricEventHandler.
            %
            % Args:
            %   registry (fabric.DataStoreRegistry): Handle to the registry.
            %   config (struct, optional): Configuration with fields:
            %       ingestMaxRetries (double): Max retries before dropping (default 3).
            %       retryIntervalSec (double): Seconds between retries (default 60).

            arguments
                registry (1,1) fabric.DataStoreRegistry
                config (1,1) struct = struct()
            end

            obj.Registry = registry;

            % Apply defaults for missing config fields
            if ~isfield(config, 'ingestMaxRetries')
                config.ingestMaxRetries = 3;
            end
            if ~isfield(config, 'retryIntervalSec')
                config.retryIntervalSec = 60;
            end
            obj.Config = config;

            % Initialize stats
            obj.stats = struct( ...
                'totalIngested', 0, ...
                'totalFailed', 0, ...
                'totalRetries', 0, ...
                'totalDropped', 0, ...
                'ingestLatencies', double.empty(1,0));
        end

        function logEntry = handleIngest(obj, event, simTimeSec, eventCalendar) %#ok<INUSD>
            % HANDLEINGEST Process a DATA_INGEST event.
            %
            % Extracts the DataItem from event.payload and adds it to the
            % target DataStore's DataCatalog and ProvenanceGraph.
            %
            % Args:
            %   event (struct): Event struct with payload containing:
            %       dataItemId (string), dataItemStruct (struct),
            %       targetDataStoreId (string).
            %   simTimeSec (double): Current simulation time in seconds.
            %   eventCalendar (sim.EventCalendar): The event calendar (unused here).
            %
            % Returns:
            %   logEntry (struct): Log entry with type 'data_ingest_complete'
            %       or 'data_routing_error'.

            payload = event.payload;
            targetId = string(payload.targetDataStoreId);

            % Check if target is a registered DataStore
            if ~obj.Registry.isDataStore(targetId)
                logEntry = struct( ...
                    'type', "data_routing_error", ...
                    'dataItemId', string(payload.dataItemId), ...
                    'targetDataStoreId', targetId, ...
                    'simTimeSec', simTimeSec, ...
                    'message', "Target is not a registered DataStore");
                obj.stats.totalFailed = obj.stats.totalFailed + 1;
                return;
            end

            % Create DataItem from the struct in payload
            dataItem = fabric.DataItem(payload.dataItemStruct);

            % Add to the target DataStore's DataCatalog
            catalog = obj.Registry.getCatalog(targetId);
            catalog.add(dataItem);

            % Add item to the ProvenanceGraph
            pg = obj.Registry.getProvenanceGraph(targetId);
            pg.addItem(dataItem.id);

            % Record provenance chain entries
            if ~isempty(dataItem.provenanceChain)
                for k = 1:numel(dataItem.provenanceChain)
                    entry = dataItem.provenanceChain(k);
                    pg.addItem(string(entry.sourceItemId));
                    pg.addDerivation( ...
                        string(entry.sourceItemId), ...
                        dataItem.id, ...
                        string(entry.transformationType), ...
                        double(entry.transformationTimeSec));
                end
            end

            % Compute ingest latency (time between item creation and ingest)
            latency = simTimeSec - dataItem.creationTimeSec;
            obj.stats.ingestLatencies(end+1) = latency;
            obj.stats.totalIngested = obj.stats.totalIngested + 1;

            % Return success log entry
            logEntry = struct( ...
                'type', "data_ingest_complete", ...
                'dataItemId', string(dataItem.id), ...
                'dataStoreId', targetId, ...
                'simTimeSec', simTimeSec);
        end

        function logEntry = handleIngestFailure(obj, event, simTimeSec, eventCalendar)
            % HANDLEINGESTFAILURE Handle a failed DATA_INGEST attempt.
            %
            % Increments retry count. If below max retries, schedules a new
            % DATA_INGEST event. Otherwise returns a dropped log entry.
            %
            % Args:
            %   event (struct): The failed event struct. payload.retryCount
            %       tracks how many retries have been attempted.
            %   simTimeSec (double): Current simulation time in seconds.
            %   eventCalendar (sim.EventCalendar): Calendar for scheduling retries.
            %
            % Returns:
            %   logEntry (struct): Either 'data_ingest_retry' or 'data_ingest_dropped'.

            payload = event.payload;

            % Increment retry count
            if ~isfield(payload, 'retryCount')
                payload.retryCount = 0;
            end
            payload.retryCount = payload.retryCount + 1;

            if payload.retryCount < obj.Config.ingestMaxRetries
                % Schedule a retry
                retryTime = simTimeSec + obj.Config.retryIntervalSec;

                retryEvent.time = retryTime;
                retryEvent.type = sim.EventCalendar.DATA_INGEST;
                retryEvent.id = uint64(randi([1, intmax('uint32')]));
                retryEvent.payload = payload;

                eventCalendar.schedule(retryEvent);

                obj.stats.totalRetries = obj.stats.totalRetries + 1;

                logEntry = struct( ...
                    'type', "data_ingest_retry", ...
                    'dataItemId', string(payload.dataItemId), ...
                    'targetDataStoreId', string(payload.targetDataStoreId), ...
                    'retryCount', payload.retryCount, ...
                    'nextRetryTimeSec', retryTime, ...
                    'simTimeSec', simTimeSec);
            else
                % Max retries exceeded — drop the event
                obj.stats.totalDropped = obj.stats.totalDropped + 1;
                obj.stats.totalFailed = obj.stats.totalFailed + 1;

                logEntry = struct( ...
                    'type', "data_ingest_dropped", ...
                    'dataItemId', string(payload.dataItemId), ...
                    'targetDataStoreId', string(payload.targetDataStoreId), ...
                    'retryCount', payload.retryCount, ...
                    'simTimeSec', simTimeSec);
            end
        end
    end
end
