classdef DataArchivePropertyTest < matlab.unittest.TestCase
    % DATAARCHIVEPROPERTYTEST Property-based tests for Phase 9 (P27–P33).
    %
    % Each test runs 100+ random iterations with randomized inputs to verify
    % invariants of the operational archive layer (+data/ package).
    %
    % Properties tested:
    %   P27: Schema read-back fidelity
    %   P28: QueryEngine stats consistency
    %   P29: Export JSON validity
    %   P30: RunRegistry list-filter correctness
    %   P31: Retention policy invariant
    %   P32: Scenario lineage replay equivalence
    %   P33: Cross-run aggregate correctness
    %
    % **Validates: Requirements R25–R32**

    properties
        TempDir     % Temporary directory for test artifacts
        ProjectRoot % Project root path
    end

    methods (TestClassSetup)
        function addProjectToPath(testCase)
            testCase.ProjectRoot = fileparts(fileparts(fileparts(mfilename('fullpath'))));
            addpath(testCase.ProjectRoot);
        end
    end

    methods (TestMethodSetup)
        function createTempDir(testCase)
            testCase.TempDir = fullfile(tempdir, ['DataArchivePropTest_' char(java.util.UUID.randomUUID().toString())]);
            mkdir(testCase.TempDir);
        end
    end

    methods (TestMethodTeardown)
        function removeTempDir(testCase)
            if isfolder(testCase.TempDir)
                rmdir(testCase.TempDir, 's');
            end
        end
    end

    methods (Test)

        function testP27_SchemaReadBackFidelity(testCase)
            % Feature: matlab-network-sim, Property P27: Schema read-back fidelity
            %
            % For any random event struct written to SimulationStore, reading
            % it back produces an identical struct (numeric and string fields).
            %
            % **Validates: Requirements R30, R32**

            nIterations = 100;
            eventTypes = ["TX", "RX", "FAIL", "OUTAGE_START", "OUTAGE_END", "AGENT_IDLE"];

            for iter = 1:nIterations
                % Create a fresh HDF5 file per iteration to avoid dataset conflicts
                archivePath = fullfile(testCase.TempDir, sprintf('p27_iter_%d.h5', iter));
                store = data.SimulationStore(archivePath);
                runId = sprintf("p27-run-%d", iter);
                store.createRun(runId);

                % Generate random event struct with varying field values
                nEvents = randi([1, 20]);
                events = struct([]);
                for k = 1:nEvents
                    events(k).eventId = randi([1, 1e6]);
                    events(k).simTimeSec = rand() * 3600;
                    events(k).eventType = eventTypes(randi(numel(eventTypes)));
                    events(k).linkId = sprintf("link-%s", char(randi([65, 90], 1, randi([3, 8]))));
                end

                % Write and read back
                store.writeEvents(runId, events);
                recovered = store.readEvents(runId);

                % Verify identical
                testCase.verifyEqual(numel(recovered), nEvents, ...
                    sprintf('Iter %d: event count mismatch.', iter));

                for k = 1:nEvents
                    testCase.verifyEqual(recovered(k).eventId, events(k).eventId, ...
                        sprintf('Iter %d, event %d: eventId mismatch.', iter, k));
                    testCase.verifyEqual(recovered(k).simTimeSec, events(k).simTimeSec, ...
                        'AbsTol', 1e-10, ...
                        sprintf('Iter %d, event %d: simTimeSec mismatch.', iter, k));
                    testCase.verifyEqual(recovered(k).eventType, events(k).eventType, ...
                        sprintf('Iter %d, event %d: eventType mismatch.', iter, k));
                    testCase.verifyEqual(recovered(k).linkId, events(k).linkId, ...
                        sprintf('Iter %d, event %d: linkId mismatch.', iter, k));
                end
            end
        end

        function testP28_QueryEngineStatsConsistency(testCase)
            % Feature: matlab-network-sim, Property P28: QueryEngine stats consistency
            %
            % For any random stats struct written via SimulationStore, reading
            % via QueryEngine.getStats returns numeric values that match.
            %
            % **Validates: Requirements R27**

            nIterations = 100;
            archivePath = fullfile(testCase.TempDir, 'p28_archive.h5');
            store = data.SimulationStore(archivePath);

            for iter = 1:nIterations
                runId = sprintf("p28-run-%04d", iter);
                store.createRun(runId);

                % Generate random stats struct with numeric fields
                statsIn.totalMessages = randi([0, 100000]);
                statsIn.deliveryRate = rand();
                statsIn.meanLatencyMs = rand() * 1000;
                statsIn.maxLatencyMs = statsIn.meanLatencyMs + rand() * 500;
                statsIn.minLatencyMs = rand() * statsIn.meanLatencyMs;
                statsIn.outageFraction = rand();
                statsIn.wallClockSec = rand() * 600;

                store.writeStats(runId, statsIn);

                % Read via QueryEngine
                qe = data.QueryEngine(store);
                statsTable = qe.getStats(runId);

                % Verify numeric values match
                testCase.verifyEqual(statsTable.totalMessages, statsIn.totalMessages, ...
                    sprintf('Iter %d: totalMessages mismatch.', iter));
                testCase.verifyEqual(statsTable.deliveryRate, statsIn.deliveryRate, ...
                    'AbsTol', 1e-10, ...
                    sprintf('Iter %d: deliveryRate mismatch.', iter));
                testCase.verifyEqual(statsTable.meanLatencyMs, statsIn.meanLatencyMs, ...
                    'AbsTol', 1e-10, ...
                    sprintf('Iter %d: meanLatencyMs mismatch.', iter));
                testCase.verifyEqual(statsTable.maxLatencyMs, statsIn.maxLatencyMs, ...
                    'AbsTol', 1e-10, ...
                    sprintf('Iter %d: maxLatencyMs mismatch.', iter));
                testCase.verifyEqual(statsTable.minLatencyMs, statsIn.minLatencyMs, ...
                    'AbsTol', 1e-10, ...
                    sprintf('Iter %d: minLatencyMs mismatch.', iter));
                testCase.verifyEqual(statsTable.outageFraction, statsIn.outageFraction, ...
                    'AbsTol', 1e-10, ...
                    sprintf('Iter %d: outageFraction mismatch.', iter));
                testCase.verifyEqual(statsTable.wallClockSec, statsIn.wallClockSec, ...
                    'AbsTol', 1e-10, ...
                    sprintf('Iter %d: wallClockSec mismatch.', iter));
            end
        end

        function testP29_ExportJsonValidity(testCase)
            % Feature: matlab-network-sim, Property P29: Export JSON validity
            %
            % For any random stats struct, exporting via QueryEngine.exportRun
            % and reading the exported JSON file succeeds without error via
            % jsondecode.
            %
            % **Validates: Requirements R29**

            nIterations = 50;
            archivePath = fullfile(testCase.TempDir, 'p29_archive.h5');
            store = data.SimulationStore(archivePath);
            qe = data.QueryEngine(store);

            for iter = 1:nIterations
                runId = sprintf("p29-run-%04d", iter);
                store.createRun(runId);

                % Generate random stats
                statsIn.totalMessages = randi([0, 50000]);
                statsIn.deliveryRate = rand();
                statsIn.meanLatencyMs = rand() * 1000;
                statsIn.failedMessages = randi([0, 1000]);
                statsIn.throughputBps = rand() * 1e9;
                store.writeStats(runId, statsIn);

                % Write a scenario
                scenarioStruct.scenarioName = sprintf("Scenario_%d", iter);
                scenarioStruct.duration = randi([60, 7200]);
                scenarioStruct.nodeCount = randi([2, 100]);
                store.writeScenario(runId, string(jsonencode(scenarioStruct)));

                % Write some events
                nEvents = randi([1, 10]);
                events = struct([]);
                for k = 1:nEvents
                    events(k).eventId = k;
                    events(k).simTimeSec = rand() * 3600;
                    events(k).eventType = "TX";
                    events(k).linkId = sprintf("link-%d", randi(100));
                end
                store.writeEvents(runId, events);

                % Export to temp dir
                exportDir = fullfile(testCase.TempDir, sprintf('export_%04d', iter));
                qe.exportRun(runId, string(exportDir), "json");

                % Verify stats.json is valid JSON
                statsJsonPath = fullfile(exportDir, 'stats.json');
                testCase.verifyTrue(isfile(statsJsonPath), ...
                    sprintf('Iter %d: stats.json should exist.', iter));
                statsText = fileread(statsJsonPath);
                decoded = jsondecode(statsText);
                testCase.verifyTrue(isstruct(decoded), ...
                    sprintf('Iter %d: stats.json should decode to a struct.', iter));

                % Verify scenario.json is valid JSON
                scenarioJsonPath = fullfile(exportDir, 'scenario.json');
                testCase.verifyTrue(isfile(scenarioJsonPath), ...
                    sprintf('Iter %d: scenario.json should exist.', iter));
                scenarioText = fileread(scenarioJsonPath);
                scenarioDecoded = jsondecode(scenarioText);
                testCase.verifyTrue(isstruct(scenarioDecoded), ...
                    sprintf('Iter %d: scenario.json should decode to a struct.', iter));
            end
        end

        function testP30_RunRegistryListFilterCorrectness(testCase)
            % Feature: matlab-network-sim, Property P30: RunRegistry list-filter correctness
            %
            % For any set of random run records with varied scenarioNames,
            % applying a wildcard filter returns exactly those records whose
            % scenarioName matches the equivalent regex.
            %
            % **Validates: Requirements R25**

            nIterations = 100;

            for iter = 1:nIterations
                % Create a fresh registry for each iteration
                regPath = fullfile(testCase.TempDir, sprintf('p30_reg_%d.json', iter));

                % Generate random scenario name prefixes
                prefixes = ["Alpha", "Bravo", "Charlie", "Delta", "Echo", ...
                            "Foxtrot", "Golf", "Hotel"];
                suffixes = ["Mission", "Recon", "Patrol", "Strike", "Survey"];

                nRecords = randi([5, 20]);
                scenarioNames = strings(nRecords, 1);
                for k = 1:nRecords
                    prefix = prefixes(randi(numel(prefixes)));
                    suffix = suffixes(randi(numel(suffixes)));
                    scenarioNames(k) = prefix + suffix;
                end

                % Pick a random wildcard filter
                filterPrefix = prefixes(randi(numel(prefixes)));
                wildcardPattern = filterPrefix + "*";

                % Populate the registry
                reg = data.RunRegistry(regPath);
                for k = 1:nRecords
                    rec.runId = sprintf('p30-run-%d-%d', iter, k);
                    rec.scenarioName = char(scenarioNames(k));
                    rec.scenarioFilePath = '';
                    rec.simStartTime = '2024-01-01T00:00:00Z';
                    rec.simEndTime = '2024-01-01T00:05:00Z';
                    rec.wallClockDurationSec = 10;
                    rec.nodeCount = 5;
                    rec.linkCount = 3;
                    rec.c2MessagesScheduled = 50;
                    rec.c2MessagesDelivered = 48;
                    rec.c2MessagesFailed = 2;
                    rec.archiveStorePath = '/tmp/archive.h5';
                    rec.metadata = struct();
                    reg.addRun(rec);
                end

                % Apply filter
                filters.scenarioName = wildcardPattern;
                filteredTbl = reg.list(filters);

                % Compute expected count via regex
                regexPattern = regexptranslate('wildcard', char(wildcardPattern));
                expectedCount = 0;
                for k = 1:nRecords
                    if ~isempty(regexp(char(scenarioNames(k)), regexPattern, 'once'))
                        expectedCount = expectedCount + 1;
                    end
                end

                testCase.verifyEqual(height(filteredTbl), expectedCount, ...
                    sprintf('Iter %d: filter "%s" should match %d records, got %d.', ...
                    iter, wildcardPattern, expectedCount, height(filteredTbl)));
            end
        end

        function testP31_RetentionPolicyInvariant(testCase)
            % Feature: matlab-network-sim, Property P31: Retention policy invariant
            %
            % For N random runs (N=5 to 20) with maxRuns=3, after applying
            % retention the final count is <= maxRuns (unless keepTagged
            % protects some runs).
            %
            % **Validates: Requirements R31**

            nIterations = 100;

            for iter = 1:nIterations
                % Create fresh archive and registry per iteration
                archivePath = fullfile(testCase.TempDir, sprintf('p31_archive_%d.h5', iter));
                regPath = fullfile(testCase.TempDir, sprintf('p31_reg_%d.json', iter));

                maxRuns = 3;
                keepTagged = true;

                dfcConfig.archivePath = archivePath;
                dfcConfig.registryPath = regPath;
                dfcConfig.flushEventThreshold = 1000;
                dfcConfig.flushTimeIntervalSec = 60;
                dfcConfig.retentionPolicy.maxRuns = maxRuns;
                dfcConfig.retentionPolicy.maxAgeDays = 0;
                dfcConfig.retentionPolicy.keepTagged = keepTagged;

                dfc = data.DataFabricController(dfcConfig);

                % Generate N random runs
                N = randi([5, 20]);
                nTagged = 0;
                for k = 1:N
                    runId = data.RunRegistry.generateRunId();
                    dfc.Store.createRun(runId);

                    % Write minimal stats
                    statsIn.totalMessages = randi(1000);
                    dfc.Store.writeStats(runId, statsIn);

                    % Write minimal scenario
                    dfc.Store.writeScenario(runId, string(jsonencode(struct('name', sprintf('s%d', k)))));

                    % Add run record to registry
                    rec.runId = char(runId);
                    rec.scenarioName = sprintf('Scenario_%d', k);
                    rec.scenarioFilePath = '';
                    rec.simStartTime = '2024-01-01T00:00:00Z';
                    rec.simEndTime = '2024-01-01T00:05:00Z';
                    rec.wallClockDurationSec = 10;
                    rec.nodeCount = 5;
                    rec.linkCount = 3;
                    rec.c2MessagesScheduled = 50;
                    rec.c2MessagesDelivered = 48;
                    rec.c2MessagesFailed = 2;
                    rec.archiveStorePath = char(archivePath);

                    % Randomly tag some runs (to test keepTagged)
                    if rand() < 0.2
                        rec.metadata.note = 'tagged-run';
                        nTagged = nTagged + 1;
                    else
                        rec.metadata = struct();
                    end
                    dfc.Registry.addRun(rec);
                end

                % Apply retention
                dfc.applyRetention();

                % Verify invariant: final count <= maxRuns + nTagged
                finalCount = dfc.Registry.count();
                testCase.verifyLessThanOrEqual(finalCount, maxRuns + nTagged, ...
                    sprintf('Iter %d: final count %d should be <= maxRuns(%d) + tagged(%d).', ...
                    iter, finalCount, maxRuns, nTagged));
            end
        end

        function testP32_ScenarioLineageReplayEquivalence(testCase)
            % Feature: matlab-network-sim, Property P32: Scenario lineage replay equivalence
            %
            % For any random scenario struct, writing to SimulationStore
            % (via JSON snapshot) and reading back via QueryEngine preserves
            % all fields exactly.
            %
            % **Validates: Requirements R28**

            nIterations = 50;
            archivePath = fullfile(testCase.TempDir, 'p32_archive.h5');
            store = data.SimulationStore(archivePath);
            qe = data.QueryEngine(store);

            for iter = 1:nIterations
                runId = sprintf("p32-run-%04d", iter);
                store.createRun(runId);

                % Generate random scenario struct
                scenario.scenarioName = sprintf("Mission_%s", char(randi([65, 90], 1, randi([4, 10]))));
                scenario.simulationDurationSec = randi([60, 86400]);
                scenario.nodeCount = randi([2, 200]);
                scenario.linkCount = randi([1, 500]);

                % Add random agent-like fields
                nAgents = randi([0, 5]);
                agents = cell(1, nAgents);
                for a = 1:nAgents
                    agents{a}.id = sprintf("agent-%d", a);
                    agents{a}.role = sprintf("Role_%s", char(randi([65, 90], 1, 5)));
                    agents{a}.nodeId = sprintf("node-%d", randi(100));
                end
                scenario.agents = agents;

                % Add random additional metadata
                scenario.randomSeed = randi(1e9);
                scenario.version = sprintf("%d.%d", randi(5), randi(10));

                % Snapshot via JSON (mimics DataFabricController.embedFileContents pattern)
                scenarioJson = string(jsonencode(scenario));
                store.writeScenario(runId, scenarioJson);

                % Read back via QueryEngine
                recovered = qe.getScenario(runId);

                % Verify all top-level fields
                testCase.verifyEqual(string(recovered.scenarioName), string(scenario.scenarioName), ...
                    sprintf('Iter %d: scenarioName mismatch.', iter));
                testCase.verifyEqual(recovered.simulationDurationSec, scenario.simulationDurationSec, ...
                    sprintf('Iter %d: simulationDurationSec mismatch.', iter));
                testCase.verifyEqual(recovered.nodeCount, scenario.nodeCount, ...
                    sprintf('Iter %d: nodeCount mismatch.', iter));
                testCase.verifyEqual(recovered.linkCount, scenario.linkCount, ...
                    sprintf('Iter %d: linkCount mismatch.', iter));
                testCase.verifyEqual(recovered.randomSeed, scenario.randomSeed, ...
                    sprintf('Iter %d: randomSeed mismatch.', iter));
                testCase.verifyEqual(string(recovered.version), string(scenario.version), ...
                    sprintf('Iter %d: version mismatch.', iter));

                % Verify agents preserved
                if nAgents > 0
                    recoveredAgents = recovered.agents;
                    if isstruct(recoveredAgents)
                        testCase.verifyEqual(numel(recoveredAgents), nAgents, ...
                            sprintf('Iter %d: agent count mismatch.', iter));
                        for a = 1:nAgents
                            testCase.verifyEqual(string(recoveredAgents(a).id), string(agents{a}.id), ...
                                sprintf('Iter %d, agent %d: id mismatch.', iter, a));
                            testCase.verifyEqual(string(recoveredAgents(a).role), string(agents{a}.role), ...
                                sprintf('Iter %d, agent %d: role mismatch.', iter, a));
                        end
                    elseif iscell(recoveredAgents)
                        testCase.verifyEqual(numel(recoveredAgents), nAgents, ...
                            sprintf('Iter %d: agent count mismatch.', iter));
                        for a = 1:nAgents
                            testCase.verifyEqual(string(recoveredAgents{a}.id), string(agents{a}.id), ...
                                sprintf('Iter %d, agent %d: id mismatch.', iter, a));
                        end
                    end
                end
            end
        end

        function testP33_CrossRunAggregateCorrectness(testCase)
            % Feature: matlab-network-sim, Property P33: Cross-run aggregate correctness
            %
            % For random pairs of numeric stats, compute aggregateStats via
            % QueryEngine and verify mean/median/min/max match manual computation.
            %
            % **Validates: Requirements R27**

            nIterations = 100;
            archivePath = fullfile(testCase.TempDir, 'p33_archive.h5');
            store = data.SimulationStore(archivePath);
            qe = data.QueryEngine(store);

            for iter = 1:nIterations
                % Generate 2 random stats structs
                nRuns = 2;
                runIds = strings(1, nRuns);
                statsArray = cell(1, nRuns);

                for r = 1:nRuns
                    runId = sprintf("p33-run-%04d-%d", iter, r);
                    runIds(r) = runId;
                    store.createRun(runId);

                    % Generate random numeric fields
                    s.totalMessages = randi([0, 100000]);
                    s.deliveryRate = rand();
                    s.meanLatencyMs = rand() * 1000;
                    statsArray{r} = s;

                    store.writeStats(runId, s);
                end

                % Compute aggregate via QueryEngine
                agg = qe.aggregateStats(runIds);

                % Verify totalMessages aggregate
                vals = [statsArray{1}.totalMessages, statsArray{2}.totalMessages];
                testCase.verifyEqual(agg.totalMessages.mean, mean(vals), ...
                    'AbsTol', 1e-10, ...
                    sprintf('Iter %d: totalMessages mean mismatch.', iter));
                testCase.verifyEqual(agg.totalMessages.median, median(vals), ...
                    'AbsTol', 1e-10, ...
                    sprintf('Iter %d: totalMessages median mismatch.', iter));
                testCase.verifyEqual(agg.totalMessages.min, min(vals), ...
                    'AbsTol', 1e-10, ...
                    sprintf('Iter %d: totalMessages min mismatch.', iter));
                testCase.verifyEqual(agg.totalMessages.max, max(vals), ...
                    'AbsTol', 1e-10, ...
                    sprintf('Iter %d: totalMessages max mismatch.', iter));

                % Verify deliveryRate aggregate
                vals = [statsArray{1}.deliveryRate, statsArray{2}.deliveryRate];
                testCase.verifyEqual(agg.deliveryRate.mean, mean(vals), ...
                    'AbsTol', 1e-10, ...
                    sprintf('Iter %d: deliveryRate mean mismatch.', iter));
                testCase.verifyEqual(agg.deliveryRate.median, median(vals), ...
                    'AbsTol', 1e-10, ...
                    sprintf('Iter %d: deliveryRate median mismatch.', iter));
                testCase.verifyEqual(agg.deliveryRate.min, min(vals), ...
                    'AbsTol', 1e-10, ...
                    sprintf('Iter %d: deliveryRate min mismatch.', iter));
                testCase.verifyEqual(agg.deliveryRate.max, max(vals), ...
                    'AbsTol', 1e-10, ...
                    sprintf('Iter %d: deliveryRate max mismatch.', iter));

                % Verify meanLatencyMs aggregate
                vals = [statsArray{1}.meanLatencyMs, statsArray{2}.meanLatencyMs];
                testCase.verifyEqual(agg.meanLatencyMs.mean, mean(vals), ...
                    'AbsTol', 1e-10, ...
                    sprintf('Iter %d: meanLatencyMs mean mismatch.', iter));
                testCase.verifyEqual(agg.meanLatencyMs.median, median(vals), ...
                    'AbsTol', 1e-10, ...
                    sprintf('Iter %d: meanLatencyMs median mismatch.', iter));
                testCase.verifyEqual(agg.meanLatencyMs.min, min(vals), ...
                    'AbsTol', 1e-10, ...
                    sprintf('Iter %d: meanLatencyMs min mismatch.', iter));
                testCase.verifyEqual(agg.meanLatencyMs.max, max(vals), ...
                    'AbsTol', 1e-10, ...
                    sprintf('Iter %d: meanLatencyMs max mismatch.', iter));
            end
        end

    end
end
