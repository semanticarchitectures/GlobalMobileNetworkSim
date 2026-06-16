%% run_airdrop_video.m
% Scenario runner script that executes the Airdrop Mission scenario
% with position tracking enabled and generates a mission video.
%
% Usage (from the project root):
%   matlab -nodisplay -nosplash -r "run_airdrop_video; exit"
%
% Or interactively:
%   cd /path/to/GlobalMobileNetworkSim
%   run_airdrop_video
%
% Outputs are written to:
%   output/airdrop_mission/
%     AirdropMission_event_log.csv
%     AirdropMission_mission_video.mp4
%
% Requirements: 6.2, 6.3, 6.4, 6.5

fprintf('=============================================================\n');
fprintf('  GlobalMobileNetworkSim — Airdrop Mission (Video)\n');
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
fprintf('[1/4] Loading scenario: %s\n', scenarioFile);
try
    scenario = io.ScenarioLoader.load(scenarioFile);
catch ME
    fprintf('[ERROR] Failed to load scenario: %s\n', ME.message);
    return;
end
fprintf('       Scenario: %s  (%.0f s, %d nodes, %d links)\n', ...
    scenario.scenarioName, ...
    scenario.simulationDurationSec, ...
    numel(scenario.nodes), ...
    numel(scenario.links));

% -------------------------------------------------------------------------
% 3. Run simulation with position tracking
% -------------------------------------------------------------------------
fprintf('[2/4] Constructing SimController (positionUpdateIntervalSec = 10)...\n');
try
    sc = sim.SimController(scenario);
    sc.positionUpdateIntervalSec = 10;
catch ME
    fprintf('[ERROR] Failed to construct SimController: %s\n', ME.message);
    return;
end

fprintf('       Running simulation (%.0f seconds simulated time)...\n', ...
    scenario.simulationDurationSec);
wallStart = tic;
try
    sc.run();
catch ME
    fprintf('[ERROR] Simulation failed: %s\n', ME.message);
    return;
end
wallElapsed = toc(wallStart);
fprintf('       Simulation complete in %.2f s wall-clock time\n', wallElapsed);

% -------------------------------------------------------------------------
% 4. Write event log CSV
% -------------------------------------------------------------------------
fprintf('[3/4] Writing event log...\n');
rw = io.ReportWriter(outputDir, 'AirdropMission');
try
    rw.writeEventLog(sc.eventLog);
catch ME
    fprintf('[ERROR] Failed to write event log: %s\n', ME.message);
    return;
end

eventLogCsvPath = fullfile(outputDir, 'AirdropMission_event_log.csv');
fprintf('       Event log: %s  (%d events)\n', eventLogCsvPath, numel(sc.eventLog));

% -------------------------------------------------------------------------
% 5. Generate mission video
% -------------------------------------------------------------------------
fprintf('[4/4] Generating mission video...\n');
try
    vg = io.MissionVideoGenerator(outputDir, 'AirdropMission');
    vg.generate(eventLogCsvPath, scenario);
catch ME
    fprintf('[ERROR] Video generation failed: %s\n', ME.message);
    fprintf('       Event log CSV is available at: %s\n', ...
        fullfile(pwd, eventLogCsvPath));
    return;
end

% -------------------------------------------------------------------------
% Done — print output path
% -------------------------------------------------------------------------
mp4Path = fullfile(pwd, outputDir, 'AirdropMission_mission_video.mp4');
fprintf('\n=============================================================\n');
fprintf('  Video generated successfully!\n');
fprintf('  Output: %s\n', mp4Path);
fprintf('=============================================================\n');
