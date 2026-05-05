classdef PlotFunctionsTest < matlab.unittest.TestCase
    % PlotFunctionsTest  Smoke tests for io.PlotFunctions.
    %
    % Verifies that each static plotting method returns a valid figure handle
    % without throwing a MATLAB error.  All figures are created with
    % 'Visible','off' inside PlotFunctions, so no windows are opened.
    %
    % Tests:
    %   1. testLatencyHistogramWithData
    %        — latencyHistogram with a valid statsReport and latency vector
    %          returns a figure handle
    %   2. testLatencyHistogramEmptyLatencies
    %        — latencyHistogram with empty latencies returns a figure handle
    %   3. testOutageGanttWithData
    %        — outageGantt with a valid statsReport returns a figure handle
    %   4. testOutageGanttEmptyPerLink
    %        — outageGantt with empty perLink returns a figure handle
    %   5. testFidelityBoxPlotWithData
    %        — fidelityBoxPlot with a valid evalReports array returns a figure handle
    %   6. testFidelityBoxPlotEmptyInput
    %        — fidelityBoxPlot with empty input returns a figure handle
    %
    % Requirements: 9.4, 9.5, 15.5

    % ======================================================================
    % TestClassSetup: add workspace root to MATLAB path
    % ======================================================================
    methods (TestClassSetup)
        function addWorkspaceRootToPath(testCase)
            % Determine workspace root (two levels up from tests/io/).
            thisDir = fileparts(mfilename('fullpath'));
            rootDir = fileparts(fileparts(thisDir));
            addpath(rootDir);
            testCase.addTeardown(@() rmpath(rootDir));
        end
    end

    % ======================================================================
    % TestMethodTeardown: close all figures to avoid accumulation
    % ======================================================================
    methods (TestMethodTeardown)
        function closeAllFigures(~)
            close all;
        end
    end

    % ======================================================================
    % Helpers
    % ======================================================================
    methods (Access = private)

        function statsReport = makeStatsReport(~)
            % Build a minimal statsReport matching §4.3.
            statsReport.scenarioName         = 'test_scenario';
            statsReport.simStartTimeSec      = 0;
            statsReport.simEndTimeSec        = 3600;
            statsReport.wallClockDurationSec = 5.2;
            statsReport.c2Messages.scheduled = 50;
            statsReport.c2Messages.delivered = 45;
            statsReport.c2Messages.failed    = 5;
            statsReport.latency.meanMs       = 310.0;
            statsReport.latency.medianMs     = 290.0;
            statsReport.latency.p95Ms        = 600.0;

            % Two per-link entries.
            link1.linkId                  = 'link_A';
            link1.meanEffectiveBwBps      = 9e8;
            link1.meanBgLoadFraction      = 0.10;
            link1.totalC2MessagesRouted   = 30;
            link1.totalOutageDurationSec  = 60;
            link1.outageFraction          = 0.017;

            link2.linkId                  = 'link_B';
            link2.meanEffectiveBwBps      = 5e8;
            link2.meanBgLoadFraction      = 0.25;
            link2.totalC2MessagesRouted   = 15;
            link2.totalOutageDurationSec  = 180;
            link2.outageFraction          = 0.05;

            statsReport.perLink = [link1, link2];

            statsReport.agentFidelity.mean = 0.85;
            statsReport.agentFidelity.min  = 0.70;
            statsReport.agentFidelity.max  = 0.95;
        end

        function evalReports = makeEvalReports(~)
            % Build a minimal evalReports struct array (two runs, two agents each).
            agent1.agentId       = 'agent_A';
            agent1.role          = 'Aircrew';
            agent1.fidelityScore = 0.90;
            agent1.missingActions = struct('actionType', {}, 'expectedTimeSec', {}, 'reason', {});
            agent1.extraActions   = struct('actionType', {}, 'observedTimeSec', {});
            agent1.deviations     = struct('actionType', {}, 'expectedTimeSec', {}, ...
                                           'observedTimeSec', {}, 'deviationSec', {});

            agent2.agentId       = 'agent_B';
            agent2.role          = 'Command_Staff';
            agent2.fidelityScore = 0.75;
            agent2.missingActions = struct('actionType', {}, 'expectedTimeSec', {}, 'reason', {});
            agent2.extraActions   = struct('actionType', {}, 'observedTimeSec', {});
            agent2.deviations     = struct('actionType', {}, 'expectedTimeSec', {}, ...
                                           'observedTimeSec', {}, 'deviationSec', {});

            run1.runId       = 'run-uuid-0001';
            run1.timestamp   = '2024-01-15T10:00:00Z';
            run1.scenarioName = 'test_scenario';
            run1.agents      = [agent1, agent2];

            agent3.agentId       = 'agent_A';
            agent3.role          = 'Aircrew';
            agent3.fidelityScore = 0.80;
            agent3.missingActions = struct('actionType', {}, 'expectedTimeSec', {}, 'reason', {});
            agent3.extraActions   = struct('actionType', {}, 'observedTimeSec', {});
            agent3.deviations     = struct('actionType', {}, 'expectedTimeSec', {}, ...
                                           'observedTimeSec', {}, 'deviationSec', {});

            agent4.agentId       = 'agent_B';
            agent4.role          = 'Command_Staff';
            agent4.fidelityScore = 0.65;
            agent4.missingActions = struct('actionType', {}, 'expectedTimeSec', {}, 'reason', {});
            agent4.extraActions   = struct('actionType', {}, 'observedTimeSec', {});
            agent4.deviations     = struct('actionType', {}, 'expectedTimeSec', {}, ...
                                           'observedTimeSec', {}, 'deviationSec', {});

            run2.runId       = 'run-uuid-0002';
            run2.timestamp   = '2024-01-15T11:00:00Z';
            run2.scenarioName = 'test_scenario';
            run2.agents      = [agent3, agent4];

            evalReports = [run1, run2];
        end

    end

    % ======================================================================
    % Tests
    % ======================================================================
    methods (Test)

        % ------------------------------------------------------------------
        % Test 1: latencyHistogram with valid statsReport and latency vector
        % ------------------------------------------------------------------
        function testLatencyHistogramWithData(testCase)
            % latencyHistogram should return a valid figure handle when given
            % a statsReport and a non-empty latency vector.
            %
            % Requirements: 9.4

            statsReport = testCase.makeStatsReport();
            latenciesMs = [280, 295, 310, 320, 600, 290, 305, 315, 280, 590];

            fig = io.PlotFunctions.latencyHistogram(statsReport, latenciesMs);

            testCase.verifyTrue(isgraphics(fig, 'figure'), ...
                'latencyHistogram should return a figure handle');
            testCase.verifyTrue(isvalid(fig), ...
                'Returned figure handle should be valid');
        end

        % ------------------------------------------------------------------
        % Test 2: latencyHistogram with empty latencies
        % ------------------------------------------------------------------
        function testLatencyHistogramEmptyLatencies(testCase)
            % latencyHistogram should return a valid figure handle when
            % latenciesMs is empty (no delivered messages).
            %
            % Requirements: 9.4

            statsReport = testCase.makeStatsReport();

            % Call with empty latency vector.
            fig = io.PlotFunctions.latencyHistogram(statsReport, []);

            testCase.verifyTrue(isgraphics(fig, 'figure'), ...
                'latencyHistogram with empty latencies should return a figure handle');
            testCase.verifyTrue(isvalid(fig), ...
                'Returned figure handle should be valid');
        end

        % ------------------------------------------------------------------
        % Test 3: outageGantt with valid statsReport
        % ------------------------------------------------------------------
        function testOutageGanttWithData(testCase)
            % outageGantt should return a valid figure handle when given a
            % statsReport with non-empty perLink data.
            %
            % Requirements: 9.5

            statsReport = testCase.makeStatsReport();

            fig = io.PlotFunctions.outageGantt(statsReport);

            testCase.verifyTrue(isgraphics(fig, 'figure'), ...
                'outageGantt should return a figure handle');
            testCase.verifyTrue(isvalid(fig), ...
                'Returned figure handle should be valid');
        end

        % ------------------------------------------------------------------
        % Test 4: outageGantt with empty perLink
        % ------------------------------------------------------------------
        function testOutageGanttEmptyPerLink(testCase)
            % outageGantt should return a valid figure handle when
            % statsReport.perLink is empty.
            %
            % Requirements: 9.5

            statsReport = testCase.makeStatsReport();
            statsReport.perLink = struct( ...
                'linkId', {}, ...
                'meanEffectiveBwBps', {}, ...
                'meanBgLoadFraction', {}, ...
                'totalC2MessagesRouted', {}, ...
                'totalOutageDurationSec', {}, ...
                'outageFraction', {});

            fig = io.PlotFunctions.outageGantt(statsReport);

            testCase.verifyTrue(isgraphics(fig, 'figure'), ...
                'outageGantt with empty perLink should return a figure handle');
            testCase.verifyTrue(isvalid(fig), ...
                'Returned figure handle should be valid');
        end

        % ------------------------------------------------------------------
        % Test 5: fidelityBoxPlot with valid evalReports array
        % ------------------------------------------------------------------
        function testFidelityBoxPlotWithData(testCase)
            % fidelityBoxPlot should return a valid figure handle when given
            % a non-empty evalReports struct array.
            %
            % Requirements: 15.5

            evalReports = testCase.makeEvalReports();

            fig = io.PlotFunctions.fidelityBoxPlot(evalReports);

            testCase.verifyTrue(isgraphics(fig, 'figure'), ...
                'fidelityBoxPlot should return a figure handle');
            testCase.verifyTrue(isvalid(fig), ...
                'Returned figure handle should be valid');
        end

        % ------------------------------------------------------------------
        % Test 6: fidelityBoxPlot with empty input
        % ------------------------------------------------------------------
        function testFidelityBoxPlotEmptyInput(testCase)
            % fidelityBoxPlot should return a valid figure handle when given
            % an empty input (no evaluation data).
            %
            % Requirements: 15.5

            fig = io.PlotFunctions.fidelityBoxPlot([]);

            testCase.verifyTrue(isgraphics(fig, 'figure'), ...
                'fidelityBoxPlot with empty input should return a figure handle');
            testCase.verifyTrue(isvalid(fig), ...
                'Returned figure handle should be valid');
        end

    end % methods (Test)

end % classdef
