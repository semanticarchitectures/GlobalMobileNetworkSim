classdef FabricEventHandler < handle
    % FABRICEVENTHANDLER Handle class for processing data fabric events.
    %
    % Handles DATA_INGEST, DATA_FETCH, and DATA_QUERY events by routing
    % DataItems to/from their target DataStore's DataCatalog and
    % ProvenanceGraph. Manages retry logic for failed ingestions with
    % configurable retry limits.
    %
    % Usage:
    %   reg = fabric.DataStoreRegistry();
    %   reg.register("node_1", struct());
    %   handler = fabric.FabricEventHandler(reg);
    %   logEntry = handler.handleIngest(event, 10.0, eventCalendar);
    %   logEntry = handler.handleFetch(event, 10.0, icamController);
    %   logEntry = handler.handleQuery(event, 10.0, icamController);
    %
    % Requirements: R34, R36, R37

    properties (SetAccess = private)
        stats (1,1) struct
    end

    properties (Access = private)
        Registry        % fabric.DataStoreRegistry handle
        Config          % struct with ingestMaxRetries, retryIntervalSec
        ReplicationEngine   % fabric.ReplicationEngine handle (optional)
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
            obj.ReplicationEngine = [];

            % Initialize stats
            obj.stats = struct( ...
                'totalIngested', 0, ...
                'totalFailed', 0, ...
                'totalRetries', 0, ...
                'totalDropped', 0, ...
                'ingestLatencies', double.empty(1,0), ...
                'totalFetchRequests', 0, ...
                'totalFetchResults', 0, ...
                'totalFetchDenied', 0, ...
                'totalItemNotFound', 0, ...
                'totalQueryRequests', 0, ...
                'totalQueryResults', 0);
        end

        function setReplicationEngine(obj, engine)
            % SETREPLICATIONENGINE Attach a ReplicationEngine for post-ingest replication.
            %
            % Args:
            %   engine (fabric.ReplicationEngine): The replication engine handle.

            arguments
                obj
                engine (1,1) fabric.ReplicationEngine
            end

            obj.ReplicationEngine = engine;
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

            % Trigger replication if a ReplicationEngine is attached
            if ~isempty(obj.ReplicationEngine)
                obj.ReplicationEngine.onIngestComplete(dataItem, targetId, simTimeSec);
            end

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

        function logEntry = handleFetch(obj, event, simTimeSec, icamController)
            % HANDLEFETCH Process a DATA_FETCH event.
            %
            % Retrieves a single DataItem from the target DataStore's catalog,
            % checks ICAM access control (if configured), and returns a result
            % or denied log entry.
            %
            % Args:
            %   event (struct): Event struct with payload containing:
            %       dataItemId (string), requestingEntityId (string),
            %       requestingNodeId (string), targetDataStoreId (string).
            %   simTimeSec (double): Current simulation time in seconds.
            %   icamController: icam.ICAMController handle or [] if not configured.
            %
            % Returns:
            %   logEntry (struct): Log entry with type 'data_fetch_result',
            %       'data_fetch_denied', or 'item_not_found'.
            %
            % Requirements: R36, R37

            arguments
                obj
                event (1,1) struct
                simTimeSec (1,1) double
                icamController = []
            end

            payload = event.payload;
            dataItemId = string(payload.dataItemId);
            requestingEntityId = string(payload.requestingEntityId);
            requestingNodeId = string(payload.requestingNodeId);
            targetDataStoreId = string(payload.targetDataStoreId);

            obj.stats.totalFetchRequests = obj.stats.totalFetchRequests + 1;

            % Check if target is a registered DataStore
            if ~obj.Registry.isDataStore(targetDataStoreId)
                obj.stats.totalItemNotFound = obj.stats.totalItemNotFound + 1;
                logEntry = struct( ...
                    'type', "data_routing_error", ...
                    'dataItemId', dataItemId, ...
                    'requestingEntityId', requestingEntityId, ...
                    'targetDataStoreId', targetDataStoreId, ...
                    'simTimeSec', simTimeSec, ...
                    'message', "Target is not a registered DataStore");
                return;
            end

            % Get the DataCatalog for the target DataStore
            catalog = obj.Registry.getCatalog(targetDataStoreId);

            % Check if item exists
            if ~catalog.exists(dataItemId)
                obj.stats.totalItemNotFound = obj.stats.totalItemNotFound + 1;
                logEntry = struct( ...
                    'type', "item_not_found", ...
                    'dataItemId', dataItemId, ...
                    'requestingEntityId', requestingEntityId, ...
                    'requestingNodeId', requestingNodeId, ...
                    'targetDataStoreId', targetDataStoreId, ...
                    'simTimeSec', simTimeSec);
                return;
            end

            % Retrieve item metadata
            itemStruct = catalog.get(dataItemId);

            % ICAM access control check
            if ~isempty(icamController) && obj.hasCheckSend(icamController)
                messageType = "data_item:" + string(itemStruct.classification);
                % Use checkSend with requesting entity as source
                decision = icamController.checkSend( ...
                    requestingEntityId, targetDataStoreId, ...
                    messageType, itemStruct.enclaveId, simTimeSec);

                if strcmp(decision, 'deny')
                    obj.stats.totalFetchDenied = obj.stats.totalFetchDenied + 1;
                    logEntry = struct( ...
                        'type', "data_fetch_denied", ...
                        'dataItemId', dataItemId, ...
                        'requestingEntityId', requestingEntityId, ...
                        'requestingNodeId', requestingNodeId, ...
                        'targetDataStoreId', targetDataStoreId, ...
                        'classification', string(itemStruct.classification), ...
                        'simTimeSec', simTimeSec, ...
                        'reason', "access_denied");
                    return;
                end
            else
                % No ICAM configured — permit all with warning (logged once)
                obj.warnNoIcam();
            end

            % Permitted — return result with item metadata and provenance
            obj.stats.totalFetchResults = obj.stats.totalFetchResults + 1;
            logEntry = struct( ...
                'type', "data_fetch_result", ...
                'dataItemId', dataItemId, ...
                'requestingEntityId', requestingEntityId, ...
                'requestingNodeId', requestingNodeId, ...
                'targetDataStoreId', targetDataStoreId, ...
                'dataItemType', string(itemStruct.dataItemType), ...
                'classification', string(itemStruct.classification), ...
                'enclaveId', string(itemStruct.enclaveId), ...
                'creatorEntityId', string(itemStruct.creatorEntityId), ...
                'creatorNodeId', string(itemStruct.creatorNodeId), ...
                'creationTimeSec', itemStruct.creationTimeSec, ...
                'sizeBytes', itemStruct.sizeBytes, ...
                'provenanceChain', itemStruct.provenanceChain, ...
                'simTimeSec', simTimeSec);
        end

        function logEntry = handleQuery(obj, event, simTimeSec, icamController)
            % HANDLEQUERY Process a DATA_QUERY event.
            %
            % Queries the target DataStore's DataCatalog with criteria and
            % filters results by ICAM access control (if configured). Returns
            % metadata of permitted items only.
            %
            % Args:
            %   event (struct): Event struct with payload containing:
            %       queryCriteria (struct), requestingEntityId (string),
            %       requestingNodeId (string), targetDataStoreId (string).
            %   simTimeSec (double): Current simulation time in seconds.
            %   icamController: icam.ICAMController handle or [] if not configured.
            %
            % Returns:
            %   logEntry (struct): Log entry with type 'data_query_result'
            %       containing metadata of permitted items.
            %
            % Requirements: R36, R37

            arguments
                obj
                event (1,1) struct
                simTimeSec (1,1) double
                icamController = []
            end

            payload = event.payload;
            queryCriteria = payload.queryCriteria;
            requestingEntityId = string(payload.requestingEntityId);
            requestingNodeId = string(payload.requestingNodeId);
            targetDataStoreId = string(payload.targetDataStoreId);

            obj.stats.totalQueryRequests = obj.stats.totalQueryRequests + 1;

            % Check if target is a registered DataStore
            if ~obj.Registry.isDataStore(targetDataStoreId)
                logEntry = struct( ...
                    'type', "data_routing_error", ...
                    'requestingEntityId', requestingEntityId, ...
                    'targetDataStoreId', targetDataStoreId, ...
                    'simTimeSec', simTimeSec, ...
                    'message', "Target is not a registered DataStore");
                return;
            end

            % Get the DataCatalog for the target DataStore
            catalog = obj.Registry.getCatalog(targetDataStoreId);

            % Query the catalog with the criteria
            matchingItems = catalog.query(queryCriteria);

            % Filter by ICAM access control if configured
            if ~isempty(icamController) && obj.hasCheckSend(icamController)
                permittedItems = obj.filterByIcam( ...
                    matchingItems, requestingEntityId, targetDataStoreId, ...
                    icamController, simTimeSec);
            else
                % No ICAM configured — permit all with warning (logged once)
                obj.warnNoIcam();
                permittedItems = matchingItems;
            end

            % Build result metadata array
            nPermitted = numel(permittedItems);
            if nPermitted == 0
                resultMetadata = struct('id', {}, 'dataItemType', {}, ...
                    'classification', {}, 'enclaveId', {}, ...
                    'creatorEntityId', {}, 'creationTimeSec', {}, ...
                    'sizeBytes', {}, 'provenanceChain', {});
            else
                resultMetadata = permittedItems;
            end

            obj.stats.totalQueryResults = obj.stats.totalQueryResults + 1;

            logEntry.type = "data_query_result";
            logEntry.requestingEntityId = requestingEntityId;
            logEntry.requestingNodeId = requestingNodeId;
            logEntry.targetDataStoreId = targetDataStoreId;
            logEntry.matchCount = nPermitted;
            logEntry.permittedItems = resultMetadata;
            logEntry.simTimeSec = simTimeSec;
        end
    end

    methods
        function payload = createC2LogItem(obj, event, simTimeSec, c2LogDataStoreId)
            % CREATEC2LOGITEM Create a DATA_INGEST payload from a C2 message event.
            %
            % Builds a DataItem of type 'c2_log' with classification
            % UNCLASSIFIED and provenance referencing the C2_Message ID.
            % Returns a DATA_INGEST payload struct ready to be scheduled as
            % an event, or an empty struct if c2LogDataStoreId is invalid.
            %
            % Args:
            %   event (struct): C2 message event with payload containing at
            %       minimum: messageId, sourceEntityId, sourceNodeId, sizeBytes.
            %   simTimeSec (double): Current simulation time in seconds.
            %   c2LogDataStoreId (string): ID of the DataStore to ingest to.
            %
            % Returns:
            %   payload (struct): DATA_INGEST payload struct with fields
            %       dataItemId, dataItemStruct, targetDataStoreId. Empty
            %       struct if c2LogDataStoreId is invalid or empty.
            %
            % Requirements: R34, R38

            arguments
                obj %#ok<INUSD>
                event (1,1) struct
                simTimeSec (1,1) double
                c2LogDataStoreId (1,1) string
            end

            % Validate c2LogDataStoreId — must be non-empty and a registered DataStore
            if strlength(c2LogDataStoreId) == 0 || ~obj.Registry.isDataStore(c2LogDataStoreId)
                payload = struct();
                return;
            end

            % Extract message info from event payload
            msgPayload = event.payload;

            % Generate a new unique ID for the c2_log DataItem
            itemId = fabric.DataItem.generateId();

            % Build the DataItem struct
            itemStruct.id = itemId;
            itemStruct.dataItemType = "c2_log";
            itemStruct.creatorEntityId = string(msgPayload.sourceEntityId);
            itemStruct.creatorNodeId = string(msgPayload.sourceNodeId);
            itemStruct.creationTimeSec = simTimeSec;
            itemStruct.classification = "UNCLASSIFIED";

            % Use message sizeBytes if available, otherwise default
            if isfield(msgPayload, 'sizeBytes')
                itemStruct.sizeBytes = double(msgPayload.sizeBytes);
            else
                itemStruct.sizeBytes = 256;  % default c2_log size
            end

            % Use enclave from the target DataStore config if available
            cfg = obj.Registry.getConfig(c2LogDataStoreId);
            if isfield(cfg, 'enclaveId')
                itemStruct.enclaveId = string(cfg.enclaveId);
            else
                itemStruct.enclaveId = "default";
            end

            % Build provenance chain referencing the C2 message ID
            provEntry.sourceItemId = string(msgPayload.messageId);
            provEntry.sourceDataStoreId = "";
            provEntry.transformationType = "c2_message_log";
            provEntry.transformationTimeSec = simTimeSec;
            itemStruct.provenanceChain = provEntry;

            % Build the DATA_INGEST payload struct
            payload.dataItemId = itemId;
            payload.dataItemStruct = itemStruct;
            payload.targetDataStoreId = c2LogDataStoreId;
        end
    end

    methods (Access = private)
        function tf = hasCheckSend(~, icamController)
            % HASCHECKSEND Check if icamController has the checkSend method.
            %
            % Returns:
            %   tf (logical): true if icamController has checkSend.

            tf = ismethod(icamController, 'checkSend');
        end

        function warnNoIcam(~)
            % WARNNOICAM Log a one-time warning that data access control is unenforced.

            persistent warned
            if isempty(warned)
                warned = false;
            end

            if ~warned
                warning('netsim:fabric:noIcamConfigured', ...
                    'No ICAM layer configured — data access control is unenforced (permit-all).');
                warned = true;
            end
        end

        function permitted = filterByIcam(~, items, requestingEntityId, ...
                targetDataStoreId, icamController, simTimeSec)
            % FILTERBYICAM Filter items by ICAM access control.
            %
            % Checks each item's classification against the ICAM policy and
            % returns only those items for which access is permitted.
            %
            % Args:
            %   items (struct array): Matching items from catalog query.
            %   requestingEntityId (string): The requesting entity.
            %   targetDataStoreId (string): The DataStore being queried.
            %   icamController: icam.ICAMController handle.
            %   simTimeSec (double): Current simulation time.
            %
            % Returns:
            %   permitted (struct array): Items permitted by ICAM.

            if isempty(items)
                permitted = items;
                return;
            end

            nItems = numel(items);
            mask = true(1, nItems);

            for k = 1:nItems
                messageType = "data_item:" + string(items(k).classification);
                decision = icamController.checkSend( ...
                    requestingEntityId, targetDataStoreId, ...
                    messageType, items(k).enclaveId, simTimeSec);
                if strcmp(decision, 'deny')
                    mask(k) = false;
                end
            end

            permitted = items(mask);
        end
    end
end
