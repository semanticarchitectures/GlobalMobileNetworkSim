classdef PolicyDecisionPointTest < matlab.unittest.TestCase
    % PolicyDecisionPointTest  Unit tests for icam.PolicyDecisionPoint.
    %
    % Covers:
    %   1. Permit decision for matching rule
    %   2. Deny decision for matching rule
    %   3. First-matching-rule semantics
    %   4. Wildcard '*' matches any messageType
    %   5. Fail-open returns permit when no rule matches
    %   6. Fail-closed returns deny when no rule matches
    %   7. netsim:icam:policyJsonError thrown on malformed JSON
    %
    % Requirements: 20.1, 20.3, 20.5

    properties (Access = private)
        FixtureDir  % path to tests/icam/fixtures/
    end

    methods (TestMethodSetup)
        function setFixtureDir(testCase)
            % Resolve the fixture directory relative to this test file.
            thisFile = mfilename('fullpath');
            testCase.FixtureDir = fullfile(fileparts(thisFile), 'fixtures');
        end
    end

    % ======================================================================
    % Helper: write a temporary policy JSON file
    % ======================================================================
    methods (Access = private)

        function filePath = writeTempPolicy(testCase, policyStruct)
            % Serialize policyStruct to a temp JSON file and return its path.
            tmpFile = [tempname() '.json'];
            fid = fopen(tmpFile, 'w');
            testCase.assertNotEqual(fid, -1, 'Could not open temp file for writing');
            fprintf(fid, '%s', jsonencode(policyStruct));
            fclose(fid);
            filePath = tmpFile;
        end

        function pdp = makePdpFromStruct(testCase, policyStruct)
            % Build a PolicyDecisionPoint from a policy struct via temp file.
            filePath = testCase.writeTempPolicy(policyStruct);
            pdp = icam.PolicyDecisionPoint(filePath);
            delete(filePath);
        end

    end

    % ======================================================================
    % Test 1: Permit decision for matching rule
    % ======================================================================
    methods (Test)

        function testPermitDecisionForMatchingRule(testCase)
            % A rule with decision='permit' should return 'permit'.
            %
            % Requirements: 20.3

            policy.enclaves   = struct('enclaveId', 'enc-alpha', ...
                                       'cacheTtlSec', 300, ...
                                       'failPolicy', 'closed');
            policy.trustAnchors = struct('trustAnchorId', 'TA1', ...
                                         'nodeId', 'n1', ...
                                         'certificateValidityPeriodSec', 3600);
            policy.rules = struct('enclave', 'enc-alpha', ...
                                  'role', 'pilot', ...
                                  'messageType', 'POSITION_REPORT', ...
                                  'decision', 'permit');

            pdp = testCase.makePdpFromStruct(policy);
            result = pdp.evaluate('entity1', 'entity2', 'POSITION_REPORT', 'enc-alpha', 0.0);

            testCase.verifyEqual(result.decision, 'permit', ...
                'Matching permit rule should return permit');
        end

        % ======================================================================
        % Test 2: Deny decision for matching rule
        % ======================================================================

        function testDenyDecisionForMatchingRule(testCase)
            % A rule with decision='deny' should return 'deny'.
            %
            % Requirements: 20.3

            policy.enclaves   = struct('enclaveId', 'enc-alpha', ...
                                       'cacheTtlSec', 300, ...
                                       'failPolicy', 'open');
            policy.trustAnchors = struct('trustAnchorId', 'TA1', ...
                                         'nodeId', 'n1', ...
                                         'certificateValidityPeriodSec', 3600);
            policy.rules = struct('enclave', 'enc-alpha', ...
                                  'role', 'pilot', ...
                                  'messageType', 'COMMAND_MSG', ...
                                  'decision', 'deny');

            pdp = testCase.makePdpFromStruct(policy);
            result = pdp.evaluate('entity1', 'entity2', 'COMMAND_MSG', 'enc-alpha', 0.0);

            testCase.verifyEqual(result.decision, 'deny', ...
                'Matching deny rule should return deny');
        end

        % ======================================================================
        % Test 3: First-matching-rule semantics
        % ======================================================================

        function testFirstMatchingRuleWins(testCase)
            % When multiple rules match, the first one in the list should win.
            %
            % Requirements: 20.3

            % Rule 1: permit POSITION_REPORT in enc-alpha
            % Rule 2: deny * in enc-alpha  (would match POSITION_REPORT too)
            % Expected: permit (rule 1 wins)
            filePath = fullfile(testCase.FixtureDir, 'test_policy.json');
            pdp = icam.PolicyDecisionPoint(filePath);

            result = pdp.evaluate('pilot1', 'entity2', 'POSITION_REPORT', 'enc-alpha', 0.0);
            testCase.verifyEqual(result.decision, 'permit', ...
                'First matching rule (permit POSITION_REPORT) should win over later deny *');
        end

        function testFirstMatchingRuleWinsForNonSpecificMessage(testCase)
            % For a message type not covered by the first rule, the second rule
            % (deny *) should apply.
            %
            % Requirements: 20.3

            filePath = fullfile(testCase.FixtureDir, 'test_policy.json');
            pdp = icam.PolicyDecisionPoint(filePath);

            % COMMAND_MSG is not POSITION_REPORT, so rule 1 doesn't match;
            % rule 2 (deny *) should match.
            result = pdp.evaluate('pilot1', 'entity2', 'COMMAND_MSG', 'enc-alpha', 0.0);
            testCase.verifyEqual(result.decision, 'deny', ...
                'Second rule (deny *) should apply when first rule does not match');
        end

        % ======================================================================
        % Test 4: Wildcard '*' matches any messageType
        % ======================================================================

        function testWildcardMatchesAnyMessageType(testCase)
            % A rule with messageType='*' should match any message type string.
            %
            % Requirements: 20.3

            policy.enclaves   = struct('enclaveId', 'enc-bravo', ...
                                       'cacheTtlSec', 60, ...
                                       'failPolicy', 'closed');
            policy.trustAnchors = struct('trustAnchorId', 'TA1', ...
                                         'nodeId', 'n1', ...
                                         'certificateValidityPeriodSec', 3600);
            policy.rules = struct('enclave', 'enc-bravo', ...
                                  'role', 'commander', ...
                                  'messageType', '*', ...
                                  'decision', 'permit');

            pdp = testCase.makePdpFromStruct(policy);

            % Try several different message types
            msgTypes = {'POSITION_REPORT', 'COMMAND_MSG', 'STATUS_UPDATE', 'ANYTHING'};
            for i = 1:numel(msgTypes)
                result = pdp.evaluate('e1', 'e2', msgTypes{i}, 'enc-bravo', 0.0);
                testCase.verifyEqual(result.decision, 'permit', ...
                    sprintf('Wildcard rule should permit message type: %s', msgTypes{i}));
            end
        end

        function testWildcardFromFixture(testCase)
            % Verify wildcard behavior using the fixture policy file.
            %
            % Requirements: 20.3

            filePath = fullfile(testCase.FixtureDir, 'test_policy.json');
            pdp = icam.PolicyDecisionPoint(filePath);

            % enc-bravo has a wildcard permit rule for commander
            result = pdp.evaluate('cmd1', 'e2', 'RANDOM_MSG_TYPE', 'enc-bravo', 0.0);
            testCase.verifyEqual(result.decision, 'permit', ...
                'Wildcard rule in enc-bravo should permit any message type');
        end

        % ======================================================================
        % Test 5: Fail-open returns permit when no rule matches
        % ======================================================================

        function testFailOpenReturnsPermitWhenNoRuleMatches(testCase)
            % When no rule matches and failPolicy='open', result should be 'permit'.
            %
            % Requirements: 20.5

            policy.enclaves   = struct('enclaveId', 'enc-open', ...
                                       'cacheTtlSec', 60, ...
                                       'failPolicy', 'open');
            policy.trustAnchors = struct('trustAnchorId', 'TA1', ...
                                         'nodeId', 'n1', ...
                                         'certificateValidityPeriodSec', 3600);
            policy.rules = struct('enclave', 'enc-other', ...
                                  'role', 'pilot', ...
                                  'messageType', 'MSG', ...
                                  'decision', 'deny');

            pdp = testCase.makePdpFromStruct(policy);

            % No rule matches enc-open
            result = pdp.evaluate('e1', 'e2', 'ANY_MSG', 'enc-open', 0.0);
            testCase.verifyEqual(result.decision, 'permit', ...
                'Fail-open enclave should return permit when no rule matches');
        end

        function testEvaluateWithPdpUnreachableFailOpen(testCase)
            % evaluateWithPdpUnreachable should return permit for fail-open.
            %
            % Requirements: 20.5

            policy.enclaves   = struct('enclaveId', 'enc-open', ...
                                       'cacheTtlSec', 60, ...
                                       'failPolicy', 'open');
            policy.trustAnchors = struct('trustAnchorId', 'TA1', ...
                                         'nodeId', 'n1', ...
                                         'certificateValidityPeriodSec', 3600);
            policy.rules = struct.empty(0, 1);

            pdp = testCase.makePdpFromStruct(policy);

            result = pdp.evaluateWithPdpUnreachable('enc-open');
            testCase.verifyEqual(result.decision, 'permit', ...
                'evaluateWithPdpUnreachable should return permit for fail-open');
        end

        % ======================================================================
        % Test 6: Fail-closed returns deny when no rule matches
        % ======================================================================

        function testFailClosedReturnsDenyWhenNoRuleMatches(testCase)
            % When no rule matches and failPolicy='closed', result should be 'deny'.
            %
            % Requirements: 20.5

            policy.enclaves   = struct('enclaveId', 'enc-closed', ...
                                       'cacheTtlSec', 300, ...
                                       'failPolicy', 'closed');
            policy.trustAnchors = struct('trustAnchorId', 'TA1', ...
                                         'nodeId', 'n1', ...
                                         'certificateValidityPeriodSec', 3600);
            policy.rules = struct('enclave', 'enc-other', ...
                                  'role', 'pilot', ...
                                  'messageType', 'MSG', ...
                                  'decision', 'permit');

            pdp = testCase.makePdpFromStruct(policy);

            % No rule matches enc-closed
            result = pdp.evaluate('e1', 'e2', 'ANY_MSG', 'enc-closed', 0.0);
            testCase.verifyEqual(result.decision, 'deny', ...
                'Fail-closed enclave should return deny when no rule matches');
        end

        function testEvaluateWithPdpUnreachableFailClosed(testCase)
            % evaluateWithPdpUnreachable should return deny for fail-closed.
            %
            % Requirements: 20.5

            policy.enclaves   = struct('enclaveId', 'enc-closed', ...
                                       'cacheTtlSec', 300, ...
                                       'failPolicy', 'closed');
            policy.trustAnchors = struct('trustAnchorId', 'TA1', ...
                                         'nodeId', 'n1', ...
                                         'certificateValidityPeriodSec', 3600);
            policy.rules = struct.empty(0, 1);

            pdp = testCase.makePdpFromStruct(policy);

            result = pdp.evaluateWithPdpUnreachable('enc-closed');
            testCase.verifyEqual(result.decision, 'deny', ...
                'evaluateWithPdpUnreachable should return deny for fail-closed');
        end

        function testDefaultFailPolicyIsClosedForUnknownEnclave(testCase)
            % When the enclave is not in the policy, default failPolicy is 'closed'.
            %
            % Requirements: 20.5

            policy.enclaves   = struct('enclaveId', 'enc-alpha', ...
                                       'cacheTtlSec', 300, ...
                                       'failPolicy', 'open');
            policy.trustAnchors = struct('trustAnchorId', 'TA1', ...
                                         'nodeId', 'n1', ...
                                         'certificateValidityPeriodSec', 3600);
            policy.rules = struct.empty(0, 1);

            pdp = testCase.makePdpFromStruct(policy);

            % Unknown enclave → default closed
            result = pdp.evaluate('e1', 'e2', 'MSG', 'enc-unknown', 0.0);
            testCase.verifyEqual(result.decision, 'deny', ...
                'Unknown enclave should default to fail-closed (deny)');
        end

        % ======================================================================
        % Test 7: netsim:icam:policyJsonError thrown on malformed JSON
        % ======================================================================

        function testPolicyJsonErrorOnMalformedJson(testCase)
            % Constructor should throw netsim:icam:policyJsonError on bad JSON.
            %
            % Requirements: 20.1

            tmpFile = [tempname() '.json'];
            fid = fopen(tmpFile, 'w');
            fprintf(fid, '{ this is not valid json !!!');
            fclose(fid);

            testCase.verifyError( ...
                @() icam.PolicyDecisionPoint(tmpFile), ...
                'netsim:icam:policyJsonError', ...
                'Constructor should throw netsim:icam:policyJsonError on malformed JSON');

            delete(tmpFile);
        end

        function testPolicyJsonErrorOnNonExistentFile(testCase)
            % Constructor should throw netsim:icam:policyJsonError when file
            % does not exist (fileread will fail).
            %
            % Requirements: 20.1

            testCase.verifyError( ...
                @() icam.PolicyDecisionPoint('/nonexistent/path/policy.json'), ...
                'netsim:icam:policyJsonError', ...
                'Constructor should throw netsim:icam:policyJsonError for missing file');
        end

        % ======================================================================
        % Additional: getCacheTtl and getFailPolicy
        % ======================================================================

        function testGetCacheTtlReturnsConfiguredValue(testCase)
            % getCacheTtl should return the cacheTtlSec from the policy.
            %
            % Requirements: 20.1

            filePath = fullfile(testCase.FixtureDir, 'test_policy.json');
            pdp = icam.PolicyDecisionPoint(filePath);

            testCase.verifyEqual(pdp.getCacheTtl('enc-alpha'), 300, ...
                'getCacheTtl should return 300 for enc-alpha');
            testCase.verifyEqual(pdp.getCacheTtl('enc-bravo'), 60, ...
                'getCacheTtl should return 60 for enc-bravo');
        end

        function testGetCacheTtlDefaultsTo300ForUnknownEnclave(testCase)
            % getCacheTtl should return 300 for an unknown enclave.
            %
            % Requirements: 20.1

            filePath = fullfile(testCase.FixtureDir, 'test_policy.json');
            pdp = icam.PolicyDecisionPoint(filePath);

            testCase.verifyEqual(pdp.getCacheTtl('enc-unknown'), 300, ...
                'getCacheTtl should default to 300 for unknown enclave');
        end

        function testGetFailPolicyReturnsConfiguredValue(testCase)
            % getFailPolicy should return the failPolicy from the policy.
            %
            % Requirements: 20.5

            filePath = fullfile(testCase.FixtureDir, 'test_policy.json');
            pdp = icam.PolicyDecisionPoint(filePath);

            testCase.verifyEqual(pdp.getFailPolicy('enc-alpha'), 'closed', ...
                'getFailPolicy should return closed for enc-alpha');
            testCase.verifyEqual(pdp.getFailPolicy('enc-bravo'), 'open', ...
                'getFailPolicy should return open for enc-bravo');
        end

        function testResultStructHasDecisionAndReasonFields(testCase)
            % evaluate should return a struct with 'decision' and 'reason' fields.
            %
            % Requirements: 20.3

            filePath = fullfile(testCase.FixtureDir, 'test_policy.json');
            pdp = icam.PolicyDecisionPoint(filePath);

            result = pdp.evaluate('e1', 'e2', 'POSITION_REPORT', 'enc-alpha', 0.0);
            testCase.verifyTrue(isfield(result, 'decision'), ...
                'Result should have a decision field');
            testCase.verifyTrue(isfield(result, 'reason'), ...
                'Result should have a reason field');
        end

    end % methods (Test)

end % classdef
