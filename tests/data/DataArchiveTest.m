classdef DataArchiveTest < matlab.unittest.TestCase
    % DATAARCHIVETEST Unit tests for Phase 9 — Operational Archive Layer.
    %
    % Covers:
    %   1. SimulationStore — HDF5-backed archive CRUD
    %   2. RunRegistry — JSON flat-file run catalog
    %   3. EventArchiver — Buffered event sink with flush thresholds
    %   4. Integration — Full DataFabricController → archive → QueryEngine flow
    %
    % All tests use temporary files/directories cleaned up in teardown.

    properties (TestParameter)
    end

    properties
        TempDir     % Temporary directory for test artifacts
        ProjectRoot % Project root path (for path management)
    end

    methods (TestClassSetup)
        function addProjectToPath(testCase)
            % Add the project root to the MATLAB path so +data package is visible.
            testCase.ProjectRoot = fileparts(fileparts(fileparts(mfilename('fullpath'))));
            addpath(testCase.ProjectRoot);
        end
    end

    methods (TestMethodSetup)
        function createTempDir(testCase)
            testCase.TempDir = fullfile(tempdir, ['DataArchiveTest_' char(java.util.UUID.randomUUID().toString())]);
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

    % =====================================================================
    % 1. SimulationStore Tests
    % =====================================================================
    methods (Test)

        function testSimStoreCreatesHDF5File(testCase)
            % Verify that constructing a SimulationStore creates the HDF5 file.
            archivePath = fullfile(testCase.TempDir, 'test_archive.h5');
            store = data.SimulationStore(archivePath);  %#ok<NASGU>
            testCase.verifyTrue(isfile(archivePath), ...
                'SimulationStore constructor should create an HDF5 file.');
        end

        function testSimStoreWritesSchemaVersion(testCase)
            % Verify the schema version attribute is written and readable.
            archivePath = fullfile(testCase.TempDir, 'test_archive.h5');
            store = data.SimulationStore(archivePath);  %#ok<NASGU>
            version = string(h5readatt(char(archivePath), '/', 'schemaVersion'));
            testCase.verifyEqual(version, data.SchemaVersion.CURRENT, ...
                'Schema version attribute should match SchemaVersion.CURRENT.');
        end

        function testSimStoreCreateRunGroupStructure(testCase)
            % Verify createRun creates the expected group structure.
            archivePath = fullfile(testCase.TempDir, 'test_archive.h5');
            store = data.SimulationStore(archivePath);
            runId = "test-run-001";
            store.createRun(runId);

            % Verify expected subgroups exist
            info = h5info(char(archivePath), '/runs/test-run-001');
            groupNames = {info.Groups.Name};
            expectedSubgroups = {'/runs/test-run-001/events', ...
                                 '/runs/test-run-001/stats', ...
                                 '/runs/test-run-001/scenario', ...
                                 '/runs/test-run-001/agent', ...
                                 '/runs/test-run-001/icam'};
            for i = 1:numel(expectedSubgroups)
                testCase.verifyTrue(ismember(expectedSubgroups{i}, groupNames), ...
                    sprintf('Expected subgroup "%s" should exist.', expectedSubgroups{i}));
            end
        end

        function testSimStoreWriteReadEventsRoundTrip(testCase)
            % Verify writeEvents/readEvents round-trip with mixed fields.
            archivePath = fullfile(testCase.TempDir, 'test_archive.h5');
            store = data.SimulationStore(archivePath);
            runId = "events-run";
            store.createRun(runId);

            % Create event struct array with numeric and string fields
            events(1).eventId = 1;
            events(1).simTimeSec = 10.5;
            events(1).eventType = "TX";
            events(1).linkId = "link-A";

            events(2).eventId = 2;
            events(2).simTimeSec = 20.3;
            events(2).eventType = "RX";
            events(2).linkId = "link-B";

            store.writeEvents(runId, events);
            recovered = store.readEvents(runId);

            testCase.verifyEqual(numel(recovered), 2, ...
                'Should recover 2 events.');
            testCase.verifyEqual(recovered(1).eventId, 1, ...
                'First event eventId should match.');
            testCase.verifyEqual(recovered(2).simTimeSec, 20.3, ...
                'Second event simTimeSec should match.');
            testCase.verifyEqual(recovered(1).eventType, "TX", ...
                'First event eventType string should match.');
            testCase.verifyEqual(recovered(2).linkId, "link-B", ...
                'Second event linkId string should match.');
        end

        function testSimStoreWriteReadStatsRoundTrip(testCase)
            % Verify writeStats/readStats round-trip with nested struct.
            archivePath = fullfile(testCase.TempDir, 'test_archive.h5');
            store = data.SimulationStore(archivePath);
            runId = "stats-run";
            store.createRun(runId);

            statsIn.totalMessages = 100;
            statsIn.deliveryRate = 0.95;
            statsIn.latency.mean = 45.2;
            statsIn.latency.max = 120.0;
            statsIn.latency.min = 5.0;

            store.writeStats(runId, statsIn);
            statsOut = store.readStats(runId);

            testCase.verifyEqual(statsOut.totalMessages, 100, ...
                'totalMessages should match.');
            testCase.verifyEqual(statsOut.deliveryRate, 0.95, 'AbsTol', 1e-10, ...
                'deliveryRate should match.');
            testCase.verifyEqual(statsOut.latency.mean, 45.2, 'AbsTol', 1e-10, ...
                'Nested latency.mean should match.');
            testCase.verifyEqual(statsOut.latency.max, 120.0, 'AbsTol', 1e-10, ...
                'Nested latency.max should match.');
        end

        function testSimStoreWriteReadScenarioRoundTrip(testCase)
            % Verify writeScenario/readScenario round-trip.
            archivePath = fullfile(testCase.TempDir, 'test_archive.h5');
            store = data.SimulationStore(archivePath);
            runId = "scenario-run";
            store.createRun(runId);

            scenarioStruct.scenarioName = "TestMission";
            scenarioStruct.duration = 300;
            scenarioStruct.nodes = {"alpha", "bravo"};
            jsonIn = string(jsonencode(scenarioStruct));

            store.writeScenario(runId, jsonIn);
            jsonOut = store.readScenario(runId);

            testCase.verifyEqual(jsonOut, jsonIn, ...
                'Scenario JSON should round-trip exactly.');
        end

        function testSimStoreListRuns(testCase)
            % Verify listRuns returns correct IDs.
            archivePath = fullfile(testCase.TempDir, 'test_archive.h5');
            store = data.SimulationStore(archivePath);
            store.createRun("run-alpha");
            store.createRun("run-bravo");
            store.createRun("run-charlie");

            runIds = store.listRuns();
            testCase.verifyEqual(numel(runIds), 3, ...
                'Should list 3 runs.');
            testCase.verifyTrue(ismember('run-alpha', runIds), ...
                'run-alpha should appear in listRuns.');
            testCase.verifyTrue(ismember('run-bravo', runIds), ...
                'run-bravo should appear in listRuns.');
            testCase.verifyTrue(ismember('run-charlie', runIds), ...
                'run-charlie should appear in listRuns.');
        end

        function testSimStoreDeleteRun(testCase)
            % Verify deleteRun removes the group.
            archivePath = fullfile(testCase.TempDir, 'test_archive.h5');
            store = data.SimulationStore(archivePath);
            store.createRun("to-delete");

            testCase.verifyTrue(store.runExists("to-delete"), ...
                'Run should exist before deletion.');
            store.deleteRun("to-delete");
            testCase.verifyFalse(store.runExists("to-delete"), ...
                'Run should not exist after deletion.');
        end

        function testSimStoreRunExists(testCase)
            % Verify runExists returns correct boolean.
            archivePath = fullfile(testCase.TempDir, 'test_archive.h5');
            store = data.SimulationStore(archivePath);
            store.createRun("exists-run");

            testCase.verifyTrue(store.runExists("exists-run"), ...
                'runExists should return true for existing run.');
            testCase.verifyFalse(store.runExists("no-such-run"), ...
                'runExists should return false for non-existent run.');
        end

        function testSimStoreSchemaMajorVersionMismatchThrows(testCase)
            % Verify that opening an archive with incompatible major version throws.
            archivePath = fullfile(testCase.TempDir, 'bad_version.h5');

            % Create a valid archive first
            store = data.SimulationStore(archivePath);  %#ok<NASGU>
            clear store;

            % Tamper with the schema version to a different major
            h5writeatt(char(archivePath), '/', 'schemaVersion', '99.0');

            % Attempting to open should throw schema mismatch error
            testCase.verifyError(@() data.SimulationStore(archivePath), ...
                'netsim:data:schemaMajorVersionMismatch');
        end

    end

    % =====================================================================
    % 2. RunRegistry Tests
    % =====================================================================
    methods (Test)

        function testRegistryCreatesEmptyOnMissingFile(testCase)
            % Missing registry file should create empty registry (with warning).
            regPath = fullfile(testCase.TempDir, 'nonexistent_registry.json');
            testCase.verifyWarning(@() data.RunRegistry(regPath), ...
                'netsim:data:registryMissing');
        end

        function testRegistryAddRunGetRecordRoundTrip(testCase)
            % addRun + getRecord should round-trip.
            regPath = fullfile(testCase.TempDir, 'registry.json');
            reg = data.RunRegistry(regPath);

            record.runId = 'run-abc-123';
            record.scenarioName = 'TestScenario';
            record.scenarioFilePath = '/tmp/test.json';
            record.simStartTime = '2024-01-01T00:00:00Z';
            record.simEndTime = '2024-01-01T00:05:00Z';
            record.wallClockDurationSec = 10;
            record.nodeCount = 5;
            record.linkCount = 3;
            record.c2MessagesScheduled = 50;
            record.c2MessagesDelivered = 48;
            record.c2MessagesFailed = 2;
            record.archiveStorePath = '/tmp/archive.h5';
            record.metadata = struct();

            reg.addRun(record);
            recovered = reg.getRecord("run-abc-123");

            testCase.verifyEqual(string(recovered.runId), "run-abc-123", ...
                'Recovered record runId should match.');
            testCase.verifyEqual(string(recovered.scenarioName), "TestScenario", ...
                'Recovered record scenarioName should match.');
        end

        function testRegistryListNoFilters(testCase)
            % list with no filters should return all records.
            regPath = fullfile(testCase.TempDir, 'registry.json');
            reg = data.RunRegistry(regPath);

            for i = 1:3
                rec.runId = sprintf('run-%d', i);
                rec.scenarioName = sprintf('Scenario%d', i);
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

            tbl = reg.list();
            testCase.verifyEqual(height(tbl), 3, ...
                'list() with no filters should return all 3 records.');
        end

        function testRegistryListWithScenarioNameWildcard(testCase)
            % list with scenarioName wildcard filter.
            regPath = fullfile(testCase.TempDir, 'registry.json');
            reg = data.RunRegistry(regPath);

            names = {"AirdropMission", "DragonCart", "AirdropRecon"};
            for i = 1:3
                rec.runId = sprintf('run-%d', i);
                rec.scenarioName = char(names{i});
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

            filters.scenarioName = "Airdrop*";
            tbl = reg.list(filters);
            testCase.verifyEqual(height(tbl), 2, ...
                'Wildcard "Airdrop*" should match 2 records.');
        end

        function testRegistryAnnotate(testCase)
            % annotate should add metadata to a run record.
            regPath = fullfile(testCase.TempDir, 'registry.json');
            reg = data.RunRegistry(regPath);

            rec.runId = 'annotate-run';
            rec.scenarioName = 'Test';
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

            reg.annotate("annotate-run", "note", "baseline run");
            recovered = reg.getRecord("annotate-run");
            testCase.verifyEqual(string(recovered.metadata.note), "baseline run", ...
                'Annotation should be retrievable.');
        end

        function testRegistryRemoveRun(testCase)
            % removeRun should remove the record from the registry.
            regPath = fullfile(testCase.TempDir, 'registry.json');
            reg = data.RunRegistry(regPath);

            rec.runId = 'remove-me';
            rec.scenarioName = 'Test';
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

            testCase.verifyEqual(reg.count(), 1);
            reg.removeRun("remove-me");
            testCase.verifyEqual(reg.count(), 0, ...
                'Count should be 0 after removeRun.');
        end

        function testRegistryCount(testCase)
            % count should return the correct number of records.
            regPath = fullfile(testCase.TempDir, 'registry.json');
            reg = data.RunRegistry(regPath);

            testCase.verifyEqual(reg.count(), 0, 'Empty registry count = 0.');

            for i = 1:4
                rec.runId = sprintf('count-run-%d', i);
                rec.scenarioName = 'Test';
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

            testCase.verifyEqual(reg.count(), 4, 'count should be 4 after adding 4 runs.');
        end

        function testRegistryGenerateRunIdUUIDFormat(testCase)
            % generateRunId should return a valid UUID v4 format string.
            id = data.RunRegistry.generateRunId();
            % UUID format: 8-4-4-4-12 hex characters
            pattern = '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';
            testCase.verifyNotEmpty(regexp(char(id), pattern), ...
                'generateRunId should return a UUID v4 format string.');
        end

    end

    % =====================================================================
    % 3. EventArchiver Tests
    % =====================================================================
    methods (Test)

        function testArchiverBuffersWithoutFlush(testCase)
            % Events below threshold should be buffered, not flushed.
            archivePath = fullfile(testCase.TempDir, 'archiver_test.h5');
            store = data.SimulationStore(archivePath);
            runId = "archiver-buffer-run";
            store.createRun(runId);

            config.flushEventThreshold = 10;
            config.flushTimeIntervalSec = 1000;  % very large so time won't trigger
            archiver = data.EventArchiver(store, runId, config);

            % Add 5 events (below threshold of 10)
            for i = 1:5
                evt.eventId = i;
                evt.simTimeSec = double(i);
                evt.eventType = "TX";
                evt.linkId = "link-1";
                archiver.archive(evt);
            end

            % Events should still be buffered (not yet archived)
            testCase.verifyEqual(uint64(0), archiver.eventsArchived, ...
                'Events below threshold should not be flushed.');
        end

        function testArchiverAutoFlushAtEventThreshold(testCase)
            % Events at threshold count should trigger auto-flush.
            archivePath = fullfile(testCase.TempDir, 'archiver_flush_count.h5');
            store = data.SimulationStore(archivePath);
            runId = "archiver-flush-count-run";
            store.createRun(runId);

            config.flushEventThreshold = 5;
            config.flushTimeIntervalSec = 1000;
            archiver = data.EventArchiver(store, runId, config);

            % Add exactly 5 events (reaches threshold)
            for i = 1:5
                evt.eventId = i;
                evt.simTimeSec = double(i);
                evt.eventType = "TX";
                evt.linkId = "link-1";
                archiver.archive(evt);
            end

            testCase.verifyEqual(archiver.eventsArchived, uint64(5), ...
                'Archiver should auto-flush at event count threshold.');
        end

        function testArchiverAutoFlushAtTimeInterval(testCase)
            % Events exceeding the time interval should trigger auto-flush.
            archivePath = fullfile(testCase.TempDir, 'archiver_flush_time.h5');
            store = data.SimulationStore(archivePath);
            runId = "archiver-flush-time-run";
            store.createRun(runId);

            config.flushEventThreshold = 1000;  % very large so count won't trigger
            config.flushTimeIntervalSec = 10;
            archiver = data.EventArchiver(store, runId, config);

            % Add events with simTimeSec that crosses the interval
            evt.eventId = 1;
            evt.simTimeSec = 0.0;
            evt.eventType = "TX";
            evt.linkId = "link-1";
            archiver.archive(evt);

            % This event crosses the 10-second interval boundary
            evt.eventId = 2;
            evt.simTimeSec = 11.0;
            evt.eventType = "RX";
            evt.linkId = "link-2";
            archiver.archive(evt);

            testCase.verifyEqual(archiver.eventsArchived, uint64(2), ...
                'Archiver should auto-flush when sim time interval exceeded.');
        end

        function testArchiverFinalizeFlushesRemaining(testCase)
            % finalize should flush all remaining buffered events.
            archivePath = fullfile(testCase.TempDir, 'archiver_finalize.h5');
            store = data.SimulationStore(archivePath);
            runId = "archiver-finalize-run";
            store.createRun(runId);

            config.flushEventThreshold = 100;
            config.flushTimeIntervalSec = 1000;
            archiver = data.EventArchiver(store, runId, config);

            % Add 3 events (won't auto-flush)
            for i = 1:3
                evt.eventId = i;
                evt.simTimeSec = double(i);
                evt.eventType = "TX";
                evt.linkId = "link-1";
                archiver.archive(evt);
            end

            testCase.verifyEqual(archiver.eventsArchived, uint64(0), ...
                'Before finalize, events should be buffered.');

            archiver.finalize();

            testCase.verifyEqual(archiver.eventsArchived, uint64(3), ...
                'After finalize, all events should be archived.');
        end

        function testArchiverEventsArchivedCounter(testCase)
            % eventsArchived counter should increment correctly across flushes.
            archivePath = fullfile(testCase.TempDir, 'archiver_counter.h5');
            store = data.SimulationStore(archivePath);
            runId = "archiver-counter-run";
            store.createRun(runId);

            config.flushEventThreshold = 3;
            config.flushTimeIntervalSec = 1000;
            archiver = data.EventArchiver(store, runId, config);

            % Add 3 events → auto-flush (count = 3)
            for i = 1:3
                evt.eventId = i;
                evt.simTimeSec = double(i);
                evt.eventType = "TX";
                evt.linkId = "link-1";
                archiver.archive(evt);
            end
            testCase.verifyEqual(archiver.eventsArchived, uint64(3));

            % Add 2 more + finalize (count = 5)
            for i = 4:5
                evt.eventId = i;
                evt.simTimeSec = double(i);
                evt.eventType = "RX";
                evt.linkId = "link-2";
                archiver.archive(evt);
            end
            archiver.finalize();
            testCase.verifyEqual(archiver.eventsArchived, uint64(5), ...
                'eventsArchived should accumulate across flushes.');
        end

    end

    % =====================================================================
    % 4. Integration Test
    % =====================================================================
    methods (Test)

        function testFullArchiveQueryIntegration(testCase)
            % Full integration: DataFabricController → archive → QueryEngine.
            % Creates a run, archives events, writes stats/scenario, then
            % queries back using QueryEngine to verify correctness.
            archivePath = fullfile(testCase.TempDir, 'integration_archive.h5');
            regPath = fullfile(testCase.TempDir, 'integration_registry.json');

            % Create store and archiver manually (simulating DFC internals)
            store = data.SimulationStore(archivePath);
            reg = data.RunRegistry(regPath);
            runId = data.RunRegistry.generateRunId();

            % Create run group
            store.createRun(runId);

            % Write scenario
            scenarioStruct.scenarioName = "IntegrationTest";
            scenarioStruct.duration = 120;
            scenarioStruct.nodeCount = 4;
            scenarioJson = string(jsonencode(scenarioStruct));
            store.writeScenario(runId, scenarioJson);

            % Archive events via EventArchiver
            config.flushEventThreshold = 100;
            config.flushTimeIntervalSec = 1000;
            archiver = data.EventArchiver(store, runId, config);

            for i = 1:10
                evt.eventId = i;
                evt.simTimeSec = double(i) * 5;
                evt.eventType = "TX";
                evt.linkId = "link-int";
                archiver.archive(evt);
            end
            archiver.finalize();

            % Write stats
            statsIn.totalMessages = 10;
            statsIn.deliveryRate = 1.0;
            statsIn.meanLatencyMs = 22.5;
            store.writeStats(runId, statsIn);

            % Add to registry
            rec.runId = char(runId);
            rec.scenarioName = 'IntegrationTest';
            rec.scenarioFilePath = '';
            rec.simStartTime = '2024-06-01T12:00:00Z';
            rec.simEndTime = '2024-06-01T12:02:00Z';
            rec.wallClockDurationSec = 5;
            rec.nodeCount = 4;
            rec.linkCount = 2;
            rec.c2MessagesScheduled = 10;
            rec.c2MessagesDelivered = 10;
            rec.c2MessagesFailed = 0;
            rec.archiveStorePath = char(archivePath);
            rec.metadata = struct();
            reg.addRun(rec);

            % Query via QueryEngine
            qe = data.QueryEngine(store);

            % Verify scenario
            scenario = qe.getScenario(runId);
            testCase.verifyEqual(string(scenario.scenarioName), "IntegrationTest", ...
                'QueryEngine should return correct scenario name.');
            testCase.verifyEqual(scenario.duration, 120, ...
                'QueryEngine should return correct scenario duration.');

            % Verify events
            events = qe.getEvents(runId);
            testCase.verifyEqual(numel(events), 10, ...
                'QueryEngine should return all 10 archived events.');
            testCase.verifyEqual(events(1).simTimeSec, 5.0, ...
                'First event simTimeSec should be 5.');
            testCase.verifyEqual(events(10).simTimeSec, 50.0, ...
                'Last event simTimeSec should be 50.');

            % Verify stats
            statsTable = qe.getStats(runId);
            testCase.verifyEqual(height(statsTable), 1, ...
                'Stats table should have one row.');
            testCase.verifyEqual(statsTable.totalMessages, 10, ...
                'Stats totalMessages should be 10.');
            testCase.verifyEqual(statsTable.deliveryRate, 1.0, 'AbsTol', 1e-10, ...
                'Stats deliveryRate should be 1.0.');

            % Verify registry
            testCase.verifyEqual(reg.count(), 1, ...
                'Registry should have 1 record.');
            regRec = reg.getRecord(runId);
            testCase.verifyEqual(string(regRec.scenarioName), "IntegrationTest", ...
                'Registry record scenarioName should match.');
        end

    end
end
