classdef DataCatalog < handle
    % DATACATALOG Handle class providing O(1) lookup and bulk query of DataItems.
    %
    % Maintains a containers.Map for fast ID-based access and a
    % struct-of-arrays backing store for efficient bulk filtering operations.
    %
    % Usage:
    %   catalog = fabric.DataCatalog();
    %   item = fabric.DataItem(s);
    %   catalog.add(item);
    %   retrieved = catalog.get(item.id);
    %   matches = catalog.query(struct('classification', "SECRET"));
    %
    % Requirements: R33, R38

    properties (Access = private)
        Map         % containers.Map: id -> index into backing arrays
        % Struct-of-arrays backing store for bulk operations
        Ids (:,1) string = string.empty(0,1)
        DataItemTypes (:,1) string = string.empty(0,1)
        CreatorEntityIds (:,1) string = string.empty(0,1)
        CreatorNodeIds (:,1) string = string.empty(0,1)
        CreationTimesSec (:,1) double = double.empty(0,1)
        SizesBytes (:,1) double = double.empty(0,1)
        Classifications (:,1) string = string.empty(0,1)
        EnclaveIds (:,1) string = string.empty(0,1)
        ProvenanceChains cell = {}
    end

    methods
        function obj = DataCatalog()
            % DATACATALOG Construct an empty DataCatalog.

            obj.Map = containers.Map('KeyType', 'char', 'ValueType', 'double');
        end

        function add(obj, dataItem)
            % ADD Add a DataItem to the catalog.
            %
            % Args:
            %   dataItem (fabric.DataItem): The item to add.
            %
            % Throws:
            %   netsim:fabric:duplicateItem if item ID already exists.

            arguments
                obj
                dataItem (1,1) fabric.DataItem
            end

            key = char(dataItem.id);
            if obj.Map.isKey(key)
                error('netsim:fabric:duplicateItem', ...
                    'DataItem with id "%s" already exists in catalog.', key);
            end

            % Append to backing arrays
            idx = numel(obj.Ids) + 1;
            obj.Ids(idx,1) = dataItem.id;
            obj.DataItemTypes(idx,1) = dataItem.dataItemType;
            obj.CreatorEntityIds(idx,1) = dataItem.creatorEntityId;
            obj.CreatorNodeIds(idx,1) = dataItem.creatorNodeId;
            obj.CreationTimesSec(idx,1) = dataItem.creationTimeSec;
            obj.SizesBytes(idx,1) = dataItem.sizeBytes;
            obj.Classifications(idx,1) = dataItem.classification;
            obj.EnclaveIds(idx,1) = dataItem.enclaveId;
            obj.ProvenanceChains{idx,1} = dataItem.provenanceChain;

            % Map stores the index
            obj.Map(key) = idx;
        end

        function s = get(obj, itemId)
            % GET Retrieve a DataItem struct by ID.
            %
            % Args:
            %   itemId (string): The item ID to look up.
            %
            % Returns:
            %   s (struct): Struct representation of the DataItem.
            %
            % Throws:
            %   netsim:fabric:itemNotFound if the ID is not in the catalog.

            arguments
                obj
                itemId (1,1) string
            end

            key = char(itemId);
            if ~obj.Map.isKey(key)
                error('netsim:fabric:itemNotFound', ...
                    'DataItem with id "%s" not found in catalog.', key);
            end

            idx = obj.Map(key);
            s = obj.buildStructAtIndex(idx);
        end

        function tf = exists(obj, itemId)
            % EXISTS Check if an item ID is in the catalog.
            %
            % Args:
            %   itemId (string): The item ID to check.
            %
            % Returns:
            %   tf (logical): true if the item exists.

            arguments
                obj
                itemId (1,1) string
            end

            tf = obj.Map.isKey(char(itemId));
        end

        function remove(obj, itemId)
            % REMOVE Remove an item from the catalog.
            %
            % Uses a swap-with-last approach for O(1) removal from the
            % backing arrays while maintaining Map index consistency.
            %
            % Args:
            %   itemId (string): The item ID to remove.
            %
            % Throws:
            %   netsim:fabric:itemNotFound if the ID is not in the catalog.

            arguments
                obj
                itemId (1,1) string
            end

            key = char(itemId);
            if ~obj.Map.isKey(key)
                error('netsim:fabric:itemNotFound', ...
                    'DataItem with id "%s" not found in catalog.', key);
            end

            idx = obj.Map(key);
            lastIdx = numel(obj.Ids);

            if idx ~= lastIdx
                % Swap with last element
                obj.Ids(idx) = obj.Ids(lastIdx);
                obj.DataItemTypes(idx) = obj.DataItemTypes(lastIdx);
                obj.CreatorEntityIds(idx) = obj.CreatorEntityIds(lastIdx);
                obj.CreatorNodeIds(idx) = obj.CreatorNodeIds(lastIdx);
                obj.CreationTimesSec(idx) = obj.CreationTimesSec(lastIdx);
                obj.SizesBytes(idx) = obj.SizesBytes(lastIdx);
                obj.Classifications(idx) = obj.Classifications(lastIdx);
                obj.EnclaveIds(idx) = obj.EnclaveIds(lastIdx);
                obj.ProvenanceChains{idx} = obj.ProvenanceChains{lastIdx};

                % Update the swapped element's index in the Map
                swappedKey = char(obj.Ids(idx));
                obj.Map(swappedKey) = idx;
            end

            % Remove last element from arrays
            obj.Ids(lastIdx) = [];
            obj.DataItemTypes(lastIdx) = [];
            obj.CreatorEntityIds(lastIdx) = [];
            obj.CreatorNodeIds(lastIdx) = [];
            obj.CreationTimesSec(lastIdx) = [];
            obj.SizesBytes(lastIdx) = [];
            obj.Classifications(lastIdx) = [];
            obj.EnclaveIds(lastIdx) = [];
            obj.ProvenanceChains(lastIdx) = [];

            % Remove from Map
            obj.Map.remove(key);
        end

        function n = count(obj)
            % COUNT Return the number of items in the catalog.
            %
            % Returns:
            %   n (double): Item count.

            n = numel(obj.Ids);
        end

        function results = query(obj, criteria)
            % QUERY Return struct array of items matching criteria.
            %
            % Criteria is a struct with optional fields: classification,
            % enclaveId, dataItemType, creatorEntityId. All specified
            % fields must match (AND logic).
            %
            % Args:
            %   criteria (struct): Filter criteria.
            %
            % Returns:
            %   results (struct array): Matching items as structs.

            arguments
                obj
                criteria (1,1) struct
            end

            if obj.count() == 0
                results = struct('id', {}, 'dataItemType', {}, ...
                    'creatorEntityId', {}, 'creatorNodeId', {}, ...
                    'creationTimeSec', {}, 'sizeBytes', {}, ...
                    'classification', {}, 'enclaveId', {}, ...
                    'provenanceChain', {});
                return;
            end

            % Start with all indices
            mask = true(numel(obj.Ids), 1);

            if isfield(criteria, 'classification') && ~isempty(criteria.classification)
                mask = mask & (obj.Classifications == string(criteria.classification));
            end

            if isfield(criteria, 'enclaveId') && ~isempty(criteria.enclaveId)
                mask = mask & (obj.EnclaveIds == string(criteria.enclaveId));
            end

            if isfield(criteria, 'dataItemType') && ~isempty(criteria.dataItemType)
                mask = mask & (obj.DataItemTypes == string(criteria.dataItemType));
            end

            if isfield(criteria, 'creatorEntityId') && ~isempty(criteria.creatorEntityId)
                mask = mask & (obj.CreatorEntityIds == string(criteria.creatorEntityId));
            end

            matchIndices = find(mask);
            if isempty(matchIndices)
                results = struct('id', {}, 'dataItemType', {}, ...
                    'creatorEntityId', {}, 'creatorNodeId', {}, ...
                    'creationTimeSec', {}, 'sizeBytes', {}, ...
                    'classification', {}, 'enclaveId', {}, ...
                    'provenanceChain', {});
                return;
            end

            results = arrayfun(@(i) obj.buildStructAtIndex(i), matchIndices);
        end

        function ids = listIds(obj)
            % LISTIDS Return string array of all item IDs in the catalog.
            %
            % Returns:
            %   ids (string array): All item IDs.

            ids = obj.Ids;
        end
    end

    methods (Access = private)
        function s = buildStructAtIndex(obj, idx)
            % BUILDSTRUCTATINDEX Build a DataItem struct from backing arrays.

            s.id = obj.Ids(idx);
            s.dataItemType = obj.DataItemTypes(idx);
            s.creatorEntityId = obj.CreatorEntityIds(idx);
            s.creatorNodeId = obj.CreatorNodeIds(idx);
            s.creationTimeSec = obj.CreationTimesSec(idx);
            s.sizeBytes = obj.SizesBytes(idx);
            s.classification = obj.Classifications(idx);
            s.enclaveId = obj.EnclaveIds(idx);
            s.provenanceChain = obj.ProvenanceChains{idx};
        end
    end
end
