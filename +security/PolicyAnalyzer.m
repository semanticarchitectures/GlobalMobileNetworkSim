classdef PolicyAnalyzer
    % PolicyAnalyzer  Static analysis of implemented and intended security policies.
    %
    % Analyzes icam_policy.json for structural defects: gaps, conflicts,
    % dead rules, orphaned role bindings. When an IntendedPolicy is provided,
    % additionally identifies intent mismatches.
    %
    % Produces a PolicyAnalysisReport struct in JSON-serializable format.
    %
    % Requirements: R44

    methods (Static)

        function report = analyze(implementedPolicyPath, intendedPolicy, scenario)
            % analyze  Perform static analysis on implemented policy.
            %
            %   report = security.PolicyAnalyzer.analyze( ...
            %       implementedPolicyPath, intendedPolicy, scenario)
            %
            %   Inputs:
            %     implementedPolicyPath — path to icam_policy.json
            %     intendedPolicy        — struct from IntendedPolicyLoader.load()
            %                             (pass [] if not available)
            %     scenario              — struct from ScenarioLoader.load()
            %                             (must have entities, nodes fields)
            %
            %   Returns PolicyAnalysisReport struct with:
            %     gaps               — struct array of uncovered combinations
            %     conflicts          — struct array of conflicting rule pairs
            %     deadRules          — struct array of shadowed rules
            %     orphanedRoleBindings — struct array of unmatched roles
            %     intentMismatches   — struct array of intent vs implementation diffs
            %     summary            — counts struct
            %
            % Requirements: R44

            % Load the implemented policy via PDP file read
            if ~isfile(implementedPolicyPath)
                error('netsim:security:policyLoadError', ...
                    'Implemented policy file not found: %s', implementedPolicyPath);
            end
            try
                rawText = fileread(implementedPolicyPath);
                implPolicy = jsondecode(rawText);
            catch ME
                error('netsim:security:policyLoadError', ...
                    'Failed to parse implemented policy file "%s": %s', ...
                    implementedPolicyPath, ME.message);
            end

            % Extract universe of values from scenario
            [roles, classifications, enclaves, operations] = ...
                security.PolicyAnalyzer.extractUniverse(scenario);

            % Get implemented rules (normalize)
            implRules = security.PolicyAnalyzer.normalizeImplRules(implPolicy);

            % --- Gaps ---
            gaps = security.PolicyAnalyzer.findGaps(implRules, roles, ...
                classifications, enclaves, operations);

            % --- Conflicts ---
            conflicts = security.PolicyAnalyzer.findConflicts(implRules);

            % --- Dead Rules ---
            deadRules = security.PolicyAnalyzer.findDeadRules(implRules);

            % --- Orphaned Role Bindings ---
            orphanedRoleBindings = security.PolicyAnalyzer.findOrphanedRoles(...
                implRules, scenario);

            % --- Intent Mismatches ---
            if ~isempty(intendedPolicy)
                intentMismatches = security.PolicyAnalyzer.findIntentMismatches(...
                    implRules, implPolicy, intendedPolicy, roles, ...
                    classifications, enclaves, operations);
            else
                intentMismatches = struct('role', {}, 'classification', {}, ...
                    'enclave', {}, 'operation', {}, ...
                    'implementedOutcome', {}, 'intendedOutcome', {});
            end

            % Build report
            report.gaps = gaps;
            report.conflicts = conflicts;
            report.deadRules = deadRules;
            report.orphanedRoleBindings = orphanedRoleBindings;
            report.intentMismatches = intentMismatches;
            report.summary.gapCount = numel(gaps);
            report.summary.conflictCount = numel(conflicts);
            report.summary.deadRuleCount = numel(deadRules);
            report.summary.orphanedRoleCount = numel(orphanedRoleBindings);
            report.summary.intentMismatchCount = numel(intentMismatches);
            report.summary.totalFindings = numel(gaps) + numel(conflicts) + ...
                numel(deadRules) + numel(orphanedRoleBindings) + ...
                numel(intentMismatches);
        end

        function writeReport(report, outputPath)
            % writeReport  Write PolicyAnalysisReport to a JSON file.
            %
            %   security.PolicyAnalyzer.writeReport(report, outputPath)
            %
            % Requirements: R44

            jsonText = jsonencode(report, 'PrettyPrint', true);
            fid = fopen(outputPath, 'w');
            if fid == -1
                error('netsim:security:policyLoadError', ...
                    'Cannot open file for writing: %s', outputPath);
            end
            cleanupObj = onCleanup(@() fclose(fid));
            fprintf(fid, '%s', jsonText);
        end

    end % methods (Static)

    methods (Static, Access = private)

        function rules = normalizeImplRules(implPolicy)
            % normalizeImplRules  Extract and normalize rules from icam_policy.json
            %   The implemented policy uses fields: enclave, role, messageType, decision
            %   We map messageType → operation and decision → outcome for consistency.

            if ~isfield(implPolicy, 'rules') || isempty(implPolicy.rules)
                rules = struct('role', {}, 'classification', {}, ...
                    'enclave', {}, 'operation', {}, 'outcome', {});
                return;
            end

            rawRules = implPolicy.rules;
            n = numel(rawRules);
            rules = struct('role', cell(1,n), 'classification', cell(1,n), ...
                'enclave', cell(1,n), 'operation', cell(1,n), ...
                'outcome', cell(1,n));

            for k = 1:n
                r = rawRules(k);
                % role field
                if isfield(r, 'role')
                    rules(k).role = char(r.role);
                else
                    rules(k).role = '*';
                end
                % classification field
                if isfield(r, 'classification')
                    rules(k).classification = char(r.classification);
                else
                    rules(k).classification = '*';
                end
                % enclave field
                if isfield(r, 'enclave')
                    rules(k).enclave = char(r.enclave);
                else
                    rules(k).enclave = '*';
                end
                % operation / messageType field
                if isfield(r, 'operation')
                    rules(k).operation = char(r.operation);
                elseif isfield(r, 'messageType')
                    rules(k).operation = char(r.messageType);
                else
                    rules(k).operation = '*';
                end
                % outcome / decision field
                if isfield(r, 'outcome')
                    rules(k).outcome = char(r.outcome);
                elseif isfield(r, 'decision')
                    rules(k).outcome = char(r.decision);
                else
                    rules(k).outcome = 'deny';
                end
            end
        end

        function [roles, classifications, enclaves, operations] = extractUniverse(scenario)
            % extractUniverse  Extract the universe of roles, classifications,
            %   enclaves, and operations from a scenario struct.

            roles = {};
            classifications = {};
            enclaves = {};
            operations = {'read', 'write', 'ingest'};

            % Extract roles from entities
            if isfield(scenario, 'entities') && ~isempty(scenario.entities)
                ents = scenario.entities;
                for k = 1:numel(ents)
                    if isfield(ents(k), 'role') && ~isempty(ents(k).role)
                        roles{end+1} = char(ents(k).role); %#ok<AGROW>
                    end
                    if isfield(ents(k), 'roles') && ~isempty(ents(k).roles)
                        r = ents(k).roles;
                        if ischar(r)
                            roles{end+1} = r; %#ok<AGROW>
                        elseif iscell(r)
                            roles = [roles, cellfun(@char, r, 'UniformOutput', false)]; %#ok<AGROW>
                        end
                    end
                end
            end
            roles = unique(roles);

            % Extract classifications from dataItems or dataStores
            if isfield(scenario, 'dataItems') && ~isempty(scenario.dataItems)
                items = scenario.dataItems;
                for k = 1:numel(items)
                    if isfield(items(k), 'classification') && ~isempty(items(k).classification)
                        classifications{end+1} = char(items(k).classification); %#ok<AGROW>
                    end
                end
            end
            if isfield(scenario, 'classifications') && ~isempty(scenario.classifications)
                cls = scenario.classifications;
                if iscell(cls)
                    % Flatten nested cells if necessary
                    for ci = 1:numel(cls)
                        item = cls{ci};
                        if iscell(item)
                            for cj = 1:numel(item)
                                classifications{end+1} = char(item{cj}); %#ok<AGROW>
                            end
                        elseif ischar(item) || isstring(item)
                            classifications{end+1} = char(item); %#ok<AGROW>
                        end
                    end
                elseif ischar(cls)
                    classifications{end+1} = cls;
                end
            end
            classifications = unique(classifications);

            % Extract enclaves from policy or nodes
            if isfield(scenario, 'enclaves') && ~isempty(scenario.enclaves)
                enc = scenario.enclaves;
                if isstruct(enc)
                    for k = 1:numel(enc)
                        if isfield(enc(k), 'enclaveId')
                            enclaves{end+1} = char(enc(k).enclaveId); %#ok<AGROW>
                        elseif isfield(enc(k), 'id')
                            enclaves{end+1} = char(enc(k).id); %#ok<AGROW>
                        end
                    end
                elseif iscell(enc)
                    enclaves = cellfun(@char, enc, 'UniformOutput', false);
                end
            end
            if isfield(scenario, 'nodes') && ~isempty(scenario.nodes)
                nodes = scenario.nodes;
                for k = 1:numel(nodes)
                    if isfield(nodes(k), 'enclave') && ~isempty(nodes(k).enclave)
                        enclaves{end+1} = char(nodes(k).enclave); %#ok<AGROW>
                    end
                end
            end
            enclaves = unique(enclaves);

            % Provide defaults if nothing found
            if isempty(roles)
                roles = {'*'};
            end
            if isempty(classifications)
                classifications = {'*'};
            end
            if isempty(enclaves)
                enclaves = {'default'};
            end
        end

        function gaps = findGaps(implRules, roles, classifications, enclaves, operations)
            % findGaps  Identify (role, classification, enclave, operation)
            %   combinations that no implemented rule explicitly covers.

            gaps = struct('role', {}, 'classification', {}, ...
                'enclave', {}, 'operation', {});

            for iR = 1:numel(roles)
                for iC = 1:numel(classifications)
                    for iE = 1:numel(enclaves)
                        for iO = 1:numel(operations)
                            matched = false;
                            for k = 1:numel(implRules)
                                rule = implRules(k);
                                if security.PolicyAnalyzer.ruleMatchesInput(...
                                        rule, roles{iR}, classifications{iC}, ...
                                        enclaves{iE}, operations{iO})
                                    matched = true;
                                    break;
                                end
                            end
                            if ~matched
                                g.role = roles{iR};
                                g.classification = classifications{iC};
                                g.enclave = enclaves{iE};
                                g.operation = operations{iO};
                                gaps(end+1) = g; %#ok<AGROW>
                            end
                        end
                    end
                end
            end
        end

        function conflicts = findConflicts(implRules)
            % findConflicts  Identify rule pairs with different outcomes
            %   that could match the same input.

            conflicts = struct('ruleIndex1', {}, 'ruleIndex2', {}, ...
                'rule1', {}, 'rule2', {});

            n = numel(implRules);
            for i = 1:n
                for j = (i+1):n
                    if ~strcmp(implRules(i).outcome, implRules(j).outcome)
                        % Check if rules can overlap (match the same input)
                        if security.PolicyAnalyzer.rulesCanOverlap(...
                                implRules(i), implRules(j))
                            c.ruleIndex1 = i;
                            c.ruleIndex2 = j;
                            c.rule1 = implRules(i);
                            c.rule2 = implRules(j);
                            conflicts(end+1) = c; %#ok<AGROW>
                        end
                    end
                end
            end
        end

        function deadRules = findDeadRules(implRules)
            % findDeadRules  Identify rules shadowed by earlier wildcard rules.
            %   A rule is dead if an earlier rule with wildcards always matches
            %   any input that the later rule would match.

            deadRules = struct('ruleIndex', {}, 'rule', {}, ...
                'shadowedBy', {});

            n = numel(implRules);
            for j = 2:n
                for i = 1:(j-1)
                    if security.PolicyAnalyzer.ruleShadows(implRules(i), implRules(j))
                        d.ruleIndex = j;
                        d.rule = implRules(j);
                        d.shadowedBy = i;
                        deadRules(end+1) = d; %#ok<AGROW>
                        break; % Only need first shadower
                    end
                end
            end
        end

        function orphaned = findOrphanedRoles(implRules, scenario)
            % findOrphanedRoles  Identify entity roles with no governing rule.

            orphaned = struct('role', {}, 'entityId', {});

            if ~isfield(scenario, 'entities') || isempty(scenario.entities)
                return;
            end

            % Collect all roles referenced by rules
            ruleRoles = {};
            for k = 1:numel(implRules)
                ruleRoles{end+1} = implRules(k).role; %#ok<AGROW>
            end

            % Check if any rule uses wildcard for role (covers all)
            if any(strcmp(ruleRoles, '*'))
                return; % Wildcard covers all roles
            end

            % Find entity roles not in ruleRoles
            ents = scenario.entities;
            for k = 1:numel(ents)
                entityRoles = {};
                if isfield(ents(k), 'role') && ~isempty(ents(k).role)
                    entityRoles{end+1} = char(ents(k).role); %#ok<AGROW>
                end
                if isfield(ents(k), 'roles') && ~isempty(ents(k).roles)
                    r = ents(k).roles;
                    if ischar(r)
                        entityRoles{end+1} = r; %#ok<AGROW>
                    elseif iscell(r)
                        entityRoles = [entityRoles, cellfun(@char, r, 'UniformOutput', false)]; %#ok<AGROW>
                    end
                end

                entityId = '';
                if isfield(ents(k), 'id')
                    entityId = char(ents(k).id);
                end

                for m = 1:numel(entityRoles)
                    if ~ismember(entityRoles{m}, ruleRoles)
                        o.role = entityRoles{m};
                        o.entityId = entityId;
                        orphaned(end+1) = o; %#ok<AGROW>
                    end
                end
            end
        end

        function mismatches = findIntentMismatches(implRules, implPolicy, ...
                intendedPolicy, roles, classifications, enclaves, operations)
            % findIntentMismatches  Find combinations where implemented outcome
            %   differs from intended outcome.

            mismatches = struct('role', {}, 'classification', {}, ...
                'enclave', {}, 'operation', {}, ...
                'implementedOutcome', {}, 'intendedOutcome', {});

            % Determine default outcome for implemented policy
            implDefault = 'deny'; % failPolicy default
            if isfield(implPolicy, 'enclaves') && ~isempty(implPolicy.enclaves)
                % Use first enclave failPolicy as general default
                enc = implPolicy.enclaves;
                if isstruct(enc) && numel(enc) >= 1
                    if isfield(enc(1), 'failPolicy')
                        fp = char(enc(1).failPolicy);
                        if strcmp(fp, 'open')
                            implDefault = 'permit';
                        end
                    end
                end
            end

            for iR = 1:numel(roles)
                for iC = 1:numel(classifications)
                    for iE = 1:numel(enclaves)
                        for iO = 1:numel(operations)
                            role = roles{iR};
                            cls = classifications{iC};
                            enc = enclaves{iE};
                            op = operations{iO};

                            % Get implemented outcome
                            implOutcome = security.PolicyAnalyzer.evaluateImpl(...
                                implRules, implDefault, role, cls, enc, op);

                            % Get intended outcome
                            intOutcome = security.IntendedPolicyLoader.evaluate(...
                                intendedPolicy, role, cls, enc, op);

                            if ~strcmp(implOutcome, intOutcome)
                                m.role = role;
                                m.classification = cls;
                                m.enclave = enc;
                                m.operation = op;
                                m.implementedOutcome = implOutcome;
                                m.intendedOutcome = intOutcome;
                                mismatches(end+1) = m; %#ok<AGROW>
                            end
                        end
                    end
                end
            end
        end

        function outcome = evaluateImpl(implRules, defaultOutcome, role, ...
                classification, enclave, operation)
            % evaluateImpl  Evaluate the implemented policy for a given input.
            %   First matching rule wins (order-based, like PDP).

            for k = 1:numel(implRules)
                rule = implRules(k);
                if security.PolicyAnalyzer.ruleMatchesInput(...
                        rule, role, classification, enclave, operation)
                    outcome = rule.outcome;
                    return;
                end
            end
            outcome = defaultOutcome;
        end

        function tf = ruleMatchesInput(rule, role, classification, enclave, operation)
            % ruleMatchesInput  Check if a rule matches a specific input tuple.
            tf = (strcmp(rule.role, '*') || strcmp(rule.role, role)) && ...
                 (strcmp(rule.classification, '*') || strcmp(rule.classification, classification)) && ...
                 (strcmp(rule.enclave, '*') || strcmp(rule.enclave, enclave)) && ...
                 (strcmp(rule.operation, '*') || strcmp(rule.operation, operation));
        end

        function tf = rulesCanOverlap(rule1, rule2)
            % rulesCanOverlap  Check if two rules could match the same input.
            %   Two rules overlap if, for each field, at least one of them
            %   uses a wildcard or they have the same value.
            tf = security.PolicyAnalyzer.fieldsOverlap(rule1.role, rule2.role) && ...
                 security.PolicyAnalyzer.fieldsOverlap(rule1.classification, rule2.classification) && ...
                 security.PolicyAnalyzer.fieldsOverlap(rule1.enclave, rule2.enclave) && ...
                 security.PolicyAnalyzer.fieldsOverlap(rule1.operation, rule2.operation);
        end

        function tf = fieldsOverlap(val1, val2)
            % fieldsOverlap  Two field values overlap if either is '*' or
            %   they are equal.
            tf = strcmp(val1, '*') || strcmp(val2, '*') || strcmp(val1, val2);
        end

        function tf = ruleShadows(earlier, later)
            % ruleShadows  Check if the earlier rule completely shadows
            %   the later rule (every input that matches 'later' also
            %   matches 'earlier').
            tf = security.PolicyAnalyzer.fieldCovers(earlier.role, later.role) && ...
                 security.PolicyAnalyzer.fieldCovers(earlier.classification, later.classification) && ...
                 security.PolicyAnalyzer.fieldCovers(earlier.enclave, later.enclave) && ...
                 security.PolicyAnalyzer.fieldCovers(earlier.operation, later.operation);
        end

        function tf = fieldCovers(earlierVal, laterVal)
            % fieldCovers  The earlier field covers the later if:
            %   - earlier is wildcard ('*'), or
            %   - they are equal (same specific value)
            tf = strcmp(earlierVal, '*') || strcmp(earlierVal, laterVal);
        end

    end % methods (Static, Access = private)

end % classdef
