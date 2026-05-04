classdef RoutingEngine < handle
    % RoutingEngine  Wraps MATLAB's digraph/shortestpath for network routing.
    %
    % Maintains a directed graph (digraph) of currently active links.  Edge
    % weights are the effective latency (nominal + congestion penalty) of each
    % link.  Outage links and inactive LOS links are excluded from the graph.
    %
    % On each outage transition, only the affected edges are removed or added
    % (incremental update) rather than rebuilding the full graph, keeping
    % updates O(degree) rather than O(E).  A full rebuild is triggered on
    % scenario load and after batch topology changes via rebuildGraph().
    %
    % Usage:
    %   re = network.RoutingEngine(nodeRegistry, linkRegistry)
    %   [path, totalLatencyMs] = re.selectPath(srcId, dstId, simTimeSec)
    %   re.invalidateCache(linkId)   % called on outage transitions
    %   re.rebuildGraph()            % full rebuild from active links
    %
    % Requirements: 5.2, 5.3, 5.5, 6.1, 6.2, 6.3, 6.4, 6.5

    properties (Access = private)
        nodeReg   % network.NodeRegistry
        linkReg   % network.LinkRegistry
        G         % MATLAB digraph object (current routing graph)
        % Map from linkId (string) to edge index in G (double).
        % Maintained incrementally; rebuilt by rebuildGraph().
        linkEdgeMap  % containers.Map: linkId -> edgeIndex (or 0 if not in graph)
    end

    methods (Access = public)

        % ------------------------------------------------------------------
        % Constructor
        % ------------------------------------------------------------------

        function obj = RoutingEngine(nodeRegistry, linkRegistry)
            % RoutingEngine  Construct a RoutingEngine and build the initial graph.
            %
            %   re = network.RoutingEngine(nodeRegistry, linkRegistry)
            %
            %   Builds an initial digraph from all currently active links.
            %   Edge weights are getEffectiveLatency(linkId) from LinkRegistry.
            %   Only active links (isLinkActive == true) are included as edges.
            %   Node names in the digraph are the node ID strings from NodeRegistry.
            %
            % Requirements: 6.1, 6.2

            obj.nodeReg    = nodeRegistry;
            obj.linkReg    = linkRegistry;
            obj.linkEdgeMap = containers.Map('KeyType', 'char', 'ValueType', 'double');
            obj.rebuildGraph();
        end

        % ------------------------------------------------------------------
        % selectPath
        % ------------------------------------------------------------------

        function [path, totalLatencyMs] = selectPath(obj, srcId, dstId, ~)
            % selectPath  Find the minimum-latency path between two nodes.
            %
            %   [path, totalLatencyMs] = re.selectPath(srcId, dstId, simTimeSec)
            %
            %   Uses shortestpath(G, srcNode, dstNode, 'Method', 'positive')
            %   (Dijkstra's algorithm) on the current routing digraph.
            %
            %   Returns:
            %     path           — cell array of node ID strings ordered from
            %                      src to dst; {} if no path exists
            %     totalLatencyMs — sum of edge weights along the path;
            %                      Inf if no path exists
            %
            % Requirements: 5.2, 5.3, 5.5, 6.2, 6.4

            srcStr = string(srcId);
            dstStr = string(dstId);

            % Check that both nodes exist in the graph
            nodeNames = obj.G.Nodes.Name;
            if ~any(nodeNames == srcStr) || ~any(nodeNames == dstStr)
                path           = {};
                totalLatencyMs = Inf;
                return;
            end

            % Run Dijkstra
            [pathNodes, totalLatencyMs] = shortestpath(obj.G, srcStr, dstStr, ...
                'Method', 'positive');

            if isempty(pathNodes)
                % No path found
                path           = {};
                totalLatencyMs = Inf;
            else
                % Convert string array to cell array of char/string
                path = cellstr(pathNodes);
            end
        end

        % ------------------------------------------------------------------
        % invalidateCache
        % ------------------------------------------------------------------

        function invalidateCache(obj, linkId)
            % invalidateCache  Incrementally update the digraph for a link
            %                  that has transitioned to/from outage state.
            %
            %   re.invalidateCache(linkId)
            %
            %   Checks the current active state of the link in LinkRegistry:
            %     - If link is now inactive: remove the edge from the digraph
            %     - If link is now active:   add the edge back with current
            %                                effective latency
            %
            %   This avoids a full rebuild for each outage transition.
            %
            % Requirements: 6.1, 6.3

            linkIdStr = char(linkId);
            info      = obj.linkReg.getLinkInfo(linkId);
            srcStr    = string(info.srcNodeId);
            dstStr    = string(info.dstNodeId);

            if info.isActive
                % Link became active — add edge if not already in graph
                alreadyPresent = isKey(obj.linkEdgeMap, linkIdStr) && ...
                                 obj.linkEdgeMap(linkIdStr) > 0;
                if ~alreadyPresent
                    obj.G = addedge(obj.G, srcStr, dstStr, info.effectiveLatencyMs);
                    % The new edge is always appended at the end
                    newIdx = numedges(obj.G);
                    obj.linkEdgeMap(linkIdStr) = newIdx;
                else
                    % Edge exists; update its weight
                    eIdx = obj.linkEdgeMap(linkIdStr);
                    obj.G.Edges.Weight(eIdx) = info.effectiveLatencyMs;
                end
            else
                % Link became inactive — remove edge if present in graph
                if isKey(obj.linkEdgeMap, linkIdStr) && ...
                        obj.linkEdgeMap(linkIdStr) > 0
                    eIdx  = obj.linkEdgeMap(linkIdStr);
                    obj.G = rmedge(obj.G, eIdx);
                    % After removal, edge indices of edges with higher indices
                    % shift down by 1.  Update the map accordingly.
                    obj.shiftEdgeIndicesAfter(eIdx);
                    obj.linkEdgeMap(linkIdStr) = 0;
                end
            end
        end

        % ------------------------------------------------------------------
        % rebuildGraph
        % ------------------------------------------------------------------

        function rebuildGraph(obj)
            % rebuildGraph  Full reconstruction of the digraph from all
            %               currently active links.
            %
            %   re.rebuildGraph()
            %
            %   Called at scenario load and after batch topology changes.
            %   Queries LinkRegistry for all active link IDs, retrieves
            %   source/destination node IDs and effective latencies, and
            %   constructs a fresh digraph.
            %
            % Requirements: 6.1, 6.2

            % Collect all node names from NodeRegistry
            nNodes    = obj.nodeReg.count();
            nodeNames = strings(nNodes, 1);
            for k = 1:nNodes
                nodeNames(k) = obj.nodeReg.getIdByIndex(k);
            end

            % Get all currently active link IDs
            activeLinkIds = obj.linkReg.getActiveLinkIds();
            nEdges        = numel(activeLinkIds);

            % Reset the edge map
            obj.linkEdgeMap = containers.Map('KeyType', 'char', 'ValueType', 'double');

            % Also record inactive links with index 0
            allLinkIds = obj.linkReg.getLinkIds();
            for k = 1:numel(allLinkIds)
                obj.linkEdgeMap(char(allLinkIds(k))) = 0;
            end

            if nEdges == 0
                % Build graph with nodes only, no edges
                obj.G = digraph([], [], [], cellstr(nodeNames));
                return;
            end

            % Build edge arrays
            srcNodes = strings(nEdges, 1);
            dstNodes = strings(nEdges, 1);
            weights  = zeros(nEdges, 1);

            for k = 1:nEdges
                lid  = activeLinkIds(k);
                info = obj.linkReg.getLinkInfo(lid);
                srcNodes(k) = string(info.srcNodeId);
                dstNodes(k) = string(info.dstNodeId);
                weights(k)  = info.effectiveLatencyMs;
                obj.linkEdgeMap(char(lid)) = k;
            end

            % Construct digraph with explicit node list to include isolated nodes
            obj.G = digraph(srcNodes, dstNodes, weights, cellstr(nodeNames));
        end

    end % methods (Access = public)

    % ======================================================================
    % Private helpers
    % ======================================================================
    methods (Access = private)

        function shiftEdgeIndicesAfter(obj, removedIdx)
            % shiftEdgeIndicesAfter  Decrement all edge indices > removedIdx
            %                        in the linkEdgeMap after an edge removal.
            %
            %   When rmedge removes edge at index removedIdx, all edges that
            %   had indices > removedIdx are renumbered down by 1.

            keys   = obj.linkEdgeMap.keys();
            for k = 1:numel(keys)
                key = keys{k};
                idx = obj.linkEdgeMap(key);
                if idx > removedIdx
                    obj.linkEdgeMap(key) = idx - 1;
                end
            end
        end

    end % methods (Access = private)

end % classdef
