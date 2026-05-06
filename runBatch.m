function combinedReport = runBatch(scenarioFiles, outputDir, llmClient)
% runBatch  Execute multiple scenario files sequentially and produce a
%           combined evaluation report.
%
%   combinedReport = runBatch(scenarioFiles, outputDir)
%   combinedReport = runBatch(scenarioFiles, outputDir, llmClient)
%
%   scenarioFiles — cell array of scenario JSON file paths
%   outputDir     — directory for output files (created if needed)
%   llmClient     — (optional) agent.LLMClient instance
%
%   Returns a combined evaluation report struct with:
%     runs — struct array, each with: runId, timestamp, scenarioName,
%             agents (fidelity results)
%
% Requirements: 15.1, 15.3, 16.1, 16.3, 16.5

% -------------------------------------------------------------------------
% Input validation
% -------------------------------------------------------------------------
if nargin < 2
    error('netsim:runBatch:missingArgs', ...
        'runBatch requires at least scenarioFiles and outputDir arguments.');
end

if nargin < 3
    llmClient = [];
end

if ischar(scenarioFiles)
    % Allow a single file path as a convenience.
    scenarioFiles = {scenarioFiles};
end

if ~iscell(scenarioFiles)
    error('netsim:runBatch:invalidInput', ...
        'scenarioFiles must be a cell array of file paths.');
end

% -------------------------------------------------------------------------
% Create output directory if it does not exist
% -------------------------------------------------------------------------
outputDir = char(outputDir);
if ~exist(outputDir, 'dir')
    mkdir(outputDir);
end

% -------------------------------------------------------------------------
% Initialise combined report
% -------------------------------------------------------------------------
combinedReport.runs = struct( ...
    'runId', {}, 'timestamp', {}, 'scenarioName', {}, 'agents', {});

% -------------------------------------------------------------------------
% Process each scenario file sequentially
% -------------------------------------------------------------------------
nScenarios = numel(scenarioFiles);

for k = 1:nScenarios
    scenarioFile = char(scenarioFiles{k});

    fprintf('[runBatch] Processing scenario %d/%d: %s\n', k, nScenarios, scenarioFile);

    % Load scenario from JSON.
    try
        scenario = io.ScenarioLoader.load(scenarioFile);
    catch ME
        warning('netsim:runBatch:loadError', ...
            'Failed to load scenario file "%s": %s', scenarioFile, ME.message);
        continue;
    end

    % Determine scenario name for output file naming.
    if isfield(scenario, 'scenarioName') && ~isempty(scenario.scenarioName)
        scenarioName = char(scenario.scenarioName);
    else
        % Fall back to the file base name without extension.
        [~, baseName, ~] = fileparts(scenarioFile);
        scenarioName = baseName;
    end

    % Construct SimController (with optional llmClient).
    try
        if ~isempty(llmClient)
            sc = sim.SimController(scenario, llmClient);
        else
            sc = sim.SimController(scenario);
        end
    catch ME
        warning('netsim:runBatch:constructError', ...
            'Failed to construct SimController for "%s": %s', scenarioFile, ME.message);
        continue;
    end

    % Run the simulation.
    try
        sc.run();
    catch ME
        warning('netsim:runBatch:runError', ...
            'Simulation run failed for "%s": %s', scenarioFile, ME.message);
        continue;
    end

    % Write per-run output files via ReportWriter.
    try
        rw = io.ReportWriter(outputDir, scenarioName);
        rw.writeEventLog(sc.eventLog);
        rw.writeStatisticsReport(sc.buildStatsReport());
        evalReport = sc.buildEvalReport();
        rw.writeEvaluationReport(evalReport);
        if ~isempty(sc.agentRegistry)
            rw.writeBehaviorTraces(sc.agentRegistry.getAllTracers());
        end
    catch ME
        warning('netsim:runBatch:writeError', ...
            'Failed to write output files for "%s": %s', scenarioFile, ME.message);
        % Continue — still collect the eval report.
    end

    % Collect per-run eval report into combined report.
    runEntry.runId       = sc.runId;
    runEntry.timestamp   = sc.runTimestamp;
    runEntry.scenarioName = scenarioName;
    if ~isempty(sc.evalResults) && numel(sc.evalResults) > 0
        runEntry.agents = sc.evalResults;
    else
        runEntry.agents = struct( ...
            'agentId', {}, 'role', {}, 'fidelityScore', {}, ...
            'missingActions', {}, 'extraActions', {}, 'deviations', {});
    end

    combinedReport.runs(end + 1) = runEntry;
end

% -------------------------------------------------------------------------
% Write combined evaluation report to JSON
% -------------------------------------------------------------------------
combinedReportFile = fullfile(outputDir, 'combined_eval_report.json');
try
    jsonText = jsonencode(combinedReport, 'PrettyPrint', true);
catch
    jsonText = jsonencode(combinedReport);
end

fid = fopen(combinedReportFile, 'w');
if fid == -1
    warning('netsim:runBatch:writeError', ...
        'Cannot open combined report file for writing: %s', combinedReportFile);
else
    try
        fwrite(fid, jsonText, 'char');
    catch ME
        fclose(fid);
        warning('netsim:runBatch:writeError', ...
            'Failed to write combined report: %s', ME.message);
        return;
    end
    fclose(fid);
    fprintf('[runBatch] Combined evaluation report written to: %s\n', combinedReportFile);
end

end
