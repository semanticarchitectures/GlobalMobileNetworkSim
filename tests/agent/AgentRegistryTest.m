classdef AgentRegistryTest < matlab.unittest.TestCase
    % AgentRegistryTest  Unit tests for agent.AgentRegistry.
    %
    % Tests:
    %   1. testConstructorValidatesNodeId   - throws netsim:agent:unknownNode
    %                                         for an unknown nodeId
    %   2. testConstructorCreatesTracers    - getTracer() returns a BehaviorTracer
    %   3. testGetAgentIds                  - returns correct agent IDs
    %   4. testCount                        - returns correct count
    %   5. testDeliverRecordsAction         - after deliver(), tracer has one action
    %                                         (skips actual LLM call)
    %
    % Requirements: 12.1, 12.2, 12.3, 12.4, 12.5, 13.1, 13.2, 13.3,
    %               13.4, 13.5, 11.5

    % ======================================================================
    % Test class setup — add workspace root to path and resolve fixture path
    % ======================================================================
    properties
        % Absolute path to the aircrew role fixture (resolved at setup time)
        RoleFixturePath = ''
    end

    methods (TestClassSetup)
        function addWorkspaceRootToPath(testCase)
            thisDir = fileparts(mfilename('fullpath'));
            rootDir = fileparts(fileparts(thisDir));
            addpath(rootDir);
            addpath(thisDir);
            testCase.addTeardown(@() rmpath(rootDir));
            testCase.addTeardown(@() rmpath(thisDir));
            % Resolve the fixture path to an absolute path so RoleLoader
            % can find it regardless of the current working directory.
            testCase.RoleFixturePath = fullfile(thisDir, 'fixtures', 'aircrew_role.md');
        end
    end

    % ======================================================================
    % Shared helpers
    % ======================================================================
    methods (Access = private)

        function nr = makeNodeRegistry(~)
            % Build a minimal NodeRegistry with one stationary node 'node1'.
            nodeDef.id         = 'node1';
            nodeDef.type       = 'Stationary';
            nodeDef.lat        = 40.7128;
            nodeDef.lon        = -74.0060;
            nodeDef.altM       = 0.0;
            nodeDef.trajectory = [];
            nodeDef.keplerElements = [];
            nr = network.NodeRegistry(nodeDef);
        end

        function ec = makeEventCalendar(~)
            ec = sim.EventCalendar();
        end

        function llm = makeLLMClient(~)
            % Create an LLMClient with a dummy key.
            % Actual HTTP calls will fail, but construction succeeds.
            llm = agent.LLMClient();
            llm.setApiKey('test-key-for-unit-tests');
        end

        function def = makeAgentDef(testCase, id, nodeId)
            def.id                 = id;
            def.nodeId             = nodeId;
            def.roleDefinitionFile = testCase.RoleFixturePath;
            def.idleTimeoutSec     = 300;
        end

    end

    % ======================================================================
    % Tests
    % ======================================================================
    methods (Test)

        % ------------------------------------------------------------------
        % 1. testConstructorValidatesNodeId
        % ------------------------------------------------------------------
        function testConstructorValidatesNodeId(testCase)
            % Constructing an AgentRegistry with an agent whose nodeId does
            % not exist in the NodeRegistry must throw netsim:agent:unknownNode.
            %
            % Requirements: 12.1

            nr  = testCase.makeNodeRegistry();
            ec  = testCase.makeEventCalendar();
            llm = testCase.makeLLMClient();

            % 'nonexistent_node' is not in the NodeRegistry
            def = testCase.makeAgentDef('agent1', 'nonexistent_node');

            testCase.verifyError( ...
                @() agent.AgentRegistry(def, nr, llm, ec), ...
                'netsim:agent:unknownNode', ...
                'Constructor should throw netsim:agent:unknownNode for unknown nodeId');
        end

        % ------------------------------------------------------------------
        % 2. testConstructorCreatesTracers
        % ------------------------------------------------------------------
        function testConstructorCreatesTracers(testCase)
            % After construction, getTracer() should return a BehaviorTracer
            % instance for each registered agent.
            %
            % Requirements: 13.3

            nr  = testCase.makeNodeRegistry();
            ec  = testCase.makeEventCalendar();
            llm = testCase.makeLLMClient();

            def = testCase.makeAgentDef('agent1', 'node1');
            ar  = agent.AgentRegistry(def, nr, llm, ec);

            bt = ar.getTracer('agent1');

            testCase.verifyClass(bt, 'agent.BehaviorTracer', ...
                'getTracer() should return an agent.BehaviorTracer instance');

            % The tracer should start empty
            trace = bt.getTrace();
            testCase.verifyEqual(height(trace), 0, ...
                'Newly created tracer should have an empty trace');
        end

        % ------------------------------------------------------------------
        % 3. testGetAgentIds
        % ------------------------------------------------------------------
        function testGetAgentIds(testCase)
            % getAgentIds() should return a string array containing all
            % registered agent IDs.
            %
            % Requirements: 12.1

            nr  = testCase.makeNodeRegistry();
            ec  = testCase.makeEventCalendar();
            llm = testCase.makeLLMClient();

            % Register two agents on the same node
            defs(1) = testCase.makeAgentDef('alpha', 'node1');
            defs(2) = testCase.makeAgentDef('bravo', 'node1');

            ar  = agent.AgentRegistry(defs, nr, llm, ec);
            ids = ar.getAgentIds();

            testCase.verifyEqual(numel(ids), 2, ...
                'getAgentIds() should return 2 IDs for 2 registered agents');

            % Sort both for comparison (containers.Map order is unspecified)
            testCase.verifyTrue( ...
                ismember("alpha", ids) && ismember("bravo", ids), ...
                'getAgentIds() should contain "alpha" and "bravo"');
        end

        % ------------------------------------------------------------------
        % 4. testCount
        % ------------------------------------------------------------------
        function testCount(testCase)
            % count() should return the number of registered agents.
            %
            % Requirements: 12.1

            nr  = testCase.makeNodeRegistry();
            ec  = testCase.makeEventCalendar();
            llm = testCase.makeLLMClient();

            % Single agent
            def1 = testCase.makeAgentDef('agent1', 'node1');
            ar1  = agent.AgentRegistry(def1, nr, llm, ec);
            testCase.verifyEqual(ar1.count(), uint64(1), ...
                'count() should return 1 for a single agent');

            % Two agents
            defs(1) = testCase.makeAgentDef('a1', 'node1');
            defs(2) = testCase.makeAgentDef('a2', 'node1');
            ar2  = agent.AgentRegistry(defs, nr, llm, ec);
            testCase.verifyEqual(ar2.count(), uint64(2), ...
                'count() should return 2 for two agents');
        end

        % ------------------------------------------------------------------
        % 5. testDeliverRecordsAction
        % ------------------------------------------------------------------
        function testDeliverRecordsAction(testCase)
            % After a successful deliver() call, the agent's BehaviorTracer
            % should contain exactly one recorded action of type 'LLM_RESPONSE'.
            %
            % Because deliver() calls LLMClient.complete() which requires a
            % real HTTP endpoint, we use a MockLLMClient subclass that
            % overrides complete() to return a canned response without
            % making any network call.
            %
            % Requirements: 12.2, 13.3

            nr  = testCase.makeNodeRegistry();
            ec  = testCase.makeEventCalendar();

            % Use the mock LLM client defined at the bottom of this file
            llm = AgentRegistryTest.MockLLMClient();

            def = testCase.makeAgentDef('agent1', 'node1');
            ar  = agent.AgentRegistry(def, nr, llm, ec);

            % Build a minimal C2 message
            msg.srcNodeId = 'node1';
            msg.msgId     = 'msg001';
            msg.txTime    = 0.0;
            msg.content   = 'Test message content';

            response = ar.deliver('agent1', msg, 10.0);

            bt    = ar.getTracer('agent1');
            trace = bt.getTrace();

            testCase.verifyEqual(height(trace), 1, ...
                'After one deliver() call, tracer should have exactly 1 action');

            testCase.verifyEqual(trace.actionType(1), "LLM_RESPONSE", ...
                'Recorded action type should be "LLM_RESPONSE"');

            testCase.verifyEqual(trace.simTimeSec(1), 10.0, ...
                'Recorded simTimeSec should match the simTimeSec passed to deliver()');

            % deliver() should return the LLM response struct
            testCase.verifyTrue(isstruct(response), ...
                'deliver() should return a struct');
            testCase.verifyTrue(isfield(response, 'content'), ...
                'Returned response should have a content field');
        end

        % ------------------------------------------------------------------
        % 6. testConstructorSchedulesIdleCheckEvents
        % ------------------------------------------------------------------
        function testConstructorSchedulesIdleCheckEvents(testCase)
            % The constructor should schedule one AGENT_IDLE_CHECK event per
            % agent in the EventCalendar.
            %
            % Requirements: 12.5

            nr  = testCase.makeNodeRegistry();
            ec  = testCase.makeEventCalendar();
            llm = testCase.makeLLMClient();

            def = testCase.makeAgentDef('agent1', 'node1');
            def.idleTimeoutSec = 120;

            ar = agent.AgentRegistry(def, nr, llm, ec); %#ok<NASGU>

            testCase.verifyEqual(ec.eventCount(), 1, ...
                'Constructor should schedule exactly 1 AGENT_IDLE_CHECK event');

            % Pop the event and verify its fields
            ev = ec.popNext();
            testCase.verifyEqual(ev.type, sim.EventCalendar.AGENT_IDLE_CHECK, ...
                'Scheduled event type should be AGENT_IDLE_CHECK');
            testCase.verifyEqual(ev.time, 120.0, ...
                'Idle check event time should equal idleTimeoutSec');
            testCase.verifyEqual(ev.payload.agentId, "agent1", ...
                'Idle check event payload should contain the agent ID');
        end

        % ------------------------------------------------------------------
        % 7. testCheckIdleRecordsStatusCheck
        % ------------------------------------------------------------------
        function testCheckIdleRecordsStatusCheck(testCase)
            % checkIdle() should record an 'IDLE_CHECKIN' action in the
            % BehaviorTracer after calling the LLM for a status check-in.
            %
            % Requirements: 12.5, 13.3

            nr  = testCase.makeNodeRegistry();
            ec  = testCase.makeEventCalendar();

            % Use mock LLM so checkIdle() does not make real HTTP calls
            llm = AgentRegistryTest.MockLLMClient();

            def = testCase.makeAgentDef('agent1', 'node1');
            def.idleTimeoutSec = 60;

            ar = agent.AgentRegistry(def, nr, llm, ec);

            % Call checkIdle — agent has never received a message
            ar.checkIdle('agent1', 300.0);

            bt    = ar.getTracer('agent1');
            trace = bt.getTrace();

            testCase.verifyEqual(height(trace), 1, ...
                'checkIdle() should record one IDLE_CHECKIN action');
            testCase.verifyEqual(trace.actionType(1), "IDLE_CHECKIN", ...
                'Recorded action type should be "IDLE_CHECKIN"');
        end

        % ------------------------------------------------------------------
        % 8. testCheckIdleSchedulesNextEvent
        % ------------------------------------------------------------------
        function testCheckIdleSchedulesNextEvent(testCase)
            % checkIdle() should schedule the next AGENT_IDLE_CHECK event at
            % simTimeSec + idleTimeoutSec.
            %
            % Requirements: 12.5

            nr  = testCase.makeNodeRegistry();
            ec  = testCase.makeEventCalendar();
            llm = testCase.makeLLMClient();

            def = testCase.makeAgentDef('agent1', 'node1');
            def.idleTimeoutSec = 60;

            ar = agent.AgentRegistry(def, nr, llm, ec);

            % Drain the initial idle check event scheduled by the constructor
            ec.popNext();

            % Call checkIdle at t=300
            ar.checkIdle('agent1', 300.0);

            % The next idle check should be at 300 + 60 = 360
            testCase.verifyEqual(ec.eventCount(), 1, ...
                'checkIdle() should schedule exactly one new AGENT_IDLE_CHECK event');

            ev = ec.popNext();
            testCase.verifyEqual(ev.time, 360.0, ...
                'Next idle check event time should be simTimeSec + idleTimeoutSec');
        end

        % ------------------------------------------------------------------
        % 9. testGetTracerReturnsCorrectTracer
        % ------------------------------------------------------------------
        function testGetTracerReturnsCorrectTracer(testCase)
            % getTracer() should return the tracer for the correct agent when
            % multiple agents are registered.
            %
            % Requirements: 13.3

            nr  = testCase.makeNodeRegistry();
            ec  = testCase.makeEventCalendar();
            llm = testCase.makeLLMClient();

            defs(1) = testCase.makeAgentDef('alpha', 'node1');
            defs(2) = testCase.makeAgentDef('bravo', 'node1');

            ar = agent.AgentRegistry(defs, nr, llm, ec);

            btAlpha = ar.getTracer('alpha');
            btBravo = ar.getTracer('bravo');

            % Each tracer should be a BehaviorTracer
            testCase.verifyClass(btAlpha, 'agent.BehaviorTracer', ...
                'getTracer("alpha") should return a BehaviorTracer');
            testCase.verifyClass(btBravo, 'agent.BehaviorTracer', ...
                'getTracer("bravo") should return a BehaviorTracer');

            % The two tracers should be different objects
            testCase.verifyNotSameHandle(btAlpha, btBravo, ...
                'Each agent should have its own distinct BehaviorTracer');

            % Record an action in alpha's tracer and verify bravo's is unaffected
            btAlpha.record(1.0, uint64(0), 'TEST_ACTION', '', '');
            testCase.verifyEqual(height(btAlpha.getTrace()), 1, ...
                'Alpha tracer should have 1 action after recording');
            testCase.verifyEqual(height(btBravo.getTrace()), 0, ...
                'Bravo tracer should remain empty');
        end

        % ------------------------------------------------------------------
        % 10. testGetAllTracers
        % ------------------------------------------------------------------
        function testGetAllTracers(testCase)
            % getAllTracers() should return a struct array with agentId, role,
            % and tracer fields for all registered agents.
            %
            % Requirements: 13.3

            nr  = testCase.makeNodeRegistry();
            ec  = testCase.makeEventCalendar();
            llm = testCase.makeLLMClient();

            defs(1) = testCase.makeAgentDef('alpha', 'node1');
            defs(2) = testCase.makeAgentDef('bravo', 'node1');

            ar = agent.AgentRegistry(defs, nr, llm, ec);

            result = ar.getAllTracers();

            testCase.verifyEqual(numel(result), 2, ...
                'getAllTracers() should return 2 entries for 2 agents');

            % Each entry should have the required fields
            testCase.verifyTrue(isfield(result, 'agentId'), ...
                'getAllTracers() result should have agentId field');
            testCase.verifyTrue(isfield(result, 'role'), ...
                'getAllTracers() result should have role field');
            testCase.verifyTrue(isfield(result, 'tracer'), ...
                'getAllTracers() result should have tracer field');

            % Collect agent IDs from result
            ids = string({result.agentId});
            testCase.verifyTrue(ismember("alpha", ids) && ismember("bravo", ids), ...
                'getAllTracers() should contain entries for both alpha and bravo');
        end

    end % methods (Test)

    % ======================================================================
    % Mock LLM client — returns a canned response without HTTP calls
    % ======================================================================
    methods (Static)
        function llm = MockLLMClient()
            % Return a MockLLMClientImpl instance (defined in
            % tests/agent/MockLLMClientImpl.m).
            llm = MockLLMClientImpl();
        end
    end

end % classdef AgentRegistryTest
