classdef RunBatchTest < matlab.unittest.TestCase
    % RunBatchTest  Unit tests for the runBatch top-level function.
    %
    % Tests:
    %   1. testRunBatchWithSingleScenario
    %        — runBatch with one scenario file produces a combined report
    %          with one run entry
    %   2. testRunBatchCreatesOutputDir
    %        — runBatch creates the output directory if it does not exist
    %   3. testRunBatchWritesCombinedReportJson
    %        — runBatch writes combined_eval_report.json to outputDir
    %   4. testRunBatchRunIdsAreUnique
    %        — runBatch with two scenario files produces distinct runIds
    %   5. testRunBatchWithEmptyScenarioList
    %        — runBatch with empty cell array returns empty runs
    %
    % Requirements: 15.1, 15.3, 16.1, 16.3, 16.5

    properties
        TempDirs  % cell array of temp directories to clean up
        FixtureDir  % path to the fixtures directory
    end

    % ======================================================================
    % TestClassSetup
    % ======================================================================
    methods (TestClassSetup)
        function addWorkspaceRootToPath(testCase)
            % Add workspace root to path so runBatch and packages are found.
            thisDir = fileparts(mfilename('fullpath'));
            rootDir = fileparts(fileparts(thisDir));
            addpath(rootDir);
            testCase.addTeardown(@() rmpath(rootDir));
            testCase.FixtureDir = fullfile(thisDir, 'fixtures');
        end
    end

    % ======================================================================
    % TestMethodSetup / TestMethodTeardown
    % ======================================================================
    methods (TestMethodSetup)
        function setUp(testCase)
            testCase.TempDirs = {};
        end
    end

    methods (TestMethodTeardown)
        function cleanUpTempDirs(testCase)
            for i = 1:numel(testCase.TempDirs)
                d = testCase.TempDirs{i};
                if exist(d, 'dir')
                    rmdir(d, 's');
                end
            end
        end
    end

    % ======================================================================
    % Private helpers
    % ======================================================================
    methods (Access = private)

        function outDir = makeTempDir(testCase)
            outDir = [tempname(), '_batchtest'];
            mkdir(outDir);
            testCase.TempDirs{end+1} = outDir;
        end

        function scenarioFile = makeMinimalScenarioFile(testCase, name, durationSec)
            % Write a minimal scenario JSON to a temp file and return its path.
            outDir = testCase.makeTempDir();
            scenarioFile = fullfile(outDir, [name, '.json']);

            s.scenarioName = name;
            s.simulationDurationSec = durationSec;
            s.nodes = struct( ...
                'id', {'nodeA', 'nodeB'}, ...
                'type', {'Stationary', 'Stationary'}, ...
                'lat', {40.0, 51.5}, ...
                'lon', {-74.0, -0.1}, ...
                'altM', {0.0, 0.0}, ...
                'trajectory', {[], []}, ...
                'keplerElements', {[], []});
            lk.id = 'link1';
            lk.type = 'LEO_Satellite';
            lk.srcNodeId = 'nodeA';
            lk.dstNodeId = 'nodeB';
            lk.nominalLatencyMs = 30.0;
            lk.bandwidthBps = 1e9;
            lk.outageRate = 0;
            lk.outageDuration = struct('distribution', 'fixed', 'value', 10);
            lk.backgroundTraffic = struct('distribution', 'uniform', 'min', 0.0, 'max', 0.1);
            lk.coverageRadiusM = [];
            lk.congestionPenaltyMs = 0;
            s.links = lk;

            try
                jsonText = jsonencode(s, 'PrettyPrint', true);
            catch
                jsonText = jsonencode(s);
            end
            fid = fopen(scenarioFile, 'w');
            fwrite(fid, jsonText, 'char');
            fclose(fid);
        end

    end

    % ======================================================================
    % Tests
    % ======================================================================
    methods (Test)

        % ------------------------------------------------------------------
        % Test 1: runBatch with one scenario produces one run entry
        % ------------------------------------------------------------------
        function testRunBatchWithSingleScenario(testCase)
            scenarioFile = testCase.makeMinimalScenarioFile('batch_s1', 5);
            outDir = testCase.makeTempDir();

            combinedReport = runBatch({scenarioFile}, outDir);

            testCase.verifyTrue(isstruct(combinedReport), ...
                'combinedReport should be a struct.');
            testCase.verifyTrue(isfield(combinedReport, 'runs'), ...
                'combinedReport should have a runs field.');
            testCase.verifyEqual(numel(combinedReport.runs), 1, ...
                'combinedReport.runs should have one entry for one scenario.');
        end

        % ------------------------------------------------------------------
        % Test 2: runBatch creates output directory if it does not exist
        % ------------------------------------------------------------------
        function testRunBatchCreatesOutputDir(testCase)
            scenarioFile = testCase.makeMinimalScenarioFile('batch_s2', 5);
            baseDir = tempname();
            newDir  = fullfile(baseDir, 'batch_output');
            testCase.TempDirs{end+1} = baseDir;

            testCase.verifyFalse(exist(newDir, 'dir') == 7, ...
                'Output directory should not exist before runBatch.');

            runBatch({scenarioFile}, newDir);

            testCase.verifyTrue(exist(newDir, 'dir') == 7, ...
                'runBatch should create the output directory.');
        end

        % ------------------------------------------------------------------
        % Test 3: runBatch writes combined_eval_report.json
        % ------------------------------------------------------------------
        function testRunBatchWritesCombinedReportJson(testCase)
            scenarioFile = testCase.makeMinimalScenarioFile('batch_s3', 5);
            outDir = testCase.makeTempDir();

            runBatch({scenarioFile}, outDir);

            expectedFile = fullfile(outDir, 'combined_eval_report.json');
            testCase.verifyTrue(exist(expectedFile, 'file') == 2, ...
                'runBatch should write combined_eval_report.json.');

            % Verify it is valid JSON.
            rawText = fileread(expectedFile);
            decoded = jsondecode(rawText);
            testCase.verifyTrue(isstruct(decoded), ...
                'combined_eval_report.json should decode to a struct.');
            testCase.verifyTrue(isfield(decoded, 'runs'), ...
                'Decoded combined report should have a runs field.');
        end

        % ------------------------------------------------------------------
        % Test 4: runBatch with two scenarios produces distinct runIds
        % ------------------------------------------------------------------
        function testRunBatchRunIdsAreUnique(testCase)
            f1 = testCase.makeMinimalScenarioFile('batch_s4a', 5);
            f2 = testCase.makeMinimalScenarioFile('batch_s4b', 5);
            outDir = testCase.makeTempDir();

            combinedReport = runBatch({f1, f2}, outDir);

            testCase.verifyEqual(numel(combinedReport.runs), 2, ...
                'combinedReport.runs should have two entries for two scenarios.');

            id1 = combinedReport.runs(1).runId;
            id2 = combinedReport.runs(2).runId;
            testCase.verifyNotEqual(id1, id2, ...
                'Each run should have a distinct runId.');

            ts1 = combinedReport.runs(1).timestamp;
            ts2 = combinedReport.runs(2).timestamp;
            testCase.verifyFalse(isempty(ts1), ...
                'First run timestamp should be non-empty.');
            testCase.verifyFalse(isempty(ts2), ...
                'Second run timestamp should be non-empty.');
        end

        % ------------------------------------------------------------------
        % Test 5: runBatch with empty scenario list returns empty runs
        % ------------------------------------------------------------------
        function testRunBatchWithEmptyScenarioList(testCase)
            outDir = testCase.makeTempDir();

            combinedReport = runBatch({}, outDir);

            testCase.verifyTrue(isstruct(combinedReport), ...
                'combinedReport should be a struct even with empty input.');
            testCase.verifyTrue(isfield(combinedReport, 'runs'), ...
                'combinedReport should have a runs field.');
            testCase.verifyEqual(numel(combinedReport.runs), 0, ...
                'combinedReport.runs should be empty for empty input.');
        end

        % ------------------------------------------------------------------
        % Test 6: runBatch run entry has required fields
        % ------------------------------------------------------------------
        function testRunBatchRunEntryHasRequiredFields(testCase)
            scenarioFile = testCase.makeMinimalScenarioFile('batch_s6', 5);
            outDir = testCase.makeTempDir();

            combinedReport = runBatch({scenarioFile}, outDir);

            testCase.verifyEqual(numel(combinedReport.runs), 1, ...
                'Should have one run entry.');

            run1 = combinedReport.runs(1);
            testCase.verifyTrue(isfield(run1, 'runId'), ...
                'Run entry should have runId field.');
            testCase.verifyTrue(isfield(run1, 'timestamp'), ...
                'Run entry should have timestamp field.');
            testCase.verifyTrue(isfield(run1, 'scenarioName'), ...
                'Run entry should have scenarioName field.');
            testCase.verifyTrue(isfield(run1, 'agents'), ...
                'Run entry should have agents field.');
            testCase.verifyFalse(isempty(run1.runId), ...
                'runId should be non-empty.');
            testCase.verifyFalse(isempty(run1.timestamp), ...
                'timestamp should be non-empty.');
        end

    end % methods (Test)

end % classdef
