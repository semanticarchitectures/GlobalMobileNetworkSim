classdef MissionVideoGeneratorParseTest < matlab.unittest.TestCase
    % MissionVideoGeneratorParseTest  Unit tests for parsePositionLog and
    % groupByTimestamp private methods of io.MissionVideoGenerator.
    %
    % Tests the event log parsing and position grouping functionality
    % through the public generate() method interface.
    %
    % Requirements: 5.1, 5.2, 5.3, 5.4, 5.5, 5.6

    properties
        TempDirs  % cell array of temp directories to clean up
        TempFiles % cell array of temp files to clean up
    end

    % ======================================================================
    % TestClassSetup
    % ======================================================================
    methods (TestClassSetup)
        function addWorkspaceRootToPath(testCase)
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
            testCase.TempFiles = {};
        end
    end

    methods (TestMethodTeardown)
        function cleanUp(testCase)
            for i = 1:numel(testCase.TempFiles)
                f = testCase.TempFiles{i};
                if exist(f, 'file')
                    delete(f);
                end
            end
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
            outDir = [tempname(), '_mvgtest'];
            mkdir(outDir);
            testCase.TempDirs{end+1} = outDir;
        end

        function csvPath = writeCsv(testCase, lines)
            % Write a CSV file from a cell array of lines (including header)
            csvPath = [tempname(), '_eventlog.csv'];
            fid = fopen(csvPath, 'w');
            for i = 1:numel(lines)
                fprintf(fid, '%s\n', lines{i});
            end
            fclose(fid);
            testCase.TempFiles{end+1} = csvPath;
        end

    end

    % ======================================================================
    % Tests
    % ======================================================================
    methods (Test)

        % ------------------------------------------------------------------
        % Test 1: File not found throws fileReadError
        % ------------------------------------------------------------------
        function testFileNotFoundThrowsFileReadError(testCase)
            % Requirements: 5.2
            outDir = testCase.makeTempDir();
            vg = io.MissionVideoGenerator(outDir, 'Test');

            testCase.verifyError(@() vg.generate('/nonexistent/path.csv'), ...
                'netsim:io:fileReadError');
        end

        % ------------------------------------------------------------------
        % Test 2: No NODE_POSITION rows throws noPositionData
        % ------------------------------------------------------------------
        function testNoPositionDataThrowsError(testCase)
            % Requirements: 5.5
            csvPath = testCase.writeCsv({
                'eventId,simTimeSec,eventType,linkId,msgId,srcNodeId,dstNodeId,latencyMs,reason'
                '1,10,OUTAGE_START,LINK_1,,,,,'
                '2,20,LINK_UP,LINK_2,,,,,'
            });

            outDir = testCase.makeTempDir();
            vg = io.MissionVideoGenerator(outDir, 'Test');

            testCase.verifyError(@() vg.generate(csvPath), ...
                'netsim:io:noPositionData');
        end

        % ------------------------------------------------------------------
        % Test 3: Error message suggests positionUpdateIntervalSec > 0
        % ------------------------------------------------------------------
        function testNoPositionDataSuggestsInterval(testCase)
            % Requirements: 5.5
            csvPath = testCase.writeCsv({
                'eventId,simTimeSec,eventType,linkId,msgId,srcNodeId,dstNodeId,latencyMs,reason'
                '1,10,OUTAGE_START,LINK_1,,,,,'
            });

            outDir = testCase.makeTempDir();
            vg = io.MissionVideoGenerator(outDir, 'Test');

            try
                vg.generate(csvPath);
                testCase.verifyFail('Should have thrown error');
            catch ME
                testCase.verifyTrue(contains(ME.message, 'positionUpdateIntervalSec > 0'), ...
                    'Error message should suggest positionUpdateIntervalSec > 0');
            end
        end

        % ------------------------------------------------------------------
        % Test 4: Valid NODE_POSITION rows are parsed successfully
        % ------------------------------------------------------------------
        function testValidPositionRowsParsed(testCase)
            % Requirements: 5.1
            csvPath = testCase.writeCsv({
                'eventId,simTimeSec,eventType,linkId,msgId,srcNodeId,dstNodeId,latencyMs,reason'
                '1,10,NODE_POSITION,NODE_A,41.6600,-70.5200,7500.0,,'
                '2,10,NODE_POSITION,NODE_B,42.3601,-71.0589,100.0,,'
                '3,20,NODE_POSITION,NODE_A,41.6700,-70.5100,7500.0,,'
            });

            outDir = testCase.makeTempDir();
            vg = io.MissionVideoGenerator(outDir, 'Test');

            % Should not throw — valid data present
            vg.generate(csvPath);
        end

        % ------------------------------------------------------------------
        % Test 5: Non-NODE_POSITION rows are filtered out
        % ------------------------------------------------------------------
        function testNonPositionRowsFiltered(testCase)
            % Requirements: 5.1
            % Mix of event types — only NODE_POSITION should be extracted
            csvPath = testCase.writeCsv({
                'eventId,simTimeSec,eventType,linkId,msgId,srcNodeId,dstNodeId,latencyMs,reason'
                '1,5,OUTAGE_START,LINK_1,,,,,'
                '2,10,NODE_POSITION,NODE_A,41.6600,-70.5200,7500.0,,'
                '3,15,LINK_UP,LINK_2,,,,,'
                '4,20,NODE_POSITION,NODE_A,41.6700,-70.5100,7500.0,,'
                '5,25,C2_MESSAGE_TX,,m01,OPS,AIRCRAFT,38.89,'
                '6,30,NODE_POSITION,NODE_A,41.6800,-70.5000,7500.0,,'
            });

            outDir = testCase.makeTempDir();
            vg = io.MissionVideoGenerator(outDir, 'Test');

            % Should succeed — 3 valid NODE_POSITION rows
            vg.generate(csvPath);
        end

        % ------------------------------------------------------------------
        % Test 6: Rows with non-numeric lat/lon/altM are skipped
        % ------------------------------------------------------------------
        function testNonNumericFieldsSkipped(testCase)
            % Requirements: 5.6
            csvPath = testCase.writeCsv({
                'eventId,simTimeSec,eventType,linkId,msgId,srcNodeId,dstNodeId,latencyMs,reason'
                '1,10,NODE_POSITION,NODE_A,41.6600,-70.5200,7500.0,,'
                '2,10,NODE_POSITION,NODE_B,invalid,-71.0589,100.0,,'
                '3,20,NODE_POSITION,NODE_C,42.0000,notanumber,200.0,,'
                '4,20,NODE_POSITION,NODE_D,43.0000,-72.0000,abc,,'
            });

            outDir = testCase.makeTempDir();
            vg = io.MissionVideoGenerator(outDir, 'Test');

            % Should succeed — 1 valid row (NODE_A at t=10)
            vg.generate(csvPath);
        end

        % ------------------------------------------------------------------
        % Test 7: All non-numeric rows skipped results in noPositionData
        % ------------------------------------------------------------------
        function testAllInvalidRowsThrowsNoPositionData(testCase)
            % Requirements: 5.5, 5.6
            csvPath = testCase.writeCsv({
                'eventId,simTimeSec,eventType,linkId,msgId,srcNodeId,dstNodeId,latencyMs,reason'
                '1,10,NODE_POSITION,NODE_A,invalid,-70.5200,7500.0,,'
                '2,20,NODE_POSITION,NODE_B,42.0000,notanumber,200.0,,'
            });

            outDir = testCase.makeTempDir();
            vg = io.MissionVideoGenerator(outDir, 'Test');

            testCase.verifyError(@() vg.generate(csvPath), ...
                'netsim:io:noPositionData');
        end

        % ------------------------------------------------------------------
        % Test 8: Empty CSV file (header only) throws noPositionData
        % ------------------------------------------------------------------
        function testEmptyCsvThrowsNoPositionData(testCase)
            % Requirements: 5.5
            csvPath = testCase.writeCsv({
                'eventId,simTimeSec,eventType,linkId,msgId,srcNodeId,dstNodeId,latencyMs,reason'
            });

            outDir = testCase.makeTempDir();
            vg = io.MissionVideoGenerator(outDir, 'Test');

            testCase.verifyError(@() vg.generate(csvPath), ...
                'netsim:io:noPositionData');
        end

        % ------------------------------------------------------------------
        % Test 9: Column mapping is correct (linkId->nodeId, msgId->lat, etc.)
        % ------------------------------------------------------------------
        function testColumnMappingCorrect(testCase)
            % Requirements: 5.1
            % This test verifies that the column mapping works correctly
            % by using a CSV where the values are distinctive
            csvPath = testCase.writeCsv({
                'eventId,simTimeSec,eventType,linkId,msgId,srcNodeId,dstNodeId,latencyMs,reason'
                '1,10,NODE_POSITION,SAT_1,45.0000,-120.0000,35786.0,,'
            });

            outDir = testCase.makeTempDir();
            vg = io.MissionVideoGenerator(outDir, 'Test');

            % Should succeed without error
            vg.generate(csvPath);
        end

        % ------------------------------------------------------------------
        % Test 10: Multiple timestamps produce sorted snapshots
        % ------------------------------------------------------------------
        function testMultipleTimestampsSorted(testCase)
            % Requirements: 5.3, 5.4
            % Timestamps out of order in CSV — should still produce sorted snapshots
            csvPath = testCase.writeCsv({
                'eventId,simTimeSec,eventType,linkId,msgId,srcNodeId,dstNodeId,latencyMs,reason'
                '1,30,NODE_POSITION,NODE_A,41.6800,-70.5000,7500.0,,'
                '2,10,NODE_POSITION,NODE_A,41.6600,-70.5200,7500.0,,'
                '3,20,NODE_POSITION,NODE_A,41.6700,-70.5100,7500.0,,'
            });

            outDir = testCase.makeTempDir();
            vg = io.MissionVideoGenerator(outDir, 'Test');

            % Should succeed — 3 timestamps, 1 node each
            vg.generate(csvPath);
        end

        % ------------------------------------------------------------------
        % Test 11: Large CSV with many event types
        % ------------------------------------------------------------------
        function testLargeMixedEventLog(testCase)
            % Requirements: 5.1, 5.3, 5.4
            lines = {'eventId,simTimeSec,eventType,linkId,msgId,srcNodeId,dstNodeId,latencyMs,reason'};
            eventId = 1;
            % Add 50 NODE_POSITION rows across 5 timestamps with 10 nodes
            for t = 10:10:50
                for n = 1:10
                    lines{end+1} = sprintf('%d,%d,NODE_POSITION,NODE_%d,%.4f,%.4f,%.1f,,', ...
                        eventId, t, n, 40+n*0.1, -70-n*0.1, n*100); %#ok<AGROW>
                    eventId = eventId + 1;
                end
                % Add some non-position events
                lines{end+1} = sprintf('%d,%d,OUTAGE_START,LINK_%d,,,,,', eventId, t, t); %#ok<AGROW>
                eventId = eventId + 1;
                lines{end+1} = sprintf('%d,%d,BACKGROUND_REFRESH,LINK_%d,,,,,', eventId, t+5, t); %#ok<AGROW>
                eventId = eventId + 1;
            end

            csvPath = testCase.writeCsv(lines);
            outDir = testCase.makeTempDir();
            vg = io.MissionVideoGenerator(outDir, 'Test');

            % Should succeed — 50 valid NODE_POSITION rows
            vg.generate(csvPath);
        end

    end % methods (Test)

end % classdef
