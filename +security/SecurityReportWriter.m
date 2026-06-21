classdef SecurityReportWriter
    % security.SecurityReportWriter  Write SecurityEvaluationReport to JSON/CSV.
    %
    % Static methods for serializing security evaluation results to disk.
    %
    % Requirements: R43, R44, R45, R47

    methods (Static)

        function writeReport(report, outputPath)
            % writeReport  Write SecurityEvaluationReport as JSON.
            %
            %   security.SecurityReportWriter.writeReport(report, outputPath)
            %
            %   Writes a JSON file containing:
            %     conformanceScore    — overall policy conformance score [0,1]
            %     policyAnalysis      — struct from PolicyAnalyzer.analyze()
            %     coverageStats       — coverage statistics from CoverageGenerator
            %     degradationMatrix   — DegradationSecurityMatrix results
            %     violations          — struct array of security violations
            %     evaluationCounts    — conformant/violation/overRestriction/unspecified
            %     timestamp           — ISO 8601 generation timestamp
            %
            %   report     — SecurityEvaluationReport struct
            %   outputPath — file path for JSON output
            %
            % Requirements: R43

            % Build output struct with canonical field order
            out = struct();

            % Timestamp
            out.timestamp = char(datetime('now', 'Format', 'yyyy-MM-dd''T''HH:mm:ss'));

            % Conformance score
            if isfield(report, 'conformanceScore')
                out.conformanceScore = report.conformanceScore;
            else
                out.conformanceScore = [];
            end

            % Policy analysis from PolicyAnalyzer
            if isfield(report, 'policyAnalysis')
                out.policyAnalysis = report.policyAnalysis;
            else
                out.policyAnalysis = struct();
            end

            % Coverage statistics
            if isfield(report, 'coverageStats')
                out.coverageStats = report.coverageStats;
            else
                out.coverageStats = struct();
            end

            % Degradation matrix
            if isfield(report, 'degradationMatrix')
                out.degradationMatrix = report.degradationMatrix;
            else
                out.degradationMatrix = struct();
            end

            % Violations array
            if isfield(report, 'violations')
                out.violations = report.violations;
            else
                out.violations = [];
            end

            % Evaluation counts
            if isfield(report, 'evaluationCounts')
                out.evaluationCounts = report.evaluationCounts;
            else
                out.evaluationCounts = struct();
            end

            % Serialize to JSON
            jsonText = jsonencode(out, 'PrettyPrint', true);

            % Ensure output directory exists
            [outDir, ~, ~] = fileparts(outputPath);
            if ~isempty(outDir) && ~exist(outDir, 'dir')
                mkdir(outDir);
            end

            fid = fopen(outputPath, 'w');
            if fid == -1
                error('netsim:security:reportWriteError', ...
                    'Cannot open file for writing: %s', outputPath);
            end
            cleanupObj = onCleanup(@() fclose(fid));
            fprintf(fid, '%s', jsonText);
        end

        function writeSummaryCsv(report, outputPath)
            % writeSummaryCsv  Write one CSV row per non-conformant outcome.
            %
            %   security.SecurityReportWriter.writeSummaryCsv(report, outputPath)
            %
            %   Columns: entityId, enclave, operation, actualOutcome,
            %            intendedOutcome, simTimeSec, adversarialSource
            %
            %   Only violation and over_restriction outcomes are included.
            %
            %   report     — SecurityEvaluationReport struct (must have violations)
            %   outputPath — file path for CSV output
            %
            % Requirements: R43

            % Ensure output directory exists
            [outDir, ~, ~] = fileparts(outputPath);
            if ~isempty(outDir) && ~exist(outDir, 'dir')
                mkdir(outDir);
            end

            fid = fopen(outputPath, 'w');
            if fid == -1
                error('netsim:security:reportWriteError', ...
                    'Cannot open file for writing: %s', outputPath);
            end
            cleanupObj = onCleanup(@() fclose(fid));

            % Write header
            headers = {'entityId', 'enclave', 'operation', 'actualOutcome', ...
                'intendedOutcome', 'simTimeSec', 'adversarialSource'};
            fprintf(fid, '%s\n', strjoin(headers, ','));

            % Write violation rows
            if isfield(report, 'violations') && ~isempty(report.violations)
                violations = report.violations;
                for k = 1:numel(violations)
                    v = violations(k);
                    entityId = '';
                    if isfield(v, 'entityId')
                        entityId = char(v.entityId);
                    end
                    enclave = '';
                    if isfield(v, 'enclave')
                        enclave = char(v.enclave);
                    end
                    operation = '';
                    if isfield(v, 'operation')
                        operation = char(v.operation);
                    end
                    actualOutcome = '';
                    if isfield(v, 'actualOutcome')
                        actualOutcome = char(v.actualOutcome);
                    end
                    intendedOutcome = '';
                    if isfield(v, 'intendedOutcome')
                        intendedOutcome = char(v.intendedOutcome);
                    end
                    simTimeSec = '';
                    if isfield(v, 'simTimeSec')
                        simTimeSec = num2str(v.simTimeSec, '%g');
                    end
                    adversarialSource = 'false';
                    if isfield(v, 'adversarialSource') && v.adversarialSource
                        adversarialSource = 'true';
                    end

                    fprintf(fid, '%s,%s,%s,%s,%s,%s,%s\n', ...
                        entityId, enclave, operation, actualOutcome, ...
                        intendedOutcome, simTimeSec, adversarialSource);
                end
            end
        end

    end % methods (Static)

end % classdef
