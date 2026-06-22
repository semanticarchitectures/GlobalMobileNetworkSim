classdef SecurityEvalTest < matlab.unittest.TestCase
    % SecurityEvalTest  Unit and property-based tests for the security evaluation module.
    %
    % Unit Tests (Task 75):
    %   1. testIntendedPolicyLoaderRoundTrip
    %   2. testIntendedPolicyEvaluateExactMatch
    %   3. testIntendedPolicyEvaluateWildcard
    %   4. testIntendedPolicyEvaluateDefault
    %   5. testSecurityOracleConformant
    %   6. testSecurityOracleViolation
    %   7. testSecurityOracleOverRestriction
    %   8. testSecurityOracleConformanceScore
    %   9. testScenarioLibraryListTemplates
    %  10. testScenarioLibraryInstantiate
    %
    % Property-Based Tests (Task 76, 100 iterations):
    %  11. testP41_OracleViolationCompleteness
    %  12. testP42_ConformanceScoreConsistency
    %  13. testP43_PolicyGapDetection
    %
    % Requirements: R42, R43, R44, R45, R46, R48

    properties (Access = private)
        ProjectRoot  % path to the project root directory
        TempDir      % temporary directory for test artifacts
    end

    methods (TestClassSetup)
        function addProjectToPath(testCase)
            % Add the project root to the MATLAB path so +security package is visible.
            thisFile = mfilename('fullpath');
            testsDir = fileparts(fileparts(thisFile));  % tests/security -> tests/
            testCase.ProjectRoot = fileparts(testsDir); % tests/ -> project root
            addpath(testCase.ProjectRoot);
        end
    end

    methods (TestMethodSetup)
        function createTempDir(testCase)
            % Create a unique temporary directory for each test method.
            testCase.TempDir = tempname();
            mkdir(testCase.TempDir);
        end
    end

    methods (TestMethodTeardown)
        function removeTempDir(testCase)
            % Clean up temporary directory after each test method.
            if exist(testCase.TempDir, 'dir')
                rmdir(testCase.TempDir, 's');
            end
        end
    end

    % ======================================================================
    % Helper Methods
    % ======================================================================
    methods (Access = private)

        function policy = createSamplePolicy(~)
            % Create a sample IntendedPolicy struct for testing.
            policy.description = 'Test policy';
            policy.defaultOutcome = 'deny';
            policy.rules = struct( ...
                'role', {'commander', 'analyst', '*'}, ...
                'classification', {'SECRET', 'UNCLASSIFIED', '*'}, ...
                'enclave', {'enclave_A', 'enclave_A', '*'}, ...
                'operation', {'read', 'read', 'read'}, ...
                'outcome', {'permit', 'permit', 'deny'});
        end

        function filePath = writePolicyToFile(testCase, policy)
            % Write an IntendedPolicy struct to a temp JSON file.
            filePath = fullfile(testCase.TempDir, 'intended_policy.json');
            security.IntendedPolicyLoader.save(policy, filePath);
        end

        function event = makeSecurityEvent(~, id, role, classification, enclave, operation, outcome)
            % Build a security event struct for SecurityOracle evaluation.
            event.type = 'DATA_FETCH';
            event.id = uint64(id);
            event.payload.role = role;
            event.payload.classification = classification;
            event.payload.enclave = enclave;
            event.payload.operation = operation;
            event.payload.outcome = outcome;
        end

        function topology = createMinimalTopology(~)
            % Create a minimal network topology for ScenarioLibrary tests.
            topology.nodes = struct( ...
                'id', {'node_1', 'node_2'}, ...
                'type', {'ground', 'ground'}, ...
                'enclave', {'enclave_A', 'enclave_B'});
            topology.links = struct( ...
                'id', {'link_1'}, ...
                'srcNodeId', {'node_1'}, ...
                'dstNodeId', {'node_2'});
            topology.entities = struct( ...
                'id', {'entity_1', 'entity_2'}, ...
                'nodeId', {'node_1', 'node_2'}, ...
                'role', {'analyst', 'commander'});
        end

    end

    % ======================================================================
    % Unit Tests (Task 75)
    % ======================================================================
    methods (Test)

        function testIntendedPolicyLoaderRoundTrip(testCase)
            % Save then load a policy and verify all fields match.
            %
            % Requirements: R42

            original = testCase.createSamplePolicy();
            filePath = testCase.writePolicyToFile(original);

            loaded = security.IntendedPolicyLoader.load(filePath);

            testCase.verifyEqual(loaded.description, original.description, ...
                'Description should round-trip correctly');
            testCase.verifyEqual(loaded.defaultOutcome, original.defaultOutcome, ...
                'defaultOutcome should round-trip correctly');
            testCase.verifyEqual(numel(loaded.rules), numel(original.rules), ...
                'Number of rules should match after round-trip');

            for k = 1:numel(original.rules)
                testCase.verifyEqual(loaded.rules(k).role, original.rules(k).role, ...
                    sprintf('Rule %d role should match', k));
                testCase.verifyEqual(loaded.rules(k).classification, original.rules(k).classification, ...
                    sprintf('Rule %d classification should match', k));
                testCase.verifyEqual(loaded.rules(k).enclave, original.rules(k).enclave, ...
                    sprintf('Rule %d enclave should match', k));
                testCase.verifyEqual(loaded.rules(k).operation, original.rules(k).operation, ...
                    sprintf('Rule %d operation should match', k));
                testCase.verifyEqual(loaded.rules(k).outcome, original.rules(k).outcome, ...
                    sprintf('Rule %d outcome should match', k));
            end
        end

        function testIntendedPolicyEvaluateExactMatch(testCase)
            % Exact rule matches before wildcards.
            %
            % Requirements: R42

            policy = testCase.createSamplePolicy();

            % commander + SECRET + enclave_A + read -> permit (exact, score=4)
            outcome = security.IntendedPolicyLoader.evaluate(...
                policy, 'commander', 'SECRET', 'enclave_A', 'read');
            testCase.verifyEqual(outcome, 'permit', ...
                'Exact match rule (commander/SECRET/enclave_A/read) should return permit');
        end

        function testIntendedPolicyEvaluateWildcard(testCase)
            % Wildcard rule returns correct outcome when no more specific rule matches.
            %
            % Requirements: R42

            policy = testCase.createSamplePolicy();

            % unknown_role + TOP_SECRET + enclave_B + read -> deny (wildcard rule)
            outcome = security.IntendedPolicyLoader.evaluate(...
                policy, 'unknown_role', 'TOP_SECRET', 'enclave_B', 'read');
            testCase.verifyEqual(outcome, 'deny', ...
                'Wildcard rule (*/*/*/*) should return deny');
        end

        function testIntendedPolicyEvaluateDefault(testCase)
            % No rules match, returns defaultOutcome.
            %
            % Requirements: R42

            policy.description = 'No-match policy';
            policy.defaultOutcome = 'permit';
            policy.rules = struct( ...
                'role', {'commander'}, ...
                'classification', {'SECRET'}, ...
                'enclave', {'enclave_A'}, ...
                'operation', {'read'}, ...
                'outcome', {'deny'});

            % Use a combination that does NOT match the only rule
            outcome = security.IntendedPolicyLoader.evaluate(...
                policy, 'analyst', 'UNCLASSIFIED', 'enclave_B', 'write');
            testCase.verifyEqual(outcome, 'permit', ...
                'When no rules match, defaultOutcome (permit) should be returned');
        end

        function testSecurityOracleConformant(testCase)
            % Event with matching outcome classified as conformant.
            %
            % Requirements: R43

            policy = testCase.createSamplePolicy();
            oracle = security.SecurityOracle(policy);

            % commander + SECRET + enclave_A + read -> intended=permit
            % actual=permit -> conformant
            event = testCase.makeSecurityEvent(1, 'commander', 'SECRET', 'enclave_A', 'read', 'permit');
            classification = oracle.evaluate(event, 100.0);

            testCase.verifyEqual(classification, 'conformant', ...
                'Event where actual matches intended should be conformant');
        end

        function testSecurityOracleViolation(testCase)
            % actual=permit, intended=deny classified as violation.
            %
            % Requirements: R43, R45

            policy = testCase.createSamplePolicy();
            oracle = security.SecurityOracle(policy);

            % unknown_role + TOP_SECRET + enclave_B + read -> intended=deny (wildcard rule)
            % actual=permit -> violation
            event = testCase.makeSecurityEvent(2, 'unknown_role', 'TOP_SECRET', 'enclave_B', 'read', 'permit');
            classification = oracle.evaluate(event, 200.0);

            testCase.verifyEqual(classification, 'violation', ...
                'actual=permit when intended=deny should be a violation');
            testCase.verifyGreaterThanOrEqual(numel(oracle.violations), 1, ...
                'Violation should be recorded in violations list');
        end

        function testSecurityOracleOverRestriction(testCase)
            % actual=deny, intended=permit classified as over_restriction.
            %
            % Requirements: R43

            policy = testCase.createSamplePolicy();
            oracle = security.SecurityOracle(policy);

            % commander + SECRET + enclave_A + read -> intended=permit
            % actual=deny -> over_restriction
            event = testCase.makeSecurityEvent(3, 'commander', 'SECRET', 'enclave_A', 'read', 'deny');
            classification = oracle.evaluate(event, 300.0);

            testCase.verifyEqual(classification, 'over_restriction', ...
                'actual=deny when intended=permit should be over_restriction');
        end

        function testSecurityOracleConformanceScore(testCase)
            % score = conformant/(conformant+violations+overRestrictions)
            %
            % Requirements: R43

            policy = testCase.createSamplePolicy();
            oracle = security.SecurityOracle(policy);

            % 2 conformant events
            e1 = testCase.makeSecurityEvent(1, 'commander', 'SECRET', 'enclave_A', 'read', 'permit');
            e2 = testCase.makeSecurityEvent(2, 'analyst', 'UNCLASSIFIED', 'enclave_A', 'read', 'permit');
            oracle.evaluate(e1, 10.0);
            oracle.evaluate(e2, 20.0);

            % 1 violation event (intended=deny, actual=permit)
            e3 = testCase.makeSecurityEvent(3, 'unknown_role', 'TOP_SECRET', 'enclave_B', 'read', 'permit');
            oracle.evaluate(e3, 30.0);

            % 1 over_restriction event (intended=permit, actual=deny)
            e4 = testCase.makeSecurityEvent(4, 'commander', 'SECRET', 'enclave_A', 'read', 'deny');
            oracle.evaluate(e4, 40.0);

            score = oracle.computeConformanceScore();
            expectedScore = 2 / (2 + 1 + 1);  % 0.5
            testCase.verifyEqual(score, expectedScore, 'AbsTol', 1e-12, ...
                'Conformance score should be conformant/(conformant+violations+overRestrictions)');
        end

        function testScenarioLibraryListTemplates(testCase)
            % listTemplates returns 5 templates.
            %
            % Requirements: R46, R48

            templates = security.ScenarioLibrary.listTemplates();
            testCase.verifyEqual(numel(templates), 5, ...
                'ScenarioLibrary should provide exactly 5 templates');
            testCase.verifyTrue(iscell(templates), ...
                'listTemplates should return a cell array');
        end

        function testScenarioLibraryInstantiate(testCase)
            % Instantiate each template and verify scenario has adversarialEntities.
            %
            % Requirements: R46, R48

            templates = security.ScenarioLibrary.listTemplates();
            topology = testCase.createMinimalTopology();

            for k = 1:numel(templates)
                scenario = security.ScenarioLibrary.instantiate(templates{k}, topology);

                testCase.verifyTrue(isfield(scenario, 'adversarialEntities'), ...
                    sprintf('Template "%s": scenario must have adversarialEntities field', templates{k}));
                testCase.verifyGreaterThanOrEqual(numel(scenario.adversarialEntities), 1, ...
                    sprintf('Template "%s": should have at least one adversarial entity', templates{k}));
                testCase.verifyTrue(isfield(scenario, 'scenarioName'), ...
                    sprintf('Template "%s": scenario must have scenarioName field', templates{k}));
            end
        end

    end % methods (Test) — Unit Tests

    % ======================================================================
    % Property-Based Tests (Task 76, 100 iterations)
    % ======================================================================
    methods (Test)

        function testP41_OracleViolationCompleteness(testCase)
            % **Validates: Requirements R43, R45**
            % Feature: matlab-network-sim, Property 41: Oracle Violation Completeness
            %
            % For 100 random (role, cls, enc, op) where intended=deny but
            % actual=permit, verify the event appears in the violations list.

            policy = testCase.createSamplePolicy();
            % Use a policy that denies everything by default
            policy.defaultOutcome = 'deny';
            policy.rules = struct('role', {}, 'classification', {}, ...
                'enclave', {}, 'operation', {}, 'outcome', {});

            oracle = security.SecurityOracle(policy);

            roles = {'analyst', 'commander', 'operator', 'guest', 'admin'};
            classifications = {'UNCLASSIFIED', 'SECRET', 'TOP_SECRET', 'CONFIDENTIAL'};
            enclaveList = {'enclave_A', 'enclave_B', 'enclave_C', 'enclave_D'};
            operations = {'read', 'write', 'ingest', 'delete'};

            for iter = 1:100
                role = roles{randi(numel(roles))};
                cls = classifications{randi(numel(classifications))};
                enc = enclaveList{randi(numel(enclaveList))};
                op = operations{randi(numel(operations))};

                % Verify intended outcome is deny for this combination
                intendedOutcome = security.IntendedPolicyLoader.evaluate(policy, role, cls, enc, op);
                testCase.assertEqual(intendedOutcome, 'deny', ...
                    'Pre-condition: intended outcome must be deny for this test');

                % Feed event with actual=permit (creating a violation)
                event = testCase.makeSecurityEvent(uint64(iter), role, cls, enc, op, 'permit');
                classification = oracle.evaluate(event, double(iter) * 10);

                testCase.verifyEqual(classification, 'violation', ...
                    sprintf('Iter %d: actual=permit when intended=deny must be violation', iter));
            end

            % Verify all 100 violations are recorded
            testCase.verifyEqual(numel(oracle.violations), 100, ...
                'All 100 violation events must appear in the violations list');
        end

        function testP42_ConformanceScoreConsistency(testCase)
            % **Validates: Requirements R43**
            % Feature: matlab-network-sim, Property 42: ConformanceScore Consistency
            %
            % For 100 random evaluation sets, recompute score from counts
            % and verify it matches computeConformanceScore().

            roles = {'analyst', 'commander', 'operator', 'guest', 'admin'};
            classifications = {'UNCLASSIFIED', 'SECRET', 'TOP_SECRET'};
            enclaveList = {'enclave_A', 'enclave_B', 'enclave_C'};
            operations = {'read', 'write', 'ingest'};
            outcomes = {'permit', 'deny'};

            for iter = 1:100
                % Build a random policy for each iteration
                policy.description = 'Random policy';
                policy.defaultOutcome = outcomes{randi(2)};
                nRules = randi(5);
                ruleRoles = cell(1, nRules);
                ruleCls = cell(1, nRules);
                ruleEnc = cell(1, nRules);
                ruleOps = cell(1, nRules);
                ruleOut = cell(1, nRules);
                for r = 1:nRules
                    ruleRoles{r} = roles{randi(numel(roles))};
                    ruleCls{r} = classifications{randi(numel(classifications))};
                    ruleEnc{r} = enclaveList{randi(numel(enclaveList))};
                    ruleOps{r} = operations{randi(numel(operations))};
                    ruleOut{r} = outcomes{randi(2)};
                end
                policy.rules = struct('role', ruleRoles, 'classification', ruleCls, ...
                    'enclave', ruleEnc, 'operation', ruleOps, 'outcome', ruleOut);

                oracle = security.SecurityOracle(policy);

                % Feed random events
                nEvents = randi([5, 20]);
                for e = 1:nEvents
                    role = roles{randi(numel(roles))};
                    cls = classifications{randi(numel(classifications))};
                    enc = enclaveList{randi(numel(enclaveList))};
                    op = operations{randi(numel(operations))};
                    actualOutcome = outcomes{randi(2)};

                    event = testCase.makeSecurityEvent(uint64(e), role, cls, enc, op, actualOutcome);
                    oracle.evaluate(event, double(e));
                end

                % Recompute score from counts
                counts = oracle.getCounts();
                denominator = counts.conformant + counts.violations + counts.overRestrictions;
                if denominator == 0
                    expectedScore = 1.0;
                else
                    expectedScore = counts.conformant / denominator;
                end

                actualScore = oracle.computeConformanceScore();
                testCase.verifyEqual(actualScore, expectedScore, 'AbsTol', 1e-12, ...
                    sprintf('Iter %d: computeConformanceScore must equal recomputed score from counts', iter));
            end
        end

        function testP43_PolicyGapDetection(testCase)
            % **Validates: Requirements R44**
            % Feature: matlab-network-sim, Property 43: Policy Gap Detection Completeness
            %
            % For 100 random policies with known gaps, verify PolicyAnalyzer
            % finds them.

            roles = {'analyst', 'commander', 'operator'};
            classifications = {'UNCLASSIFIED', 'SECRET', 'TOP_SECRET'};
            enclaveList = {'enclave_A', 'enclave_B'};
            operations = {'read', 'write', 'ingest'};

            for iter = 1:100
                % Build a random implemented policy that only covers a subset
                nRules = randi([1, 4]);
                implRules = struct('role', {}, 'classification', {}, ...
                    'enclave', {}, 'operation', {}, 'outcome', {});

                for r = 1:nRules
                    rule.role = roles{randi(numel(roles))};
                    rule.classification = classifications{randi(numel(classifications))};
                    rule.enclave = enclaveList{randi(numel(enclaveList))};
                    rule.operation = operations{randi(numel(operations))};
                    rule.outcome = 'permit';
                    implRules(end+1) = rule; %#ok<AGROW>
                end

                % Write the implemented policy as JSON
                implPolicy.rules = implRules;
                implFilePath = fullfile(testCase.TempDir, sprintf('impl_%d.json', iter));
                jsonText = jsonencode(implPolicy, 'PrettyPrint', true);
                fid = fopen(implFilePath, 'w');
                fprintf(fid, '%s', jsonText);
                fclose(fid);

                % Create a scenario with the roles/enclaves
                scenario.entities = struct( ...
                    'id', {'e1', 'e2', 'e3'}, ...
                    'role', roles(1:3));
                scenario.nodes = struct( ...
                    'id', {'n1', 'n2'}, ...
                    'enclave', enclaveList(1:2));
                scenario.classifications = classifications;

                % Run PolicyAnalyzer
                intendedPolicy = [];  % no intent comparison needed
                report = security.PolicyAnalyzer.analyze(implFilePath, intendedPolicy, scenario);

                % Determine expected gaps: all combos not matched by any rule
                totalCombos = numel(roles) * numel(classifications) * numel(enclaveList) * numel(operations);

                % Compute actually covered combos by checking each rule against
                % each combination (rules may use exact matches only here)
                actuallyCovered = 0;
                for iR = 1:numel(roles)
                    for iC = 1:numel(classifications)
                        for iE = 1:numel(enclaveList)
                            for iO = 1:numel(operations)
                                matched = false;
                                for k = 1:numel(implRules)
                                    rr = implRules(k);
                                    if (strcmp(rr.role, '*') || strcmp(rr.role, roles{iR})) && ...
                                       (strcmp(rr.classification, '*') || strcmp(rr.classification, classifications{iC})) && ...
                                       (strcmp(rr.enclave, '*') || strcmp(rr.enclave, enclaveList{iE})) && ...
                                       (strcmp(rr.operation, '*') || strcmp(rr.operation, operations{iO}))
                                        matched = true;
                                        break;
                                    end
                                end
                                if matched
                                    actuallyCovered = actuallyCovered + 1;
                                end
                            end
                        end
                    end
                end
                expectedGaps = totalCombos - actuallyCovered;

                testCase.verifyEqual(numel(report.gaps), expectedGaps, ...
                    sprintf('Iter %d: PolicyAnalyzer must find all %d gaps (found %d)', ...
                    iter, expectedGaps, numel(report.gaps)));
            end
        end

    end % methods (Test) — Property-Based Tests

end % classdef
