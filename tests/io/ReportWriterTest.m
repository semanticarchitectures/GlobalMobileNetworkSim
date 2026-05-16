classdef ReportWriterTest < matlab.unittest.TestCase
    % ReportWriterTest  Unit tests for io.ReportWriter.
    %
    % Tests:
    %   1. testWriteEventLogCreatesFileWithHeader
    %        — writeEventLog with empty log creates CSV with correct header
    %   2. testWriteEventLogWithOneEvent
    %        — writeEventLog with one event creates header + one data row
    %   3. testWriteStatisticsReportCreatesValidJson
    %        — writeStatisticsReport creates a JSON file readable by jsondecode
    %   4. testWriteEvaluationReportCreatesValidJson
    %        — writeEvaluationReport creates a JSON file readable by jsondecode
    %   5. testConstructorCreatesOutputDir
    %        — constructor creates outputDir when it does not exist
    %
    % Requirements: 8.5, 9.1, 9.2, 9.3, 16.1, 16.2, 16.3

    properties
        TempDirs  % cell array of temp directories to clean up
    end

    % ======================================================================
    % TestClassSetup: ensure workspace root is on the MATLAB path
    % ======================================================================
    methods (TestClassSetup)
        function addWorkspaceRootToPath(testCase)
            % Determine the workspace root (two levels up from this file's
            % directory: tests/io/ -> tests/ -> workspace root).
            thisDir = fileparts(mfilename('fullpath'));
            rootDir = fileparts(fileparts(thisDir));
            addpath(rootDir);
            testCase.addTeardown(@() rmpath(rootDir));
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
            % Create a unique temporary directory and register for cleanup.
            outDir = [tempname(), '_rwtest'];
            mkdir(outDir);
            testCase.TempDirs{end+1} = outDir;
        end

        function lines = readLines(~, filePath)
            % Read all lines from a text file into a cell array of strings.
            fid = fopen(filePath, 'r');
            lines = {};
            while ~feof(fid)
                line = fgetl(fid);
                if ischar(line)
                    lines{end+1} = line; %#ok<AGROW>
                end
            end
            fclose(fid);
        end

    end

    % ======================================================================
    % Tests
    % ======================================================================
    methods (Test)

        % ------------------------------------------------------------------
        % Test 1: writeEventLog with empty log creates CSV with correct header
        % ------------------------------------------------------------------
        function testWriteEventLogCreatesFileWithHeader(testCase)
            % writeEventLog() with an empty struct array should create a CSV
            % file whose first (and only) line is the canonical header.
            %
            % Requirements: 8.5, 9.1

            outDir = testCase.makeTempDir();
            rw = io.ReportWriter(outDir, 'test_scenario');

            % Pass an empty struct array (no rows).
            rw.writeEventLog([]);

            expectedFile = fullfile(outDir, 'test_scenario_event_log.csv');
            testCase.verifyTrue(exist(expectedFile, 'file') == 2, ...
                'writeEventLog should create the CSV file');

            lines = testCase.readLines(expectedFile);
            testCase.verifyGreaterThanOrEqual(numel(lines), 1, ...
                'CSV file should have at least one line (the header)');

            expectedHeader = 'eventId,simTimeSec,eventType,linkId,msgId,srcNodeId,dstNodeId,latencyMs,reason';
            testCase.verifyEqual(lines{1}, expectedHeader, ...
                'First line should be the canonical CSV header');
        end

        % ------------------------------------------------------------------
        % Test 2: writeEventLog with one event creates header + one data row
        % ------------------------------------------------------------------
        function testWriteEventLogWithOneEvent(testCase)
            % writeEventLog() with a single-entry struct array should produce
            % a CSV with exactly two lines: header + one data row.
            %
            % Requirements: 8.5, 9.1

            outDir = testCase.makeTempDir();
            rw = io.ReportWriter(outDir, 'myscenario');

            % Build a minimal event log entry.
            entry.eventId    = uint64(1);
            entry.simTimeSec = 10.5;
            entry.eventType  = 'C2_MESSAGE_TX';
            entry.linkId     = 'link_A';
            entry.msgId      = 'msg_001';
            entry.srcNodeId  = 'node_1';
            entry.dstNodeId  = 'node_2';
            entry.latencyMs  = 312.4;
            entry.reason     = '';

            rw.writeEventLog(entry);

            expectedFile = fullfile(outDir, 'myscenario_event_log.csv');
            testCase.verifyTrue(exist(expectedFile, 'file') == 2, ...
                'writeEventLog should create the CSV file');

            lines = testCase.readLines(expectedFile);
            testCase.verifyEqual(numel(lines), 2, ...
                'CSV should have exactly 2 lines: header + 1 data row');

            % Verify the data row contains the expected values.
            dataRow = lines{2};
            testCase.verifyTrue(contains(dataRow, 'C2_MESSAGE_TX'), ...
                'Data row should contain the event type');
            testCase.verifyTrue(contains(dataRow, 'link_A'), ...
                'Data row should contain the link ID');
            testCase.verifyTrue(contains(dataRow, 'msg_001'), ...
                'Data row should contain the message ID');
            testCase.verifyTrue(contains(dataRow, 'node_1'), ...
                'Data row should contain the source node ID');
            testCase.verifyTrue(contains(dataRow, 'node_2'), ...
                'Data row should contain the destination node ID');
        end

        % ------------------------------------------------------------------
        % Test 3: writeStatisticsReport creates a JSON file readable by jsondecode
        % ------------------------------------------------------------------
        function testWriteStatisticsReportCreatesValidJson(testCase)
            % writeStatisticsReport() should produce a valid JSON file that
            % can be decoded back to a struct with the expected top-level fields.
            %
            % Requirements: 9.1, 9.2, 9.3

            outDir = testCase.makeTempDir();
            rw = io.ReportWriter(outDir, 'stats_test');

            % Build a minimal statistics report matching §4.3.
            statsReport.scenarioName          = 'stats_test';
            statsReport.simStartTimeSec       = 0;
            statsReport.simEndTimeSec         = 3600;
            statsReport.wallClockDurationSec  = 12.4;
            statsReport.c2Messages.scheduled  = 100;
            statsReport.c2Messages.delivered  = 95;
            statsReport.c2Messages.failed     = 5;
            statsReport.latency.meanMs        = 312.4;
            statsReport.latency.medianMs      = 290.1;
            statsReport.latency.p95Ms         = 620.0;
            statsReport.perLink               = struct( ...
                'linkId', {}, ...
                'meanEffectiveBwBps', {}, ...
                'meanBgLoadFraction', {}, ...
                'totalC2MessagesRouted', {}, ...
                'totalOutageDurationSec', {}, ...
                'outageFraction', {});
            statsReport.agentFidelity.mean    = 0.87;
            statsReport.agentFidelity.min     = 0.72;
            statsReport.agentFidelity.max     = 0.95;

            rw.writeStatisticsReport(statsReport);

            expectedFile = fullfile(outDir, 'stats_test_stats.json');
            testCase.verifyTrue(exist(expectedFile, 'file') == 2, ...
                'writeStatisticsReport should create the JSON file');

            % Read back and decode.
            rawText = fileread(expectedFile);
            decoded = jsondecode(rawText);

            testCase.verifyTrue(isstruct(decoded), ...
                'Decoded JSON should be a struct');
            testCase.verifyEqual(string(decoded.scenarioName), "stats_test", ...
                'Decoded scenarioName should match');
            testCase.verifyEqual(decoded.simEndTimeSec, 3600, ...
                'Decoded simEndTimeSec should match');
            testCase.verifyTrue(isfield(decoded, 'c2Messages'), ...
                'Decoded struct should have c2Messages field');
            testCase.verifyTrue(isfield(decoded, 'latency'), ...
                'Decoded struct should have latency field');
            testCase.verifyTrue(isfield(decoded, 'agentFidelity'), ...
                'Decoded struct should have agentFidelity field');
        end

        % ------------------------------------------------------------------
        % Test 4: writeEvaluationReport creates a JSON file readable by jsondecode
        % ------------------------------------------------------------------
        function testWriteEvaluationReportCreatesValidJson(testCase)
            % writeEvaluationReport() should produce a valid JSON file that
            % can be decoded back to a struct with the expected top-level fields.
            %
            % Requirements: 16.1, 16.3

            outDir = testCase.makeTempDir();
            rw = io.ReportWriter(outDir, 'eval_test');

            % Build a minimal evaluation report matching §4.4.
            evalReport.runId       = 'test-run-uuid-1234';
            evalReport.timestamp   = '2024-01-15T10:30:00Z';
            evalReport.scenarioName = 'eval_test';

            agent1.agentId       = 'agent_A';
            agent1.role          = 'Aircrew';
            agent1.fidelityScore = 0.87;
            agent1.missingActions = struct( ...
                'actionType', {}, 'expectedTimeSec', {}, 'reason', {});
            agent1.extraActions  = struct( ...
                'actionType', {}, 'observedTimeSec', {});
            agent1.deviations    = struct( ...
                'actionType', {}, 'expectedTimeSec', {}, ...
                'observedTimeSec', {}, 'deviationSec', {});

            evalReport.agents = agent1;

            rw.writeEvaluationReport(evalReport);

            expectedFile = fullfile(outDir, 'eval_test_eval.json');
            testCase.verifyTrue(exist(expectedFile, 'file') == 2, ...
                'writeEvaluationReport should create the JSON file');

            % Read back and decode.
            rawText = fileread(expectedFile);
            decoded = jsondecode(rawText);

            testCase.verifyTrue(isstruct(decoded), ...
                'Decoded JSON should be a struct');
            testCase.verifyEqual(string(decoded.runId), "test-run-uuid-1234", ...
                'Decoded runId should match');
            testCase.verifyEqual(string(decoded.scenarioName), "eval_test", ...
                'Decoded scenarioName should match');
            testCase.verifyTrue(isfield(decoded, 'agents'), ...
                'Decoded struct should have agents field');
        end

        % ------------------------------------------------------------------
        % Test 5: constructor creates outputDir if it does not exist
        % ------------------------------------------------------------------
        function testConstructorCreatesOutputDir(testCase)
            % The constructor should create the output directory when it does
            % not already exist.
            %
            % Requirements: 8.5

            % Use a path that does not yet exist.
            baseDir = tempname();
            newDir  = fullfile(baseDir, 'subdir', 'output');
            testCase.TempDirs{end+1} = baseDir;

            testCase.verifyFalse(exist(newDir, 'dir') == 7, ...
                'Output directory should not exist before construction');

            rw = io.ReportWriter(newDir, 'ctor_test'); %#ok<NASGU>

            testCase.verifyTrue(exist(newDir, 'dir') == 7, ...
                'Constructor should create the output directory');
        end

        % ------------------------------------------------------------------
        % Test 6 (Task 32.2): writeStatisticsReport passes through icam field
        % ------------------------------------------------------------------
        function testWriteStatisticsReportPassesThroughICAMField(testCase)
            % Verify that writeStatisticsReport includes the icam block when
            % statsReport.icam is present. The existing jsonencode call handles
            % this automatically — this test confirms the field is preserved.
            %
            % Requirements: 20.6, 21.5

            outDir = tempname();
            testCase.TempDirs{end+1} = outDir;

            rw = io.ReportWriter(outDir, 'icam_test');

            % Build a stats report with an icam block
            statsReport.scenarioName         = 'icam-test';
            statsReport.simStartTimeSec      = 0;
            statsReport.simEndTimeSec        = 100;
            statsReport.wallClockDurationSec = 1.5;
            statsReport.c2Messages.scheduled = 5;
            statsReport.c2Messages.delivered = 4;
            statsReport.c2Messages.failed    = 1;
            statsReport.latency.meanMs       = 50.0;
            statsReport.latency.medianMs     = 48.0;
            statsReport.latency.p95Ms        = 90.0;
            statsReport.perLink              = struct('linkId', {}, 'meanEffectiveBwBps', {}, ...
                                                      'meanBgLoadFraction', {}, ...
                                                      'totalC2MessagesRouted', {}, ...
                                                      'totalOutageDurationSec', {}, ...
                                                      'outageFraction', {});
            statsReport.agentFidelity.mean   = NaN;
            statsReport.agentFidelity.min    = NaN;
            statsReport.agentFidelity.max    = NaN;

            % Add ICAM block
            statsReport.icam.authExchanges.total      = uint64(3);
            statsReport.icam.authExchanges.successful = uint64(2);
            statsReport.icam.authExchanges.failed     = uint64(0);
            statsReport.icam.authExchanges.timedOut   = uint64(1);
            statsReport.icam.cacheHitRate             = 0.75;
            statsReport.icam.accessDeniedCount.total  = 1;
            statsReport.icam.certRenewals.total       = uint64(0);
            statsReport.icam.certRenewals.successful  = uint64(0);
            statsReport.icam.certRenewals.failed      = uint64(0);
            statsReport.icam.entityCounts.human       = 2;
            statsReport.icam.entityCounts.npe         = 1;

            % Write the report
            rw.writeStatisticsReport(statsReport);

            % Read it back and verify icam field is present
            statsFile = fullfile(outDir, 'icam_test_stats.json');
            testCase.verifyTrue(exist(statsFile, 'file') == 2, ...
                'Statistics report file should exist after writeStatisticsReport.');

            rawText = fileread(statsFile);
            loaded  = jsondecode(rawText);

            testCase.verifyTrue(isfield(loaded, 'icam'), ...
                'Loaded stats report should contain icam field.');
            testCase.verifyTrue(isfield(loaded.icam, 'authExchanges'), ...
                'icam block should contain authExchanges field.');
            testCase.verifyTrue(isfield(loaded.icam, 'cacheHitRate'), ...
                'icam block should contain cacheHitRate field.');
            testCase.verifyTrue(isfield(loaded.icam, 'accessDeniedCount'), ...
                'icam block should contain accessDeniedCount field.');
            testCase.verifyTrue(isfield(loaded.icam, 'certRenewals'), ...
                'icam block should contain certRenewals field.');
            testCase.verifyTrue(isfield(loaded.icam, 'entityCounts'), ...
                'icam block should contain entityCounts field.');

            % Verify cacheHitRate value is preserved
            testCase.verifyEqual(loaded.icam.cacheHitRate, 0.75, 'AbsTol', 1e-10, ...
                'cacheHitRate should be preserved through JSON round-trip.');
        end

    end % methods (Test)

end % classdef
