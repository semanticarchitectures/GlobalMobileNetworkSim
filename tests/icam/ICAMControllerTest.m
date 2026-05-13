classdef ICAMControllerTest < matlab.unittest.TestCase
    % ICAMControllerTest  Unit tests for icam.ICAMController.
    %
    % Covers:
    %   1. initialize constructs all subsystems when scenario has entities
    %   2. initialize works with empty entities (no error)
    %   3. checkSend returns 'permit' for authenticated pair with permit policy
    %   4. handleAuthResponse calls authManager.recordSuccess
    %   5. buildICAMReport returns struct with all required fields
    %
    % Requirements: 17.1, 18.3, 19.3, 19.5, 20.6, 21.1, 21.5, 23.6, 24.5

    % ======================================================================
    % Helper methods
    % ======================================================================
    methods (Access = private)

        function nr = makeNodeRegistry(~, varargin)
            % Build a NodeRegistry with one or more stationary nodes.
            nodeIds = varargin;
            nNodes = numel(nodeIds);
            nodes(nNodes) = struct();
            for k = 1:nNodes
                nodes(k).id            = nodeIds{k};
                nodes(k).type          = 'Stationary';
                nodes(k).lat           = 0;
                nodes(k).lon           = 0;
                nodes(k).altM          = 0;
                nodes(k).trajectory    = [];
                nodes(k).keplerElements = [];
            end
            nr = network.NodeRegistry(nodes);
        end

        function scenario = makeScenarioWithEntities(~, nodeIds, entityIds)
            % Build a minimal scenario with entities.
            scenario.scenarioName = 'test-scenario';
            scenario.simulationDurationSec = 3600;

            nEntities = numel(entityIds);
            entities(nEntities) = struct();
            for k = 1:nEntities
                entities(k).id     = entityIds{k};
                entities(k).nodeId = nodeIds{min(k, numel(nodeIds))};
                entities(k).type   = 'human';
                entities(k).certificate.trustAnchorId = 'TA1';
                entities(k).certificate.validityPeriodSec = 3600;
                entities(k).roleBindings.enclaveId = 'enc-alpha';
                entities(k).roleBindings.roleName  = 'pilot';
            end
            scenario.entities = entities;
        end

        function scenario = makeEmptyScenario(~)
            % Build a minimal scenario with no entities.
            scenario.scenarioName = 'empty-scenario';
            scenario.simulationDurationSec = 3600;
        end

    end

    % ======================================================================
    % Test 1: initialize constructs all subsystems when scenario has entities
    % ======================================================================
    methods (Test)

        function testInitializeConstructsAllSubsystems(testCase)
            % initialize should construct EntityRegistry, CredentialStore,
            % AuthenticationManager, PDP, CredentialCache, and PEP when the
            % scenario has entities.
            %
            % Requirements: 17.1, 18.1, 19.1, 20.1, 21.1, 23.1

            nr = testCase.makeNodeRegistry('N1', 'N2');
            scenario = testCase.makeScenarioWithEntities({'N1', 'N2'}, {'E1', 'E2'});
            ec = sim.EventCalendar();

            ic = icam.ICAMController();
            ic.initialize(scenario, nr, ec);

            testCase.verifyNotEmpty(ic.entityRegistry, ...
                'EntityRegistry should be constructed');
            testCase.verifyNotEmpty(ic.credentialStore, ...
                'CredentialStore should be constructed');
            testCase.verifyNotEmpty(ic.authManager, ...
                'AuthenticationManager should be constructed');
            testCase.verifyNotEmpty(ic.pdp, ...
                'PolicyDecisionPoint should be constructed');
            testCase.verifyNotEmpty(ic.credentialCache, ...
                'CredentialCache should be constructed');
            testCase.verifyNotEmpty(ic.pep, ...
                'PolicyEnforcementPoint should be constructed');
        end

        function testInitializeIssuesCertificatesForAllEntities(testCase)
            % initialize should issue certificates for all entities in the scenario.
            %
            % Requirements: 18.1

            nr = testCase.makeNodeRegistry('N1', 'N2');
            scenario = testCase.makeScenarioWithEntities({'N1', 'N2'}, {'E1', 'E2'});
            ec = sim.EventCalendar();

            ic = icam.ICAMController();
            ic.initialize(scenario, nr, ec);

            % Verify certificates were issued
            cert1 = ic.credentialStore.getCertificate('E1');
            cert2 = ic.credentialStore.getCertificate('E2');

            testCase.verifyNotEmpty(cert1, 'Certificate for E1 should be issued');
            testCase.verifyNotEmpty(cert2, 'Certificate for E2 should be issued');
        end

        function testInitializeStoresEventCalendarReference(testCase)
            % initialize should store the eventCalendar reference.
            %
            % Requirements: 19.2

            nr = testCase.makeNodeRegistry('N1');
            scenario = testCase.makeEmptyScenario();
            ec = sim.EventCalendar();

            ic = icam.ICAMController();
            ic.initialize(scenario, nr, ec);

            testCase.verifyEqual(ic.eventCalendar, ec, ...
                'EventCalendar reference should be stored');
        end

        % ======================================================================
        % Test 2: initialize works with empty entities (no error)
        % ======================================================================

        function testInitializeWithEmptyEntities(testCase)
            % initialize should work without error when the scenario has no entities.
            %
            % Requirements: 17.1

            nr = testCase.makeNodeRegistry('N1');
            scenario = testCase.makeEmptyScenario();
            ec = sim.EventCalendar();

            ic = icam.ICAMController();

            testCase.verifyWarningFree(@() ic.initialize(scenario, nr, ec), ...
                'initialize should not error with empty entities');

            testCase.verifyNotEmpty(ic.entityRegistry, ...
                'EntityRegistry should be constructed even with no entities');
            testCase.verifyEqual(ic.entityRegistry.count(), 0, ...
                'EntityRegistry should have count() == 0');
        end

        function testInitializeWithNoEntitiesField(testCase)
            % initialize should work when the scenario has no 'entities' field at all.
            %
            % Requirements: 17.1

            nr = testCase.makeNodeRegistry('N1');
            scenario.scenarioName = 'no-entities-field';
            scenario.simulationDurationSec = 3600;
            ec = sim.EventCalendar();

            ic = icam.ICAMController();

            testCase.verifyWarningFree(@() ic.initialize(scenario, nr, ec), ...
                'initialize should not error when entities field is missing');
        end

        % ======================================================================
        % Test 3: checkSend returns 'permit' for authenticated pair with permit policy
        % ======================================================================

        function testCheckSendReturnsPermitForAuthenticatedPair(testCase)
            % checkSend should return 'permit' when the pair is authenticated
            % and the policy permits the message.
            %
            % Requirements: 19.1, 21.1

            nr = testCase.makeNodeRegistry('N1', 'N2');
            scenario = testCase.makeScenarioWithEntities({'N1', 'N2'}, {'E1', 'E2'});
            ec = sim.EventCalendar();

            ic = icam.ICAMController();
            ic.initialize(scenario, nr, ec);

            % Pre-authenticate the pair
            ic.authManager.recordSuccess('E1', 'E2', 0.0);

            % checkSend should return 'permit' (default permissive PDP)
            decision = ic.checkSend('E1', 'E2', 'MSG_TYPE', 'enc-alpha', 0.0);

            testCase.verifyEqual(decision, 'permit', ...
                'checkSend should return permit for authenticated pair with permit policy');
        end

        function testCheckSendReturnsPendingForUnauthenticatedPair(testCase)
            % checkSend should return 'pending' when the pair is not yet authenticated.
            %
            % Requirements: 19.1, 19.2

            nr = testCase.makeNodeRegistry('N1', 'N2');
            scenario = testCase.makeScenarioWithEntities({'N1', 'N2'}, {'E1', 'E2'});
            ec = sim.EventCalendar();

            ic = icam.ICAMController();
            ic.initialize(scenario, nr, ec);

            % checkSend should return 'pending' and schedule auth events
            decision = ic.checkSend('E1', 'E2', 'MSG_TYPE', 'enc-alpha', 0.0);

            testCase.verifyEqual(decision, 'pending', ...
                'checkSend should return pending for unauthenticated pair');
            testCase.verifyGreaterThan(ec.eventCount(), 0, ...
                'Auth events should be scheduled');
        end

        function testCheckSendReturnsDenyWhenPolicyDenies(testCase)
            % checkSend should return 'deny' when the policy denies the message.
            %
            % Requirements: 21.1, 21.5

            nr = testCase.makeNodeRegistry('N1', 'N2');
            scenario = testCase.makeScenarioWithEntities({'N1', 'N2'}, {'E1', 'E2'});

            % Create a deny-all policy
            policy.enclaves   = struct('enclaveId', 'enc-alpha', ...
                                       'cacheTtlSec', 300, ...
                                       'failPolicy', 'closed');
            policy.trustAnchors = struct('trustAnchorId', 'TA1', ...
                                         'nodeId', 'n1', ...
                                         'certificateValidityPeriodSec', 3600);
            policy.rules = struct.empty(0, 1);

            tmpFile = [tempname() '.json'];
            fid = fopen(tmpFile, 'w');
            fprintf(fid, '%s', jsonencode(policy));
            fclose(fid);

            scenario.policyDefinitionFile = tmpFile;

            ec = sim.EventCalendar();
            ic = icam.ICAMController();
            ic.initialize(scenario, nr, ec);

            delete(tmpFile);

            % Pre-authenticate the pair
            ic.authManager.recordSuccess('E1', 'E2', 0.0);

            % checkSend should return 'deny' (fail-closed policy)
            decision = ic.checkSend('E1', 'E2', 'MSG_TYPE', 'enc-alpha', 0.0);

            testCase.verifyEqual(decision, 'deny', ...
                'checkSend should return deny when policy denies');
        end

        % ======================================================================
        % Test 4: handleAuthResponse calls authManager.recordSuccess
        % ======================================================================

        function testHandleAuthResponseRecordsSuccess(testCase)
            % handleAuthResponse should call authManager.recordSuccess.
            %
            % Requirements: 19.3, 19.4

            nr = testCase.makeNodeRegistry('N1', 'N2');
            scenario = testCase.makeScenarioWithEntities({'N1', 'N2'}, {'E1', 'E2'});
            ec = sim.EventCalendar();

            ic = icam.ICAMController();
            ic.initialize(scenario, nr, ec);

            % Build an AUTH_RESPONSE event
            event.time = 10.0;
            event.type = sim.EventCalendar.AUTH_RESPONSE;
            event.id   = uint64(1);
            event.payload.srcEntityId = 'E1';
            event.payload.dstEntityId = 'E2';
            event.payload.success     = true;

            % Before: not authenticated
            testCase.verifyFalse(ic.authManager.isAuthenticated('E1', 'E2'), ...
                'Pair should not be authenticated before handleAuthResponse');

            % Handle the event
            ic.handleAuthResponse(event);

            % After: authenticated
            testCase.verifyTrue(ic.authManager.isAuthenticated('E1', 'E2'), ...
                'Pair should be authenticated after handleAuthResponse');
        end

        function testHandleAuthResponseIncrementsSuccessCount(testCase)
            % handleAuthResponse should increment nAuthSuccessful.
            %
            % Requirements: 19.3

            nr = testCase.makeNodeRegistry('N1', 'N2');
            scenario = testCase.makeScenarioWithEntities({'N1', 'N2'}, {'E1', 'E2'});
            ec = sim.EventCalendar();

            ic = icam.ICAMController();
            ic.initialize(scenario, nr, ec);

            event.time = 10.0;
            event.type = sim.EventCalendar.AUTH_RESPONSE;
            event.id   = uint64(1);
            event.payload.srcEntityId = 'E1';
            event.payload.dstEntityId = 'E2';
            event.payload.success     = true;

            ic.handleAuthResponse(event);

            report = ic.buildICAMReport();
            testCase.verifyEqual(report.authExchanges.successful, uint64(1), ...
                'nAuthSuccessful should be 1 after one handleAuthResponse');
        end

        % ======================================================================
        % Test 5: buildICAMReport returns struct with all required fields
        % ======================================================================

        function testBuildICAMReportHasAllRequiredFields(testCase)
            % buildICAMReport should return a struct with all required top-level fields.
            %
            % Requirements: 20.6, 21.5, 23.6, 24.5

            nr = testCase.makeNodeRegistry('N1');
            scenario = testCase.makeEmptyScenario();
            ec = sim.EventCalendar();

            ic = icam.ICAMController();
            ic.initialize(scenario, nr, ec);

            report = ic.buildICAMReport();

            % Verify all required top-level fields
            testCase.verifyTrue(isfield(report, 'authExchanges'), ...
                'Report should have authExchanges field');
            testCase.verifyTrue(isfield(report, 'cacheHitRate'), ...
                'Report should have cacheHitRate field');
            testCase.verifyTrue(isfield(report, 'accessDeniedCount'), ...
                'Report should have accessDeniedCount field');
            testCase.verifyTrue(isfield(report, 'certRenewals'), ...
                'Report should have certRenewals field');
            testCase.verifyTrue(isfield(report, 'entityCounts'), ...
                'Report should have entityCounts field');
            testCase.verifyTrue(isfield(report, 'pdpStats'), ...
                'Report should have pdpStats field');
            testCase.verifyTrue(isfield(report, 'perEnclaveRoleBindingCounts'), ...
                'Report should have perEnclaveRoleBindingCounts field');
        end

        function testBuildICAMReportAuthExchangesSubFields(testCase)
            % buildICAMReport authExchanges should have all required sub-fields.
            %
            % Requirements: 19.1, 19.3, 19.5

            nr = testCase.makeNodeRegistry('N1');
            scenario = testCase.makeEmptyScenario();
            ec = sim.EventCalendar();

            ic = icam.ICAMController();
            ic.initialize(scenario, nr, ec);

            report = ic.buildICAMReport();

            testCase.verifyTrue(isfield(report.authExchanges, 'total'), ...
                'authExchanges should have total field');
            testCase.verifyTrue(isfield(report.authExchanges, 'successful'), ...
                'authExchanges should have successful field');
            testCase.verifyTrue(isfield(report.authExchanges, 'failed'), ...
                'authExchanges should have failed field');
            testCase.verifyTrue(isfield(report.authExchanges, 'timedOut'), ...
                'authExchanges should have timedOut field');
        end

        function testBuildICAMReportAccessDeniedCountSubFields(testCase)
            % buildICAMReport accessDeniedCount should have all required sub-fields.
            %
            % Requirements: 21.5

            nr = testCase.makeNodeRegistry('N1');
            scenario = testCase.makeEmptyScenario();
            ec = sim.EventCalendar();

            ic = icam.ICAMController();
            ic.initialize(scenario, nr, ec);

            report = ic.buildICAMReport();

            testCase.verifyTrue(isfield(report.accessDeniedCount, 'total'), ...
                'accessDeniedCount should have total field');
            testCase.verifyTrue(isfield(report.accessDeniedCount, 'perEntity'), ...
                'accessDeniedCount should have perEntity field');
            testCase.verifyTrue(isfield(report.accessDeniedCount, 'perEnclave'), ...
                'accessDeniedCount should have perEnclave field');
        end

        function testBuildICAMReportCertRenewalsSubFields(testCase)
            % buildICAMReport certRenewals should have all required sub-fields.
            %
            % Requirements: 18.3, 18.4, 18.5

            nr = testCase.makeNodeRegistry('N1');
            scenario = testCase.makeEmptyScenario();
            ec = sim.EventCalendar();

            ic = icam.ICAMController();
            ic.initialize(scenario, nr, ec);

            report = ic.buildICAMReport();

            testCase.verifyTrue(isfield(report.certRenewals, 'total'), ...
                'certRenewals should have total field');
            testCase.verifyTrue(isfield(report.certRenewals, 'successful'), ...
                'certRenewals should have successful field');
            testCase.verifyTrue(isfield(report.certRenewals, 'failed'), ...
                'certRenewals should have failed field');
        end

        function testBuildICAMReportEntityCountsSubFields(testCase)
            % buildICAMReport entityCounts should have human and npe fields.
            %
            % Requirements: 24.5

            nr = testCase.makeNodeRegistry('N1');
            scenario = testCase.makeEmptyScenario();
            ec = sim.EventCalendar();

            ic = icam.ICAMController();
            ic.initialize(scenario, nr, ec);

            report = ic.buildICAMReport();

            testCase.verifyTrue(isfield(report.entityCounts, 'human'), ...
                'entityCounts should have human field');
            testCase.verifyTrue(isfield(report.entityCounts, 'npe'), ...
                'entityCounts should have npe field');
        end

        function testBuildICAMReportEntityCountsCorrect(testCase)
            % buildICAMReport should count human and NPE entities correctly.
            %
            % Requirements: 24.5

            nr = testCase.makeNodeRegistry('N1', 'N2', 'N3');
            scenario.scenarioName = 'test-scenario';
            scenario.simulationDurationSec = 3600;

            entities(1).id     = 'E1';
            entities(1).nodeId = 'N1';
            entities(1).type   = 'human';
            entities(2).id     = 'E2';
            entities(2).nodeId = 'N2';
            entities(2).type   = 'NPE';
            entities(3).id     = 'E3';
            entities(3).nodeId = 'N3';
            entities(3).type   = 'human';
            scenario.entities = entities;

            ec = sim.EventCalendar();
            ic = icam.ICAMController();
            ic.initialize(scenario, nr, ec);

            report = ic.buildICAMReport();

            testCase.verifyEqual(report.entityCounts.human, 2, ...
                'Should count 2 human entities');
            testCase.verifyEqual(report.entityCounts.npe, 1, ...
                'Should count 1 NPE entity');
        end

        function testBuildICAMReportCacheHitRateComputation(testCase)
            % buildICAMReport should compute cacheHitRate correctly.
            %
            % Requirements: 23.6

            nr = testCase.makeNodeRegistry('N1', 'N2');
            scenario = testCase.makeScenarioWithEntities({'N1', 'N2'}, {'E1', 'E2'});
            ec = sim.EventCalendar();

            ic = icam.ICAMController();
            ic.initialize(scenario, nr, ec);

            % Pre-authenticate
            ic.authManager.recordSuccess('E1', 'E2', 0.0);

            % First call — cache miss
            ic.checkSend('E1', 'E2', 'MSG', 'enc-alpha', 0.0);

            % Second call — cache hit
            ic.checkSend('E1', 'E2', 'MSG', 'enc-alpha', 10.0);

            report = ic.buildICAMReport();

            % cacheHitRate = hits / (hits + misses) = 1 / 2 = 0.5
            testCase.verifyEqual(report.cacheHitRate, 0.5, ...
                'cacheHitRate should be 0.5 (1 hit, 1 miss)');
        end

        % ======================================================================
        % Additional: handleAuthTimeout
        % ======================================================================

        function testHandleAuthTimeoutIncrementsTimedOutCount(testCase)
            % handleAuthTimeout should increment nAuthTimedOut.
            %
            % Requirements: 19.5

            nr = testCase.makeNodeRegistry('N1', 'N2');
            scenario = testCase.makeScenarioWithEntities({'N1', 'N2'}, {'E1', 'E2'});
            ec = sim.EventCalendar();

            ic = icam.ICAMController();
            ic.initialize(scenario, nr, ec);

            event.time = 30.0;
            event.type = sim.EventCalendar.AUTH_TIMEOUT;
            event.id   = uint64(1);
            event.payload.srcEntityId = 'E1';
            event.payload.dstEntityId = 'E2';

            ic.handleAuthTimeout(event);

            report = ic.buildICAMReport();
            testCase.verifyEqual(report.authExchanges.timedOut, uint64(1), ...
                'nAuthTimedOut should be 1 after one handleAuthTimeout');
        end

        % ======================================================================
        % Additional: checkExpiredCredentials
        % ======================================================================

        function testCheckExpiredCredentialsSchedulesRenewalEvents(testCase)
            % checkExpiredCredentials should schedule CERT_RENEWAL_REQUEST events
            % for expired certificates.
            %
            % Requirements: 18.3

            nr = testCase.makeNodeRegistry('N1');
            scenario = testCase.makeScenarioWithEntities({'N1'}, {'E1'});
            ec = sim.EventCalendar();

            ic = icam.ICAMController();
            ic.initialize(scenario, nr, ec);

            % Manually expire the certificate by setting expirySec to 0
            ic.credentialStore.issueCertificate('E1', 'TA1', struct('enclaveId', 'enc', 'roleName', 'role'), 0, 0);

            % Check at t=10 — cert should be expired
            ic.checkExpiredCredentials(10.0);

            % Verify a CERT_RENEWAL_REQUEST event was scheduled
            foundRenewal = false;
            while ~ec.isEmpty()
                ev = ec.popNext();
                if strcmp(ev.type, sim.EventCalendar.CERT_RENEWAL_REQUEST)
                    foundRenewal = true;
                    break;
                end
            end

            testCase.verifyTrue(foundRenewal, ...
                'CERT_RENEWAL_REQUEST event should be scheduled for expired cert');
        end

    end % methods (Test)

end % classdef
