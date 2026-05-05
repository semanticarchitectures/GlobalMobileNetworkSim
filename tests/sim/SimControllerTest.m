classdef SimControllerTest < matlab.unittest.TestCase
    % SimControllerTest  Unit tests for sim.SimController.
    %
    % Covers:
    %   1. Constructor creates SimController with simTimeSec=0,
    %      isPaused=false, isStopped=false
    %   2. run() with simulationDurationSec=0 completes without error
    %      and sets isStopped=true
    %   3. pause() sets isPaused=true; resume() sets it back to false
    %   4. stop() sets isStopped=true
    %   5. inspect() returns struct with correct fields including
    %      simTimeSec and isPaused
    %   6. Scenario with nodes and links runs without error (Task 8.1)
    %   7. C2_MESSAGE_TX with valid path produces C2_MESSAGE_RX (Task 8.1)
    %   8. C2_MESSAGE_TX with all links in outage produces C2_MESSAGE_FAIL (Task 8.1)
    %
    % Requirements: 8.1, 8.2, 8.3, 8.4, 4.1, 4.2, 4.3, 4.4, 5.1, 5.2,
    %               5.3, 5.4, 5.5, 5.6, 6.3, 1.2, 2.5, 2.6

    % -----------------------------------------------------------------
    % Helper: build a minimal scenario struct
    % -----------------------------------------------------------------
    methods (Static)
        function s = makeScenario(durationSec)
            s.simulationDurationSec = durationSec;
        end

        function scenario = makeNetworkScenario(durationSec)
            % makeNetworkScenario  Build a scenario with two stationary nodes
            % connected by a single LEO_Satellite link.  Outage rate is set
            % to zero so no outage events are generated during the run.

            scenario.simulationDurationSec = durationSec;

            % Two stationary nodes
            n1.id   = 'nodeA';
            n1.type = 'Stationary';
            n1.lat  = 40.0;
            n1.lon  = -74.0;
            n1.altM = 0.0;
            n1.trajectory    = [];
            n1.keplerElements = [];

            n2.id   = 'nodeB';
            n2.type = 'Stationary';
            n2.lat  = 51.5;
            n2.lon  = -0.1;
            n2.altM = 0.0;
            n2.trajectory    = [];
            n2.keplerElements = [];

            scenario.nodes = [n1, n2];

            % One LEO_Satellite link with zero outage rate
            lk.id               = 'link1';
            lk.type             = 'LEO_Satellite';
            lk.srcNodeId        = 'nodeA';
            lk.dstNodeId        = 'nodeB';
            lk.nominalLatencyMs = 50.0;
            lk.bandwidthBps     = 1e9;
            lk.outageRate       = 0;   % no outages
            lk.outageDuration   = struct('distribution', 'fixed', 'value', 10);
            lk.backgroundTraffic = struct('distribution', 'uniform', 'min', 0.0, 'max', 0.1);
            lk.coverageRadiusM  = NaN;
            lk.congestionPenaltyMs = 0;

            scenario.links = lk;
        end
    end

    % -----------------------------------------------------------------
    % Tests
    % -----------------------------------------------------------------
    methods (Test)

        % --- Test 1: Constructor initialises state correctly ---
        function testConstructorInitialState(testCase)
            sc = sim.SimController(SimControllerTest.makeScenario(100));

            testCase.verifyEqual(sc.simTimeSec, 0.0, ...
                'simTimeSec should be 0 after construction.');
            testCase.verifyFalse(sc.isPaused, ...
                'isPaused should be false after construction.');
            testCase.verifyFalse(sc.isStopped, ...
                'isStopped should be false after construction.');
            testCase.verifyEqual(sc.nextEventId, uint64(1), ...
                'nextEventId should start at 1.');
            testCase.verifyClass(sc.eventCalendar, 'sim.EventCalendar', ...
                'eventCalendar should be a sim.EventCalendar instance.');
        end

        % --- Test 1b: Constructor stores scenario ---
        function testConstructorStoresScenario(testCase)
            s = SimControllerTest.makeScenario(3600);
            sc = sim.SimController(s);
            testCase.verifyEqual(sc.scenario.simulationDurationSec, 3600, ...
                'scenario.simulationDurationSec should be stored.');
        end

        % --- Test 1c: Constructor rejects non-struct ---
        function testConstructorRejectsNonStruct(testCase)
            testCase.verifyError( ...
                @() sim.SimController(42), ...
                'sim:SimController:invalidScenario');
        end

        % --- Test 1d: Constructor rejects scenario without required field ---
        function testConstructorRejectsMissingField(testCase)
            testCase.verifyError( ...
                @() sim.SimController(struct('foo', 1)), ...
                'sim:SimController:missingField');
        end

        % --- Test 2: run() with duration=0 completes and sets isStopped ---
        function testRunZeroDurationCompletesAndSetsStopped(testCase)
            sc = sim.SimController(SimControllerTest.makeScenario(0));
            testCase.verifyWarningFree(@() sc.run(), ...
                'run() with duration=0 should complete without warnings.');
            testCase.verifyTrue(sc.isStopped, ...
                'isStopped should be true after run() completes.');
        end

        % --- Test 2b: run() advances simTimeSec to duration ---
        function testRunAdvancesSimTime(testCase)
            sc = sim.SimController(SimControllerTest.makeScenario(10));
            sc.run();
            testCase.verifyEqual(sc.simTimeSec, 10.0, 'AbsTol', 1e-12, ...
                'simTimeSec should equal simulationDurationSec after run().');
        end

        % --- Test 2c: run() records wallClockStart ---
        function testRunRecordsWallClockStart(testCase)
            sc = sim.SimController(SimControllerTest.makeScenario(0));
            sc.run();
            testCase.verifyNotEmpty(sc.wallClockStart, ...
                'wallClockStart should be set after run().');
        end

        % --- Test 2d: run() logs a SIM_END entry ---
        function testRunLogsSIMENDEntry(testCase)
            sc = sim.SimController(SimControllerTest.makeScenario(0));
            sc.run();
            testCase.verifyTrue(any([sc.eventLog.eventType] == "SIM_END"), ...
                'eventLog should contain a SIM_END entry after run().');
        end

        % --- Test 3: pause() sets isPaused=true ---
        function testPauseSetsFlag(testCase)
            sc = sim.SimController(SimControllerTest.makeScenario(100));
            sc.pause();
            testCase.verifyTrue(sc.isPaused, ...
                'isPaused should be true after pause().');
        end

        % --- Test 3b: resume() clears isPaused ---
        function testResumeClears(testCase)
            sc = sim.SimController(SimControllerTest.makeScenario(100));
            sc.pause();
            sc.resume();
            testCase.verifyFalse(sc.isPaused, ...
                'isPaused should be false after resume().');
        end

        % --- Test 4: stop() sets isStopped=true ---
        function testStopSetsFlag(testCase)
            sc = sim.SimController(SimControllerTest.makeScenario(100));
            sc.stop();
            testCase.verifyTrue(sc.isStopped, ...
                'isStopped should be true after stop().');
        end

        % --- Test 5: inspect() returns struct with required fields ---
        function testInspectReturnsRequiredFields(testCase)
            sc = sim.SimController(SimControllerTest.makeScenario(100));
            state = sc.inspect();

            testCase.verifyTrue(isstruct(state), ...
                'inspect() should return a struct.');
            testCase.verifyTrue(isfield(state, 'simTimeSec'), ...
                'inspect() result should have simTimeSec field.');
            testCase.verifyTrue(isfield(state, 'queuedEventCount'), ...
                'inspect() result should have queuedEventCount field.');
            testCase.verifyTrue(isfield(state, 'isPaused'), ...
                'inspect() result should have isPaused field.');
            testCase.verifyTrue(isfield(state, 'isStopped'), ...
                'inspect() result should have isStopped field.');
        end

        % --- Test 5b: inspect() returns correct values before run ---
        function testInspectValuesBeforeRun(testCase)
            sc = sim.SimController(SimControllerTest.makeScenario(100));
            state = sc.inspect();

            testCase.verifyEqual(state.simTimeSec, 0.0, 'AbsTol', 1e-12, ...
                'simTimeSec should be 0 before run().');
            testCase.verifyFalse(state.isPaused, ...
                'isPaused should be false before run().');
            testCase.verifyFalse(state.isStopped, ...
                'isStopped should be false before run().');
            testCase.verifyEqual(state.queuedEventCount, 0, ...
                'queuedEventCount should be 0 before any events are scheduled.');
        end

        % --- Test 5c: inspect() reflects simTimeSec after run ---
        function testInspectSimTimeAfterRun(testCase)
            sc = sim.SimController(SimControllerTest.makeScenario(42));
            sc.run();
            state = sc.inspect();
            testCase.verifyEqual(state.simTimeSec, 42.0, 'AbsTol', 1e-12, ...
                'inspect().simTimeSec should equal duration after run().');
            testCase.verifyTrue(state.isStopped, ...
                'inspect().isStopped should be true after run().');
        end

        % --- Additional: stats struct is initialised ---
        function testStatsInitialised(testCase)
            sc = sim.SimController(SimControllerTest.makeScenario(0));
            testCase.verifyTrue(isstruct(sc.stats), ...
                'stats should be a struct.');
            testCase.verifyTrue(isfield(sc.stats, 'c2MessagesTx'), ...
                'stats should have c2MessagesTx field.');
            testCase.verifyTrue(isfield(sc.stats, 'c2MessagesRx'), ...
                'stats should have c2MessagesRx field.');
            testCase.verifyTrue(isfield(sc.stats, 'c2MessagesFail'), ...
                'stats should have c2MessagesFail field.');
        end

        % --- Additional: eventCount() returns 0 on fresh controller ---
        function testEventCountZeroInitially(testCase)
            sc = sim.SimController(SimControllerTest.makeScenario(100));
            testCase.verifyEqual(sc.eventCount(), 0, ...
                'eventCount() should be 0 before any events are scheduled.');
        end

        % --- Additional: run() with extra events processes them ---
        function testRunProcessesScheduledEvents(testCase)
            sc = sim.SimController(SimControllerTest.makeScenario(100));

            % Schedule a C2_MESSAGE_TX event before calling run().
            ev.time    = 50.0;
            ev.type    = sim.EventCalendar.C2_MESSAGE_TX;
            ev.id      = uint64(9999);
            ev.payload = struct('msgId', 'msg1', 'srcNodeId', 'A', ...
                                'dstNodeId', 'B', 'sizeBytes', 512);
            sc.eventCalendar.schedule(ev);

            sc.run();

            % Verify the TX event was logged.
            testCase.verifyTrue(any([sc.eventLog.eventType] == "C2_MESSAGE_TX"), ...
                'eventLog should contain a C2_MESSAGE_TX entry.');
            testCase.verifyEqual(sc.stats.c2MessagesTx, uint64(1), ...
                'c2MessagesTx counter should be 1 after one TX event.');
        end

        % --- Test 6 (Task 8.1): Scenario with nodes and links runs without error ---
        function testNetworkScenarioRunsWithoutError(testCase)
            % Build a scenario with two nodes and one link.
            scenario = SimControllerTest.makeNetworkScenario(10);

            % Construction and run should complete without error.
            sc = sim.SimController(scenario);

            % Verify subsystems were constructed.
            testCase.verifyNotEmpty(sc.nodeRegistry, ...
                'nodeRegistry should be constructed when scenario has nodes.');
            testCase.verifyNotEmpty(sc.linkRegistry, ...
                'linkRegistry should be constructed when scenario has links.');
            testCase.verifyNotEmpty(sc.routingEngine, ...
                'routingEngine should be constructed when scenario has nodes and links.');

            % inspect() should report correct node/link counts.
            state = sc.inspect();
            testCase.verifyEqual(state.nodeCount, 2, ...
                'nodeCount should be 2 for a two-node scenario.');
            testCase.verifyEqual(state.linkCount, 1, ...
                'linkCount should be 1 for a one-link scenario.');

            % run() should complete without error.
            testCase.verifyWarningFree(@() sc.run(), ...
                'run() with a network scenario should complete without warnings.');
            testCase.verifyTrue(sc.isStopped, ...
                'isStopped should be true after run() completes.');
        end

        % --- Test 7 (Task 8.1): C2_MESSAGE_TX with valid path produces C2_MESSAGE_RX ---
        function testC2TxWithValidPathProducesRx(testCase)
            % Build a scenario with two nodes and one active link, plus a
            % C2 message scheduled at t=1 (well before the sim end at t=100).
            scenario = SimControllerTest.makeNetworkScenario(100);

            msg.id               = 'msg-001';
            msg.srcNodeId        = 'nodeA';
            msg.dstNodeId        = 'nodeB';
            msg.sizeBytes        = 512;
            msg.scheduledTimeSec = 1.0;
            scenario.c2Messages  = msg;

            sc = sim.SimController(scenario);
            sc.run();

            % The TX event should have been logged.
            testCase.verifyTrue(any([sc.eventLog.eventType] == "C2_MESSAGE_TX"), ...
                'eventLog should contain a C2_MESSAGE_TX entry.');

            % A C2_MESSAGE_RX event should have been logged (path exists).
            testCase.verifyTrue(any([sc.eventLog.eventType] == "C2_MESSAGE_RX"), ...
                'eventLog should contain a C2_MESSAGE_RX entry when a path exists.');

            % Stats counters should reflect one TX and one RX.
            testCase.verifyEqual(sc.stats.c2MessagesTx, uint64(1), ...
                'c2MessagesTx should be 1.');
            testCase.verifyEqual(sc.stats.c2MessagesRx, uint64(1), ...
                'c2MessagesRx should be 1.');
            testCase.verifyEqual(sc.stats.c2MessagesFail, uint64(0), ...
                'c2MessagesFail should be 0 when a path exists.');

            % deliveredLatenciesMs should have one entry.
            testCase.verifyEqual(numel(sc.deliveredLatenciesMs), 1, ...
                'deliveredLatenciesMs should have one entry after one delivered message.');
        end

        % --- Test 8 (Task 8.1): C2_MESSAGE_TX with all links in outage produces C2_MESSAGE_FAIL ---
        function testC2TxWithAllLinksInOutageProducesFail(testCase)
            % Build a scenario with two nodes and one link, then manually
            % put the link into outage before scheduling the C2 message.
            scenario = SimControllerTest.makeNetworkScenario(100);

            msg.id               = 'msg-002';
            msg.srcNodeId        = 'nodeA';
            msg.dstNodeId        = 'nodeB';
            msg.sizeBytes        = 512;
            msg.scheduledTimeSec = 1.0;
            scenario.c2Messages  = msg;

            sc = sim.SimController(scenario);

            % Force the link into outage so no path is available.
            sc.linkRegistry.setOutage('link1', true);
            sc.routingEngine.invalidateCache('link1');

            sc.run();

            % The TX event should have been logged.
            testCase.verifyTrue(any([sc.eventLog.eventType] == "C2_MESSAGE_TX"), ...
                'eventLog should contain a C2_MESSAGE_TX entry.');

            % A C2_MESSAGE_FAIL event should have been logged (no path).
            testCase.verifyTrue(any([sc.eventLog.eventType] == "C2_MESSAGE_FAIL"), ...
                'eventLog should contain a C2_MESSAGE_FAIL entry when all links are in outage.');

            % No C2_MESSAGE_RX should have been logged.
            testCase.verifyFalse(any([sc.eventLog.eventType] == "C2_MESSAGE_RX"), ...
                'eventLog should NOT contain a C2_MESSAGE_RX entry when no path exists.');

            % Stats counters should reflect one TX and one FAIL.
            testCase.verifyEqual(sc.stats.c2MessagesTx, uint64(1), ...
                'c2MessagesTx should be 1.');
            testCase.verifyEqual(sc.stats.c2MessagesFail, uint64(1), ...
                'c2MessagesFail should be 1 when no path exists.');
            testCase.verifyEqual(sc.stats.c2MessagesRx, uint64(0), ...
                'c2MessagesRx should be 0 when no path exists.');
        end

        % --- Test 9 (Task 11.1): buildStatsReport() returns struct with all required fields ---
        function testBuildStatsReportHasRequiredFields(testCase)
            % Build a network scenario with one C2 message and run it.
            scenario = SimControllerTest.makeNetworkScenario(100);
            scenario.scenarioName = 'test-scenario';

            msg.id               = 'msg-stats';
            msg.srcNodeId        = 'nodeA';
            msg.dstNodeId        = 'nodeB';
            msg.sizeBytes        = 512;
            msg.scheduledTimeSec = 1.0;
            scenario.c2Messages  = msg;

            sc = sim.SimController(scenario);
            sc.run();

            report = sc.buildStatsReport();

            % Verify top-level fields exist
            testCase.verifyTrue(isstruct(report), ...
                'buildStatsReport() should return a struct.');
            testCase.verifyTrue(isfield(report, 'scenarioName'), ...
                'report should have scenarioName field.');
            testCase.verifyTrue(isfield(report, 'simStartTimeSec'), ...
                'report should have simStartTimeSec field.');
            testCase.verifyTrue(isfield(report, 'simEndTimeSec'), ...
                'report should have simEndTimeSec field.');
            testCase.verifyTrue(isfield(report, 'wallClockDurationSec'), ...
                'report should have wallClockDurationSec field.');
            testCase.verifyTrue(isfield(report, 'c2Messages'), ...
                'report should have c2Messages field.');
            testCase.verifyTrue(isfield(report, 'latency'), ...
                'report should have latency field.');
            testCase.verifyTrue(isfield(report, 'perLink'), ...
                'report should have perLink field.');
            testCase.verifyTrue(isfield(report, 'agentFidelity'), ...
                'report should have agentFidelity field.');

            % Verify c2Messages sub-fields
            testCase.verifyTrue(isfield(report.c2Messages, 'scheduled'), ...
                'c2Messages should have scheduled field.');
            testCase.verifyTrue(isfield(report.c2Messages, 'delivered'), ...
                'c2Messages should have delivered field.');
            testCase.verifyTrue(isfield(report.c2Messages, 'failed'), ...
                'c2Messages should have failed field.');

            % Verify latency sub-fields
            testCase.verifyTrue(isfield(report.latency, 'meanMs'), ...
                'latency should have meanMs field.');
            testCase.verifyTrue(isfield(report.latency, 'medianMs'), ...
                'latency should have medianMs field.');
            testCase.verifyTrue(isfield(report.latency, 'p95Ms'), ...
                'latency should have p95Ms field.');

            % Verify agentFidelity sub-fields
            testCase.verifyTrue(isfield(report.agentFidelity, 'mean'), ...
                'agentFidelity should have mean field.');
            testCase.verifyTrue(isfield(report.agentFidelity, 'min'), ...
                'agentFidelity should have min field.');
            testCase.verifyTrue(isfield(report.agentFidelity, 'max'), ...
                'agentFidelity should have max field.');

            % Verify perLink has one entry for the one link
            testCase.verifyEqual(numel(report.perLink), 1, ...
                'perLink should have one entry for the one-link scenario.');
            testCase.verifyTrue(isfield(report.perLink, 'linkId'), ...
                'perLink entry should have linkId field.');
            testCase.verifyTrue(isfield(report.perLink, 'meanEffectiveBwBps'), ...
                'perLink entry should have meanEffectiveBwBps field.');
            testCase.verifyTrue(isfield(report.perLink, 'meanBgLoadFraction'), ...
                'perLink entry should have meanBgLoadFraction field.');
            testCase.verifyTrue(isfield(report.perLink, 'totalC2MessagesRouted'), ...
                'perLink entry should have totalC2MessagesRouted field.');
            testCase.verifyTrue(isfield(report.perLink, 'totalOutageDurationSec'), ...
                'perLink entry should have totalOutageDurationSec field.');
            testCase.verifyTrue(isfield(report.perLink, 'outageFraction'), ...
                'perLink entry should have outageFraction field.');

            % Verify scenario name is captured
            testCase.verifyEqual(report.scenarioName, 'test-scenario', ...
                'scenarioName should match scenario.scenarioName.');

            % Verify c2Messages counts are correct (1 TX, 1 RX, 0 fail)
            testCase.verifyEqual(report.c2Messages.scheduled, 1, ...
                'c2Messages.scheduled should be 1.');
            testCase.verifyEqual(report.c2Messages.delivered, 1, ...
                'c2Messages.delivered should be 1.');
            testCase.verifyEqual(report.c2Messages.failed, 0, ...
                'c2Messages.failed should be 0.');

            % Verify latency is finite (one delivered message)
            testCase.verifyTrue(isfinite(report.latency.meanMs), ...
                'latency.meanMs should be finite after one delivered message.');
        end

        % --- Test 10 (Task 11.1): wallClockDurationSec is positive finite after run ---
        function testWallClockDurationSecIsPositiveFinite(testCase)
            scenario = SimControllerTest.makeNetworkScenario(10);
            sc = sim.SimController(scenario);
            sc.run();

            testCase.verifyTrue(isfinite(sc.wallClockDurationSec), ...
                'wallClockDurationSec should be finite after run().');
            testCase.verifyGreaterThan(sc.wallClockDurationSec, 0, ...
                'wallClockDurationSec should be positive after run().');
        end

    end

end
