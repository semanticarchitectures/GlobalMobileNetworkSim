classdef SimControllerICAMTest < matlab.unittest.TestCase
    % SimControllerICAMTest  Integration tests for ICAM wiring in SimController.
    %
    % Tests:
    %   1. SimController with entities in scenario constructs icamController
    %   2. SimController without entities has icamController = []
    %   3. C2_MESSAGE_TX with ICAM deny records access-denied in event log
    %   4. buildStatsReport includes icam block when icamController is present
    %
    % Requirements: 19.2, 20.2, 20.4, 21.1, 21.2, 21.3, 17.3, 17.6, 20.6, 21.5

    % -----------------------------------------------------------------
    % Helper methods
    % -----------------------------------------------------------------
    methods (Static)

        function scenario = makeBaseNetworkScenario(durationSec)
            % makeBaseNetworkScenario  Build a two-node, one-link scenario.

            scenario.simulationDurationSec = durationSec;
            scenario.scenarioName = 'icam-test';

            n1.id   = 'nodeA';
            n1.type = 'Stationary';
            n1.lat  = 40.0;
            n1.lon  = -74.0;
            n1.altM = 0.0;
            n1.trajectory     = [];
            n1.keplerElements = [];

            n2.id   = 'nodeB';
            n2.type = 'Stationary';
            n2.lat  = 51.5;
            n2.lon  = -0.1;
            n2.altM = 0.0;
            n2.trajectory     = [];
            n2.keplerElements = [];

            scenario.nodes = [n1, n2];

            lk.id                  = 'link1';
            lk.type                = 'LEO_Satellite';
            lk.srcNodeId           = 'nodeA';
            lk.dstNodeId           = 'nodeB';
            lk.nominalLatencyMs    = 50.0;
            lk.bandwidthBps        = 1e9;
            lk.outageRate          = 0;
            lk.outageDuration      = struct('distribution', 'fixed', 'value', 10);
            lk.backgroundTraffic   = struct('distribution', 'uniform', 'min', 0.0, 'max', 0.1);
            lk.coverageRadiusM     = NaN;
            lk.congestionPenaltyMs = 0;

            scenario.links = lk;
        end

        function scenario = makeScenarioWithEntities(durationSec)
            % makeScenarioWithEntities  Add entities to the base scenario.

            scenario = SimControllerICAMTest.makeBaseNetworkScenario(durationSec);

            e1.id     = 'entity-A';
            e1.nodeId = 'nodeA';
            e1.type   = 'human';

            e2.id     = 'entity-B';
            e2.nodeId = 'nodeB';
            e2.type   = 'npe';

            scenario.entities = [e1, e2];
        end

        function scenario = makeScenarioWithPolicyFile(durationSec)
            % makeScenarioWithPolicyFile  Add a policyDefinitionFile to the base scenario.

            scenario = SimControllerICAMTest.makeBaseNetworkScenario(durationSec);

            % Write a minimal permissive policy to a temp file
            policy.enclaves = struct('enclaveId', 'default', 'cacheTtlSec', 300, 'failPolicy', 'open');
            policy.trustAnchors = struct('trustAnchorId', 'ta1', 'nodeId', 'nodeA', 'certificateValidityPeriodSec', 3600);
            policy.rules = struct.empty(0, 1);

            tmpFile = [tempname() '.json'];
            fid = fopen(tmpFile, 'w');
            fprintf(fid, '%s', jsonencode(policy));
            fclose(fid);

            scenario.policyDefinitionFile = tmpFile;
        end

    end

    % -----------------------------------------------------------------
    % Tests
    % -----------------------------------------------------------------
    methods (Test)

        % --- Test 1: SimController with entities constructs icamController ---
        function testICAMControllerConstructedWithEntities(testCase)
            % Requirements: 21.1, 17.3

            scenario = SimControllerICAMTest.makeScenarioWithEntities(10);
            sc = sim.SimController(scenario);

            testCase.verifyNotEmpty(sc.icamController, ...
                'icamController should be constructed when scenario has entities.');
            testCase.verifyClass(sc.icamController, 'icam.ICAMController', ...
                'icamController should be an icam.ICAMController instance.');
        end

        % --- Test 1b: SimController with policyDefinitionFile constructs icamController ---
        function testICAMControllerConstructedWithPolicyFile(testCase)
            % Requirements: 21.1, 17.6

            scenario = SimControllerICAMTest.makeScenarioWithPolicyFile(10);
            sc = sim.SimController(scenario);

            testCase.verifyNotEmpty(sc.icamController, ...
                'icamController should be constructed when scenario has policyDefinitionFile.');
            testCase.verifyClass(sc.icamController, 'icam.ICAMController', ...
                'icamController should be an icam.ICAMController instance.');

            % Clean up temp file
            if isfield(scenario, 'policyDefinitionFile') && ...
                    exist(scenario.policyDefinitionFile, 'file')
                delete(scenario.policyDefinitionFile);
            end
        end

        % --- Test 2: SimController without entities has icamController = [] ---
        function testICAMControllerEmptyWithoutEntities(testCase)
            % Requirements: 21.1

            scenario = SimControllerICAMTest.makeBaseNetworkScenario(10);
            sc = sim.SimController(scenario);

            testCase.verifyEmpty(sc.icamController, ...
                'icamController should be [] when scenario has no entities or policyDefinitionFile.');
        end

        % --- Test 2b: SimController without nodes has icamController = [] even with entities ---
        function testICAMControllerEmptyWithoutNodes(testCase)
            % icamController requires nodeRegistry to be non-empty

            scenario.simulationDurationSec = 10;
            scenario.entities = struct('id', 'e1', 'nodeId', 'nodeA', 'type', 'human');

            sc = sim.SimController(scenario);

            testCase.verifyEmpty(sc.icamController, ...
                'icamController should be [] when nodeRegistry is empty (no nodes in scenario).');
        end

        % --- Test 3: C2_MESSAGE_TX with ICAM deny records access-denied ---
        function testC2TxICAMDenyRecordsAccessDenied(testCase)
            % Requirements: 21.2, 21.3, 20.2

            scenario = SimControllerICAMTest.makeScenarioWithEntities(100);

            % Add a C2 message
            msg.id               = 'msg-deny-test';
            msg.srcNodeId        = 'nodeA';
            msg.dstNodeId        = 'nodeB';
            msg.sizeBytes        = 512;
            msg.scheduledTimeSec = 1.0;
            scenario.c2Messages  = msg;

            sc = sim.SimController(scenario);

            % Replace icamController with a mock that always denies
            sc.icamController = SimControllerICAMTest.makeDenyingICAMController();

            sc.run();

            % Verify access-denied was logged
            reasons = {sc.eventLog.reason};
            hasAccessDenied = any(strcmp(reasons, 'access-denied'));
            testCase.verifyTrue(hasAccessDenied, ...
                'Event log should contain an access-denied entry when ICAM denies.');

            % Verify no C2_MESSAGE_RX was logged (message was discarded)
            testCase.verifyFalse(any([sc.eventLog.eventType] == "C2_MESSAGE_RX"), ...
                'No C2_MESSAGE_RX should be logged when ICAM denies the message.');

            % Verify c2MessagesFail was incremented
            testCase.verifyGreaterThan(double(sc.stats.c2MessagesFail), 0, ...
                'c2MessagesFail should be incremented when ICAM denies.');
        end

        % --- Test 3b: C2_MESSAGE_TX with ICAM permit proceeds to routing ---
        function testC2TxICAMPermitProceedsToRouting(testCase)
            % Requirements: 21.1, 21.2

            scenario = SimControllerICAMTest.makeScenarioWithEntities(100);

            msg.id               = 'msg-permit-test';
            msg.srcNodeId        = 'nodeA';
            msg.dstNodeId        = 'nodeB';
            msg.sizeBytes        = 512;
            msg.scheduledTimeSec = 1.0;
            scenario.c2Messages  = msg;

            sc = sim.SimController(scenario);

            % Replace icamController with a mock that always permits
            sc.icamController = SimControllerICAMTest.makePermittingICAMController();

            sc.run();

            % Verify C2_MESSAGE_RX was logged (routing proceeded)
            testCase.verifyTrue(any([sc.eventLog.eventType] == "C2_MESSAGE_RX"), ...
                'C2_MESSAGE_RX should be logged when ICAM permits the message.');

            % Verify no access-denied entries
            reasons = {sc.eventLog.reason};
            testCase.verifyFalse(any(strcmp(reasons, 'access-denied')), ...
                'No access-denied entry should be logged when ICAM permits.');
        end

        % --- Test 4: buildStatsReport includes icam block when icamController present ---
        function testBuildStatsReportIncludesICAMBlock(testCase)
            % Requirements: 20.6, 21.5

            scenario = SimControllerICAMTest.makeScenarioWithEntities(10);
            sc = sim.SimController(scenario);
            sc.run();

            report = sc.buildStatsReport();

            testCase.verifyTrue(isfield(report, 'icam'), ...
                'buildStatsReport() should include icam field when icamController is present.');

            % Verify required ICAM sub-fields
            testCase.verifyTrue(isfield(report.icam, 'authExchanges'), ...
                'icam block should have authExchanges field.');
            testCase.verifyTrue(isfield(report.icam, 'cacheHitRate'), ...
                'icam block should have cacheHitRate field.');
            testCase.verifyTrue(isfield(report.icam, 'accessDeniedCount'), ...
                'icam block should have accessDeniedCount field.');
            testCase.verifyTrue(isfield(report.icam, 'certRenewals'), ...
                'icam block should have certRenewals field.');
            testCase.verifyTrue(isfield(report.icam, 'entityCounts'), ...
                'icam block should have entityCounts field.');
        end

        % --- Test 4b: buildStatsReport without icamController has no icam field ---
        function testBuildStatsReportNoICAMBlockWithoutController(testCase)
            % Requirements: 20.6

            scenario = SimControllerICAMTest.makeBaseNetworkScenario(10);
            sc = sim.SimController(scenario);
            sc.run();

            report = sc.buildStatsReport();

            testCase.verifyFalse(isfield(report, 'icam'), ...
                'buildStatsReport() should NOT include icam field when icamController is [].');
        end

        % --- Test 5: ICAM event types dispatched to correct handlers ---
        function testICAMEventTypesDispatched(testCase)
            % Requirements: 19.2, 20.4

            scenario = SimControllerICAMTest.makeScenarioWithEntities(100);
            sc = sim.SimController(scenario);

            % Schedule AUTH_RESPONSE event manually
            authRespEvent.time                    = 5.0;
            authRespEvent.type                    = sim.EventCalendar.AUTH_RESPONSE;
            authRespEvent.id                      = uint64(9001);
            authRespEvent.payload.srcEntityId     = 'nodeA';
            authRespEvent.payload.dstEntityId     = 'nodeB';
            sc.eventCalendar.schedule(authRespEvent);

            % Schedule CERT_RENEWAL_REQUEST event manually
            certRenewEvent.time               = 6.0;
            certRenewEvent.type               = sim.EventCalendar.CERT_RENEWAL_REQUEST;
            certRenewEvent.id                 = uint64(9002);
            certRenewEvent.payload.entityId   = 'entity-A';
            certRenewEvent.payload.trustAnchorId = 'default-ta';
            sc.eventCalendar.schedule(certRenewEvent);

            % Run should complete without error (events dispatched to handlers)
            testCase.verifyWarningFree(@() sc.run(), ...
                'SimController should dispatch ICAM events without error.');
        end

        % --- Test 6: SimController without icamController behaves identically (no regression) ---
        function testNoRegressionWithoutICAM(testCase)
            % Requirements: 21.1

            scenario = SimControllerICAMTest.makeBaseNetworkScenario(100);

            msg.id               = 'msg-regression';
            msg.srcNodeId        = 'nodeA';
            msg.dstNodeId        = 'nodeB';
            msg.sizeBytes        = 512;
            msg.scheduledTimeSec = 1.0;
            scenario.c2Messages  = msg;

            sc = sim.SimController(scenario);

            testCase.verifyEmpty(sc.icamController, ...
                'icamController should be [] for base scenario.');

            sc.run();

            % Verify normal routing still works
            testCase.verifyTrue(any([sc.eventLog.eventType] == "C2_MESSAGE_RX"), ...
                'C2_MESSAGE_RX should be logged without ICAM (no regression).');
            testCase.verifyEqual(sc.stats.c2MessagesRx, uint64(1), ...
                'c2MessagesRx should be 1 without ICAM.');
        end

    end

    % -----------------------------------------------------------------
    % Private helpers: mock ICAM controllers
    % -----------------------------------------------------------------
    methods (Static, Access = private)

        function ic = makeDenyingICAMController()
            % makeDenyingICAMController  Return a mock ICAMController that always denies.
            % Uses fail-closed policy (no rules) and pre-authenticates pairs.

            policy.enclaves = struct('enclaveId', 'default', 'cacheTtlSec', 0, 'failPolicy', 'closed');
            policy.trustAnchors = struct('trustAnchorId', 'ta1', 'nodeId', 'nodeA', 'certificateValidityPeriodSec', 3600);
            policy.rules = struct.empty(0, 1);  % no rules -> fail-closed -> deny all

            tmpFile = [tempname() '.json'];
            fid = fopen(tmpFile, 'w');
            fprintf(fid, '%s', jsonencode(policy));
            fclose(fid);

            % Build a minimal scenario with the deny policy
            denyScenario.simulationDurationSec = 100;
            denyScenario.policyDefinitionFile  = tmpFile;

            % Build a minimal node registry
            n1.id   = 'nodeA';
            n1.type = 'Stationary';
            n1.lat  = 40.0;
            n1.lon  = -74.0;
            n1.altM = 0.0;
            n1.trajectory     = [];
            n1.keplerElements = [];
            nr = network.NodeRegistry([n1]);

            ec = sim.EventCalendar();

            ic = icam.ICAMController();
            ic.initialize(denyScenario, nr, ec);

            % Pre-authenticate all pairs so checkSend reaches the PDP
            ic.authManager.recordSuccess('nodeA', 'nodeB', 0.0);

            delete(tmpFile);
        end

        function ic = makePermittingICAMController()
            % makePermittingICAMController  Return a mock ICAMController that always permits.

            policy.enclaves = struct('enclaveId', 'default', 'cacheTtlSec', 300, 'failPolicy', 'open');
            policy.trustAnchors = struct('trustAnchorId', 'ta1', 'nodeId', 'nodeA', 'certificateValidityPeriodSec', 3600);
            policy.rules = struct.empty(0, 1);

            tmpFile = [tempname() '.json'];
            fid = fopen(tmpFile, 'w');
            fprintf(fid, '%s', jsonencode(policy));
            fclose(fid);

            permitScenario.simulationDurationSec = 100;
            permitScenario.policyDefinitionFile  = tmpFile;

            n1.id   = 'nodeA';
            n1.type = 'Stationary';
            n1.lat  = 40.0;
            n1.lon  = -74.0;
            n1.altM = 0.0;
            n1.trajectory     = [];
            n1.keplerElements = [];
            nr = network.NodeRegistry([n1]);

            ec = sim.EventCalendar();

            ic = icam.ICAMController();
            ic.initialize(permitScenario, nr, ec);

            delete(tmpFile);
        end

    end

end
