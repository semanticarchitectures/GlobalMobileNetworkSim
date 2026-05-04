classdef BackgroundTrafficModelTest < matlab.unittest.TestCase
    % BackgroundTrafficModelTest  Unit tests for network.BackgroundTrafficModel.
    %
    % Covers:
    %   1. Constructor validates normal distribution — throws netsim:link:invalidBgParams
    %      when std <= 0
    %   2. Constructor validates lognormal distribution — throws netsim:link:invalidBgParams
    %      when sigma <= 0
    %   3. Constructor validates uniform distribution — throws netsim:link:invalidBgParams
    %      when min > max
    %   4. resample schedules a BACKGROUND_REFRESH event in the calendar
    %   5. BACKGROUND_REFRESH event time equals simTimeSec + refreshIntervalSec
    %   6. scheduleAllInitialRefreshes schedules one event per link
    %   7. resample updates effective bandwidth (calls linkRegistry.refreshBackground)
    %
    % Requirements: 3.1, 3.2, 3.3, 3.4, 3.5

    % ======================================================================
    % Shared helpers
    % ======================================================================
    methods (Access = private)

        function nr = makeTwoNodeRegistry(~)
            % Two stationary nodes used by all link definitions.
            nd(1).id             = 'A';
            nd(1).type           = 'Stationary';
            nd(1).lat            = 0;
            nd(1).lon            = 0;
            nd(1).altM           = 0;
            nd(1).trajectory     = [];
            nd(1).keplerElements = [];

            nd(2).id             = 'B';
            nd(2).type           = 'Stationary';
            nd(2).lat            = 0;
            nd(2).lon            = 1;
            nd(2).altM           = 0;
            nd(2).trajectory     = [];
            nd(2).keplerElements = [];

            nr = network.NodeRegistry(nd);
        end

        function lk = makeLink(~, id, bgDist)
            % Build a minimal link definition with the given background
            % traffic distribution struct.
            lk.id                  = id;
            lk.type                = 'LEO_Satellite';
            lk.srcNodeId           = 'A';
            lk.dstNodeId           = 'B';
            lk.nominalLatencyMs    = 20;
            lk.bandwidthBps        = 1e9;
            lk.outageRate          = 0.001;
            lk.outageDuration      = struct('distribution', 'exponential', 'mean', 60);
            lk.backgroundTraffic   = bgDist;
            lk.coverageRadiusM     = NaN;
            lk.congestionPenaltyMs = 50;
        end

        function [lr, ec] = makeRegistryAndCalendar(testCase, linkDefs)
            % Build a LinkRegistry and a fresh EventCalendar from linkDefs.
            nr = testCase.makeTwoNodeRegistry();
            lr = network.LinkRegistry(linkDefs, nr);
            ec = sim.EventCalendar();
        end

    end

    % ======================================================================
    % Tests
    % ======================================================================
    methods (Test)

        % ------------------------------------------------------------------
        % Test 1: Constructor validates normal std <= 0
        % ------------------------------------------------------------------

        function testConstructorThrowsForNormalStdZero(testCase)
            % normal distribution with std = 0 should throw netsim:link:invalidBgParams.
            % Requirements: 3.5
            bgDist = struct('distribution', 'normal', 'mean', 0.3, 'std', 0);
            lk = testCase.makeLink('L1', bgDist);
            [lr, ec] = testCase.makeRegistryAndCalendar(lk);

            testCase.verifyError( ...
                @() network.BackgroundTrafficModel(lr, ec), ...
                'netsim:link:invalidBgParams', ...
                'normal distribution with std=0 should throw netsim:link:invalidBgParams.');
        end

        function testConstructorThrowsForNormalStdNegative(testCase)
            % normal distribution with std < 0 should throw netsim:link:invalidBgParams.
            % Requirements: 3.5
            bgDist = struct('distribution', 'normal', 'mean', 0.3, 'std', -1);
            lk = testCase.makeLink('L1', bgDist);
            [lr, ec] = testCase.makeRegistryAndCalendar(lk);

            testCase.verifyError( ...
                @() network.BackgroundTrafficModel(lr, ec), ...
                'netsim:link:invalidBgParams', ...
                'normal distribution with std<0 should throw netsim:link:invalidBgParams.');
        end

        function testConstructorAcceptsValidNormal(testCase)
            % normal distribution with std > 0 should not throw.
            % Requirements: 3.5
            bgDist = struct('distribution', 'normal', 'mean', 0.3, 'std', 0.1);
            lk = testCase.makeLink('L1', bgDist);
            [lr, ec] = testCase.makeRegistryAndCalendar(lk);

            testCase.verifyWarningFree( ...
                @() network.BackgroundTrafficModel(lr, ec), ...
                'Valid normal distribution should not throw.');
        end

        % ------------------------------------------------------------------
        % Test 2: Constructor validates lognormal sigma <= 0
        % ------------------------------------------------------------------

        function testConstructorThrowsForLognormalSigmaZero(testCase)
            % lognormal distribution with sigma = 0 should throw netsim:link:invalidBgParams.
            % Requirements: 3.5
            bgDist = struct('distribution', 'lognormal', 'mu', 0, 'sigma', 0);
            lk = testCase.makeLink('L1', bgDist);
            [lr, ec] = testCase.makeRegistryAndCalendar(lk);

            testCase.verifyError( ...
                @() network.BackgroundTrafficModel(lr, ec), ...
                'netsim:link:invalidBgParams', ...
                'lognormal distribution with sigma=0 should throw netsim:link:invalidBgParams.');
        end

        function testConstructorThrowsForLognormalSigmaNegative(testCase)
            % lognormal distribution with sigma < 0 should throw netsim:link:invalidBgParams.
            % Requirements: 3.5
            bgDist = struct('distribution', 'lognormal', 'mu', 0, 'sigma', -0.5);
            lk = testCase.makeLink('L1', bgDist);
            [lr, ec] = testCase.makeRegistryAndCalendar(lk);

            testCase.verifyError( ...
                @() network.BackgroundTrafficModel(lr, ec), ...
                'netsim:link:invalidBgParams', ...
                'lognormal distribution with sigma<0 should throw netsim:link:invalidBgParams.');
        end

        function testConstructorAcceptsValidLognormal(testCase)
            % lognormal distribution with sigma > 0 should not throw.
            % Requirements: 3.5
            bgDist = struct('distribution', 'lognormal', 'mu', 0, 'sigma', 0.5);
            lk = testCase.makeLink('L1', bgDist);
            [lr, ec] = testCase.makeRegistryAndCalendar(lk);

            testCase.verifyWarningFree( ...
                @() network.BackgroundTrafficModel(lr, ec), ...
                'Valid lognormal distribution should not throw.');
        end

        % ------------------------------------------------------------------
        % Test 3: Constructor validates uniform min > max
        % ------------------------------------------------------------------

        function testConstructorThrowsForUniformMinGtMax(testCase)
            % uniform distribution with min > max should throw netsim:link:invalidBgParams.
            % Requirements: 3.5
            bgDist = struct('distribution', 'uniform', 'min', 0.8, 'max', 0.2);
            lk = testCase.makeLink('L1', bgDist);
            [lr, ec] = testCase.makeRegistryAndCalendar(lk);

            testCase.verifyError( ...
                @() network.BackgroundTrafficModel(lr, ec), ...
                'netsim:link:invalidBgParams', ...
                'uniform distribution with min>max should throw netsim:link:invalidBgParams.');
        end

        function testConstructorAcceptsValidUniform(testCase)
            % uniform distribution with min <= max should not throw.
            % Requirements: 3.5
            bgDist = struct('distribution', 'uniform', 'min', 0.1, 'max', 0.4);
            lk = testCase.makeLink('L1', bgDist);
            [lr, ec] = testCase.makeRegistryAndCalendar(lk);

            testCase.verifyWarningFree( ...
                @() network.BackgroundTrafficModel(lr, ec), ...
                'Valid uniform distribution should not throw.');
        end

        function testConstructorAcceptsUniformMinEqualMax(testCase)
            % uniform distribution with min == max (degenerate) should not throw.
            % Requirements: 3.5
            bgDist = struct('distribution', 'uniform', 'min', 0.3, 'max', 0.3);
            lk = testCase.makeLink('L1', bgDist);
            [lr, ec] = testCase.makeRegistryAndCalendar(lk);

            testCase.verifyWarningFree( ...
                @() network.BackgroundTrafficModel(lr, ec), ...
                'Degenerate uniform distribution (min==max) should not throw.');
        end

        % ------------------------------------------------------------------
        % Test 4: resample schedules a BACKGROUND_REFRESH event in the calendar
        % ------------------------------------------------------------------

        function testResampleSchedulesBackgroundRefreshEvent(testCase)
            % After resample, the calendar should contain a BACKGROUND_REFRESH event.
            % Requirements: 3.4
            bgDist = struct('distribution', 'uniform', 'min', 0.1, 'max', 0.3);
            lk = testCase.makeLink('L1', bgDist);
            [lr, ec] = testCase.makeRegistryAndCalendar(lk);

            btm = network.BackgroundTrafficModel(lr, ec, 60);
            btm.resample('L1', 100);

            testCase.verifyFalse(ec.isEmpty(), ...
                'Calendar should not be empty after resample.');

            ev = ec.popNext();
            testCase.verifyEqual(ev.type, sim.EventCalendar.BACKGROUND_REFRESH, ...
                'Scheduled event type should be BACKGROUND_REFRESH.');
        end

        function testResampleEventPayloadContainsLinkId(testCase)
            % The BACKGROUND_REFRESH event payload must contain the linkId.
            % Requirements: 3.4
            bgDist = struct('distribution', 'uniform', 'min', 0.1, 'max', 0.3);
            lk = testCase.makeLink('L1', bgDist);
            [lr, ec] = testCase.makeRegistryAndCalendar(lk);

            btm = network.BackgroundTrafficModel(lr, ec, 60);
            btm.resample('L1', 100);

            ev = ec.popNext();
            testCase.verifyTrue(isfield(ev.payload, 'linkId'), ...
                'Event payload should have a linkId field.');
            testCase.verifyEqual(string(ev.payload.linkId), "L1", ...
                'Event payload linkId should match the resampled link.');
        end

        % ------------------------------------------------------------------
        % Test 5: BACKGROUND_REFRESH event time equals simTimeSec + refreshIntervalSec
        % ------------------------------------------------------------------

        function testResampleEventTimeIsSimTimePlusInterval(testCase)
            % The scheduled event time should be simTimeSec + refreshIntervalSec.
            % Requirements: 3.4
            bgDist = struct('distribution', 'uniform', 'min', 0.1, 'max', 0.3);
            lk = testCase.makeLink('L1', bgDist);
            [lr, ec] = testCase.makeRegistryAndCalendar(lk);

            refreshInterval = 60;
            simTime         = 150;
            btm = network.BackgroundTrafficModel(lr, ec, refreshInterval);
            btm.resample('L1', simTime);

            ev = ec.popNext();
            testCase.verifyEqual(ev.time, simTime + refreshInterval, 'AbsTol', 1e-9, ...
                'Event time should equal simTimeSec + refreshIntervalSec.');
        end

        function testResampleEventTimeWithCustomInterval(testCase)
            % Verify event time with a non-default refresh interval.
            % Requirements: 3.4
            bgDist = struct('distribution', 'uniform', 'min', 0.1, 'max', 0.3);
            lk = testCase.makeLink('L1', bgDist);
            [lr, ec] = testCase.makeRegistryAndCalendar(lk);

            refreshInterval = 120;
            simTime         = 500;
            btm = network.BackgroundTrafficModel(lr, ec, refreshInterval);
            btm.resample('L1', simTime);

            ev = ec.popNext();
            testCase.verifyEqual(ev.time, 620, 'AbsTol', 1e-9, ...
                'Event time should be 500 + 120 = 620 s.');
        end

        % ------------------------------------------------------------------
        % Test 6: scheduleAllInitialRefreshes schedules one event per link
        % ------------------------------------------------------------------

        function testScheduleAllInitialRefreshesOneEventPerLink(testCase)
            % scheduleAllInitialRefreshes should schedule exactly one event per link.
            % Requirements: 3.4
            bgDist = struct('distribution', 'uniform', 'min', 0.1, 'max', 0.3);
            nr = testCase.makeTwoNodeRegistry();
            lk(1) = testCase.makeLink('L1', bgDist);
            lk(2) = testCase.makeLink('L2', bgDist);
            lk(3) = testCase.makeLink('L3', bgDist);
            lr = network.LinkRegistry(lk, nr);
            ec = sim.EventCalendar();

            btm = network.BackgroundTrafficModel(lr, ec, 60);
            btm.scheduleAllInitialRefreshes(0);

            testCase.verifyEqual(ec.eventCount(), 3, ...
                'scheduleAllInitialRefreshes should schedule one event per link (3 links → 3 events).');
        end

        function testScheduleAllInitialRefreshesEventTimes(testCase)
            % All initial refresh events should be at startTimeSec + refreshIntervalSec.
            % Requirements: 3.4
            bgDist = struct('distribution', 'uniform', 'min', 0.1, 'max', 0.3);
            nr = testCase.makeTwoNodeRegistry();
            lk(1) = testCase.makeLink('L1', bgDist);
            lk(2) = testCase.makeLink('L2', bgDist);
            lr = network.LinkRegistry(lk, nr);
            ec = sim.EventCalendar();

            startTime       = 10;
            refreshInterval = 60;
            btm = network.BackgroundTrafficModel(lr, ec, refreshInterval);
            btm.scheduleAllInitialRefreshes(startTime);

            expectedTime = startTime + refreshInterval;
            ev1 = ec.popNext();
            ev2 = ec.popNext();

            testCase.verifyEqual(ev1.time, expectedTime, 'AbsTol', 1e-9, ...
                'First initial refresh event time should be startTimeSec + refreshIntervalSec.');
            testCase.verifyEqual(ev2.time, expectedTime, 'AbsTol', 1e-9, ...
                'Second initial refresh event time should be startTimeSec + refreshIntervalSec.');
        end

        function testScheduleAllInitialRefreshesAllTypesAreBackgroundRefresh(testCase)
            % All events scheduled by scheduleAllInitialRefreshes should be
            % BACKGROUND_REFRESH type.
            % Requirements: 3.4
            bgDist = struct('distribution', 'uniform', 'min', 0.1, 'max', 0.3);
            nr = testCase.makeTwoNodeRegistry();
            lk(1) = testCase.makeLink('L1', bgDist);
            lk(2) = testCase.makeLink('L2', bgDist);
            lr = network.LinkRegistry(lk, nr);
            ec = sim.EventCalendar();

            btm = network.BackgroundTrafficModel(lr, ec, 60);
            btm.scheduleAllInitialRefreshes(0);

            ev1 = ec.popNext();
            ev2 = ec.popNext();

            testCase.verifyEqual(ev1.type, sim.EventCalendar.BACKGROUND_REFRESH, ...
                'First event should be BACKGROUND_REFRESH.');
            testCase.verifyEqual(ev2.type, sim.EventCalendar.BACKGROUND_REFRESH, ...
                'Second event should be BACKGROUND_REFRESH.');
        end

        % ------------------------------------------------------------------
        % Test 7: resample updates effective bandwidth (calls refreshBackground)
        % ------------------------------------------------------------------

        function testResampleUpdatesEffectiveBandwidth(testCase)
            % After resample, effective bandwidth should reflect the new load.
            % We use a uniform [0.5, 0.5] distribution (deterministic 50% load)
            % so we can predict the exact effective bandwidth.
            % Requirements: 3.1, 3.2
            bgDist = struct('distribution', 'uniform', 'min', 0.5, 'max', 0.5);
            lk = testCase.makeLink('L1', bgDist);
            [lr, ec] = testCase.makeRegistryAndCalendar(lk);

            btm = network.BackgroundTrafficModel(lr, ec, 60);

            % Before resample, effective BW = full bandwidth (load = 0)
            bwBefore = lr.getEffectiveBandwidth('L1');
            testCase.verifyEqual(bwBefore, 1e9, 'AbsTol', 1, ...
                'Initial effective bandwidth should equal total bandwidth.');

            btm.resample('L1', 0);

            % After resample with 50% load, effective BW = 0.5 * 1e9
            bwAfter = lr.getEffectiveBandwidth('L1');
            testCase.verifyEqual(bwAfter, 0.5e9, 'AbsTol', 1, ...
                'Effective bandwidth should be 50% of total after 50% load resample.');
        end

        function testResampleWithFullLoadSetsCongestion(testCase)
            % After resample with load >= 1.0, effective bandwidth should be 0.
            % Requirements: 3.3
            bgDist = struct('distribution', 'uniform', 'min', 1.0, 'max', 1.0);
            lk = testCase.makeLink('L1', bgDist);
            [lr, ec] = testCase.makeRegistryAndCalendar(lk);

            btm = network.BackgroundTrafficModel(lr, ec, 60);
            btm.resample('L1', 0);

            bw = lr.getEffectiveBandwidth('L1');
            testCase.verifyEqual(bw, 0, 'AbsTol', 1e-9, ...
                'Effective bandwidth should be 0 when load = 1.0 (congested).');
        end

        % ------------------------------------------------------------------
        % Test 8: Default refresh interval is 60 seconds
        % ------------------------------------------------------------------

        function testDefaultRefreshIntervalIs60(testCase)
            % When no refreshIntervalSec is provided, default should be 60 s.
            % Requirements: 3.4
            bgDist = struct('distribution', 'uniform', 'min', 0.1, 'max', 0.3);
            lk = testCase.makeLink('L1', bgDist);
            [lr, ec] = testCase.makeRegistryAndCalendar(lk);

            btm = network.BackgroundTrafficModel(lr, ec);  % no interval arg
            btm.resample('L1', 0);

            ev = ec.popNext();
            testCase.verifyEqual(ev.time, 60, 'AbsTol', 1e-9, ...
                'Default refresh interval should be 60 s (event at t=0+60=60).');
        end

    end % methods (Test)

end % classdef
