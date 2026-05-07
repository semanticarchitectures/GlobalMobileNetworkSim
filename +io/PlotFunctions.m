classdef PlotFunctions
    % io.PlotFunctions  Static visualization functions for simulation results.
    %
    % Provides three static methods for plotting simulation output:
    %   - latencyHistogram  : histogram of C2 message delivery latencies
    %   - outageGantt       : per-link outage fraction as a Gantt-style chart
    %   - fidelityBoxPlot   : per-agent fidelity scores across multiple runs
    %
    % All methods return a figure handle and create figures with
    % 'Visible','off' so they do not open windows during automated tests.
    %
    % Requirements: 9.4, 9.5, 15.5

    methods (Static)

        function fig = latencyHistogram(statsReport, latenciesMs)
            % latencyHistogram  Plot a histogram of C2 message latencies.
            %
            %   fig = io.PlotFunctions.latencyHistogram(statsReport)
            %   fig = io.PlotFunctions.latencyHistogram(statsReport, latenciesMs)
            %
            %   statsReport  — struct from SimController.buildStatsReport().
            %                  Uses statsReport.latency (meanMs, medianMs, p95Ms)
            %                  and statsReport.c2Messages.delivered.
            %   latenciesMs  — (optional) raw double array of per-message
            %                  latencies in milliseconds.
            %
            %   If latenciesMs is provided and non-empty, plots a histogram
            %   with vertical lines for mean and p95.  Otherwise, displays a
            %   'No delivered messages' annotation.
            %
            %   Returns the figure handle.
            %
            % Requirements: 9.4

            fig = figure('Visible', 'off');

            % Resolve optional second argument.
            hasLatencies = nargin >= 2 && ~isempty(latenciesMs);

            if hasLatencies
                % ---- Histogram of raw latency values ----
                ax = axes(fig); %#ok<LAXES>
                histogram(ax, latenciesMs);
                xlabel(ax, 'Latency (ms)');
                ylabel(ax, 'Count');
                title(ax, 'C2 Message Latency Distribution');

                % Add vertical reference lines when statistics are available.
                if isfield(statsReport, 'latency')
                    lat = statsReport.latency;
                    hold(ax, 'on');

                    if isfield(lat, 'meanMs') && ~isempty(lat.meanMs) && ...
                            isnumeric(lat.meanMs) && ~isnan(lat.meanMs)
                        xline(ax, lat.meanMs, '--b', 'Mean', ...
                            'LabelVerticalAlignment', 'bottom');
                    end

                    if isfield(lat, 'p95Ms') && ~isempty(lat.p95Ms) && ...
                            isnumeric(lat.p95Ms) && ~isnan(lat.p95Ms)
                        xline(ax, lat.p95Ms, '--r', 'p95', ...
                            'LabelVerticalAlignment', 'bottom');
                    end

                    hold(ax, 'off');
                end
            else
                % ---- No data: display annotation ----
                ax = axes(fig); %#ok<LAXES>
                axis(ax, 'off');
                text(ax, 0.5, 0.5, 'No delivered messages', ...
                    'HorizontalAlignment', 'center', ...
                    'VerticalAlignment',   'middle', ...
                    'Units',               'normalized', ...
                    'FontSize',            12);
                title(ax, 'C2 Message Latency Distribution');
            end
        end

        % ------------------------------------------------------------------

        function fig = outageGantt(statsReport, linkIds)
            % outageGantt  Plot per-link outage fractions as a Gantt-style chart.
            %
            %   fig = io.PlotFunctions.outageGantt(statsReport)
            %   fig = io.PlotFunctions.outageGantt(statsReport, linkIds)
            %
            %   statsReport — struct from SimController.buildStatsReport().
            %                 Uses statsReport.perLink (struct array with
            %                 fields linkId and outageFraction).
            %   linkIds     — (optional) cell array of link ID strings to
            %                 include.  If empty or omitted, all links in
            %                 statsReport.perLink are used.
            %
            %   Returns the figure handle.
            %
            % Requirements: 9.5

            fig = figure('Visible', 'off');

            % Determine whether there is any per-link data.
            hasData = isfield(statsReport, 'perLink') && ...
                      ~isempty(statsReport.perLink);

            if ~hasData
                ax = axes(fig); %#ok<LAXES>
                axis(ax, 'off');
                text(ax, 0.5, 0.5, 'No link data available', ...
                    'HorizontalAlignment', 'center', ...
                    'VerticalAlignment',   'middle', ...
                    'Units',               'normalized', ...
                    'FontSize',            12);
                title(ax, 'Per-Link Outage Summary');
                return;
            end

            perLink = statsReport.perLink;

            % Filter by requested linkIds when provided.
            if nargin >= 2 && ~isempty(linkIds)
                % Build index of matching entries.
                keep = false(numel(perLink), 1);
                for k = 1:numel(perLink)
                    lid = char(perLink(k).linkId);
                    keep(k) = any(strcmp(lid, linkIds));
                end
                perLink = perLink(keep);
            end

            if isempty(perLink)
                ax = axes(fig); %#ok<LAXES>
                axis(ax, 'off');
                text(ax, 0.5, 0.5, 'No link data available', ...
                    'HorizontalAlignment', 'center', ...
                    'VerticalAlignment',   'middle', ...
                    'Units',               'normalized', ...
                    'FontSize',            12);
                title(ax, 'Per-Link Outage Summary');
                return;
            end

            % Extract outage fractions and link labels.
            nLinks         = numel(perLink);
            outageFractions = zeros(nLinks, 1);
            labels          = cell(nLinks, 1);
            for k = 1:nLinks
                outageFractions(k) = perLink(k).outageFraction;
                labels{k}          = char(perLink(k).linkId);
            end

            % ---- Horizontal bar chart ----
            ax = axes(fig); %#ok<LAXES>
            barh(ax, outageFractions);
            ax.YTick      = 1:nLinks;
            ax.YTickLabel = labels;
            xlabel(ax, 'Outage Fraction');
            ylabel(ax, 'Link ID');
            title(ax, 'Per-Link Outage Summary');
            xlim(ax, [0, max(1, max(outageFractions) * 1.1)]);
        end

        % ------------------------------------------------------------------

        function fig = fidelityBoxPlot(evalReports)
            % fidelityBoxPlot  Box-and-whisker chart of agent fidelity scores.
            %
            %   fig = io.PlotFunctions.fidelityBoxPlot(evalReports)
            %
            %   evalReports — struct array or cell array of Evaluation_Report
            %                 structs (schema §4.4).  Each report must have an
            %                 'agents' field containing structs with a
            %                 'fidelityScore' field.
            %
            %   Plots one box per report (x-axis: run index, y-axis: fidelity
            %   score in [0, 1]).  If evalReports is empty or contains no
            %   agent data, displays a 'No evaluation data' annotation.
            %
            %   Returns the figure handle.
            %
            % Requirements: 15.5

            fig = figure('Visible', 'off');

            % Normalise input to a cell array of report structs.
            if isempty(evalReports)
                reports = {};
            elseif isstruct(evalReports)
                nR = numel(evalReports);
                reports = cell(nR, 1);
                for k = 1:nR
                    reports{k} = evalReports(k);
                end
            elseif iscell(evalReports)
                reports = evalReports(:);
            else
                reports = {};
            end

            % Collect fidelity score vectors, one per report.
            nReports = numel(reports);
            scoreData = cell(nReports, 1);
            hasAny    = false;

            for r = 1:nReports
                rep = reports{r};
                if ~isstruct(rep) || ~isfield(rep, 'agents') || isempty(rep.agents)
                    scoreData{r} = [];
                    continue;
                end
                agents = rep.agents;
                nA     = numel(agents);
                scores = zeros(nA, 1);
                for a = 1:nA
                    if isstruct(agents) 
                        ag = agents(a);
                    else
                        ag = agents{a};
                    end
                    if isfield(ag, 'fidelityScore')
                        scores(a) = ag.fidelityScore;
                    end
                end
                scoreData{r} = scores;
                hasAny = true;
            end

            if ~hasAny || nReports == 0
                ax = axes(fig); %#ok<LAXES>
                axis(ax, 'off');
                text(ax, 0.5, 0.5, 'No evaluation data', ...
                    'HorizontalAlignment', 'center', ...
                    'VerticalAlignment',   'middle', ...
                    'Units',               'normalized', ...
                    'FontSize',            12);
                title(ax, 'Agent Fidelity Score Distribution');
                return;
            end

            % Build a combined data matrix for boxplot.
            % Each column corresponds to one run; pad shorter columns with NaN.
            maxLen = max(cellfun(@numel, scoreData));
            if maxLen == 0
                ax = axes(fig); %#ok<LAXES>
                axis(ax, 'off');
                text(ax, 0.5, 0.5, 'No evaluation data', ...
                    'HorizontalAlignment', 'center', ...
                    'VerticalAlignment',   'middle', ...
                    'Units',               'normalized', ...
                    'FontSize',            12);
                title(ax, 'Agent Fidelity Score Distribution');
                return;
            end

            dataMatrix = NaN(maxLen, nReports);
            for r = 1:nReports
                v = scoreData{r};
                if ~isempty(v)
                    dataMatrix(1:numel(v), r) = v;
                end
            end

            % Build x-axis labels (run index or runId when available).
            xLabels = cell(nReports, 1);
            for r = 1:nReports
                rep = reports{r};
                if isstruct(rep) && isfield(rep, 'runId') && ~isempty(rep.runId)
                    xLabels{r} = char(rep.runId);
                else
                    xLabels{r} = num2str(r);
                end
            end

            % ---- Box-and-whisker chart ----
            ax = axes(fig); %#ok<LAXES>
            boxplot(ax, dataMatrix, 'Labels', xLabels);
            ylabel(ax, 'Fidelity Score');
            xlabel(ax, 'Run');
            title(ax, 'Agent Fidelity Score Distribution');
            ylim(ax, [0, 1]);
        end

        % ------------------------------------------------------------------

        function fig = missionMap(scenario, simController)
            % missionMap  Plot node locations, aircraft trajectory, and
            %             communication links on a geographic map.
            %
            %   fig = io.PlotFunctions.missionMap(scenario)
            %   fig = io.PlotFunctions.missionMap(scenario, simController)
            %
            %   scenario      — struct from io.ScenarioLoader.load()
            %   simController — (optional) sim.SimController after run();
            %                   used to overlay delivered/failed message
            %                   counts per link from the event log.
            %
            %   The plot shows:
            %     - World coastline outline (drawn from built-in MATLAB data)
            %     - Stationary nodes as filled circles with labels
            %     - Mobile waypoint trajectory as a dashed line with arrow
            %     - Satellite nodes shown at their initial position
            %     - Communication links as lines between connected nodes,
            %       coloured by link type
            %     - A legend identifying node types and link types
            %
            %   Returns the figure handle.

            fig = figure('Visible', 'off', 'Position', [100 100 1200 700]);
            ax  = axes(fig);
            hold(ax, 'on');

            % ---- Draw world map background ----
            % Use MATLAB's built-in coast data if available, otherwise skip.
            try
                load('coast', 'lat', 'long'); %#ok<LOAD>
                plot(ax, long, lat, 'Color', [0.7 0.7 0.7], 'LineWidth', 0.5);
            catch
                % coast data not available — draw a simple grid instead
                for lon = -180:30:180
                    plot(ax, [lon lon], [-90 90], 'Color', [0.9 0.9 0.9], 'LineWidth', 0.3);
                end
                for lat = -90:30:90
                    plot(ax, [-180 180], [lat lat], 'Color', [0.9 0.9 0.9], 'LineWidth', 0.3);
                end
            end

            % ---- Colour scheme for link types ----
            linkColors = struct( ...
                'GEO_Satellite',  [0.8  0.2  0.2], ...   % red
                'LEO_Satellite',  [0.2  0.5  0.9], ...   % blue
                'Fiber',          [0.1  0.7  0.1], ...   % green
                'Line_Of_Sight',  [0.9  0.6  0.0]);      % orange

            % ---- Build node position lookup ----
            nodes = scenario.nodes;
            if isstruct(nodes)
                nNodes = numel(nodes);
                getNode = @(k) nodes(k);
            else
                nNodes = numel(nodes);
                getNode = @(k) nodes{k};
            end

            nodeLat  = containers.Map('KeyType','char','ValueType','double');
            nodeLon  = containers.Map('KeyType','char','ValueType','double');
            nodeType = containers.Map('KeyType','char','ValueType','char');

            for k = 1:nNodes
                nd = getNode(k);
                nid = char(nd.id);
                nodeLat(nid)  = nd.lat;
                nodeLon(nid)  = nd.lon;
                nodeType(nid) = char(nd.type);
            end

            % ---- Draw communication links ----
            links = scenario.links;
            if isstruct(links)
                nLinks = numel(links);
                getLink = @(k) links(k);
            else
                nLinks = numel(links);
                getLink = @(k) links{k};
            end

            % Track which link types we've drawn (for legend)
            drawnLinkTypes = {};
            linkHandles    = [];

            for k = 1:nLinks
                lk  = getLink(k);
                lid = char(lk.type);
                src = char(lk.srcNodeId);
                dst = char(lk.dstNodeId);

                if ~nodeLat.isKey(src) || ~nodeLat.isKey(dst)
                    continue;
                end

                % Skip satellite relay nodes as link endpoints for clarity —
                % only draw links that connect to ground/mobile nodes
                srcIsSat = contains(src, 'SAT');
                dstIsSat = contains(dst, 'SAT');
                if srcIsSat && dstIsSat
                    continue;  % inter-satellite link, skip
                end

                % Get colour for this link type
                if isfield(linkColors, lid)
                    lc = linkColors.(lid);
                else
                    lc = [0.5 0.5 0.5];
                end

                x1 = nodeLon(src);  y1 = nodeLat(src);
                x2 = nodeLon(dst);  y2 = nodeLat(dst);

                % For satellite links, draw a curved arc via the satellite
                % position to make the relay hop visible
                if srcIsSat || dstIsSat
                    satId = src;
                    gndId = dst;
                    if dstIsSat
                        satId = dst;
                        gndId = src;
                    end
                    if nodeLat.isKey(satId)
                        % Draw two-segment path: ground → satellite → other ground
                        % (only draw the ground-to-satellite segment here)
                        sx = nodeLon(satId);
                        sy = nodeLat(satId);
                        gx = nodeLon(gndId);
                        gy = nodeLat(gndId);
                        h = plot(ax, [gx sx], [gy sy], '--', ...
                            'Color', [lc, 0.5], 'LineWidth', 0.8);
                    else
                        h = plot(ax, [x1 x2], [y1 y2], '--', ...
                            'Color', lc, 'LineWidth', 0.8);
                    end
                else
                    h = plot(ax, [x1 x2], [y1 y2], '-', ...
                        'Color', lc, 'LineWidth', 1.5);
                end

                % Track for legend (one entry per link type)
                if ~any(strcmp(drawnLinkTypes, lid))
                    drawnLinkTypes{end+1} = lid; %#ok<AGROW>
                    linkHandles(end+1)    = h;   %#ok<AGROW>
                end
            end

            % ---- Draw aircraft trajectory ----
            trajHandle = [];
            for k = 1:nNodes
                nd = getNode(k);
                if isfield(nd, 'trajectory') && ~isempty(nd.trajectory) && ...
                        isstruct(nd.trajectory) && ...
                        isfield(nd.trajectory, 'type') && ...
                        strcmp(nd.trajectory.type, 'waypoints')
                    wps = nd.trajectory.waypoints;
                    if isstruct(wps)
                        nWp = numel(wps);
                        wpLat = zeros(nWp,1);
                        wpLon = zeros(nWp,1);
                        for w = 1:nWp
                            wpLat(w) = wps(w).lat;
                            wpLon(w) = wps(w).lon;
                        end
                    else
                        nWp = numel(wps);
                        wpLat = zeros(nWp,1);
                        wpLon = zeros(nWp,1);
                        for w = 1:nWp
                            wpLat(w) = wps{w}.lat;
                            wpLon(w) = wps{w}.lon;
                        end
                    end

                    trajHandle = plot(ax, wpLon, wpLat, 'k--', ...
                        'LineWidth', 2.0, 'DisplayName', ...
                        sprintf('%s trajectory', char(nd.id)));

                    % Mark waypoints
                    plot(ax, wpLon, wpLat, 'k.', 'MarkerSize', 6);

                    % Arrow at midpoint to show direction
                    mid = max(1, floor(nWp/2));
                    if mid < nWp
                        dx = wpLon(mid+1) - wpLon(mid);
                        dy = wpLat(mid+1) - wpLat(mid);
                        quiver(ax, wpLon(mid), wpLat(mid), dx*0.3, dy*0.3, ...
                            0, 'k', 'LineWidth', 2, 'MaxHeadSize', 3);
                    end

                    % Mark start and end
                    plot(ax, wpLon(1),   wpLat(1),   'k^', ...
                        'MarkerSize', 10, 'MarkerFaceColor', 'k');
                    plot(ax, wpLon(end), wpLat(end), 'ks', ...
                        'MarkerSize', 10, 'MarkerFaceColor', 'k');
                    text(ax, wpLon(1)+0.5,   wpLat(1)+0.5,   'Start', ...
                        'FontSize', 8, 'Color', 'k');
                    text(ax, wpLon(end)+0.5, wpLat(end)+0.5, 'End', ...
                        'FontSize', 8, 'Color', 'k');
                end
            end

            % ---- Draw nodes ----
            nodeMarkers  = struct('Stationary','o','Mobile','^');
            nodeColors   = struct( ...
                'Stationary', [0.2 0.2 0.8], ...
                'Mobile',     [0.8 0.4 0.0]);

            stationaryHandle = [];
            mobileHandle     = [];
            satHandle        = [];

            for k = 1:nNodes
                nd  = getNode(k);
                nid = char(nd.id);
                lat = nodeLat(nid);
                lon = nodeLon(nid);
                typ = char(nd.type);

                isSat = isfield(nd, 'keplerElements') && ...
                        ~isempty(nd.keplerElements) && ...
                        isstruct(nd.keplerElements);

                hasWaypoints = isfield(nd, 'trajectory') && ...
                               ~isempty(nd.trajectory) && ...
                               isstruct(nd.trajectory);

                if isSat
                    % Satellite nodes: show at initial position with star marker
                    h = plot(ax, lon, lat, 'p', ...
                        'MarkerSize', 12, ...
                        'MarkerFaceColor', [0.6 0.0 0.8], ...
                        'MarkerEdgeColor', [0.4 0.0 0.6], ...
                        'LineWidth', 1.5);
                    if isempty(satHandle), satHandle = h; end
                    text(ax, lon+1, lat+1, nid, ...
                        'FontSize', 7, 'Color', [0.4 0.0 0.6], ...
                        'FontWeight', 'bold');

                elseif hasWaypoints
                    % Mobile waypoint nodes: already drawn as trajectory
                    % Just label the start position
                    text(ax, lon-2, lat-1.5, nid, ...
                        'FontSize', 9, 'Color', 'k', 'FontWeight', 'bold');

                else
                    % Stationary nodes
                    h = plot(ax, lon, lat, 'o', ...
                        'MarkerSize', 12, ...
                        'MarkerFaceColor', nodeColors.Stationary, ...
                        'MarkerEdgeColor', nodeColors.Stationary * 0.7, ...
                        'LineWidth', 1.5);
                    if isempty(stationaryHandle), stationaryHandle = h; end
                    text(ax, lon+0.8, lat+0.8, nid, ...
                        'FontSize', 9, 'Color', nodeColors.Stationary, ...
                        'FontWeight', 'bold');
                end
            end

            % ---- Overlay message delivery stats (if simController provided) ----
            if nargin >= 2 && ~isempty(simController) && ...
                    ~isempty(simController.eventLog)
                % Count delivered messages per src→dst pair
                deliveredPairs = containers.Map('KeyType','char','ValueType','double');
                failedPairs    = containers.Map('KeyType','char','ValueType','double');
                evLog = simController.eventLog;
                for e = 1:numel(evLog)
                    ev = evLog(e);
                    if string(ev.eventType) == "C2_MESSAGE_RX"
                        key = sprintf('%s->%s', char(ev.srcNodeId), char(ev.dstNodeId));
                        if deliveredPairs.isKey(key)
                            deliveredPairs(key) = deliveredPairs(key) + 1;
                        else
                            deliveredPairs(key) = 1;
                        end
                    elseif string(ev.eventType) == "C2_MESSAGE_FAIL"
                        key = sprintf('%s->%s', char(ev.srcNodeId), char(ev.dstNodeId));
                        if failedPairs.isKey(key)
                            failedPairs(key) = failedPairs(key) + 1;
                        else
                            failedPairs(key) = 1;
                        end
                    end
                end

                % Annotate each unique src→dst pair with delivery count
                allKeys = [deliveredPairs.keys(), failedPairs.keys()];
                allKeys = unique(allKeys);
                for ki = 1:numel(allKeys)
                    key   = allKeys{ki};
                    parts = strsplit(key, '->');
                    if numel(parts) ~= 2, continue; end
                    src = parts{1};  dst = parts{2};
                    if ~nodeLat.isKey(src) || ~nodeLat.isKey(dst), continue; end

                    mx = (nodeLon(src) + nodeLon(dst)) / 2;
                    my = (nodeLat(src) + nodeLat(dst)) / 2;

                    nDel  = 0;  if deliveredPairs.isKey(key), nDel  = deliveredPairs(key); end
                    nFail = 0;  if failedPairs.isKey(key),    nFail = failedPairs(key);    end

                    if nDel > 0 || nFail > 0
                        label = sprintf('%d/%d', nDel, nDel+nFail);
                        col   = [0 0.6 0];
                        if nFail > 0, col = [0.7 0.3 0]; end
                        text(ax, mx, my, label, ...
                            'FontSize', 7, 'Color', col, ...
                            'HorizontalAlignment', 'center', ...
                            'BackgroundColor', [1 1 1]);
                    end
                end
            end

            % ---- Formatting ----
            xlim(ax, [-100, 60]);
            ylim(ax, [25, 75]);
            xlabel(ax, 'Longitude (°)');
            ylabel(ax, 'Latitude (°)');
            grid(ax, 'on');
            ax.GridAlpha = 0.2;

            % Title
            if isfield(scenario, 'scenarioName')
                title(ax, sprintf('Mission Map — %s', scenario.scenarioName), ...
                    'FontSize', 13, 'FontWeight', 'bold');
            else
                title(ax, 'Mission Map', 'FontSize', 13, 'FontWeight', 'bold');
            end

            % ---- Legend ----
            legendHandles = [];
            legendLabels  = {};

            if ~isempty(stationaryHandle)
                legendHandles(end+1) = stationaryHandle;
                legendLabels{end+1}  = 'Stationary node';
            end
            if ~isempty(satHandle)
                legendHandles(end+1) = satHandle;
                legendLabels{end+1}  = 'Satellite node';
            end
            if ~isempty(trajHandle)
                legendHandles(end+1) = trajHandle;
                legendLabels{end+1}  = 'Aircraft trajectory';
            end
            for li = 1:numel(drawnLinkTypes)
                legendHandles(end+1) = linkHandles(li); %#ok<AGROW>
                legendLabels{end+1}  = strrep(drawnLinkTypes{li}, '_', ' '); %#ok<AGROW>
            end

            if ~isempty(legendHandles)
                legend(ax, legendHandles, legendLabels, ...
                    'Location', 'southwest', 'FontSize', 8);
            end

            hold(ax, 'off');
        end

    end % methods (Static)

end % classdef
