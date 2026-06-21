classdef DataArchiveBenchmarkTest < matlab.unittest.TestCase
    % DATAARCHIVEBENCHMARKTEST Benchmark and HDF5 accessibility tests for
    % Phase 9 — Operational Archive Layer.
    %
    % Task 47: Performance benchmarks
    %   1. Archive 100 runs with 1000 events each, verify QueryEngine
    %      handles them within 5 seconds.
    %   2. EventArchiver overhead test: time archiving 10,000 events,
    %      verify < 1ms per event average.
    %
    % Task 48: HDF5 external accessibility
    %   3. Write archive, then verify using h5info that:
    %      - Root group has schemaVersion attribute
    %      - Root group has README attribute
    %      - Run groups contain expected subgroups (events, stats, scenario, agent, icam)
    %      - Datasets are standard types (H5T_IEEE_F64LE for doubles, variable-length strings)
    %      - String data is stored as UTF-8

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
            testCase.TempDir = fullfile(tempdir, ['DataArchiveBenchmark_' char(java.util.UUID.randomUUID().toString())]);
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
    % Task 47: Performance Benchmarks
    % =====================================================================
    methods (Test)

        function testQueryEngine100RunsWith1000EventsWithin5Seconds(testCase)
            % Benchmark: archive 100 runs with 1000 events each, then
            % verify QueryEngine can retrieve events from all runs within
            % 5 seconds total.
            archivePath = fullfile(testCase.TempDir, 'benchmark_100runs.h5');
            store = data.SimulationStore(archivePath);

            numRuns = 100;
            numEventsPerRun = 1000;

            % Phase 1: Populate archive with 100 runs
            for r = 1:numRuns
                runId = sprintf("bench-run-%04d", r);
                store.createRun(runId);

                % Generate events for this run
                events = struct();
                for e = 1:numEventsPerRun
                    events(e).eventId = e;
                    events(e).simTimeSec = double(e) * 0.1;
                    events(e).eventType = "TX";
                    events(e).linkId = sprintf("link-%d", mod(e, 10));
                end
                store.writeEvents(runId, events);

                % Write minimal stats
                statsIn.totalMessages = numEventsPerRun;
                statsIn.deliveryRate = 0.95;
                statsIn.meanLatencyMs = 30.0 + rand() * 10;
                store.writeStats(runId, statsIn);
            end

            % Phase 2: Time QueryEngine retrieval across all runs
            qe = data.QueryEngine(store);
            tic;
            for r = 1:numRuns
                runId = sprintf("bench-run-%04d", r);
                evts = qe.getEvents(runId);
                testCase.verifyEqual(numel(evts), numEventsPerRun, ...
                    sprintf('Run %d should have %d events.', r, numEventsPerRun));
            end
            elapsed = toc;

            testCase.verifyLessThan(elapsed, 5.0, ...
                sprintf('QueryEngine should handle 100 runs x 1000 events within 5s (actual: %.2fs).', elapsed));
        end

        function testEventArchiverOverheadLessThan1msPerEvent(testCase)
            % Benchmark: time archiving 10,000 events via EventArchiver,
            % verify average overhead is < 1ms per event.
            archivePath = fullfile(testCase.TempDir, 'benchmark_archiver.h5');
            store = data.SimulationStore(archivePath);
            runId = "archiver-perf-run";
            store.createRun(runId);

            numEvents = 10000;
            config.flushEventThreshold = 500;
            config.flushTimeIntervalSec = 1000;
            archiver = data.EventArchiver(store, runId, config);

            % Time the archiving of 10,000 events
            tic;
            for i = 1:numEvents
                evt.eventId = i;
                evt.simTimeSec = double(i) * 0.01;
                evt.eventType = "TX";
                evt.linkId = "link-perf";
                evt.srcNodeId = "node-A";
                evt.dstNodeId = "node-B";
                evt.latencyMs = 25.0 + rand() * 10;
                archiver.archive(evt);
            end
            archiver.finalize();
            elapsed = toc;

            avgMsPerEvent = (elapsed / numEvents) * 1000;

            testCase.verifyEqual(archiver.eventsArchived, uint64(numEvents), ...
                'All 10,000 events should be archived.');
            testCase.verifyLessThan(avgMsPerEvent, 1.0, ...
                sprintf('EventArchiver should average < 1ms/event (actual: %.4f ms/event).', avgMsPerEvent));
        end

    end

    % =====================================================================
    % Task 48: HDF5 External Accessibility Verification
    % =====================================================================
    methods (Test)

        function testRootGroupHasSchemaVersionAttribute(testCase)
            % Verify using h5info that root group has schemaVersion attribute.
            archivePath = fullfile(testCase.TempDir, 'accessibility_test.h5');
            store = data.SimulationStore(archivePath); %#ok<NASGU>

            info = h5info(char(archivePath), '/');
            attrNames = {info.Attributes.Name};

            testCase.verifyTrue(ismember('schemaVersion', attrNames), ...
                'Root group must have a schemaVersion attribute.');

            % Also verify the value is a valid version string
            version = h5readatt(char(archivePath), '/', 'schemaVersion');
            testCase.verifyTrue(contains(string(version), '.'), ...
                'schemaVersion should be in MAJOR.MINOR format.');
        end

        function testRootGroupHasREADMEAttribute(testCase)
            % Verify using h5info that root group has README attribute.
            archivePath = fullfile(testCase.TempDir, 'accessibility_readme.h5');
            store = data.SimulationStore(archivePath); %#ok<NASGU>

            info = h5info(char(archivePath), '/');
            attrNames = {info.Attributes.Name};

            testCase.verifyTrue(ismember('README', attrNames), ...
                'Root group must have a README attribute.');

            % Verify README contains descriptive content
            readme = h5readatt(char(archivePath), '/', 'README');
            testCase.verifyTrue(strlength(string(readme)) > 50, ...
                'README attribute should contain meaningful descriptive text.');
        end

        function testRunGroupsContainExpectedSubgroups(testCase)
            % Verify that run groups contain the expected subgroups:
            % events, stats, scenario, agent, icam.
            archivePath = fullfile(testCase.TempDir, 'accessibility_subgroups.h5');
            store = data.SimulationStore(archivePath);
            runId = "access-run-001";
            store.createRun(runId);

            info = h5info(char(archivePath), '/runs/access-run-001');
            groupNames = cellfun(@(g) g(find(g == '/', 1, 'last')+1:end), ...
                {info.Groups.Name}, 'UniformOutput', false);

            expectedSubgroups = {'events', 'stats', 'scenario', 'agent', 'icam'};
            for i = 1:numel(expectedSubgroups)
                testCase.verifyTrue(ismember(expectedSubgroups{i}, groupNames), ...
                    sprintf('Run group must contain "%s" subgroup.', expectedSubgroups{i}));
            end
        end

        function testNumericDatasetsUseIEEE_F64LE(testCase)
            % Verify that numeric (double) datasets use H5T_IEEE_F64LE type.
            archivePath = fullfile(testCase.TempDir, 'accessibility_types.h5');
            store = data.SimulationStore(archivePath);
            runId = "types-run";
            store.createRun(runId);

            % Write events with numeric fields
            events(1).eventId = 1;
            events(1).simTimeSec = 10.5;
            events(1).eventType = "TX";
            events(2).eventId = 2;
            events(2).simTimeSec = 20.3;
            events(2).eventType = "RX";
            store.writeEvents(runId, events);

            % Use low-level HDF5 API to inspect numeric dataset type
            fileId = H5F.open(char(archivePath), 'H5F_ACC_RDONLY', 'H5P_DEFAULT');
            cleanupFile = onCleanup(@() H5F.close(fileId));

            dsetId = H5D.open(fileId, '/runs/types-run/events/simTimeSec');
            typeId = H5D.get_type(dsetId);
            cleanupType = onCleanup(@() H5T.close(typeId));
            cleanupDset = onCleanup(@() H5D.close(dsetId));

            % Verify it is a float type
            typeClass = H5T.get_class(typeId);
            testCase.verifyEqual(typeClass, H5ML.get_constant_value('H5T_FLOAT'), ...
                'Numeric datasets should use H5T_FLOAT class (IEEE floating point).');

            % Verify 64-bit precision (8 bytes)
            typeSize = H5T.get_size(typeId);
            testCase.verifyEqual(double(typeSize), 8, ...
                'Double datasets should be 8 bytes (64-bit IEEE float, i.e. H5T_IEEE_F64LE).');

            % Verify little-endian byte order
            order = H5T.get_order(typeId);
            testCase.verifyEqual(order, H5ML.get_constant_value('H5T_ORDER_LE'), ...
                'Numeric datasets should use little-endian byte order (H5T_IEEE_F64LE).');
        end

        function testStringDatasetsAreVariableLengthUTF8(testCase)
            % Verify that string datasets use variable-length UTF-8 encoding.
            archivePath = fullfile(testCase.TempDir, 'accessibility_strings.h5');
            store = data.SimulationStore(archivePath);
            runId = "strings-run";
            store.createRun(runId);

            % Write events with string fields
            events(1).eventId = 1;
            events(1).simTimeSec = 5.0;
            events(1).eventType = "TX";
            events(1).linkId = "link-alpha";
            events(2).eventId = 2;
            events(2).simTimeSec = 10.0;
            events(2).eventType = "RX";
            events(2).linkId = "link-bravo";
            store.writeEvents(runId, events);

            % Inspect string dataset type using low-level HDF5 API
            fileId = H5F.open(char(archivePath), 'H5F_ACC_RDONLY', 'H5P_DEFAULT');
            cleanupFile = onCleanup(@() H5F.close(fileId));

            dsetId = H5D.open(fileId, '/runs/strings-run/events/eventType');
            typeId = H5D.get_type(dsetId);
            cleanupType = onCleanup(@() H5T.close(typeId));
            cleanupDset = onCleanup(@() H5D.close(dsetId));

            % Verify it is a string type
            typeClass = H5T.get_class(typeId);
            testCase.verifyEqual(typeClass, H5ML.get_constant_value('H5T_STRING'), ...
                'String datasets should use H5T_STRING class.');

            % Verify variable-length
            isVarLen = H5T.is_variable_str(typeId);
            testCase.verifyTrue(logical(isVarLen), ...
                'String datasets should be variable-length.');

            % Verify UTF-8 character set
            cset = H5T.get_cset(typeId);
            testCase.verifyEqual(cset, H5ML.get_constant_value('H5T_CSET_UTF8'), ...
                'String datasets should use UTF-8 character set encoding.');
        end

    end
end
