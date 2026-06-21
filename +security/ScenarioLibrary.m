classdef ScenarioLibrary
    % security.ScenarioLibrary  Pre-built security scenario templates.
    %
    % Provides a library of adversarial scenario templates that can be
    % instantiated with a specific network topology for security testing.
    %
    % Requirements: R46, R48

    methods (Static)

        function templates = listTemplates()
            % listTemplates  Return cell array of available template names.
            %
            %   templates = security.ScenarioLibrary.listTemplates()
            %
            %   Returns:
            %     {'insider_data_exfiltration', ...
            %      'outsider_authentication_bypass', ...
            %      'pdp_outage_exploitation', ...
            %      'cross_enclave_escalation', ...
            %      'expired_credential_persistence'}
            %
            % Requirements: R46, R48

            templates = { ...
                'insider_data_exfiltration', ...
                'outsider_authentication_bypass', ...
                'pdp_outage_exploitation', ...
                'cross_enclave_escalation', ...
                'expired_credential_persistence' ...
            };
        end

        function scenario = instantiate(templateName, topology)
            % instantiate  Create a fully populated scenario from a template.
            %
            %   scenario = security.ScenarioLibrary.instantiate(templateName, topology)
            %
            %   templateName — one of the names from listTemplates()
            %   topology     — struct with fields:
            %     nodes    — struct array with id, type, enclave fields
            %     links    — struct array with id, srcNodeId, dstNodeId fields
            %     entities — struct array with id, nodeId, role fields
            %
            %   Returns a scenario struct ready for security evaluation with:
            %     scenarioName, simulationDurationSec, nodes, links, entities,
            %     adversarialEntities, degradationConfig, classifications,
            %     dataItems, enclaves
            %
            % Requirements: R46, R48

            validTemplates = security.ScenarioLibrary.listTemplates();
            if ~ismember(templateName, validTemplates)
                error('netsim:security:unknownTemplate', ...
                    'Unknown scenario template: %s. Valid templates: %s', ...
                    templateName, strjoin(validTemplates, ', '));
            end

            % Extract topology info
            nodeIds = {};
            enclaveIds = {};
            entityIds = {};

            if isfield(topology, 'nodes') && ~isempty(topology.nodes)
                for k = 1:numel(topology.nodes)
                    nodeIds{end+1} = char(topology.nodes(k).id); %#ok<AGROW>
                    if isfield(topology.nodes(k), 'enclave') && ...
                            ~isempty(topology.nodes(k).enclave)
                        enclaveIds{end+1} = char(topology.nodes(k).enclave); %#ok<AGROW>
                    end
                end
            end
            enclaveIds = unique(enclaveIds);

            if isfield(topology, 'entities') && ~isempty(topology.entities)
                for k = 1:numel(topology.entities)
                    entityIds{end+1} = char(topology.entities(k).id); %#ok<AGROW>
                end
            end

            % Select first available node/entity for substitution
            targetNode = 'node_1';
            if ~isempty(nodeIds)
                targetNode = nodeIds{1};
            end
            targetEntity = 'entity_1';
            if ~isempty(entityIds)
                targetEntity = entityIds{1};
            end
            targetEnclave = 'enclave_A';
            if ~isempty(enclaveIds)
                targetEnclave = enclaveIds{1};
            end
            secondEnclave = 'enclave_B';
            if numel(enclaveIds) >= 2
                secondEnclave = enclaveIds{2};
            end

            % Build base scenario from topology
            scenario.scenarioName = templateName;
            scenario.simulationDurationSec = 3600;
            scenario.nodes = topology.nodes;
            if isfield(topology, 'links')
                scenario.links = topology.links;
            else
                scenario.links = struct('id', {}, 'srcNodeId', {}, 'dstNodeId', {});
            end
            if isfield(topology, 'entities')
                scenario.entities = topology.entities;
            else
                scenario.entities = struct('id', {}, 'nodeId', {}, 'role', {});
            end
            scenario.classifications = {'UNCLASSIFIED', 'SECRET', 'TOP_SECRET'};
            scenario.enclaves = enclaveIds;
            scenario.dataItems = struct( ...
                'id', {'data_1', 'data_2'}, ...
                'classification', {'SECRET', 'TOP_SECRET'});
            scenario.adversarialEntities = struct('id', {}, 'nodeId', {}, ...
                'type', {}, 'role', {}, 'adversarial', {}, 'attackPatterns', {});

            % Apply template-specific adversarial configuration
            switch templateName
                case 'insider_data_exfiltration'
                    scenario = security.ScenarioLibrary.applyInsiderExfiltration(...
                        scenario, targetNode, targetEntity, targetEnclave);

                case 'outsider_authentication_bypass'
                    scenario = security.ScenarioLibrary.applyOutsiderAuthBypass(...
                        scenario, targetNode, targetEnclave);

                case 'pdp_outage_exploitation'
                    scenario = security.ScenarioLibrary.applyPdpOutageExploit(...
                        scenario, targetNode, targetEnclave);

                case 'cross_enclave_escalation'
                    scenario = security.ScenarioLibrary.applyCrossEnclaveEscalation(...
                        scenario, targetNode, targetEnclave, secondEnclave);

                case 'expired_credential_persistence'
                    scenario = security.ScenarioLibrary.applyExpiredCredential(...
                        scenario, targetNode, targetEntity, targetEnclave);
            end
        end

    end % methods (Static)

    methods (Static, Access = private)

        function scenario = applyInsiderExfiltration(scenario, targetNode, targetEntity, targetEnclave)
            % Insider with valid credentials attempts to access data above clearance.
            adversary.id = sprintf('adversary_insider_%s', targetEntity);
            adversary.nodeId = targetNode;
            adversary.type = 'human';
            adversary.role = 'analyst';
            adversary.adversarial = true;
            adversary.attackPatterns = struct( ...
                'attackType', 'unauthorized_data_access', ...
                'targetClassification', 'TOP_SECRET', ...
                'targetEnclaveId', targetEnclave, ...
                'operation', 'read', ...
                'attemptTimeSec', 600, ...
                'role', 'analyst');
            scenario.adversarialEntities(end+1) = adversary;
        end

        function scenario = applyOutsiderAuthBypass(scenario, targetNode, targetEnclave)
            % External attacker attempts authentication bypass.
            adversary.id = 'adversary_outsider';
            adversary.nodeId = targetNode;
            adversary.type = 'device';
            adversary.role = 'unauthorized';
            adversary.adversarial = true;
            adversary.attackPatterns = struct( ...
                'attackType', 'unauthorized_data_access', ...
                'targetClassification', 'SECRET', ...
                'targetEnclaveId', targetEnclave, ...
                'operation', 'read', ...
                'attemptTimeSec', 300, ...
                'role', 'unauthorized');
            scenario.adversarialEntities(end+1) = adversary;
        end

        function scenario = applyPdpOutageExploit(scenario, targetNode, targetEnclave)
            % Attacker exploits PDP outage to gain fail-open access.
            adversary.id = 'adversary_pdp_exploit';
            adversary.nodeId = targetNode;
            adversary.type = 'device';
            adversary.role = 'operator';
            adversary.adversarial = true;
            adversary.attackPatterns = struct( ...
                'attackType', 'pdp_outage_exploitation', ...
                'targetClassification', 'SECRET', ...
                'targetEnclaveId', targetEnclave, ...
                'operation', 'read', ...
                'attemptTimeSec', 400, ...
                'role', 'operator', ...
                'targetPdpNodeId', targetNode, ...
                'outageDurationSec', 120, ...
                'dataFetchAttemptOffsetSec', 30);
            scenario.adversarialEntities(end+1) = adversary;

            % Add degradation config for PDP outage
            scenario.degradationConfig.scenarios = struct( ...
                'name', 'pdp_outage', ...
                'targetNodes', {{targetNode}}, ...
                'targetLinks', {{}}, ...
                'outageDurationSec', 120, ...
                'startTimeSec', 350, ...
                'type', 'pdp_outage');
        end

        function scenario = applyCrossEnclaveEscalation(scenario, targetNode, ~, dstEnclave)
            % Attacker attempts to access resources in unauthorized enclave.
            adversary.id = 'adversary_cross_enclave';
            adversary.nodeId = targetNode;
            adversary.type = 'human';
            adversary.role = 'analyst';
            adversary.adversarial = true;
            adversary.attackPatterns = struct( ...
                'attackType', 'cross_enclave_access', ...
                'targetClassification', 'SECRET', ...
                'targetEnclaveId', dstEnclave, ...
                'operation', 'read', ...
                'attemptTimeSec', 500, ...
                'role', 'analyst');
            scenario.adversarialEntities(end+1) = adversary;
        end

        function scenario = applyExpiredCredential(scenario, targetNode, targetEntity, targetEnclave)
            % Attacker uses expired credentials after trust anchor outage.
            adversary.id = sprintf('adversary_expired_%s', targetEntity);
            adversary.nodeId = targetNode;
            adversary.type = 'human';
            adversary.role = 'operator';
            adversary.adversarial = true;
            adversary.attackPatterns = struct( ...
                'attackType', 'expired_credential_access', ...
                'targetClassification', 'SECRET', ...
                'targetEnclaveId', targetEnclave, ...
                'operation', 'write', ...
                'attemptTimeSec', 800, ...
                'role', 'operator');
            scenario.adversarialEntities(end+1) = adversary;

            % Add degradation config for trust anchor outage
            scenario.degradationConfig.scenarios = struct( ...
                'name', 'trust_anchor_outage', ...
                'targetNodes', {{targetNode}}, ...
                'targetLinks', {{}}, ...
                'outageDurationSec', 300, ...
                'startTimeSec', 600, ...
                'type', 'trust_anchor_outage');
        end

    end % methods (Static, Access = private)

end % classdef
