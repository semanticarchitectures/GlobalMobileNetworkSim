%% run_airdrop_mission.m
% Headless script to run the airdrop mission scenario and generate all
% output reports and plots.
%
% Usage (from the project root):
%   matlab -nodisplay -nosplash -r "run_airdrop_mission; exit"
%
% Or interactively:
%   cd /path/to/GlobalMobileNetworkSim
%   run_airdrop_mission
%
% To run with LLM agents, set the environment variable before launching:
%   export NETSIM_LLM_API_KEY=sk-...
%   matlab -nodisplay -nosplash -r "run_airdrop_mission; exit"
%
% Outputs are written to:
%   output/airdrop_mission/
%     AirdropMission_event_log.csv
%     AirdropMission_stats.json
%     AirdropMission_eval.json          (only when agents run)
%     AirdropMission_trace_*.csv        (one per agent, only when agents run)
%     AirdropMission_latency_histogram.png
%     AirdropMission_outage_gantt.png
%     AirdropMission_fidelity_boxplot.png (only when agents run)

fprintf('=============================================================\n');
fprintf('  GlobalMobileNetworkSim — Airdrop Mission\n');
fprintf('=============================================================\n\n');

% -------------------------------------------------------------------------
% 1. Setup
% -------------------------------------------------------------------------
projectRoot  = fileparts(mfilename('fullpath'));
addpath(projectRoot);

scenarioFile = fullfile(projectRoot, 'scenarios', 'airdrop_mission', ...
    'airdrop_mission.json');
outputDir    = fullfile(projectRoot, 'output', 'airdrop_mission');

if ~exist(outputDir, 'dir')
    mkdir(outputDir);
    fprintf('[setup] Created output directory: %s\n', outputDir);
end

% -------------------------------------------------------------------------
% 2. Load scenario
% -------------------------------------------------------------------------
fprintf('[1/6] Loading scenario: %s\n', scenarioFile);
try
    scenario = io.ScenarioLoader.load(scenarioFile);
catch ME
    fprintf('[ERROR] Failed to load scenario: %s\n', ME.message);
    return;
end
fprintf('      Scenario: %s  (%.0f s, %d nodes, %d links, %d messages)\n', ...
    scenario.scenarioName, ...
    scenario.simulationDurationSec, ...
    numel(scenario.nodes), ...
    numel(scenario.links), ...
    numel(scenario.c2Messages));

% -------------------------------------------------------------------------
% 3. Configure LLM client (optional)
% -------------------------------------------------------------------------
apiKey = getenv('NETSIM_LLM_API_KEY');
useAgents = false;

if ~isempty(apiKey)
    fprintf('[2/6] LLM API key found — agents will be active\n');
    llmConfig.model      = 'gpt-4o';
    llmConfig.timeoutSec = 60;
    llmConfig.maxTokens  = 1024;
    llmClient = agent.LLMClient(llmConfig);
    llmClient.setApiKey(apiKey);
    useAgents = true;
else
    fprintf('[2/6] No NETSIM_LLM_API_KEY set — running network simulation only\n');
    fprintf('      (Set NETSIM_LLM_API_KEY to enable LLM agent evaluation)\n');
    llmClient = [];
end

% -------------------------------------------------------------------------
% 4. Construct and run SimController
% -------------------------------------------------------------------------
fprintf('[3/6] Constructing SimController...\n');
try
    if useAgents
        sc = sim.SimController(scenario, llmClient);
    else
        sc = sim.SimController(scenario);
    end
catch ME
    fprintf('[ERROR] Failed to construct SimController: %s\n', ME.message);
    return;
end

fprintf('      Network subsystems: %d nodes, %d links\n', ...
    sc.nodeRegistry.count(), sc.linkRegistry.count());
if useAgents && ~isempty(sc.agentRegistry)
    fprintf('      Agent registry: %d agents\n', sc.agentRegistry.count());
end

fprintf('[4/6] Running simulation (%.0f seconds simulated time)...\n', ...
    scenario.simulationDurationSec);
wallStart = tic;
try
    sc.run();
catch ME
    fprintf('[ERROR] Simulation failed: %s\n', ME.message);
    return;
end
wallElapsed = toc(wallStart);

fprintf('      Simulation complete in %.2f s wall-clock time\n', wallElapsed);
fprintf('      Run ID: %s\n', sc.runId);

% -------------------------------------------------------------------------
% 5. Print summary to console
% -------------------------------------------------------------------------
fprintf('\n--- Simulation Summary ---\n');
report = sc.buildStatsReport();

