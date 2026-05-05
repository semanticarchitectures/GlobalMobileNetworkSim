classdef RoleLoaderTest < matlab.unittest.TestCase
    % RoleLoaderTest  Unit tests for agent.RoleLoader.
    %
    % Tests:
    %   1. testLoadValidRoleFile          — load aircrew_role.md, verify
    %                                       name=="Aircrew", sourceRef contains
    %                                       the file path, fullMarkdown is
    %                                       non-empty
    %   2. testLoadExtractsCorrectRoleName — verify name is exactly "Aircrew"
    %                                       (not "# Aircrew")
    %   3. testLoadReturnsFullMarkdown    — verify fullMarkdown contains
    %                                       "## Duties"
    %   4. testLoadNonExistentFileThrows  — verify throws
    %                                       netsim:agent:roleLoadError for a
    %                                       non-existent path
    %   5. testLoadEmptyFileThrows        — load empty_role.md, verify throws
    %                                       netsim:agent:roleLoadError
    %   6. testLoadFileWithNoH1Throws     — write a temp file with content but
    %                                       no H1 heading, verify throws
    %                                       netsim:agent:roleLoadError
    %
    % Requirements: 11.1, 11.2, 11.3, 11.4

    properties
        % Absolute path to the fixtures directory.
        FixturesDir
        % Temp files created during tests, cleaned up in teardown.
        TempFiles
    end

    % ======================================================================
    % TestClassSetup: ensure workspace root is on the MATLAB path
    % ======================================================================
    methods (TestClassSetup)
        function addWorkspaceRootToPath(testCase)
            % Determine the workspace root (two levels up from this file's
            % directory: tests/agent/ -> tests/ -> workspace root).
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
            testCase.FixturesDir = fullfile(thisDir, 'fixtures');
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

        function filePath = writeTempMarkdown(testCase, content)
            % Write content string to a temp .md file; register for cleanup.
            filePath = [tempname(), '.md'];
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
        % Test 1: load valid role file — name, sourceRef, fullMarkdown
        % ------------------------------------------------------------------
        function testLoadValidRoleFile(testCase)
            % load() should return a struct with name=="Aircrew", sourceRef
            % containing the file path, and non-empty fullMarkdown.
            %
            % Requirements: 11.1, 11.2, 11.3

            filePath = fullfile(testCase.FixturesDir, 'aircrew_role.md');
            role = agent.RoleLoader.load(filePath);

            testCase.verifyTrue(isstruct(role), ...
                'load() should return a struct');
            testCase.verifyEqual(role.name, "Aircrew", ...
                'name should be "Aircrew"');
            testCase.verifyTrue(contains(role.sourceRef, 'aircrew_role'), ...
                'sourceRef should contain the file path');
            testCase.verifyFalse(strlength(role.fullMarkdown) == 0, ...
                'fullMarkdown should be non-empty');
        end

        % ------------------------------------------------------------------
        % Test 2: extracted role name does not include the "# " prefix
        % ------------------------------------------------------------------
        function testLoadExtractsCorrectRoleName(testCase)
            % The name field should be exactly "Aircrew", not "# Aircrew".
            %
            % Requirements: 11.2

            filePath = fullfile(testCase.FixturesDir, 'aircrew_role.md');
            role = agent.RoleLoader.load(filePath);

            testCase.verifyEqual(role.name, "Aircrew", ...
                'name should be exactly "Aircrew" without the "# " prefix');
            testCase.verifyFalse(startsWith(role.name, '#'), ...
                'name must not start with "#"');
        end

        % ------------------------------------------------------------------
        % Test 3: fullMarkdown contains the full file content
        % ------------------------------------------------------------------
        function testLoadReturnsFullMarkdown(testCase)
            % fullMarkdown should contain "## Duties" from the fixture file.
            %
            % Requirements: 11.3

            filePath = fullfile(testCase.FixturesDir, 'aircrew_role.md');
            role = agent.RoleLoader.load(filePath);

            testCase.verifyTrue(contains(role.fullMarkdown, '## Duties'), ...
                'fullMarkdown should contain "## Duties"');
        end

        % ------------------------------------------------------------------
        % Test 4: non-existent file throws netsim:agent:roleLoadError
        % ------------------------------------------------------------------
        function testLoadNonExistentFileThrows(testCase)
            % load() should throw netsim:agent:roleLoadError for a path that
            % does not exist.
            %
            % Requirements: 11.4

            nonExistentPath = fullfile(testCase.FixturesDir, 'does_not_exist.md');

            testCase.verifyError( ...
                @() agent.RoleLoader.load(nonExistentPath), ...
                'netsim:agent:roleLoadError', ...
                'Non-existent file should throw netsim:agent:roleLoadError');
        end

        % ------------------------------------------------------------------
        % Test 5: empty file throws netsim:agent:roleLoadError
        % ------------------------------------------------------------------
        function testLoadEmptyFileThrows(testCase)
            % load() should throw netsim:agent:roleLoadError for an empty file.
            %
            % Requirements: 11.4

            emptyFilePath = fullfile(testCase.FixturesDir, 'empty_role.md');

            testCase.verifyError( ...
                @() agent.RoleLoader.load(emptyFilePath), ...
                'netsim:agent:roleLoadError', ...
                'Empty file should throw netsim:agent:roleLoadError');
        end

        % ------------------------------------------------------------------
        % Test 6: file with no H1 heading throws netsim:agent:roleLoadError
        % ------------------------------------------------------------------
        function testLoadFileWithNoH1Throws(testCase)
            % load() should throw netsim:agent:roleLoadError when the file has
            % content but no H1 heading (no line starting with "# ").
            %
            % Requirements: 11.2, 11.4

            content = sprintf('## Section Without H1\n\nSome content here.\n\n### Subsection\nMore content.');
            tmpFile = testCase.writeTempMarkdown(content);

            testCase.verifyError( ...
                @() agent.RoleLoader.load(tmpFile), ...
                'netsim:agent:roleLoadError', ...
                'File with no H1 heading should throw netsim:agent:roleLoadError');
        end

    end % methods (Test)

end % classdef
