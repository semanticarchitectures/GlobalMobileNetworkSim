classdef ReportWriter < handle
    % io.ReportWriter  Writes simulation output files (CSV and JSON).
    %
    % Writes the event log, statistics report, evaluation report, and
    % per-agent behavior traces produced by a simulation run.
    %
    % Usage:
    %   rw = io.ReportWriter(outputDir, scenarioName);
    %   rw.writeEventLog(eventLog);
    %   rw.writeStatisticsReport(statsReport);
    %   rw.writeEvaluationReport(evalReport);
    %   rw.writeBehaviorTraces(agentRegistry);
    %
    % Requirements: 8.5, 9.1, 9.2, 9.3, 16.1, 16.2, 16.3

    % -----------------------------------------------------------------
    % Properties
    % -----------------------------------------------------------------
    properties (Access = private)
        outputDir     % directory where output files are written
        scenarioName  % prefix for output filenames
    end

    % -----------------------------------------------------------------
    % Constructor
    % -----------------------------------------------------------------
    methods
        function rw = ReportWriter(outputDir, scenarioName)
            % ReportWriter  Construct a writer for the given output directory.
            %
            %   rw = io.ReportWriter(outputDir, scenarioName)
            %
            %   outputDir    — directory where output files are written;
            %                  created if it does not already exist.
            %   scenarioName — used as a prefix for all output filenames.

            if nargin < 2
                error('io:ReportWriter:missingArgs', ...
                    'ReportWriter requires outputDir and scenarioName arguments.');
            end

            rw.outputDir    = char(outputDir);
            rw.scenarioName = char(scenarioName);

            % Create output directory if it does not exist.
            if ~exist(rw.outputDir, 'dir')
                mkdir(rw.outputDir);
            end
        end
    end

    % -----------------------------------------------------------------
    % Public methods
    % -----------------------------------------------------------------
    methods

        function writeEventLog(rw, eventLog)
            % writeEventLog  Write the event log to a CSV file.
            %
            %   rw.writeEventLog(eventLog)
            %
            %   Writes <outputDir>/<scenarioName>_event_log.csv with columns:
            %     eventId, simTimeSec, eventType, linkId, msgId,
            %     srcNodeId, dstNodeId, latencyMs, reason
            %
            %   eventLog is a struct array with those fields.
            %   An empty eventLog writes the header row only.
            %
            % Requirements: 8.5, 9.1

            filePath = fullfile(rw.outputDir, ...
                [rw.scenarioName, '_event_log.csv']);

            headers = {'eventId', 'simTimeSec', 'eventType', 'linkId', ...
                       'msgId', 'srcNodeId', 'dstNodeId', 'latencyMs', 'reason'};

            % Build rows from struct array.
            if isempty(eventLog)
                rows = {};
            else
                nRows = numel(eventLog);
                rows  = cell(nRows, 1);
                for k = 1:nRows
                    e = eventLog(k);
                    rows{k} = { ...
                        io.ReportWriter.toStr(e.eventId), ...
                        io.ReportWriter.toStr(e.simTimeSec), ...
                        io.ReportWriter.toStr(e.eventType), ...
                        io.ReportWriter.toStr(e.linkId), ...
                        io.ReportWriter.toStr(e.msgId), ...
                        io.ReportWriter.toStr(e.srcNodeId), ...
                        io.ReportWriter.toStr(e.dstNodeId), ...
                        io.ReportWriter.toStr(e.latencyMs), ...
                        io.ReportWriter.toStr(e.reason) ...
                    };
                end
            end

            rw.writeCSV(filePath, headers, rows);
        end

        function writeStatisticsReport(rw, statsReport)
            % writeStatisticsReport  Write the statistics report to a JSON file.
            %
            %   rw.writeStatisticsReport(statsReport)
            %
            %   Writes <outputDir>/<scenarioName>_stats.json.
            %   statsReport is the struct returned by SimController.buildStatsReport().
            %
            % Requirements: 9.1, 9.2, 9.3

            filePath = fullfile(rw.outputDir, ...
                [rw.scenarioName, '_stats.json']);

            rw.writeJSON(filePath, statsReport);
        end

        function writeEvaluationReport(rw, evalReport)
            % writeEvaluationReport  Write the evaluation report to a JSON file.
            %
            %   rw.writeEvaluationReport(evalReport)
            %
            %   Writes <outputDir>/<scenarioName>_eval.json.
            %   evalReport is a struct matching the Evaluation_Report schema (§4.4).
            %
            % Requirements: 16.1, 16.3

            filePath = fullfile(rw.outputDir, ...
                [rw.scenarioName, '_eval.json']);

            rw.writeJSON(filePath, evalReport);
        end

        function writeBehaviorTraces(rw, agentRegistry)
            % writeBehaviorTraces  Write one CSV per agent behavior trace.
            %
            %   rw.writeBehaviorTraces(agentRegistry)
            %
            %   Writes <outputDir>/<scenarioName>_trace_<agentId>.csv for
            %   each agent with columns:
            %     simTimeSec, agentId, role, actionType, targetAgentId, msgId
            %
            %   agentRegistry is a struct array or cell array of structs with
            %   fields: agentId, role, trace (table or struct array).
            %   An empty agentRegistry writes nothing.
            %
            % Requirements: 16.2

            if isempty(agentRegistry)
                return;
            end

            headers = {'simTimeSec', 'agentId', 'role', 'actionType', ...
                       'targetAgentId', 'msgId'};

            % Support both struct array and cell array.
            if isstruct(agentRegistry)
                nAgents  = numel(agentRegistry);
                getAgent = @(k) agentRegistry(k);
            elseif iscell(agentRegistry)
                nAgents  = numel(agentRegistry);
                getAgent = @(k) agentRegistry{k};
            else
                return;
            end

            for k = 1:nAgents
                ag = getAgent(k);

                agentId = char(ag.agentId);
                role    = char(ag.role);

                % Sanitize agentId for use in filename (replace non-alphanumeric
                % characters with underscores).
                safeId   = regexprep(agentId, '[^a-zA-Z0-9_\-]', '_');
                filePath = fullfile(rw.outputDir, ...
                    [rw.scenarioName, '_trace_', safeId, '.csv']);

                % Build rows from trace (table or struct array).
                rows = {};
                if isfield(ag, 'trace') && ~isempty(ag.trace)
                    trace = ag.trace;
                    if istable(trace)
                        nRows = height(trace);
                        rows  = cell(nRows, 1);
                        for r = 1:nRows
                            rows{r} = { ...
                                io.ReportWriter.toStr(trace.simTimeSec(r)), ...
                                io.ReportWriter.toStr(agentId), ...
                                io.ReportWriter.toStr(role), ...
                                io.ReportWriter.toStr(trace.actionType(r)), ...
                                io.ReportWriter.toStr(trace.targetAgentId(r)), ...
                                io.ReportWriter.toStr(trace.msgId(r)) ...
                            };
                        end
                    elseif isstruct(trace)
                        nRows = numel(trace);
                        rows  = cell(nRows, 1);
                        for r = 1:nRows
                            t = trace(r);
                            rows{r} = { ...
                                io.ReportWriter.toStr(t.simTimeSec), ...
                                io.ReportWriter.toStr(agentId), ...
                                io.ReportWriter.toStr(role), ...
                                io.ReportWriter.toStr(t.actionType), ...
                                io.ReportWriter.toStr(t.targetAgentId), ...
                                io.ReportWriter.toStr(t.msgId) ...
                            };
                        end
                    end
                end

                rw.writeCSV(filePath, headers, rows);
            end
        end

    end % methods (public)

    % -----------------------------------------------------------------
    % Private methods
    % -----------------------------------------------------------------
    methods (Access = private)

        function writeCSV(~, filePath, headers, rows)
            % writeCSV  Write a CSV file from headers and row data.
            %
            %   writeCSV(filePath, headers, rows)
            %
            %   headers — cell array of column header strings
            %   rows    — cell array of row cell arrays (each row is a
            %             cell array of string values, one per column)

            fid = fopen(filePath, 'w');
            if fid == -1
                error('io:ReportWriter:fileWriteError', ...
                    'Cannot open file for writing: %s', filePath);
            end

            try
                % Write header row.
                headerLine = strjoin(headers, ',');
                fprintf(fid, '%s\n', headerLine);

                % Write data rows.
                for k = 1:numel(rows)
                    row     = rows{k};
                    rowLine = strjoin(row, ',');
                    fprintf(fid, '%s\n', rowLine);
                end
            catch ME
                fclose(fid);
                rethrow(ME);
            end

            fclose(fid);
        end

        function writeJSON(~, filePath, data)
            % writeJSON  Encode data as JSON and write to filePath.
            %
            %   Uses PrettyPrint when available (MATLAB R2021a+), falls back
            %   to plain jsonencode.

            try
                jsonText = jsonencode(data, 'PrettyPrint', true);
            catch
                jsonText = jsonencode(data);
            end

            fid = fopen(filePath, 'w');
            if fid == -1
                error('io:ReportWriter:fileWriteError', ...
                    'Cannot open file for writing: %s', filePath);
            end

            try
                fwrite(fid, jsonText, 'char');
            catch ME
                fclose(fid);
                rethrow(ME);
            end

            fclose(fid);
        end

    end % methods (private)

    % -----------------------------------------------------------------
    % Private static helpers
    % -----------------------------------------------------------------
    methods (Static, Access = private)

        function s = toStr(value)
            % toStr  Convert a scalar value to a CSV-safe string.
            %
            %   Handles: numeric (including NaN/Inf), string, char, logical,
            %   uint64, and empty values.

            if isempty(value)
                s = '';
            elseif isnumeric(value) || islogical(value)
                if isnan(value)
                    s = '';
                elseif isinf(value)
                    if value > 0
                        s = 'Inf';
                    else
                        s = '-Inf';
                    end
                else
                    % Use %g for compact representation; integers print without
                    % decimal point.
                    s = num2str(value, '%g');
                end
            elseif isinteger(value)
                s = num2str(double(value));
            elseif ischar(value)
                s = value;
            elseif isstring(value)
                s = char(value);
            else
                % Fallback: convert via num2str / char.
                try
                    s = char(value);
                catch
                    s = '';
                end
            end
        end

    end % methods (Static, Access = private)

end % classdef
