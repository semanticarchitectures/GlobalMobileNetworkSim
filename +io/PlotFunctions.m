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

    end % methods (Static)

end % classdef
