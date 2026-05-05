classdef FidelityEvaluatorTest < matlab.unittest.TestCase
    % FidelityEvaluatorTest  Unit tests for agent.FidelityEvaluator.
    %
    % Tests:
    %   1. testPerfectMatch                  — all required actions present → score == 1.0
    %   2. testNoMatchUnordered              — no required actions present → score == 0.0
    %   3. testPartialMatchUnordered         — half required actions present → score == 0.5
    %   4. testEmptyReferenceActions         — empty required actions → score == 1.0
    %   5. testNetworkConstrainedAnnotation  — missing action with C2_MESSAGE_FAIL → 'network-constrained'
    %   6. testAgentFailureAnnotation        — missing action, no C2_MESSAGE_FAIL → 'agent-failure'
    %   7. testFidelityScoreInRange          — fidelityScore always in [0, 1]
    %   8. testStrictOrderingPerfectMatch    — strict, correct order → score == 1.0
    %   9. testStrictOrderingWrongOrder      — strict, wrong order → score < 1.0
    %
    % Requirements: 15.1, 15.2, 15.3, 15.4

    methods (TestClassSetup)
        function addWorkspaceRootToPath(testCase)
            thisDir = fileparts(mfilename('fullpath'));
            rootDir = fileparts(fileparts(thisDir));
            addpath(rootDir);
            testCase.addTeardown(@() rmpath(rootDir));
        end
    end

    % ======================================================================
    % Helper factory methods
    % ======================================================================
    methods (Access = private)

        function refBehavior = makeRefBehavior(~, roleName, ordering, actionTypes, expectedTimes)
            % makeRefBehavior  Build a minimal referenceBehavior struct.
            %
            % actionTypes — cell array of strings
            % expectedTimes — numeric vector (same length as actionTypes)

            nActions = numel(actionTypes);
            if nActions == 0
                actions = struct('actionType', {}, 'triggerEvent', {}, ...
                    'expectedTimeSec', {});
            else
                actions(nActions) = struct('actionType', '', ...
                    'triggerEvent', '', 'expectedTimeSec', 0);
                for k = 1:nActions
                    actions(k).actionType      = actionTypes{k};
                    actions(k).triggerEvent    = 'EVT';
                    actions(k).expectedTimeSec = expectedTimes(k);
                end
            end

            role.role     = roleName;
            role.ordering = ordering;
            role.actions  = actions;

            refBehavior.scenarioName = 'TestScenario';
            refBehavior.roles        = role;
        end

        function trace = makeTrace(~, actionTypes, simTimes)
            % makeTrace  Build a minimal behavior trace table.
            %
            % actionTypes — cell array of strings
            % simTimes    — numeric vector (same length as actionTypes)

            n = numel(actionTypes);
            if n == 0
                trace = table( ...
                    double.empty(0,1), ...
                    string.empty(0,1), ...
                    string.empty(0,1), ...
                    string.empty(0,1), ...
                    string.empty(0,1), ...
                    string.empty(0,1), ...
                    'VariableNames', {'simTimeSec','agentId','role', ...
                                      'actionType','targetAgentId','msgId'});
                return;
            end

            simTimeSec    = simTimes(:);
            agentId       = repmat("agent1", n, 1);
            role          = repmat("TestRole", n, 1);
            actionType    = string(actionTypes(:));
            targetAgentId = repmat("", n, 1);
            msgId         = repmat("", n, 1);

            trace = table(simTimeSec, agentId, role, actionType, ...
                targetAgentId, msgId);
        end

        function eventLog = makeEventLog(~, failTimes)
            % makeEventLog  Build a minimal event log struct array with
            % C2_MESSAGE_FAIL events at the given simulation times.

            if isempty(failTimes)
                eventLog = struct('type', {}, 'simTimeSec', {});
                return;
            end

            n = numel(failTimes);
            eventLog(n) = struct('type', '', 'simTimeSec', 0);
            for k = 1:n
                eventLog(k).type       = 'C2_MESSAGE_FAIL';
                eventLog(k).simTimeSec = failTimes(k);
            end
        end

    end % methods (Access = private)

    % ======================================================================
    % Tests
    % ======================================================================
    methods (Test)

        % ------------------------------------------------------------------
        % 1. testPerfectMatch
        % ------------------------------------------------------------------
        function testPerfectMatch(testCase)
            % All required actions are present in the trace → fidelityScore == 1.0
            %
            % Requirements: 15.1, 15.2

            refBehavior = testCase.makeRefBehavior('Aircrew', 'unordered', ...
                {'SEND_STATUS', 'REQUEST_CLEARANCE', 'ACKNOWLEDGE'}, ...
                [10, 20, 30]);

            trace = testCase.makeTrace( ...
                {'SEND_STATUS', 'REQUEST_CLEARANCE', 'ACKNOWLEDGE'}, ...
                [10, 20, 30]);

            fe = agent.FidelityEvaluator(refBehavior);
            result = fe.evaluate(trace, [], 'Aircrew');

            testCase.verifyEqual(result.fidelityScore, 1.0, ...
                'Perfect match should yield fidelityScore == 1.0');
        end

        % ------------------------------------------------------------------
        % 2. testNoMatchUnordered
        % ------------------------------------------------------------------
        function testNoMatchUnordered(testCase)
            % No required actions appear in the trace → fidelityScore == 0.0
            %
            % Requirements: 15.1, 15.2

            refBehavior = testCase.makeRefBehavior('Aircrew', 'unordered', ...
                {'SEND_STATUS', 'REQUEST_CLEARANCE'}, [10, 20]);

            trace = testCase.makeTrace({'ACKNOWLEDGE', 'LOG_ENTRY'}, [5, 15]);

            fe = agent.FidelityEvaluator(refBehavior);
            result = fe.evaluate(trace, [], 'Aircrew');

            testCase.verifyEqual(result.fidelityScore, 0.0, ...
                'No matching actions should yield fidelityScore == 0.0');
        end

        % ------------------------------------------------------------------
        % 3. testPartialMatchUnordered
        % ------------------------------------------------------------------
        function testPartialMatchUnordered(testCase)
            % Half of the required actions are present → fidelityScore == 0.5
            %
            % Requirements: 15.1, 15.2

            refBehavior = testCase.makeRefBehavior('Aircrew', 'unordered', ...
                {'SEND_STATUS', 'REQUEST_CLEARANCE', 'ACKNOWLEDGE', 'LOG_ENTRY'}, ...
                [10, 20, 30, 40]);

            % Only 2 of 4 required actions observed
            trace = testCase.makeTrace({'SEND_STATUS', 'ACKNOWLEDGE'}, [10, 30]);

            fe = agent.FidelityEvaluator(refBehavior);
            result = fe.evaluate(trace, [], 'Aircrew');

            testCase.verifyEqual(result.fidelityScore, 0.5, ...
                'Half matching actions should yield fidelityScore == 0.5');
        end

        % ------------------------------------------------------------------
        % 4. testEmptyReferenceActions
        % ------------------------------------------------------------------
        function testEmptyReferenceActions(testCase)
            % Empty required actions list → fidelityScore == 1.0
            %
            % Requirements: 15.1

            refBehavior = testCase.makeRefBehavior('Aircrew', 'unordered', {}, []);

            trace = testCase.makeTrace({'SEND_STATUS'}, [10]);

            fe = agent.FidelityEvaluator(refBehavior);
            result = fe.evaluate(trace, [], 'Aircrew');

            testCase.verifyEqual(result.fidelityScore, 1.0, ...
                'Empty reference actions should yield fidelityScore == 1.0');
        end

        % ------------------------------------------------------------------
        % 5. testNetworkConstrainedAnnotation
        % ------------------------------------------------------------------
        function testNetworkConstrainedAnnotation(testCase)
            % A missing action with a C2_MESSAGE_FAIL event near its
            % expectedTimeSec should be annotated as 'network-constrained'.
            %
            % Requirements: 15.4

            refBehavior = testCase.makeRefBehavior('Aircrew', 'unordered', ...
                {'SEND_STATUS', 'REQUEST_CLEARANCE'}, [100, 200]);

            % Trace has neither required action
            trace = testCase.makeTrace({}, []);

            % C2_MESSAGE_FAIL at t=102 — within 5 s of expectedTimeSec=100
            eventLog = testCase.makeEventLog([102]);

            fe = agent.FidelityEvaluator(refBehavior);
            result = fe.evaluate(trace, eventLog, 'Aircrew');

            % Find the missing action for SEND_STATUS (expectedTimeSec=100)
            found = false;
            for k = 1:numel(result.missingActions)
                ma = result.missingActions(k);
                if string(ma.actionType) == "SEND_STATUS"
                    testCase.verifyEqual(string(ma.reason), "network-constrained", ...
                        'SEND_STATUS near a C2_MESSAGE_FAIL should be network-constrained');
                    found = true;
                end
            end
            testCase.verifyTrue(found, 'SEND_STATUS should appear in missingActions');
        end

        % ------------------------------------------------------------------
        % 6. testAgentFailureAnnotation
        % ------------------------------------------------------------------
        function testAgentFailureAnnotation(testCase)
            % A missing action with no nearby C2_MESSAGE_FAIL should be
            % annotated as 'agent-failure'.
            %
            % Requirements: 15.4

            refBehavior = testCase.makeRefBehavior('Aircrew', 'unordered', ...
                {'SEND_STATUS'}, [100]);

            trace = testCase.makeTrace({}, []);

            % No C2_MESSAGE_FAIL events
            eventLog = testCase.makeEventLog([]);

            fe = agent.FidelityEvaluator(refBehavior);
            result = fe.evaluate(trace, eventLog, 'Aircrew');

            testCase.verifyEqual(numel(result.missingActions), 1, ...
                'Should have exactly one missing action');
            testCase.verifyEqual(string(result.missingActions(1).reason), ...
                "agent-failure", ...
                'Missing action with no network failure should be agent-failure');
        end

        % ------------------------------------------------------------------
        % 7. testFidelityScoreInRange
        % ------------------------------------------------------------------
        function testFidelityScoreInRange(testCase)
            % fidelityScore must always be in [0, 1] for various inputs.
            %
            % Requirements: 15.1

            scenarios = { ...
                {'SEND_STATUS', 'REQUEST_CLEARANCE'}, [10, 20], ...
                {'SEND_STATUS', 'REQUEST_CLEARANCE'}, [10, 20]; ...
                {'SEND_STATUS'}, [10], ...
                {}, []; ...
                {}, [], ...
                {'SEND_STATUS'}, [10]; ...
            };

            for s = 1:3
                refTypes  = scenarios{s, 1};
                refTimes  = scenarios{s, 2};
                obsTypes  = scenarios{s, 3};
                obsTimes  = scenarios{s, 4};

                refBehavior = testCase.makeRefBehavior('Role', 'unordered', ...
                    refTypes, refTimes);
                trace = testCase.makeTrace(obsTypes, obsTimes);

                fe = agent.FidelityEvaluator(refBehavior);
                result = fe.evaluate(trace, [], 'Role');

                if ~isnan(result.fidelityScore)
                    testCase.verifyGreaterThanOrEqual(result.fidelityScore, 0.0, ...
                        sprintf('Scenario %d: fidelityScore must be >= 0', s));
                    testCase.verifyLessThanOrEqual(result.fidelityScore, 1.0, ...
                        sprintf('Scenario %d: fidelityScore must be <= 1', s));
                end
            end
        end

        % ------------------------------------------------------------------
        % 8. testStrictOrderingPerfectMatch
        % ------------------------------------------------------------------
        function testStrictOrderingPerfectMatch(testCase)
            % Strict ordering: actions in the correct order → fidelityScore == 1.0
            %
            % Requirements: 15.1, 15.2

            refBehavior = testCase.makeRefBehavior('Aircrew', 'strict', ...
                {'A', 'B', 'C'}, [10, 20, 30]);

            % Observed in the same order
            trace = testCase.makeTrace({'A', 'B', 'C'}, [10, 20, 30]);

            fe = agent.FidelityEvaluator(refBehavior);
            result = fe.evaluate(trace, [], 'Aircrew');

            testCase.verifyEqual(result.fidelityScore, 1.0, ...
                'Strict ordering with correct order should yield fidelityScore == 1.0');
        end

        % ------------------------------------------------------------------
        % 9. testStrictOrderingWrongOrder
        % ------------------------------------------------------------------
        function testStrictOrderingWrongOrder(testCase)
            % Strict ordering: actions in wrong order → fidelityScore < 1.0
            %
            % Requirements: 15.2
            %
            % Reference: A, B, C  (strict)
            % Observed:  C, B, A  (reversed)
            % LCS of [A,B,C] vs [C,B,A] = length 1 (e.g., just B or just C)
            % → score = 1/3 < 1.0

            refBehavior = testCase.makeRefBehavior('Aircrew', 'strict', ...
                {'A', 'B', 'C'}, [10, 20, 30]);

            % Observed in reverse order
            trace = testCase.makeTrace({'C', 'B', 'A'}, [30, 20, 10]);

            fe = agent.FidelityEvaluator(refBehavior);
            result = fe.evaluate(trace, [], 'Aircrew');

            testCase.verifyLessThan(result.fidelityScore, 1.0, ...
                'Strict ordering with wrong order should yield fidelityScore < 1.0');
            testCase.verifyGreaterThanOrEqual(result.fidelityScore, 0.0, ...
                'fidelityScore must be >= 0');
        end

    end % methods (Test)

end % classdef
