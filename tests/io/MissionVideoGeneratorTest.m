classdef MissionVideoGeneratorTest < matlab.unittest.TestCase
    % MissionVideoGeneratorTest  Unit tests for io.MissionVideoGenerator.
    %
    % Tests constructor, configuration validation, output path construction,
    % directory creation, error conditions, basemap caching, figure visibility,
    % and end-to-end video generation with a small synthetic event log.
    %
    % Requirements: 7.1, 7.2, 7.4, 7.5, 5.2, 5.5, 8.1, 8.6

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

        function csvPath = writeSyntheticEventLog(testCase, numNodes, numTimestamps, intervalSec)
            % Generate a synthetic event log CSV with NODE_POSITION data.
            % Nodes are placed in a grid pattern around lat=40, lon=-70.
            header = 'eventId,simTimeSec,eventType,linkId,msgId,srcNodeId,dstNodeId,latencyMs,reason';
            lines = {header};
            eventId = 1;
            for t = 1:numTimestamps
                simTime = t * intervalSec;
                for n = 1:numNodes
                    lat = 40 + n * 0.5;
                    lon = -70 + t * 0.1;
                    alt = 100.0 * n;
                    lines{end+1} = sprintf('%d,%d,NODE_POSITION,NODE_%d,%.4f,%.4f,%.1f,,', ...
                        eventId, simTime, n, lat, lon, alt); %#ok<AGROW>
                    eventId = eventId + 1;
                end
            end
            csvPath = testCase.writeCsv(lines);
        end

    end

    % ======================================================================
    % Tests: Constructor and Configuration
    % ======================================================================
    methods (Test)

        % ------------------------------------------------------------------
        % Test: Constructor with default config values
        % Requirements: 7.1, 7.2
        % ------------------------------------------------------------------
        function testConstructorDefaultConfig(testCase)
            outDir = testCase.makeTempDir();
            vg = io.MissionVideoGenerator(outDir, 'TestScenario');

            % Verify output path uses default naming convention
            expectedPath = fullfile(outDir, 'TestScenario_mission_video.mp4');
            testCase.verifyEqual(vg.buildOutputPath(), expectedPath);
        end

        % ------------------------------------------------------------------
        % Test: Constructor with custom config
        % Requirements: 7.1, 7.2
        % ------------------------------------------------------------------
        function testConstructorCustomConfig(testCase)
            outDir = testCase.makeTempDir();
            cfg = struct('frameRate', 15, 'speedupFactor', 30, ...
                         'resolution', [1280 720], 'showLinks', false);
            vg = io.MissionVideoGenerator(outDir, 'CustomTest', cfg);

            % Should construct without error
            testCase.verifyNotEmpty(vg);
            testCase.verifyEqual(vg.buildOutputPath(), ...
                fullfile(outDir, 'CustomTest_mission_video.mp4'));
        end

        % ------------------------------------------------------------------
        % Test: outputDir/scenarioName storage via buildOutputPath
        % Requirements: 8.2, 8.6
        % ------------------------------------------------------------------
        function testOutputPathConstruction(testCase)
            outDir = testCase.makeTempDir();
            vg = io.MissionVideoGenerator(outDir, 'DragonCartImproved');

            expected = fullfile(outDir, 'DragonCartImproved_mission_video.mp4');
            testCase.verifyEqual(vg.buildOutputPath(), expected);
        end

        % ------------------------------------------------------------------
        % Test: Directory creation on construction
        % Requirements: 8.3
        % ------------------------------------------------------------------
        function testDirectoryCreationOnConstruction(testCase)
            baseDir = testCase.makeTempDir();
            newDir = fullfile(baseDir, 'new_subdir', 'output');
            testCase.TempDirs{end+1} = newDir;

            vg = io.MissionVideoGenerator(newDir, 'Test'); %#ok<NASGU>

            testCase.verifyTrue(exist(newDir, 'dir') == 7, ...
                'Constructor should create output directory if it does not exist');
        end

        % ------------------------------------------------------------------
        % Test: Error on missing CSV file
        % Requirements: 5.2
        % ------------------------------------------------------------------
        function testErrorOnMissingCsvFile(testCase)
            outDir = testCase.makeTempDir();
            vg = io.MissionVideoGenerator(outDir, 'Test');

            testCase.verifyError(@() vg.generate('/nonexistent/path/file.csv'), ...
                'netsim:io:fileReadError');
        end

        % ------------------------------------------------------------------
        % Test: Error on empty position data
        % Requirements: 5.5
        % ------------------------------------------------------------------
        function testErrorOnEmptyPositionData(testCase)
            csvPath = testCase.writeCsv({
                'eventId,simTimeSec,eventType,linkId,msgId,srcNodeId,dstNodeId,latencyMs,reason'
                '1,10,OUTAGE_START,LINK_1,,,,,'
            });

            outDir = testCase.makeTempDir();
            vg = io.MissionVideoGenerator(outDir, 'Test');

            testCase.verifyError(@() vg.generate(csvPath), ...
                'netsim:io:noPositionData');
        end

        % ------------------------------------------------------------------
        % Test: Error on invalid frameRate
        % Requirements: 7.4, 7.5
        % ------------------------------------------------------------------
        function testInvalidFrameRateTooLow(testCase)
            outDir = testCase.makeTempDir();
            cfg = struct('frameRate', 0);

            testCase.verifyError(...
                @() io.MissionVideoGenerator(outDir, 'Test', cfg), ...
                'netsim:io:invalidConfig');
        end

        function testInvalidFrameRateTooHigh(testCase)
            outDir = testCase.makeTempDir();
            cfg = struct('frameRate', 121);

            testCase.verifyError(...
                @() io.MissionVideoGenerator(outDir, 'Test', cfg), ...
                'netsim:io:invalidConfig');
        end

        function testInvalidFrameRateNonInteger(testCase)
            outDir = testCase.makeTempDir();
            cfg = struct('frameRate', 15.5);

            testCase.verifyError(...
                @() io.MissionVideoGenerator(outDir, 'Test', cfg), ...
                'netsim:io:invalidConfig');
        end

        % ------------------------------------------------------------------
        % Test: Error on invalid speedupFactor
        % Requirements: 7.4, 7.5
        % ------------------------------------------------------------------
        function testInvalidSpeedupFactorTooLow(testCase)
            outDir = testCase.makeTempDir();
            cfg = struct('speedupFactor', 0.05);

            testCase.verifyError(...
                @() io.MissionVideoGenerator(outDir, 'Test', cfg), ...
                'netsim:io:invalidConfig');
        end

        function testInvalidSpeedupFactorTooHigh(testCase)
            outDir = testCase.makeTempDir();
            cfg = struct('speedupFactor', 1001);

            testCase.verifyError(...
                @() io.MissionVideoGenerator(outDir, 'Test', cfg), ...
                'netsim:io:invalidConfig');
        end

        % ------------------------------------------------------------------
        % Test: Error on invalid resolution
        % Requirements: 7.4, 7.5
        % ------------------------------------------------------------------
        function testInvalidResolutionWrongSize(testCase)
            outDir = testCase.makeTempDir();
            cfg = struct('resolution', [1920 1080 3]);

            testCase.verifyError(...
                @() io.MissionVideoGenerator(outDir, 'Test', cfg), ...
                'netsim:io:invalidConfig');
        end

        function testInvalidResolutionWidthTooLarge(testCase)
            outDir = testCase.makeTempDir();
            cfg = struct('resolution', [7681 1080]);

            testCase.verifyError(...
                @() io.MissionVideoGenerator(outDir, 'Test', cfg), ...
                'netsim:io:invalidConfig');
        end

        function testInvalidResolutionHeightTooLarge(testCase)
            outDir = testCase.makeTempDir();
            cfg = struct('resolution', [1920 4321]);

            testCase.verifyError(...
                @() io.MissionVideoGenerator(outDir, 'Test', cfg), ...
                'netsim:io:invalidConfig');
        end

        function testInvalidResolutionNonInteger(testCase)
            outDir = testCase.makeTempDir();
            cfg = struct('resolution', [1920.5 1080]);

            testCase.verifyError(...
                @() io.MissionVideoGenerator(outDir, 'Test', cfg), ...
                'netsim:io:invalidConfig');
        end

        % ------------------------------------------------------------------
        % Test: Error on invalid showLinks
        % Requirements: 7.4, 7.5
        % ------------------------------------------------------------------
        function testInvalidShowLinksNonLogical(testCase)
            outDir = testCase.makeTempDir();
            cfg = struct('showLinks', 'yes');

            testCase.verifyError(...
                @() io.MissionVideoGenerator(outDir, 'Test', cfg), ...
                'netsim:io:invalidConfig');
        end

        % ------------------------------------------------------------------
        % Test: Error message contains field name
        % Requirements: 7.5
        % ------------------------------------------------------------------
        function testInvalidConfigErrorContainsFieldName(testCase)
            outDir = testCase.makeTempDir();
            cfg = struct('frameRate', -5);

            try
                io.MissionVideoGenerator(outDir, 'Test', cfg);
                testCase.verifyFail('Should have thrown error');
            catch ME
                testCase.verifyTrue(contains(ME.message, 'frameRate'), ...
                    'Error message should contain the invalid field name "frameRate"');
            end
        end

        % ------------------------------------------------------------------
        % Test: Basemap caching — constructor succeeds when cached files exist
        % Requirements: 2.3
        % ------------------------------------------------------------------
        function testBasemapCachingFromDisk(testCase)
            % The data/ directory should already have cached GeoJSON files
            % from previous runs. Verify constructor doesn't fail when
            % loading from cache.
            outDir = testCase.makeTempDir();

            % This should succeed — basemap data is loaded from cache in data/
            vg = io.MissionVideoGenerator(outDir, 'CacheTest');
            testCase.verifyNotEmpty(vg);
        end

        % ------------------------------------------------------------------
        % Test: Figure visibility off during rendering
        % Requirements: 3.1
        % ------------------------------------------------------------------
        function testFigureVisibilityOff(testCase)
            % Generate a small CSV and verify figure is not visible
            csvPath = testCase.writeSyntheticEventLog(2, 2, 10);
            outDir = testCase.makeTempDir();
            cfg = struct('frameRate', 2, 'speedupFactor', 50, ...
                         'resolution', [320 240]);
            vg = io.MissionVideoGenerator(outDir, 'VisTest', cfg);

            % Count visible figures before
            figsBefore = findall(0, 'Type', 'figure', 'Visible', 'on');
            numBefore = numel(figsBefore);

            % Generate video — figure should remain invisible
            vg.generate(csvPath);

            % Verify no new visible figures were left open
            figsAfter = findall(0, 'Type', 'figure', 'Visible', 'on');
            numAfter = numel(figsAfter);
            testCase.verifyEqual(numAfter, numBefore, ...
                'No visible figures should be left open after video generation');
        end

        % ------------------------------------------------------------------
        % Test: End-to-end with small synthetic event log
        % (5 nodes, 10 timestamps at 10s intervals)
        % Requirements: 4.1, 4.4, 8.2
        % ------------------------------------------------------------------
        function testEndToEndSmallSyntheticVideo(testCase)
            % Create synthetic event log: 5 nodes, 10 timestamps, 10s interval
            csvPath = testCase.writeSyntheticEventLog(5, 10, 10);
            outDir = testCase.makeTempDir();

            % Use speedupFactor=50, frameRate=2 to keep it fast
            cfg = struct('frameRate', 2, 'speedupFactor', 50, ...
                         'resolution', [320 240]);
            vg = io.MissionVideoGenerator(outDir, 'SyntheticTest', cfg);

            % Generate video
            vg.generate(csvPath);

            % Verify MP4 file was created
            outputPath = vg.buildOutputPath();
            testCase.verifyTrue(exist(outputPath, 'file') == 2, ...
                'MP4 file should be created after successful generation');

            % Verify file has non-zero size
            fileInfo = dir(outputPath);
            testCase.verifyGreaterThan(fileInfo.bytes, 0, ...
                'MP4 file should have non-zero size');

            % Clean up the generated video file
            testCase.TempFiles{end+1} = outputPath;
        end

    end % methods (Test)

end % classdef
