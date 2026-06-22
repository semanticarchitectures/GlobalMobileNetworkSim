classdef SecurityController < handle
    % security.SecurityController  Orchestrate all security evaluation components.
    %
    % Handle class that coordinates PolicyAnalyzer, SecurityOracle,
    % CoverageGenerator, AdversarialAgentRegistry, and NetworkDegradationTester
    % throughout a simulation run. Builds a SecurityEvaluationReport at
    % completion and writes it via SecurityReportWriter.
    %
    % Usage:
    %   sc = security.SecurityController(config);
    %   sc.onSimulationStart(scenario, eventCalendar);
    %   sc.onEvent(event, simTimeSec);  % called per event during sim
    %   sc.onSimulationComplete(simController);
    %   report = sc.securityReport;
    %
    % Requirements: R43, R44, R45, R46, R47, R48, R49, R50

    properties (SetAccess = private)
        % Final SecurityEvaluationReport struct
        securityReport
    end

    properties (Access = private)
        % Configuration struct
        config

        % Component handles
        oracle              % security.SecurityOracle
        adversarialRegistry % security.AdversarialAgentRegistry
        degradationTester   % security.NetworkDegradationTester
        coverageResult      % struct from CoverageGenerator.generate()
        policyReport        % struct from PolicyAnalyzer.analyze()

        % Scenario and policy data
        scenario
        intendedPolicy
        implementedPolicyPath

        % Output configuration
        outputDir
    end

    methods

        function obj = SecurityController(config)
            % SecurityController  Construct with optional configuration.
            %
            %   sc = security.SecurityController()
            %   sc = security.SecurityController(config)
            %
            %   config — optional struct with fields:
            %     outputDir              — directory for report output (default: 'output')
            %     implementedPolicyPath  — path to icam_policy.json
            %     intendedPolicyPath     — path to intended_policy.json
            %     coverageConfig         — config for CoverageGenerator
            %     degradationConfig      — config for NetworkDegradationTester
            %     simDurationSec         — simulation duration in seconds
            %
            % Requirements: R43

            if nargin < 1 || isempty(config)
                config = struct();
            end

            obj.config = config;
            obj.securityReport = struct();
            obj.oracle = [];
            obj.adversarialRegistry = [];
            obj.degradationTester = [];
            obj.coverageResult = struct();
            obj.policyReport = struct();
            obj.scenario = [];
            obj.intendedPolicy = [];
            obj.implementedPolicyPath = '';

            % Set output directory
            if isfield(config, 'outputDir')
                obj.outputDir = char(config.outputDir);
            else
                obj.outputDir = 'output';
            end
        end

        function onSimulationStart(obj, scenario, eventCalendar)
            % onSimulationStart  Initialize all security components from scenario.
            %
            %   sc.onSimulationStart(scenario, eventCalendar)
            %
            %   scenario      — struct from ScenarioLoader.load()
            %   eventCalendar — sim.EventCalendar handle for scheduling events
            %
            %   Initializes:
            %     - IntendedPolicy (from scenario or config path)
            %     - PolicyAnalyzer (static analysis of implemented policy)
            %     - SecurityOracle (for dynamic event evaluation)
            %     - CoverageGenerator (schedules coverage attempts)
            %     - AdversarialAgentRegistry (schedules attacks)
            %     - NetworkDegradationTester (prepares degradation scenarios)
            %
            % Requirements: R43, R44, R45, R46, R47

            obj.scenario = scenario;

            % --- Load Intended Policy ---
            obj.intendedPolicy = obj.loadIntendedPolicy(scenario);

            % --- Initialize SecurityOracle ---
            if ~isempty(obj.intendedPolicy)
                obj.oracle = security.SecurityOracle(obj.intendedPolicy);
            else
                % Create a permissive default policy for oracle
                defaultPolicy.defaultOutcome = 'permit';
                defaultPolicy.rules = struct('role', {}, 'classification', {}, ...
                    'enclave', {}, 'operation', {}, 'outcome', {});
                obj.oracle = security.SecurityOracle(defaultPolicy);
            end

            % --- Run PolicyAnalyzer (static analysis) ---
            obj.implementedPolicyPath = obj.resolveImplementedPolicyPath(scenario);
            if ~isempty(obj.implementedPolicyPath) && isfile(obj.implementedPolicyPath)
                try
                    obj.policyReport = security.PolicyAnalyzer.analyze(...
                        obj.implementedPolicyPath, obj.intendedPolicy, scenario);
                catch ME
                    warning('netsim:security:policyAnalysisFailed', ...
                        'PolicyAnalyzer failed: %s', ME.message);
                    obj.policyReport = struct();
                end
            end

            % --- Initialize CoverageGenerator ---
            coverageConfig = struct();
            if isfield(obj.config, 'coverageConfig')
                coverageConfig = obj.config.coverageConfig;
            end
            if isfield(scenario, 'simulationDurationSec')
                coverageConfig.simDurationSec = scenario.simulationDurationSec;
            end

            try
                obj.coverageResult = security.CoverageGenerator.generate(...
                    scenario, obj.intendedPolicy, eventCalendar, coverageConfig);
            catch ME
                warning('netsim:security:coverageFailed', ...
                    'CoverageGenerator failed: %s', ME.message);
                obj.coverageResult = struct('totalCombinations', 0, ...
                    'scheduledAttempts', 0, 'coveragePercent', 0, ...
                    'combinations', []);
            end

            % --- Initialize AdversarialAgentRegistry ---
            try
                obj.adversarialRegistry = security.AdversarialAgentRegistry(scenario);
                obj.adversarialRegistry.scheduleAttacks(eventCalendar);
            catch ME
                warning('netsim:security:adversarialFailed', ...
                    'AdversarialAgentRegistry failed: %s', ME.message);
                obj.adversarialRegistry = [];
            end

            % --- Initialize NetworkDegradationTester ---
            degradationConfig = struct();
            if isfield(obj.config, 'degradationConfig')
                degradationConfig = obj.config.degradationConfig;
            elseif isfield(scenario, 'degradationConfig')
                degradationConfig = scenario.degradationConfig;
            end

            try
                obj.degradationTester = security.NetworkDegradationTester(degradationConfig);
                obj.degradationTester.generateScenarios();
            catch ME
                warning('netsim:security:degradationFailed', ...
                    'NetworkDegradationTester failed: %s', ME.message);
                obj.degradationTester = [];
            end
        end

        function onEvent(obj, event, simTimeSec)
            % onEvent  Delegate security-relevant events to SecurityOracle.
            %
            %   sc.onEvent(event, simTimeSec)
            %
            %   event      — DES event struct with type and payload fields
            %   simTimeSec — current simulation time in seconds
            %
            %   Evaluates the event against the IntendedPolicy and records
            %   the classification result.
            %
            % Requirements: R43, R45

            if isempty(obj.oracle)
                return;
            end

            % Only evaluate security-relevant event types
            eventType = char(event.type);
            securityEventTypes = {'DATA_FETCH', 'DATA_QUERY', ...
                'AUTH_REQUEST', 'C2_MESSAGE_TX'};

            if ismember(eventType, securityEventTypes)
                obj.oracle.evaluate(event, simTimeSec);
            end
        end

        function onSimulationComplete(obj, simController) %#ok<INUSD>
            % onSimulationComplete  Build and write SecurityEvaluationReport.
            %
            %   sc.onSimulationComplete(simController)
            %
            %   simController — sim.SimController handle (for additional context)
            %
            %   Builds the SecurityEvaluationReport from all components and
            %   writes it to disk via SecurityReportWriter.
            %
            % Requirements: R43, R44, R45, R47

            % Build the report struct
            report = struct();

            % Conformance score from oracle
            if ~isempty(obj.oracle)
                report.conformanceScore = obj.oracle.computeConformanceScore();
                report.violations = obj.oracle.violations;
                report.evaluationCounts = obj.oracle.getCounts();
            else
                report.conformanceScore = 1.0;
                report.violations = [];
                report.evaluationCounts = struct();
            end

            % Policy analysis
            report.policyAnalysis = obj.policyReport;

            % Coverage statistics
            if ~isempty(obj.coverageResult)
                report.coverageStats.totalCombinations = obj.coverageResult.totalCombinations;
                report.coverageStats.scheduledAttempts = obj.coverageResult.scheduledAttempts;
                report.coverageStats.coveragePercent = obj.coverageResult.coveragePercent;
            else
                report.coverageStats = struct('totalCombinations', 0, ...
                    'scheduledAttempts', 0, 'coveragePercent', 0);
            end

            % Degradation matrix
            if ~isempty(obj.degradationTester) && ~isempty(obj.oracle)
                try
                    degScenarios = obj.degradationTester.generateScenarios();
                    matrixResult = obj.degradationTester.evaluateOutcomes(...
                        obj.oracle, degScenarios);
                    report.degradationMatrix = matrixResult;
                catch ME
                    warning('netsim:security:degradationEvalFailed', ...
                        'Degradation evaluation failed: %s', ME.message);
                    report.degradationMatrix = struct();
                end
            else
                report.degradationMatrix = struct();
            end

            % Store final report
            obj.securityReport = report;

            % Write report to disk
            try
                if ~exist(obj.outputDir, 'dir')
                    mkdir(obj.outputDir);
                end

                scenarioName = 'security_eval';
                if ~isempty(obj.scenario) && isfield(obj.scenario, 'scenarioName')
                    scenarioName = char(obj.scenario.scenarioName);
                end

                jsonPath = fullfile(obj.outputDir, ...
                    [scenarioName, '_security_report.json']);
                security.SecurityReportWriter.writeReport(report, jsonPath);

                csvPath = fullfile(obj.outputDir, ...
                    [scenarioName, '_security_violations.csv']);
                security.SecurityReportWriter.writeSummaryCsv(report, csvPath);
            catch ME
                warning('netsim:security:reportWriteFailed', ...
                    'Failed to write security report: %s', ME.message);
            end
        end

    end % methods

    methods (Access = private)

        function intendedPolicy = loadIntendedPolicy(obj, scenario)
            % loadIntendedPolicy  Load intended policy from config or scenario.

            intendedPolicy = [];

            % Try config path first
            if isfield(obj.config, 'intendedPolicyPath') && ...
                    ~isempty(obj.config.intendedPolicyPath)
                policyPath = char(obj.config.intendedPolicyPath);
                if isfile(policyPath)
                    try
                        intendedPolicy = security.IntendedPolicyLoader.load(policyPath);
                        return;
                    catch
                        % Fall through to scenario-based lookup
                    end
                end
            end

            % Try scenario-referenced intended policy
            if isfield(scenario, 'intendedPolicyFile') && ...
                    ~isempty(scenario.intendedPolicyFile)
                policyPath = char(scenario.intendedPolicyFile);
                if isfile(policyPath)
                    try
                        intendedPolicy = security.IntendedPolicyLoader.load(policyPath);
                        return;
                    catch
                        % Fall through
                    end
                end
            end

            % Try to find intended_policy.json relative to implemented policy
            if ~isempty(obj.implementedPolicyPath)
                [policyDir, ~, ~] = fileparts(obj.implementedPolicyPath);
                candidatePath = fullfile(policyDir, 'intended_policy.json');
                if isfile(candidatePath)
                    try
                        intendedPolicy = security.IntendedPolicyLoader.load(candidatePath);
                        return;
                    catch
                        % Fall through
                    end
                end
            end
        end

        function policyPath = resolveImplementedPolicyPath(obj, scenario)
            % resolveImplementedPolicyPath  Find implemented policy JSON path.

            policyPath = '';

            % From config
            if isfield(obj.config, 'implementedPolicyPath') && ...
                    ~isempty(obj.config.implementedPolicyPath)
                policyPath = char(obj.config.implementedPolicyPath);
                return;
            end

            % From scenario
            if isfield(scenario, 'policyDefinitionFile') && ...
                    ~isempty(scenario.policyDefinitionFile)
                policyPath = char(scenario.policyDefinitionFile);
                return;
            end

            % Try common locations
            candidates = {'icam_policy.json', 'policy/icam_policy.json'};
            for k = 1:numel(candidates)
                if isfile(candidates{k})
                    policyPath = candidates{k};
                    return;
                end
            end
        end

    end % methods (Access = private)

end % classdef
