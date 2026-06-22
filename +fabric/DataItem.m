classdef DataItem
    % DATAITEM Value class representing a data item in the data fabric.
    %
    % A DataItem captures metadata about a piece of data flowing through
    % the network simulation: sensor telemetry, mission reports, C2 logs,
    % or derived analytics products.
    %
    % Usage:
    %   s.id = fabric.DataItem.generateId();
    %   s.dataItemType = 'sensor_telemetry';
    %   s.creatorEntityId = "entity_1";
    %   s.creatorNodeId = "node_1";
    %   s.creationTimeSec = 42.0;
    %   s.sizeBytes = 1024;
    %   s.classification = "UNCLASSIFIED";
    %   s.enclaveId = "enclave_alpha";
    %   s.provenanceChain = struct('sourceItemId', {}, 'sourceDataStoreId', {}, ...
    %       'transformationType', {}, 'transformationTimeSec', {});
    %   item = fabric.DataItem(s);
    %
    % Requirements: R33, R38

    properties (SetAccess = immutable)
        id (1,1) string
        dataItemType (1,1) string
        creatorEntityId (1,1) string
        creatorNodeId (1,1) string
        creationTimeSec (1,1) double
        sizeBytes (1,1) double
        classification (1,1) string
        enclaveId (1,1) string
        provenanceChain struct
    end

    methods
        function obj = DataItem(s)
            % DATAITEM Construct a DataItem from a struct.
            %
            % Args:
            %   s (struct): Struct with all required fields.

            arguments
                s (1,1) struct
            end

            obj.id = string(s.id);
            obj.dataItemType = string(s.dataItemType);
            obj.creatorEntityId = string(s.creatorEntityId);
            obj.creatorNodeId = string(s.creatorNodeId);
            obj.creationTimeSec = double(s.creationTimeSec);
            obj.sizeBytes = double(s.sizeBytes);
            obj.classification = string(s.classification);
            obj.enclaveId = string(s.enclaveId);

            if isfield(s, 'provenanceChain') && ~isempty(s.provenanceChain)
                obj.provenanceChain = s.provenanceChain;
            else
                obj.provenanceChain = struct('sourceItemId', {}, ...
                    'sourceDataStoreId', {}, 'transformationType', {}, ...
                    'transformationTimeSec', {});
            end
        end

        function s = toStruct(obj)
            % TOSTRUCT Convert DataItem to a plain struct.
            %
            % Returns:
            %   s (struct): Struct representation of this DataItem.

            s.id = obj.id;
            s.dataItemType = obj.dataItemType;
            s.creatorEntityId = obj.creatorEntityId;
            s.creatorNodeId = obj.creatorNodeId;
            s.creationTimeSec = obj.creationTimeSec;
            s.sizeBytes = obj.sizeBytes;
            s.classification = obj.classification;
            s.enclaveId = obj.enclaveId;
            s.provenanceChain = obj.provenanceChain;
        end
    end

    methods (Static)
        function item = createFromStruct(s)
            % CREATEFROMSTRUCT Validate required fields and return a DataItem.
            %
            % Args:
            %   s (struct): Struct with data item fields.
            %
            % Returns:
            %   item (fabric.DataItem): Constructed DataItem.
            %
            % Throws:
            %   netsim:fabric:missingField if a required field is absent.

            arguments
                s (1,1) struct
            end

            requiredFields = ["id", "dataItemType", "creatorEntityId", ...
                "creatorNodeId", "creationTimeSec", "sizeBytes", ...
                "classification", "enclaveId"];

            for i = 1:numel(requiredFields)
                if ~isfield(s, requiredFields(i))
                    error('netsim:fabric:missingField', ...
                        'Required field "%s" is missing from DataItem struct.', ...
                        requiredFields(i));
                end
            end

            % Validate dataItemType
            validTypes = ["sensor_telemetry", "mission_report", "c2_log", "derived"];
            if ~ismember(string(s.dataItemType), validTypes)
                error('netsim:fabric:invalidType', ...
                    'dataItemType must be one of: %s. Got "%s".', ...
                    strjoin(validTypes, ', '), string(s.dataItemType));
            end

            item = fabric.DataItem(s);
        end

        function uid = generateId()
            % GENERATEID Generate a unique ID string (UUID v4 format).
            %
            % Returns:
            %   uid (string): UUID string, e.g. "a1b2c3d4-e5f6-..."

            % Use Java UUID for robust uniqueness
            uid = string(char(java.util.UUID.randomUUID()));
        end
    end
end
