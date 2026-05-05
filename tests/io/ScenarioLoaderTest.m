classdef ScenarioLoaderTest < matlab.unittest.TestCase
    % ScenarioLoaderTest  Unit tests for io.ScenarioLoader.
    %
    % Tests:
    %   1. testLoadFixtureSucceeds        — load simple_scenario.json, verify
    %                                       scenarioName=="SimpleTest" and
    %                                       simulationDurationSec==3600
    %   2. testLoadFixtureNodeCount       — verify numel(scenario.nodes)==2
    %   3. testLoadFixtureLinkCount       — verify numel(scenario.links)==1
    %   4. testRoundTrip                  — load, save to temp, reload, verify
    %                                       scenarioName matches
    %   5. testLoadInvalidJsonThrows      — write "{bad json", verify throws
    %                                       netsim:io:jsonSyntaxError
    %   6. testLoadMissingSimDurationThrows — write JSON without
    %                                       simulationDurationSec, verify throws
    %                                       netsim:io:missingField
    %   7. testLoadInvalidKeplerElementsThrows — node with keplerElements
    %                                       missing eccentricity, verify throws
    %                                       netsim:node:invalidKeplerElements
    %   8. testLoadReferenceBehaviorFixture — load reference_behavior.json,
    %                                       verify scenarioName=="SimpleTest"
    %                                       and numel(roles)==2
    %   9. testReferenceBehaviorRoundTrip — load, save to temp, reload, verify
    %                                       scenarioName matches
    %  10. testLoadReferenceBehaviorMissingFieldThrows — JSON without 'roles'
    %                                       field throws netsim:io:missingField
    %
    % Requirements: 7.1, 7.2, 7.3, 7.4, 1.4, 2.7, 3.5, 10.4, 14.1, 14.2,
    %               14.3, 14.4, 14.5

    properties
        % Absolute path to the fixture file, computed from this file's location.
        FixturePath
        % Temp files created during tests, cleaned up in teardown.
        TempFiles
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
            thisDir = fileparts(mfilename('fullpath'));
            testCase.FixturePath = fullfile(thisDir, 'fixtures', 'simple_scenario.json');
            testCase.TempFiles = {};
        end
    end

    methods (TestMethodTeardown)
        function cleanUpTempFiles(testCase)
            for i = 1:numel(testCase.TempFiles)
                f = testCase.TempFiles{i};
                if exist(f, 'file')
                    delete(f);
                end
            end
        end
    end

    % ======================================================================
    % Private helpers
    % ======================================================================
    methods (Access = private)

        function filePath = writeTempJson(testCase, content)
            % Write content string to a temp .json file; register for cleanup.
            filePath = [tempname(), '.json'];
            fid = fopen(filePath, 'w');
            testCase.assertNotEqual(fid, -1, 'Could not open temp file for writing');
            fwrite(fid, content, 'char');
            fclose(fid);
            testCase.TempFiles{end+1} = filePath;
        end

    end

    % ======================================================================
    % Tests
    % ======================================================================
    methods (Test)

        % ------------------------------------------------------------------
        % Test 1: load fixture succeeds — scenarioName and simulationDurationSec
        % ------------------------------------------------------------------
        function testLoadFixtureSucceeds(testCase)
            % load() should return a struct with the correct top-level fields.
            %
            % Requirements: 7.1, 7.2

            scenario = io.ScenarioLoader.load(testCase.FixturePath);

            testCase.verifyTrue(isstruct(scenario), ...
                'load() should return a struct');
            testCase.verifyEqual(string(scenario.scenarioName), "SimpleTest", ...
                'scenarioName should be "SimpleTest"');
            testCase.verifyEqual(scenario.simulationDurationSec, 3600, ...
                'simulationDurationSec should be 3600');
        end

        % ------------------------------------------------------------------
        % Test 2: fixture node count
        % ------------------------------------------------------------------
        function testLoadFixtureNodeCount(testCase)
            % load() should return a scenario with exactly 2 nodes.
            %
            % Requirements: 7.1, 7.2

            scenario = io.ScenarioLoader.load(testCase.FixturePath);

            testCase.verifyEqual(numel(scenario.nodes), 2, ...
                'Fixture should contain 2 nodes');
        end

        % ------------------------------------------------------------------
        % Test 3: fixture link count
        % ------------------------------------------------------------------
        function testLoadFixtureLinkCount(testCase)
            % load() should return a scenario with exactly 1 link.
            %
            % Requirements: 7.1, 7.2

            scenario = io.ScenarioLoader.load(testCase.FixturePath);

            testCase.verifyEqual(numel(scenario.links), 1, ...
                'Fixture should contain 1 link');
        end

        % ------------------------------------------------------------------
        % Test 4: round-trip — load, save, reload, verify scenarioName
        % ------------------------------------------------------------------
        function testRoundTrip(testCase)
            % save() followed by load() should preserve scenarioName.
            %
            % Requirements: 7.4, 7.5

            original = io.ScenarioLoader.load(testCase.FixturePath);

            tmpFile = [tempname(), '.json'];
            testCase.TempFiles{end+1} = tmpFile;

            io.ScenarioLoader.save(original, tmpFile);
            reloaded = io.ScenarioLoader.load(tmpFile);

            testCase.verifyEqual(string(reloaded.scenarioName), ...
                string(original.scenarioName), ...
                'Round-trip: scenarioName should be preserved');
        end

        % ------------------------------------------------------------------
        % Test 5: invalid JSON throws netsim:io:jsonSyntaxError
        % ------------------------------------------------------------------
        function testLoadInvalidJsonThrows(testCase)
            % load() should throw netsim:io:jsonSyntaxError for malformed JSON.
            %
            % Requirements: 7.3

            tmpFile = testCase.writeTempJson('{bad json');

            testCase.verifyError(@() io.ScenarioLoader.load(tmpFile), ...
                'netsim:io:jsonSyntaxError', ...
                'Malformed JSON should throw netsim:io:jsonSyntaxError');
        end

        % ------------------------------------------------------------------
        % Test 6: missing simulationDurationSec throws netsim:io:missingField
        % ------------------------------------------------------------------
        function testLoadMissingSimDurationThrows(testCase)
            % load() should throw netsim:io:missingField when
            % simulationDurationSec is absent.
            %
            % Requirements: 7.2

            jsonContent = '{"scenarioName": "TestScenario"}';
            tmpFile = testCase.writeTempJson(jsonContent);

            testCase.verifyError(@() io.ScenarioLoader.load(tmpFile), ...
                'netsim:io:missingField', ...
                'Missing simulationDurationSec should throw netsim:io:missingField');
        end

        % ------------------------------------------------------------------
        % Test 7: keplerElements missing eccentricity throws
        %         netsim:node:invalidKeplerElements
        % ------------------------------------------------------------------
        function testLoadInvalidKeplerElementsThrows(testCase)
            % load() should throw netsim:node:invalidKeplerElements when a
            % node's keplerElements is missing the 'eccentricity' field.
            %
            % Requirements: 10.4

            jsonContent = [ ...
                '{', ...
                '"scenarioName": "SatTest",', ...
                '"simulationDurationSec": 3600,', ...
                '"nodes": [{', ...
                '  "id": "sat1",', ...
                '  "type": "Mobile",', ...
                '  "lat": 0, "lon": 0, "altM": 0,', ...
                '  "trajectory": null,', ...
                '  "keplerElements": {', ...
                '    "semiMajorAxisM": 6778000,', ...
                '    "inclinationDeg": 53.0,', ...
                '    "raanDeg": 0.0,', ...
                '    "argPeriapsisDeg": 0.0,', ...
                '    "trueAnomalyDeg": 0.0,', ...
                '    "epochSec": 0.0', ...
                '  }', ...
                '}]', ...
                '}' ...
            ];
            tmpFile = testCase.writeTempJson(jsonContent);

            testCase.verifyError(@() io.ScenarioLoader.load(tmpFile), ...
                'netsim:node:invalidKeplerElements', ...
                'Missing eccentricity should throw netsim:node:invalidKeplerElements');
        end

        % ------------------------------------------------------------------
        % Test 8: loadReferenceBehavior loads fixture correctly
        % ------------------------------------------------------------------
        function testLoadReferenceBehaviorFixture(testCase)
            % loadReferenceBehavior() should parse reference_behavior.json and
            % return a struct with scenarioName=="SimpleTest" and 2 roles.
            %
            % Requirements: 14.1, 14.3

            thisDir = fileparts(mfilename('fullpath'));
            refFixturePath = fullfile(thisDir, 'fixtures', 'reference_behavior.json');

            refBehavior = io.ScenarioLoader.loadReferenceBehavior(refFixturePath);

            testCase.verifyTrue(isstruct(refBehavior), ...
                'loadReferenceBehavior() should return a struct');
            testCase.verifyEqual(string(refBehavior.scenarioName), "SimpleTest", ...
                'scenarioName should be "SimpleTest"');
            testCase.verifyEqual(numel(refBehavior.roles), 2, ...
                'Fixture should contain 2 roles');
        end

        % ------------------------------------------------------------------
        % Test 9: reference behavior round-trip
        % ------------------------------------------------------------------
        function testReferenceBehaviorRoundTrip(testCase)
            % saveReferenceBehavior() followed by loadReferenceBehavior() should
            % preserve scenarioName.
            %
            % Requirements: 14.3, 14.5

            thisDir = fileparts(mfilename('fullpath'));
            refFixturePath = fullfile(thisDir, 'fixtures', 'reference_behavior.json');

            original = io.ScenarioLoader.loadReferenceBehavior(refFixturePath);

            tmpFile = [tempname(), '.json'];
            testCase.TempFiles{end+1} = tmpFile;

            io.ScenarioLoader.saveReferenceBehavior(original, tmpFile);
            reloaded = io.ScenarioLoader.loadReferenceBehavior(tmpFile);

            testCase.verifyEqual(string(reloaded.scenarioName), ...
                string(original.scenarioName), ...
                'Round-trip: scenarioName should be preserved');
        end

        % ------------------------------------------------------------------
        % Test 10: loadReferenceBehavior with missing 'roles' field throws
        %          netsim:io:missingField
        % ------------------------------------------------------------------
        function testLoadReferenceBehaviorMissingFieldThrows(testCase)
            % loadReferenceBehavior() should throw netsim:io:missingField when
            % the JSON is missing the required 'roles' field.
            %
            % Requirements: 14.1, 14.3

            jsonContent = '{"scenarioName": "TestScenario"}';
            tmpFile = testCase.writeTempJson(jsonContent);

            testCase.verifyError( ...
                @() io.ScenarioLoader.loadReferenceBehavior(tmpFile), ...
                'netsim:io:missingField', ...
                'Missing roles field should throw netsim:io:missingField');
        end

    end % methods (Test)

end % classdef
