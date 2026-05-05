classdef BehaviorTracerTest < matlab.unittest.TestCase
    % BehaviorTracerTest  Unit tests for agent.BehaviorTracer.
    %
    % Tests:
    %   1. testConstructorCreatesEmptyTrace   - new tracer has empty trace (height 0)
    %   2. testRecordAppendsRow               - after one record() call, trace has 1 row
    %   3. testRecordMultipleRows             - after 3 record() calls, trace has 3 rows
    %   4. testRecordStoresCorrectValues      - verify simTimeSec, actionType,
    %                                          targetAgentId, msgId stored correctly
    %   5. testGetTraceReturnsTable           - getTrace() returns a MATLAB table
    %   6. testExportCSVCreatesFile           - exportCSV creates a file at the given path
    %   7. testExportCSVHasCorrectHeader      - first line of CSV is the canonical header
    %   8. testExportCSVHasCorrectDataRow     - after one record, CSV has header + one
    %                                          data row with correct values
    %   9. testExportCSVEmptyTrace            - empty trace exports header only
    %
    % Requirements: 13.3, 16.2

    properties
        TempFiles
    end

    methods (TestClassSetup)
        function addWorkspaceRootToPath(testCase)
            thisDir = fileparts(mfilename('fullpath'));
            rootDir = fileparts(fileparts(thisDir));
            addpath(rootDir);
            testCase.addTeardown(@() rmpath(rootDir));
        end
    end

    methods (TestMethodSetup)
        function setUp(testCase)
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

    methods (Access = private)
        function filePath = makeTempCSV(testCase)
            filePath = [tempname(), '.csv'];
            testCase.TempFiles{end+1} = filePath;
        end
    end

    methods (Test)

        function testConstructorCreatesEmptyTrace(testCase)
            % A newly constructed BehaviorTracer should have an empty trace
            % (height 0).
            %
            % Requirements: 13.3
            bt = agent.BehaviorTracer('agent1', 'Aircrew');
            trace = bt.getTrace();
            testCase.verifyEqual(height(trace), 0, ...
                'New tracer should have an empty trace with height 0');
        end

        function testRecordAppendsRow(testCase)
            % After one record() call the trace should have exactly 1 row.
            %
            % Requirements: 13.3
            bt = agent.BehaviorTracer('agent1', 'Aircrew');
            bt.record(10.0, uint64(1), 'SEND_STATUS', 'agent2', 'msg001');
            trace = bt.getTrace();
            testCase.verifyEqual(height(trace), 1, ...
                'Trace should have 1 row after one record() call');
        end

        function testRecordMultipleRows(testCase)
            % After 3 record() calls the trace should have exactly 3 rows.
            %
            % Requirements: 13.3
            bt = agent.BehaviorTracer('agent1', 'Aircrew');
            bt.record(10.0, uint64(1), 'SEND_STATUS',       'agent2', 'msg001');
            bt.record(20.0, uint64(2), 'ACKNOWLEDGE',        'agent3', 'msg002');
            bt.record(30.0, uint64(3), 'REQUEST_CLEARANCE',  '',       '');
            trace = bt.getTrace();
            testCase.verifyEqual(height(trace), 3, ...
                'Trace should have 3 rows after three record() calls');
        end

        function testRecordStoresCorrectValues(testCase)
            % Verify that simTimeSec, actionType, targetAgentId, and msgId
            % are stored with the values supplied to record().
            %
            % Requirements: 13.3
            bt = agent.BehaviorTracer('pilotA', 'Aircrew');
            bt.record(42.5, uint64(99), 'REQUEST_CLEARANCE', 'controlB', 'msg007');
            trace = bt.getTrace();

            testCase.verifyEqual(trace.simTimeSec(1), 42.5, ...
                'simTimeSec should be 42.5');
            testCase.verifyEqual(trace.actionType(1), "REQUEST_CLEARANCE", ...
                'actionType should be "REQUEST_CLEARANCE"');
            testCase.verifyEqual(trace.targetAgentId(1), "controlB", ...
                'targetAgentId should be "controlB"');
            testCase.verifyEqual(trace.msgId(1), "msg007", ...
                'msgId should be "msg007"');
        end

        function testGetTraceReturnsTable(testCase)
            % getTrace() should return a MATLAB table.
            %
            % Requirements: 13.3
            bt = agent.BehaviorTracer('agent1', 'Aircrew');
            trace = bt.getTrace();
            testCase.verifyTrue(istable(trace), ...
                'getTrace() should return a MATLAB table');
        end

        function testExportCSVCreatesFile(testCase)
            % exportCSV should create a file at the specified path.
            %
            % Requirements: 16.2
            bt = agent.BehaviorTracer('agent1', 'Aircrew');
            filePath = testCase.makeTempCSV();
            bt.exportCSV(filePath);
            testCase.verifyTrue(isfile(filePath), ...
                'exportCSV should create a file at the given path');
        end

        function testExportCSVHasCorrectHeader(testCase)
            % The first line of the exported CSV should be the canonical header.
            %
            % Requirements: 16.2
            bt = agent.BehaviorTracer('agent1', 'Aircrew');
            filePath = testCase.makeTempCSV();
            bt.exportCSV(filePath);

            fid = fopen(filePath, 'r');
            firstLine = fgetl(fid);
            fclose(fid);

            testCase.verifyEqual(firstLine, ...
                'simTimeSec,agentId,role,actionType,targetAgentId,msgId', ...
                'First line of CSV should be the canonical header');
        end

        function testExportCSVHasCorrectDataRow(testCase)
            % After one record() call the CSV should contain the header plus
            % one data row with the correct field values.
            %
            % Requirements: 16.2
            bt = agent.BehaviorTracer('pilotA', 'Aircrew');
            bt.record(15.0, uint64(5), 'SEND_STATUS', 'groundB', 'msg010');
            filePath = testCase.makeTempCSV();
            bt.exportCSV(filePath);

            fid = fopen(filePath, 'r');
            header   = fgetl(fid);  %#ok<NASGU>
            dataLine = fgetl(fid);
            fclose(fid);

            testCase.verifyFalse(isequal(dataLine, -1), ...
                'CSV should contain a data row after one record() call');

            parts = strsplit(dataLine, ',');
            testCase.verifyEqual(numel(parts), 6, ...
                'Data row should have 6 comma-separated fields');
            testCase.verifyEqual(str2double(parts{1}), 15.0, ...
                'First field (simTimeSec) should be 15.0');
            testCase.verifyEqual(parts{2}, 'pilotA', ...
                'Second field (agentId) should be "pilotA"');
            testCase.verifyEqual(parts{3}, 'Aircrew', ...
                'Third field (role) should be "Aircrew"');
            testCase.verifyEqual(parts{4}, 'SEND_STATUS', ...
                'Fourth field (actionType) should be "SEND_STATUS"');
            testCase.verifyEqual(parts{5}, 'groundB', ...
                'Fifth field (targetAgentId) should be "groundB"');
            testCase.verifyEqual(parts{6}, 'msg010', ...
                'Sixth field (msgId) should be "msg010"');
        end

        function testExportCSVEmptyTrace(testCase)
            % An empty trace should export a file containing only the header.
            %
            % Requirements: 16.2
            bt = agent.BehaviorTracer('agent1', 'Aircrew');
            filePath = testCase.makeTempCSV();
            bt.exportCSV(filePath);

            fid = fopen(filePath, 'r');
            header    = fgetl(fid);  %#ok<NASGU>
            secondLine = fgetl(fid);
            fclose(fid);

            testCase.verifyEqual(secondLine, -1, ...
                'Empty trace CSV should contain only the header (no data rows)');
        end

    end % methods (Test)

end % classdef