fprintf('  C2 Messages scheduled : %d\n', report.c2Messages.scheduled);
fprintf('  C2 Messages delivered : %d\n', report.c2Messages.delivered);
fprintf('  C2 Messages failed    : %d\n', report.c2Messages.failed);

if ~isnan(report.latency.meanMs)
    fprintf('  Latency mean          : %.1f ms\n', report.latency.meanMs);
    fprintf('  Latency median        : %.1f ms\n', report.latency.medianMs);
    fprintf('  Latency p95           : %.1f ms\n', report.latency.p95Ms);
else
    fprintf('  Latency               : no messages delivered\n');
end

fprintf('\n  Per-link outage summary:\n');
for k = 1:numel(report.perLink)
    lk = report.perLink(k);
    fprintf('    %-25s  outage fraction: %.3f  msgs routed: %d\n', ...
        lk.linkId, lk.outageFraction, lk.totalC2MessagesRouted);
end

if useAgents && ~isnan(report.agentFidelity.mean)
    fprintf('\n  Agent fidelity:\n');
    fprintf('    Mean : %.3f\n', report.agentFidelity.mean);
    fprintf('    Min  : %.3f\n', report.agentFidelity.min);
    fprintf('    Max  : %.3f\n', report.agentFidelity.max);
end

% -------------------------------------------------------------------------
% 6. Write output files
% -------------------------------------------------------------------------
fprintf('\n[5/6] Writing output files to: %s\n', outputDir);
rw = io.ReportWriter(outputDir, 'AirdropMission');

% Event log CSV
try
    rw.writeEventLog(sc.eventLog);
    fprintf('      AirdropMission_event_log.csv  (%d events)\n', numel(sc.eventLog));
catch ME
    fprintf('      [WARN] Event log write failed: %s\n', ME.message);
end

% Statistics report JSON
try
    rw.writeStatisticsReport(report);
    fprintf('      AirdropMission_stats.json\n');
catch ME
    fprintf('      [WARN] Stats report write failed: %s\n', ME.message);
end

% Evaluation report and behavior traces (agents only)
if useAgents
    try
        evalReport = sc.buildEvalReport();
        rw.writeEvaluationReport(evalReport);
        fprintf('      AirdropMission_eval.json\n');
    catch ME
        fprintf('      [WARN] Eval report write failed: %s\n', ME.message);
    end

    if ~isempty(sc.agentRegistry)
        try
            rw.writeBehaviorTraces(sc.agentRegistry.getAllTracers());
            fprintf('      AirdropMission_trace_*.csv  (one per agent)\n');
        catch ME
            fprintf('      [WARN] Behavior trace write failed: %s\n', ME.message);
        end
    end
end

% -------------------------------------------------------------------------
% 7. Generate and save plots
% -------------------------------------------------------------------------
fprintf('[6/6] Generating plots...\n');

% Latency histogram
try
    fig1 = io.PlotFunctions.latencyHistogram(report, sc.deliveredLatenciesMs);
    set(fig1, 'Visible', 'off');
    saveas(fig1, fullfile(outputDir, 'AirdropMission_latency_histogram.png'));
    close(fig1);
    fprintf('      AirdropMission_latency_histogram.png\n');
catch ME
    fprintf('      [WARN] Latency histogram failed: %s\n', ME.message);
end

% Outage Gantt chart
try
    fig2 = io.PlotFunctions.outageGantt(report);
    set(fig2, 'Visible', 'off');
    saveas(fig2, fullfile(outputDir, 'AirdropMission_outage_gantt.png'));
    close(fig2);
    fprintf('      AirdropMission_outage_gantt.png\n');
catch ME
    fprintf('      [WARN] Outage Gantt failed: %s\n', ME.message);
end

% Fidelity box plot (agents only)
if useAgents && ~isempty(sc.evalResults) && numel(sc.evalResults) > 0
    try
        evalReport = sc.buildEvalReport();
        fig3 = io.PlotFunctions.fidelityBoxPlot(evalReport);
        set(fig3, 'Visible', 'off');
        saveas(fig3, fullfile(outputDir, 'AirdropMission_fidelity_boxplot.png'));
        close(fig3);
        fprintf('      AirdropMission_fidelity_boxplot.png\n');
    catch ME
        fprintf('      [WARN] Fidelity box plot failed: %s\n', ME.message);
    end
end

% -------------------------------------------------------------------------
% Done
% -------------------------------------------------------------------------
fprintf('\n=============================================================\n');
fprintf('  Run complete. Output: %s\n', outputDir);
fprintf('=============================================================\n');
