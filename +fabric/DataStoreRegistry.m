classdef DataStoreRegistry < handle
    % DATASTOREREGISTRY Handle class tracking which nodes are DataStores.
    %
    % Maintains a registry of DataStore node IDs and holds per-node
    % DataCatalog and ProvenanceGraph references. Provides methods to
    % register, query, and retrieve catalogs/graphs for DataStore nodes.
    %
    % Usage:
    %   reg = fabric.DataStoreRegistry();
    %   cfg.replicationPolicy = "all";
    %   reg.register("node_1", cfg);
    %   tf = reg.isDataStore("node_1");       % true
    %   catalog = reg.getCatalog("node_1");
    %   pg = reg.getProvenanceGraph("node_1");
    %   ids = reg.listDataStores();
    %
    % Requirements: R35

    properties (Access = private)
        NodeMap         % containers.Map: nodeId (char) -> struct with catalog, graph, config
    end

    methods
        function obj = DataStoreRegistry()
            % DATASTOREREGISTRY Construct an empty registry.

            obj.NodeMap = containers.Map('KeyType', 'char', 'ValueType', 'any');
        end

        function register(obj, nodeId, config)
            % REGISTER Register a node as a DataStore.
            %
            % Creates a DataCatalog and ProvenanceGraph for the node.
            % If already registered, this is a no-op.
            %
            % Args:
            %   nodeId (string): The node ID to register as a DataStore.
            %   config (struct, optional): Configuration struct with fields
            %       such as replicationPolicy, replicationTargets, etc.

            arguments
                obj
                nodeId (1,1) string
                config (1,1) struct = struct()
            end

            key = char(nodeId);
            if obj.NodeMap.isKey(key)
                return;  % Already registered
            end

            entry.catalog = fabric.DataCatalog();
            entry.provenanceGraph = fabric.ProvenanceGraph();
            entry.config = config;

            obj.NodeMap(key) = entry;
        end

        function tf = isDataStore(obj, nodeId)
            % ISDATASTORE Check if a node is registered as a DataStore.
            %
            % Args:
            %   nodeId (string): The node ID to check.
            %
            % Returns:
            %   tf (logical): true if the node is a registered DataStore.

            arguments
                obj
                nodeId (1,1) string
            end

            tf = obj.NodeMap.isKey(char(nodeId));
        end

        function catalog = getCatalog(obj, nodeId)
            % GETCATALOG Return the DataCatalog for a DataStore node.
            %
            % Args:
            %   nodeId (string): The DataStore node ID.
            %
            % Returns:
            %   catalog (fabric.DataCatalog): The node's catalog.
            %
            % Throws:
            %   netsim:fabric:notADataStore if nodeId is not registered.

            arguments
                obj
                nodeId (1,1) string
            end

            key = char(nodeId);
            if ~obj.NodeMap.isKey(key)
                error('netsim:fabric:notADataStore', ...
                    'Node "%s" is not registered as a DataStore.', key);
            end

            entry = obj.NodeMap(key);
            catalog = entry.catalog;
        end

        function pg = getProvenanceGraph(obj, nodeId)
            % GETPROVENANCEGRAPH Return the ProvenanceGraph for a DataStore node.
            %
            % Args:
            %   nodeId (string): The DataStore node ID.
            %
            % Returns:
            %   pg (fabric.ProvenanceGraph): The node's provenance graph.
            %
            % Throws:
            %   netsim:fabric:notADataStore if nodeId is not registered.

            arguments
                obj
                nodeId (1,1) string
            end

            key = char(nodeId);
            if ~obj.NodeMap.isKey(key)
                error('netsim:fabric:notADataStore', ...
                    'Node "%s" is not registered as a DataStore.', key);
            end

            entry = obj.NodeMap(key);
            pg = entry.provenanceGraph;
        end

        function ids = listDataStores(obj)
            % LISTDATASTORES Return string array of registered DataStore node IDs.
            %
            % Returns:
            %   ids (string): String array of all registered DataStore node IDs.

            keys = obj.NodeMap.keys();
            if isempty(keys)
                ids = string.empty(1, 0);
            else
                ids = string(keys);
            end
        end

        function n = count(obj)
            % COUNT Return the number of registered DataStores.
            %
            % Returns:
            %   n (double): Number of registered DataStore nodes.

            n = obj.NodeMap.Count;
        end

        function cfg = getConfig(obj, nodeId)
            % GETCONFIG Return the config struct for a DataStore node.
            %
            % Args:
            %   nodeId (string): The DataStore node ID.
            %
            % Returns:
            %   cfg (struct): The configuration struct for this DataStore.
            %
            % Throws:
            %   netsim:fabric:notADataStore if nodeId is not registered.

            arguments
                obj
                nodeId (1,1) string
            end

            key = char(nodeId);
            if ~obj.NodeMap.isKey(key)
                error('netsim:fabric:notADataStore', ...
                    'Node "%s" is not registered as a DataStore.', key);
            end

            entry = obj.NodeMap(key);
            cfg = entry.config;
        end
    end

    methods (Static)
        function reg = fromScenario(scenario)
            % FROMSCENARIO Create a populated DataStoreRegistry from a scenario struct.
            %
            % Scans scenario.nodes for any node with field dataStore = true,
            % registers each one with its dataStoreConfig (if present).
            %
            % Args:
            %   scenario (struct): Scenario struct as returned by io.ScenarioLoader.load.
            %
            % Returns:
            %   reg (fabric.DataStoreRegistry): Populated registry.

            arguments
                scenario (1,1) struct
            end

            reg = fabric.DataStoreRegistry();

            % If no nodes field, return empty registry
            if ~isfield(scenario, 'nodes') || isempty(scenario.nodes)
                return;
            end

            nodes = scenario.nodes;

            % Handle struct array or cell array from jsondecode
            if isstruct(nodes)
                nNodes = numel(nodes);
                getNode = @(k) nodes(k);
            elseif iscell(nodes)
                nNodes = numel(nodes);
                getNode = @(k) nodes{k};
            else
                return;
            end

            for k = 1:nNodes
                nd = getNode(k);

                % Check if this node is a DataStore
                if isfield(nd, 'dataStore') && isequal(nd.dataStore, true)
                    nodeId = string(nd.id);

                    % Extract config if present
                    if isfield(nd, 'dataStoreConfig') && isstruct(nd.dataStoreConfig)
                        config = nd.dataStoreConfig;
                    else
                        config = struct();
                    end

                    reg.register(nodeId, config);
                end
            end
        end
    end
end
