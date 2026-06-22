classdef ProvenanceGraph < handle
    % PROVENANCEGRAPH Handle class tracking data item derivation lineage.
    %
    % Uses MATLAB's digraph internally to model directed derivation
    % relationships between DataItems. Supports lineage queries (ancestors)
    % and descendant queries via BFS traversal with depth bounds.
    %
    % Usage:
    %   pg = fabric.ProvenanceGraph();
    %   pg.addItem("item_1");
    %   pg.addItem("item_2");
    %   pg.addDerivation("item_1", "item_2", "aggregation", 100.5);
    %   ancestors = pg.getLineage("item_2", 5);
    %
    % Requirements: R33, R38

    properties (Access = private)
        Graph       % digraph object
        NodeMap     % containers.Map: itemId -> node index (for fast lookup)
    end

    methods
        function obj = ProvenanceGraph()
            % PROVENANCEGRAPH Construct an empty provenance graph.

            obj.Graph = digraph();
            obj.NodeMap = containers.Map('KeyType', 'char', 'ValueType', 'double');
        end

        function addItem(obj, itemId)
            % ADDITEM Add a node to the provenance graph.
            %
            % Args:
            %   itemId (string): The data item ID to add as a node.
            %
            % If the item already exists, this is a no-op.

            arguments
                obj
                itemId (1,1) string
            end

            key = char(itemId);
            if obj.NodeMap.isKey(key)
                return;  % Already exists
            end

            % Add node to digraph
            obj.Graph = addnode(obj.Graph, key);
            obj.NodeMap(key) = numnodes(obj.Graph);
        end

        function addDerivation(obj, sourceItemId, derivedItemId, transformationType, timeSec)
            % ADDDERIVATION Add a directed edge from source to derived item.
            %
            % Creates an edge source -> derived, representing that
            % derivedItemId was produced from sourceItemId via the
            % specified transformation.
            %
            % Args:
            %   sourceItemId (string): The source data item ID.
            %   derivedItemId (string): The derived data item ID.
            %   transformationType (string): Type of transformation applied.
            %   timeSec (double): Simulation time of the derivation.

            arguments
                obj
                sourceItemId (1,1) string
                derivedItemId (1,1) string
                transformationType (1,1) string
                timeSec (1,1) double
            end

            % Ensure both nodes exist
            obj.addItem(sourceItemId);
            obj.addItem(derivedItemId);

            % Add directed edge: source -> derived with metadata
            obj.Graph = addedge(obj.Graph, char(sourceItemId), char(derivedItemId), ...
                table(string(transformationType), timeSec, ...
                'VariableNames', {'TransformationType', 'TimeSec'}));
        end

        function ancestors = getLineage(obj, itemId, maxDepth)
            % GETLINEAGE Return ancestor items up to maxDepth hops via BFS.
            %
            % Traverses the graph in reverse (following edges backwards)
            % to find all source items that contributed to this item.
            %
            % Args:
            %   itemId (string): The item to trace lineage for.
            %   maxDepth (double): Maximum BFS depth.
            %
            % Returns:
            %   ancestors (struct array): Struct array with fields:
            %       itemId, depth, transformationType, timeSec

            arguments
                obj
                itemId (1,1) string
                maxDepth (1,1) double {mustBePositive, mustBeInteger}
            end

            ancestors = obj.bfsTraversal(itemId, maxDepth, 'predecessors');
        end

        function descendants = getDescendants(obj, itemId, maxDepth)
            % GETDESCENDANTS Return derived items up to maxDepth hops via BFS.
            %
            % Traverses the graph forward (following edges) to find all
            % items derived from this item.
            %
            % Args:
            %   itemId (string): The item to find descendants for.
            %   maxDepth (double): Maximum BFS depth.
            %
            % Returns:
            %   descendants (struct array): Struct array with fields:
            %       itemId, depth, transformationType, timeSec

            arguments
                obj
                itemId (1,1) string
                maxDepth (1,1) double {mustBePositive, mustBeInteger}
            end

            descendants = obj.bfsTraversal(itemId, maxDepth, 'successors');
        end

        function n = nodeCount(obj)
            % NODECOUNT Return the number of items (nodes) in the graph.
            %
            % Returns:
            %   n (double): Number of nodes.

            n = numnodes(obj.Graph);
        end

        function n = edgeCount(obj)
            % EDGECOUNT Return the number of derivation edges in the graph.
            %
            % Returns:
            %   n (double): Number of edges.

            n = numedges(obj.Graph);
        end
    end

    methods (Access = private)
        function results = bfsTraversal(obj, startId, maxDepth, direction)
            % BFSTRAVERSAL Perform BFS in the specified direction.
            %
            % Args:
            %   startId (string): Starting node.
            %   maxDepth (double): Max hops.
            %   direction (string): 'predecessors' or 'successors'.
            %
            % Returns:
            %   results (struct array): Found nodes with metadata.

            results = struct('itemId', {}, 'depth', {}, ...
                'transformationType', {}, 'timeSec', {});

            key = char(startId);
            if ~obj.NodeMap.isKey(key)
                return;  % Node not in graph
            end

            % BFS queue: {nodeId, depth}
            visited = containers.Map('KeyType', 'char', 'ValueType', 'logical');
            visited(key) = true;

            queue = {key, 0};
            head = 1;

            while head <= size(queue, 1)
                currentNode = queue{head, 1};
                currentDepth = queue{head, 2};
                head = head + 1;

                if currentDepth >= maxDepth
                    continue;
                end

                % Get neighbors based on direction
                if strcmp(direction, 'predecessors')
                    neighbors = predecessors(obj.Graph, currentNode);
                else
                    neighbors = successors(obj.Graph, currentNode);
                end

                for i = 1:numel(neighbors)
                    neighborId = char(neighbors{i});
                    if visited.isKey(neighborId)
                        continue;
                    end
                    visited(neighborId) = true;

                    % Get edge metadata
                    if strcmp(direction, 'predecessors')
                        edgeIdx = findedge(obj.Graph, neighborId, currentNode);
                    else
                        edgeIdx = findedge(obj.Graph, currentNode, neighborId);
                    end

                    if edgeIdx > 0
                        tType = obj.Graph.Edges.TransformationType(edgeIdx);
                        tTime = obj.Graph.Edges.TimeSec(edgeIdx);
                    else
                        tType = "";
                        tTime = 0;
                    end

                    entry.itemId = string(neighborId);
                    entry.depth = currentDepth + 1;
                    entry.transformationType = tType;
                    entry.timeSec = tTime;
                    results(end+1) = entry; %#ok<AGROW>

                    % Add to queue
                    queue{end+1, 1} = neighborId; %#ok<AGROW>
                    queue{end, 2} = currentDepth + 1;
                end
            end
        end
    end
end
