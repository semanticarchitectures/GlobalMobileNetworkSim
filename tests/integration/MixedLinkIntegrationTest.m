classdef MixedLinkIntegrationTest < matlab.unittest.TestCase
    % MixedLinkIntegrationTest  Integration tests for a 5-node mixed-link scenario.
    %
    % Exercises the full simulation pipeline end-to-end using a fixture
    % scenario with GEO satellite, LEO satellite, fiber, LOS, and additional
    % satellite links.
    %
    % Tests:
    %   1. testScenarioLoadsWithoutError
    %   2. testSimulationRunsToCompletion
    %   3. testEventLogCSVIsWrittenAndParseable
    %   4. testStatisticsReportHasRequiredFields
    %   5. testStatisticsReportHasCorrectLinkCount
    %   6. testDeliveredMessagesHavePositiveLatency
    %   7. testGEOLinkLatencyIsAtLeast270ms
    %   8. testFiberLinkLatencyComputedFromDistance
    %
    % Requirements: 2.2, 2.3, 2.4, 2.5, 2.6, 4.1, 5.4, 8.5, 9.1, 9.2, 9.3

    % -----------------------------------------------------------------
    % Properties
    % -----------------------------------------------------------------
    properties
        TempOutputDir   % temporary directory for output files (per test)
        FixturePath     % absolute path to the mixed_link_scenario.json fixture
    end

    % -----------------------------------------------------------------
    % TestClassSetup: add workspace root to MATLAB path
    % -----------------------------------------------------------------
    methods (TestClassSetup)
        function addWorkspaceRootToPath(testCase)
            % Determine workspace root: tests/integration/ -> tests/ -> root
            thisDir = fileparts(mfilename('fullpath'));
            rootDir = fileparts(fileparts(thisDir));
            addpath(rootDir);
            testCase.addTeardown(@() rmpath(rootDir));

            % Store fixture path for use in all tests.
            testCase.FixturePath = fullfile(thisDir, 'fixtures', ...
                'mixed_link_scenario.json');
        end
    end

    % -----------------------------------------------------------------
    % TestMethodSetup / TestMethodTeardown
    % -----------------------------------------------------------------
    methods (TestMethodSetup)
        function createTempOutputDir(testCase)
            testCase.TempOutputDir = [tempname(), '_mixed_link_test'];
            mkdir(testCase.TempOutputDir);
        end
    end

    methods (TestMethodTeardown)
        function cleanUpTempOutputDir(testCase)
            if exist(testCase.TempOutputDir, 'dir')
                rmdir(testCase.TempOutputDir, 's');
            end
        end
    end

    % -----------------------------------------------------------------
    % Private helpers
    % -----------------------------------------------------------------
    methods (Access = private)

        function scenario = loadFixture(testCase)
            % loadFixture  Load the mixed-link scenario fixture via ScenarioLoader.
            scenario = io.ScenarioLoader.load(testCase.FixturePath);
        end

        function sc = buildAndRunController(testCase)
            % buildAndRunController  Load fixture, construct SimController, run.
            scenario = testCase.loadFixture();
            sc = sim.SimController(scenario);
            sc.run();
        end

        function lines = readLines(~, filePath)
            % readLines  Read all lines from a text file into a cell array.
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

    % -----------------------------------------------------------------
    % Tests
    % -----------------------------------------------------------------
    methods (Test)

        % ------------------------------------------------------------------
        % Test 1: Scenario loads without error
        % ------------------------------------------------------------------
        function testScenarioLoadsWithoutError(testCase)
            % Verify that io.ScenarioLoader.load() accepts the fixture without
            % throwing any error.
            %
            % Requirements: 2.2, 2.3, 2.4, 2.5, 2.6

            testCase.verifyTrue(exist(testCase.FixturePath, 'file') == 2, ...
                'Fixture file must exist at the expected path.');

            scenario = testCase.verifyWarningFree( ...
                @() io.ScenarioLoader.load(testCase.FixturePath), ...
                'ScenarioLoader.load() should complete without warnings.');

            testCase.verifyTrue(isstruct(scenario), ...
                'Loaded scenario must be a struct.');
            testCase.verifyEqual(string(scenario.scenarioName), "MixedLinkTest", ...
                'scenarioName should match fixture value.');
            testCase.verifyEqual(scenario.simulationDurationSec, 600, ...
                'simulationDurationSec should be 600.');
            testCase.verifyEqual(numel(scenario.nodes), 5, ...
                'Scenario should have 5 nodes.');
            testCase.verifyEqual(numel(scenario.links), 6, ...
                'Scenario should have 6 links.');
            testCase.verifyEqual(numel(scenario.c2Messages), 3, ...
                'Scenario should have 3 C2 messages.');
        end

        % ------------------------------------------------------------------
        % Test 2: Simulation runs to completion
        % ------------------------------------------------------------------
        function testSimulationRunsToCompletion(testCase)
            % Verify that SimController.run() completes the full 600-second
            % simulation and sets isStopped=true with simTimeSec==600.
            %
            % Requirements: 8.1, 8.4

            scenario = testCase.loadFixture();
            sc = sim.SimController(scenario);
            sc.run();

            testCase.verifyTrue(sc.isStopped, ...
                'isStopped should be true after run() completes.');
            testCase.verifyEqual(sc.simTimeSec, 600.0, 'AbsTol', 1e-9, ...
                'simTimeSec should equal simulationDurationSec (600) after run().');
        end

        % ------------------------------------------------------------------
        % Test 3: Event log CSV is written and parseable
        % ------------------------------------------------------------------
        function testEventLogCSVIsWrittenAndParseable(testCase)
            % After running the simulation, write the event log via
            % ReportWriter and verify the CSV file exists with the canonical
            % header as its first line.
            %
            % Requirements: 8.5, 9.1

            sc = testCase.buildAndRunController();

            rw = io.ReportWriter(testCase.TempOutputDir, 'MixedLinkTest');
            rw.writeEventLog(sc.eventLog);

            expectedFile = fullfile(testCase.TempOutputDir, ...
                'MixedLinkTest_event_log.csv');
            testCase.verifyTrue(exist(expectedFile, 'file') == 2, ...
                'Event log CSV file should exist after writeEventLog().');

            lines = testCase.readLines(expectedFile);
            testCase.verifyGreaterThanOrEqual(numel(lines), 1, ...
                'CSV file should have at least one line (the header).');

            expectedHeader = 'eventId,simTimeSec,eventType,linkId,msgId,srcNodeId,dstNodeId,latencyMs,reason';
            testCase.verifyEqual(lines{1}, expectedHeader, ...
                'First line of event log CSV should be the canonical header.');
        end

        % ------------------------------------------------------------------
        % Test 4: Statistics report has all required fields
        % ------------------------------------------------------------------
        function testStatisticsReportHasRequiredFields(testCase)
            % buildStatsReport() should return a struct containing all
            % required top-level fields and sub-fields.
            %
            % Requirements: 9.1, 9.2, 9.3

            sc = testCase.buildAndRunController();
            report = sc.buildStatsReport();

            testCase.verifyTrue(isstruct(report), ...
                'buildStatsReport() should return a struct.');

            % Top-level required fields
            requiredFields = {'scenarioName', 'simStartTimeSec', ...
                'simEndTimeSec', 'wallClockDurationSec', 'c2Messages', ...
                'latency', 'perLink', 'agentFidelity'};
            for k = 1:numel(requiredFields)
                testCase.verifyTrue(isfield(report, requiredFields{k}), ...
                    sprintf('report should have field "%s".', requiredFields{k}));
            end

            % c2Messages sub-fields
            testCase.verifyTrue(isfield(report.c2Messages, 'scheduled'), ...
                'c2Messages should have "scheduled" field.');
            testCase.verifyTrue(isfield(report.c2Messages, 'delivered'), ...
                'c2Messages should have "delivered" field.');
            testCase.verifyTrue(isfield(report.c2Messages, 'failed'), ...
                'c2Messages should have "failed" field.');

            % latency sub-fields
            testCase.verifyTrue(isfield(report.latency, 'meanMs'), ...
                'latency should have "meanMs" field.');
            testCase.verifyTrue(isfield(report.latency, 'medianMs'), ...
                'latency should have "medianMs" field.');
            testCase.verifyTrue(isfield(report.latency, 'p95Ms'), ...
                'latency should have "p95Ms" field.');

            % agentFidelity sub-fields
            testCase.verifyTrue(isfield(report.agentFidelity, 'mean'), ...
                'agentFidelity should have "mean" field.');
            testCase.verifyTrue(isfield(report.agentFidelity, 'min'), ...
                'agentFidelity should have "min" field.');
            testCase.verifyTrue(isfield(report.agentFidelity, 'max'), ...
                'agentFidelity should have "max" field.');

            % scenarioName should match fixture
            testCase.verifyEqual(string(report.scenarioName), "MixedLinkTest", ...
                'scenarioName in report should match fixture scenarioName.');
        end

        % ------------------------------------------------------------------
        % Test 5: Statistics report has correct link count (6 links)
        % ------------------------------------------------------------------
        function testStatisticsReportHasCorrectLinkCount(testCase)
            % perLink should have exactly 6 entries — one per link in the
            % fixture scenario.
            %
            % Requirements: 9.2

            sc = testCase.buildAndRunController();
            report = sc.buildStatsReport();

            testCase.verifyEqual(numel(report.perLink), 6, ...
                'perLink should have 6 entries (one per link in the scenario).');

            % Each entry should have the required per-link fields.
            requiredLinkFields = {'linkId', 'meanEffectiveBwBps', ...
                'meanBgLoadFraction', 'totalC2MessagesRouted', ...
                'totalOutageDurationSec', 'outageFraction'};
            for k = 1:numel(requiredLinkFields)
                testCase.verifyTrue(isfield(report.perLink, requiredLinkFields{k}), ...
                    sprintf('perLink entry should have field "%s".', ...
                    requiredLinkFields{k}));
            end
        end

        % ------------------------------------------------------------------
        % Test 6: Delivered messages have positive latency
        % ------------------------------------------------------------------
        function testDeliveredMessagesHavePositiveLatency(testCase)
            % All entries in deliveredLatenciesMs should be strictly positive.
            % (At least one message should be delivered given the 600-second
            % simulation with 3 scheduled messages and multiple active paths.)
            %
            % Requirements: 5.4, 9.3

            sc = testCase.buildAndRunController();

            % At least one message should have been delivered.
            testCase.verifyGreaterThanOrEqual(sc.stats.c2MessagesRx, uint64(1), ...
                'At least one C2 message should be delivered in the 600-second run.');

            lats = sc.deliveredLatenciesMs;
            testCase.verifyNotEmpty(lats, ...
                'deliveredLatenciesMs should be non-empty after at least one delivery.');

            testCase.verifyTrue(all(lats > 0), ...
                'All entries in deliveredLatenciesMs should be strictly positive.');
        end

        % ------------------------------------------------------------------
        % Test 7: GEO link has positive mean effective bandwidth (link was active)
        % ------------------------------------------------------------------
        function testGEOLinkLatencyIsAtLeast270ms(testCase)
            % The GEO_LINK entry in perLink should have meanEffectiveBwBps > 0,
            % confirming the link was active during the simulation.
            % (The GEO latency floor of >= 270 ms is enforced by LinkRegistry.)
            %
            % Requirements: 2.2

            sc = testCase.buildAndRunController();
            report = sc.buildStatsReport();

            % Find the GEO_LINK entry in perLink.
            geoEntry = [];
            for k = 1:numel(report.perLink)
                if string(report.perLink(k).linkId) == "GEO_LINK"
                    geoEntry = report.perLink(k);
                    break;
                end
            end

            testCase.verifyNotEmpty(geoEntry, ...
                'perLink should contain an entry for GEO_LINK.');
            testCase.verifyGreaterThan(geoEntry.meanEffectiveBwBps, 0, ...
                'GEO_LINK meanEffectiveBwBps should be > 0 (link was active).');

            % Also verify the GEO_LINK nominal latency is >= 270 ms via
            % the LinkRegistry directly.
            geoLatency = sc.linkRegistry.getEffectiveLatency('GEO_LINK');
            testCase.verifyGreaterThanOrEqual(geoLatency, 270, ...
                'GEO_LINK effective latency should be >= 270 ms (GEO floor).');
        end

        % ------------------------------------------------------------------
        % Test 8: Fiber link latency is computed from geographic distance
        % ------------------------------------------------------------------
        function testFiberLinkLatencyComputedFromDistance(testCase)
            % FIBER_LINK connects NYC (40.7128, -74.0060) to LON (51.5074, -0.1278).
            % The WGS-84 geodesic distance is approximately 5570 km.
            % At 200,000 km/s propagation speed, the one-way latency is
            % approximately 27.85 ms.
            %
            % Verify that the effective latency stored in the LinkRegistry
            % is consistent with this geographic distance (within 5% tolerance
            % to account for exact Vincenty computation).
            %
            % Requirements: 2.4

            scenario = testCase.loadFixture();
            sc = sim.SimController(scenario);

            % Retrieve the fiber link latency from the registry (before run).
            fiberLatencyMs = sc.linkRegistry.getEffectiveLatency('FIBER_LINK');

            % NYC to LON geodesic distance is ~5570 km.
            % At 200,000 km/s = 200,000,000 m/s:
            %   latency = 5,570,000 m / 200,000,000 m/s * 1000 ms/s ≈ 27.85 ms
            % Allow ±5 ms tolerance for exact Vincenty result.
            testCase.verifyGreaterThan(fiberLatencyMs, 20, ...
                'FIBER_LINK latency should be > 20 ms (NYC-LON distance).');
            testCase.verifyLessThan(fiberLatencyMs, 40, ...
                'FIBER_LINK latency should be < 40 ms (NYC-LON distance).');

            % Cross-check: compute expected latency from GeoUtils directly.
            distM = network.GeoUtils.vincenty(40.7128, -74.0060, 51.5074, -0.1278);
            expectedLatencyMs = distM / 200000000 * 1000;

            testCase.verifyEqual(fiberLatencyMs, expectedLatencyMs, 'AbsTol', 1e-6, ...
                'FIBER_LINK latency should equal vincenty(NYC,LON)/200000000*1000 ms.');
        end

    end % methods (Test)

end % classdef
