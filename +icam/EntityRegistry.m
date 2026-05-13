classdef EntityRegistry < handle
    % EntityRegistry  Manages all entities and sub-entities for the ICAM layer.
    %
    % Uses struct-of-arrays storage for memory efficiency, consistent with
    % NodeRegistry and LinkRegistry. Supports 10,000+ entities within the
    % 16 GB RAM constraint (Requirement 17.5).
    %
    % Internal storage fields:
    %   entities.entityId       — string array, N×1
    %   entities.nodeId         — string array, N×1
    %   entities.entityType     — string array, N×1 ('human' or 'NPE')
    %   entities.parentEntityId — string array, N×1 (empty string for top-level)
    %   entities.enclaveIds     — cell array of string arrays, N×1
    %
    % Requirements: 17.1, 17.2, 17.3, 17.4, 17.5

    properties (Access = private)
        % Struct-of-arrays internal storage
        entities    % struct with fields: entityId, nodeId, entityType,
                    %   parentEntityId, enclaveIds
        n           % number of entities (scalar double)
    end

    methods (Access = public)

        % ------------------------------------------------------------------
        % Constructor
        % ------------------------------------------------------------------

        function obj = EntityRegistry(entityDefs, nodeRegistry)
            % EntityRegistry  Construct an EntityRegistry from entity definitions.
            %
            %   er = icam.EntityRegistry(entityDefs, nodeRegistry)
            %
            %   entityDefs may be:
            %     - A struct array (one element per entity)
            %     - A cell array of structs (one cell per entity)
            %     - An empty array [] (creates an empty registry)
            %
            %   Each element must have fields:
            %     id              (string)  — unique entity identifier
            %     nodeId          (string)  — parent node identifier
            %     type            (string)  — 'human' or 'NPE'
            %
            %   Optional fields:
            %     parentEntityId  (string)  — parent entity ID (empty for top-level)
            %     enclaveIds      (cell)    — cell array of enclave ID strings
            %     roleBindings    (struct)  — struct array with enclaveId/roleName
            %
            %   nodeRegistry must be a network.NodeRegistry instance.
            %   Every entityDef.nodeId is validated against nodeRegistry.indexOf().
            %
            %   Throws:
            %     netsim:icam:unknownNode      — if any nodeId is not in NodeRegistry
            %     netsim:icam:duplicateEntityId — if any entityId appears more than once
            %
            % Requirements: 17.1, 17.2, 17.3, 17.4

            % Normalise input to a cell array of structs
            if isempty(entityDefs)
                cellDefs = {};
                nEntities = 0;
            elseif isstruct(entityDefs)
                nEntities = numel(entityDefs);
                cellDefs = cell(nEntities, 1);
                for k = 1:nEntities
                    cellDefs{k} = entityDefs(k);
                end
            elseif iscell(entityDefs)
                cellDefs = entityDefs(:);
                nEntities = numel(cellDefs);
            else
                error('netsim:icam:invalidInput', ...
                    'entityDefs must be a struct array, cell array, or empty.');
            end

            obj.n = nEntities;

            % Pre-allocate struct-of-arrays
            obj.entities.entityId       = strings(nEntities, 1);
            obj.entities.nodeId         = strings(nEntities, 1);
            obj.entities.entityType     = strings(nEntities, 1);
            obj.entities.parentEntityId = strings(nEntities, 1);
            obj.entities.enclaveIds     = cell(nEntities, 1);

            % Populate arrays, validate nodeIds, and check for duplicates
            for k = 1:nEntities
                def = cellDefs{k};

                entityId = string(def.id);
                nodeId   = string(def.nodeId);

                % Check for duplicate entityId (against already-stored entries)
                if k > 1
                    if any(obj.entities.entityId(1:k-1) == entityId)
                        error('netsim:icam:duplicateEntityId', ...
                            'Duplicate entity ID: "%s"', entityId);
                    end
                end

                % Validate nodeId against NodeRegistry
                try
                    nodeRegistry.indexOf(nodeId);
                catch
                    error('netsim:icam:unknownNode', ...
                        'Entity "%s": node "%s" not found', entityId, nodeId);
                end

                obj.entities.entityId(k)   = entityId;
                obj.entities.nodeId(k)     = nodeId;
                obj.entities.entityType(k) = string(def.type);

                % Optional: parentEntityId
                if isfield(def, 'parentEntityId') && ~isempty(def.parentEntityId)
                    obj.entities.parentEntityId(k) = string(def.parentEntityId);
                else
                    obj.entities.parentEntityId(k) = "";
                end

                % Optional: enclaveIds
                if isfield(def, 'enclaveIds') && ~isempty(def.enclaveIds)
                    obj.entities.enclaveIds{k} = def.enclaveIds;
                else
                    obj.entities.enclaveIds{k} = {};
                end
            end
        end

        % ------------------------------------------------------------------
        % Public methods
        % ------------------------------------------------------------------

        function entity = getEntity(obj, entityId)
            % getEntity  Return a struct with all fields for the given entity.
            %
            %   entity = er.getEntity(entityId)
            %
            %   Returns a struct with fields:
            %     entityId, nodeId, entityType, parentEntityId, enclaveIds
            %
            %   Throws netsim:icam:unknownEntity if entityId is not found.
            %
            % Requirements: 17.1, 17.3

            idx = obj.indexOf(entityId);
            entity = obj.buildEntityStruct(idx);
        end

        function subEntities = getSubEntities(obj, nodeId)
            % getSubEntities  Return struct array of all entities at a given node.
            %
            %   subEntities = er.getSubEntities(nodeId)
            %
            %   Returns a struct array (possibly empty) of all entities whose
            %   nodeId matches the given nodeId.
            %
            % Requirements: 17.2

            nodeIdStr = string(nodeId);
            matches = find(obj.entities.nodeId == nodeIdStr);

            if isempty(matches)
                subEntities = struct( ...
                    'entityId',       {}, ...
                    'nodeId',         {}, ...
                    'entityType',     {}, ...
                    'parentEntityId', {}, ...
                    'enclaveIds',     {});
                return;
            end

            % Build struct array from matching indices
            nMatch = numel(matches);
            subEntities = repmat(struct( ...
                'entityId',       "", ...
                'nodeId',         "", ...
                'entityType',     "", ...
                'parentEntityId', "", ...
                'enclaveIds',     {{}}), nMatch, 1);

            for k = 1:nMatch
                idx = matches(k);
                subEntities(k) = obj.buildEntityStruct(idx);
            end
        end

        function idx = indexOf(obj, entityId)
            % indexOf  Return the integer index of an entity in the internal arrays.
            %
            %   idx = er.indexOf(entityId)
            %
            %   Throws netsim:icam:unknownEntity if entityId is not found.
            %
            % Requirements: 17.3

            entityIdStr = string(entityId);
            matches = find(obj.entities.entityId == entityIdStr, 1);

            if isempty(matches)
                error('netsim:icam:unknownEntity', ...
                    'Entity with ID "%s" was not found in the EntityRegistry.', ...
                    entityIdStr);
            end

            idx = matches;
        end

        function n = count(obj)
            % count  Return the total number of entities in the registry.
            %
            %   n = er.count()
            %
            % Requirements: 17.5

            n = obj.n;
        end

        function addEntity(obj, def)
            % addEntity  Add a single entity definition to the registry.
            %
            %   er.addEntity(def)
            %
            %   def must have the same fields as entityDefs elements passed
            %   to the constructor (id, nodeId, type; optionally parentEntityId,
            %   enclaveIds, roleBindings).
            %
            %   The nodeRegistry reference used at construction time is not
            %   available here, so nodeId validation is skipped. Callers that
            %   need nodeId validation should use the constructor.
            %
            %   Throws netsim:icam:duplicateEntityId if the entity ID already exists.
            %
            % Requirements: 17.3

            entityId = string(def.id);

            % Check for duplicate
            if obj.n > 0 && any(obj.entities.entityId(1:obj.n) == entityId)
                error('netsim:icam:duplicateEntityId', ...
                    'Duplicate entity ID: "%s"', entityId);
            end

            % Grow arrays by one
            obj.n = obj.n + 1;
            k = obj.n;

            obj.entities.entityId(k)   = entityId;
            obj.entities.nodeId(k)     = string(def.nodeId);
            obj.entities.entityType(k) = string(def.type);

            if isfield(def, 'parentEntityId') && ~isempty(def.parentEntityId)
                obj.entities.parentEntityId(k) = string(def.parentEntityId);
            else
                obj.entities.parentEntityId(k) = "";
            end

            if isfield(def, 'enclaveIds') && ~isempty(def.enclaveIds)
                obj.entities.enclaveIds{k} = def.enclaveIds;
            else
                obj.entities.enclaveIds{k} = {};
            end
        end

        function ids = getEntityIds(obj)
            % getEntityIds  Return a string array of all entity IDs.
            %
            %   ids = er.getEntityIds()
            %
            % Requirements: 17.1

            if obj.n == 0
                ids = strings(0, 1);
            else
                ids = obj.entities.entityId(1:obj.n);
            end
        end

    end % methods (Access = public)

    % ======================================================================
    % Private helpers
    % ======================================================================
    methods (Access = private)

        function entity = buildEntityStruct(obj, idx)
            % buildEntityStruct  Build a scalar entity struct from index idx.

            entity.entityId       = obj.entities.entityId(idx);
            entity.nodeId         = obj.entities.nodeId(idx);
            entity.entityType     = obj.entities.entityType(idx);
            entity.parentEntityId = obj.entities.parentEntityId(idx);
            entity.enclaveIds     = obj.entities.enclaveIds{idx};
        end

    end % methods (Access = private)

end % classdef
