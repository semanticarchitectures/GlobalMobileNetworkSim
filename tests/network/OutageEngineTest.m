classdef OutageEngineTest < matlab.unittest.TestCase
    % OutageEngineTest  Unit tests for network.OutageEngine.
    %
    % Covers:
    %   1. scheduleNextOutage schedules an OUTAGE_START event in the calendar
    %   2. scheduleOutageEnd schedules an OUTAGE_END event in the calendar
    %   3. scheduleAllInitialOutages schedules one OUTAGE_START per link
    %   4. OUTAGE_START event time is > currentTimeSec (positive inter-arrival)
    %   5. OUTAGE_END event time is > OUTAGE_START time (positive duration)
    %
    % Requirements: 4.1, 4.2, 4.3, 4.4, 4.5

    % ======================================================================
    % Shared helpers
    % ======================================================================
    methods (Access = private)

        function nr = makeTwoNodeRegistry(~)
            % Two stationary nodes used as link endpoints.
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

        function lk = makeLink(~, id, outageRate, outageDist)
            % Build a minimal link definition struct.
            lk.id               = id;
            lk.type             = 'LEO_Satellite';
            lk.srcNodeId        = 'A';
            lk.dstNodeId        = 'B';
            lk.nominalLatencyMs = 20;
            lk.bandwidthBps     = 1e9;
            lk.outageRate       = outageRate;
            lk.outageDuration   = outageDist;
            lk.backgroundTraffic = struct('distribution', 'uniform', 'min', 0.1, 'max', 0.3);
            lk.coverageRadiusM  = NaN;
        end

        function [oe, ec, lr] = makeEngine(testCase, linkDefs)
            % Build a LinkRegistry, EventCalendar, and OutageEngine.
            nr = testCase.makeTwoNodeRegistry();
            lr = network.LinkRegistry(linkDefs, nr);
            ec = sim.EventCalendar();
            oe = network.OutageEngine(lr, ec);
        end

    end

    % ======================================================================
    % Tests
    % ======================================================================
    methods (Test)

        % ------------------------------------------------------------------
        % Test 1: scheduleNextOutage schedules an OUTAGE_START event
        % ------------------------------------------------------------------

        function testScheduleNextOutageAddsEvent(testCase)
            % After calling scheduleNextOutage, the calendar should contain
            % exactly one event of type OUTAGE_START.
            % Requirements: 4.1
            lk = testCase.makeLink('L1', 0.01, ...
                struct('distribution', 'exponential', 'mean', 60));
            [oe, ec, ~] = testCase.makeEngine(lk);

            testCase.verifyTrue(ec.isEmpty(), 'Calendar should start empty.');

            oe.scheduleNextOutage('L1', 0);

            testCase.verifyFalse(ec.isEmpty(), ...
                'Calendar should have one event after scheduleNextOutage.');
            testCase.verifyEqual(ec.eventCount(), 1, ...
                'Exactly one event should be scheduled.');

            ev = ec.popNext();
            testCase.verifyEqual(ev.type, sim.EventCalendar.OUTAGE_START, ...
                'Scheduled event should be of type OUTAGE_START.');
            testCase.verifyEqual(ev.payload.linkId, "L1", ...
                'OUTAGE_START payload should contain the correct linkId.');
        end

        % ------------------------------------------------------------------
        % Test 2: scheduleOutageEnd schedules an OUTAGE_END event
        % ------------------------------------------------------------------

        function testScheduleOutageEndAddsEvent(testCase)
            % After calling scheduleOutageEnd, the calendar should contain
            % exactly one event of type OUTAGE_END.
            % Requirements: 4.2, 4.5
            lk = testCase.makeLink('L1', 0.01, ...
                struct('distribution', 'exponential', 'mean', 60));
            [oe, ec, ~] = testCase.makeEngine(lk);

            oe.scheduleOutageEnd('L1', 100);

            testCase.verifyEqual(ec.eventCount(), 1, ...
                'Exactly one event should be scheduled.');

            ev = ec.popNext();
            testCase.verifyEqual(ev.type, sim.EventCalendar.OUTAGE_END, ...
                'Scheduled event should be of type OUTAGE_END.');
            testCase.verifyEqual(ev.payload.linkId, "L1", ...
                'OUTAGE_END payload should contain the correct linkId.');
        end

        % ------------------------------------------------------------------
        % Test 3: scheduleAllInitialOutages schedules one OUTAGE_START per link
        % ------------------------------------------------------------------

        function testScheduleAllInitialOutagesOnePerLink(testCase)
            % With N links, scheduleAllInitialOutages should schedule exactly
            % N OUTAGE_START events.
            % Requirements: 4.1
            lk(1) = testCase.makeLink('L1', 0.01, ...
                struct('distribution', 'exponential', 'mean', 60));
            lk(2) = testCase.makeLink('L2', 0.005, ...
                struct('distribution', 'fixed', 'value', 120));
            lk(3) = testCase.makeLink('L3', 0.02, ...
                struct('distribution', 'lognormal', 'mu', 3, 'sigma', 0.5));
            [oe, ec, ~] = testCase.makeEngine(lk);

            oe.scheduleAllInitialOutages(0);

            testCase.verifyEqual(ec.eventCount(), 3, ...
                'scheduleAllInitialOutages should schedule one event per link (3 links).');

            % All events should be OUTAGE_START
            for k = 1:3
                ev = ec.popNext();
                testCase.verifyEqual(ev.type, sim.EventCalendar.OUTAGE_START, ...
                    sprintf('Event %d should be OUTAGE_START.', k));
            end
        end

        function testScheduleAllInitialOutagesSingleLink(testCase)
            % With a single link, exactly one OUTAGE_START is scheduled.
            % Requirements: 4.1
            lk = testCase.makeLink('L1', 0.01, ...
                struct('distribution', 'exponential', 'mean', 60));
            [oe, ec, ~] = testCase.makeEngine(lk);

            oe.scheduleAllInitialOutages(0);

            testCase.verifyEqual(ec.eventCount(), 1, ...
                'One OUTAGE_START should be scheduled for a single link.');
        end

        % ------------------------------------------------------------------
        % Test 4: OUTAGE_START event time is > currentTimeSec
        % ------------------------------------------------------------------

        function testOutageStartTimeIsAfterCurrentTime(testCase)
            % The scheduled OUTAGE_START time must be strictly greater than
            % currentTimeSec (positive inter-arrival time from exprnd).
            % Requirements: 4.1
            rng(42);  % fixed seed for reproducibility
            lk = testCase.makeLink('L1', 0.01, ...
                struct('distribution', 'exponential', 'mean', 60));
            [oe, ec, ~] = testCase.makeEngine(lk);

            currentTime = 500;
            oe.scheduleNextOutage('L1', currentTime);

            ev = ec.popNext();
            testCase.verifyGreaterThan(ev.time, currentTime, ...
                'OUTAGE_START time must be strictly greater than currentTimeSec.');
        end

        function testOutageStartTimeIsAfterCurrentTimeNonZero(testCase)
            % Same check with a non-zero starting time.
            % Requirements: 4.1
            rng(7);
            lk = testCase.makeLink('L1', 0.1, ...
                struct('distribution', 'exponential', 'mean', 10));
            [oe, ec, ~] = testCase.makeEngine(lk);

            currentTime = 1234.5;
            oe.scheduleNextOutage('L1', currentTime);

            ev = ec.popNext();
            testCase.verifyGreaterThan(ev.time, currentTime, ...
                'OUTAGE_START time must be > currentTimeSec for non-zero start time.');
        end

        % ------------------------------------------------------------------
        % Test 5: OUTAGE_END event time is > OUTAGE_START time
        % ------------------------------------------------------------------

        function testOutageEndTimeIsAfterStartTime(testCase)
            % The OUTAGE_END time must be strictly greater than the
            % outageStartTimeSec passed to scheduleOutageEnd.
            % Requirements: 4.2, 4.5
            rng(13);
            lk = testCase.makeLink('L1', 0.01, ...
                struct('distribution', 'exponential', 'mean', 60));
            [oe, ec, ~] = testCase.makeEngine(lk);

            outageStartTime = 300;
            oe.scheduleOutageEnd('L1', outageStartTime);

            ev = ec.popNext();
            testCase.verifyGreaterThan(ev.time, outageStartTime, ...
                'OUTAGE_END time must be strictly greater than outageStartTimeSec.');
        end

        function testOutageEndTimeAfterStartTimeLognormal(testCase)
            % Verify positive duration for lognormal distribution.
            % Requirements: 4.5
            rng(99);
            lk = testCase.makeLink('L1', 0.01, ...
                struct('distribution', 'lognormal', 'mu', 3, 'sigma', 0.5));
            [oe, ec, ~] = testCase.makeEngine(lk);

            outageStartTime = 100;
            oe.scheduleOutageEnd('L1', outageStartTime);

            ev = ec.popNext();
            testCase.verifyGreaterThan(ev.time, outageStartTime, ...
                'OUTAGE_END time must be > outageStartTimeSec for lognormal distribution.');
        end

        function testOutageEndTimeAfterStartTimeFixed(testCase)
            % Verify correct time for fixed duration distribution.
            % Requirements: 4.5
            lk = testCase.makeLink('L1', 0.01, ...
                struct('distribution', 'fixed', 'value', 120));
            [oe, ec, ~] = testCase.makeEngine(lk);

            outageStartTime = 50;
            oe.scheduleOutageEnd('L1', outageStartTime);

            ev = ec.popNext();
            testCase.verifyEqual(ev.time, outageStartTime + 120, 'AbsTol', 1e-9, ...
                'OUTAGE_END time should equal outageStartTimeSec + fixed duration.');
        end

        % ------------------------------------------------------------------
        % Additional: zero outage rate does not schedule any event
        % ------------------------------------------------------------------

        function testZeroOutageRateSchedulesNoEvent(testCase)
            % A link with outageRate = 0 should not schedule any OUTAGE_START.
            % Requirements: 4.1
            lk = testCase.makeLink('L1', 0, ...
                struct('distribution', 'exponential', 'mean', 60));
            [oe, ec, ~] = testCase.makeEngine(lk);

            oe.scheduleNextOutage('L1', 0);

            testCase.verifyTrue(ec.isEmpty(), ...
                'No event should be scheduled when outageRate = 0.');
        end

        % ------------------------------------------------------------------
        % Additional: payload linkId matches the requested link
        % ------------------------------------------------------------------

        function testOutageStartPayloadLinkId(testCase)
            % The OUTAGE_START payload.linkId must match the link that was
            % passed to scheduleNextOutage.
            % Requirements: 4.1
            lk(1) = testCase.makeLink('LinkAlpha', 0.01, ...
                struct('distribution', 'exponential', 'mean', 60));
            lk(2) = testCase.makeLink('LinkBeta',  0.01, ...
                struct('distribution', 'exponential', 'mean', 60));
            [oe, ec, ~] = testCase.makeEngine(lk);

            oe.scheduleNextOutage('LinkBeta', 0);

            ev = ec.popNext();
            testCase.verifyEqual(ev.payload.linkId, "LinkBeta", ...
                'OUTAGE_START payload.linkId should match the scheduled link.');
        end

        function testOutageEndPayloadLinkId(testCase)
            % The OUTAGE_END payload.linkId must match the link that was
            % passed to scheduleOutageEnd.
            % Requirements: 4.2
            lk = testCase.makeLink('MyLink', 0.01, ...
                struct('distribution', 'fixed', 'value', 30));
            [oe, ec, ~] = testCase.makeEngine(lk);

            oe.scheduleOutageEnd('MyLink', 200);

            ev = ec.popNext();
            testCase.verifyEqual(ev.payload.linkId, "MyLink", ...
                'OUTAGE_END payload.linkId should match the scheduled link.');
        end

        % ------------------------------------------------------------------
        % Additional: scheduleAllInitialOutages with zero-rate links
        % ------------------------------------------------------------------

        function testScheduleAllInitialOutagesSkipsZeroRate(testCase)
            % Links with outageRate = 0 should not contribute events.
            % Requirements: 4.1
            lk(1) = testCase.makeLink('L1', 0.01, ...
                struct('distribution', 'exponential', 'mean', 60));
            lk(2) = testCase.makeLink('L2', 0, ...
                struct('distribution', 'exponential', 'mean', 60));
            [oe, ec, ~] = testCase.makeEngine(lk);

            oe.scheduleAllInitialOutages(0);

            testCase.verifyEqual(ec.eventCount(), 1, ...
                'Only the link with non-zero outageRate should produce an event.');
        end

    end % methods (Test)

end % classdef
