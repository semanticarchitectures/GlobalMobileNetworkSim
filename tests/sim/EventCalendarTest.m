classdef EventCalendarTest < matlab.unittest.TestCase
    % EventCalendarTest  Unit tests for sim.EventCalendar.
    %
    % Covers:
    %   1. Empty calendar: isEmpty() returns true
    %   2. Single event: schedule then popNext returns the event
    %   3. Multiple events: popNext always returns events in non-decreasing
    %      time order (insert 10 events with random times, pop all, verify sorted)
    %   4. reschedule: change an event's time, verify it comes out at the
    %      right position
    %   5. popNext on empty calendar throws an error
    %
    % Requirements: 8.1

    % -----------------------------------------------------------------
    % Helper: build a minimal event struct
    % -----------------------------------------------------------------
    methods (Static)
        function ev = makeEvent(time, id)
            ev.time    = time;
            ev.type    = sim.EventCalendar.C2_MESSAGE_TX;
            ev.id      = uint64(id);
            ev.payload = struct();
        end
    end

    % -----------------------------------------------------------------
    % Tests
    % -----------------------------------------------------------------
    methods (Test)

        % --- Test 1: isEmpty on a fresh calendar ---
        function testEmptyCalendarIsEmpty(testCase)
            ec = sim.EventCalendar();
            testCase.verifyTrue(ec.isEmpty(), ...
                'A newly created EventCalendar should be empty.');
        end

        % --- Test 2: isEmpty returns false after scheduling ---
        function testNotEmptyAfterSchedule(testCase)
            ec = sim.EventCalendar();
            ec.schedule(EventCalendarTest.makeEvent(1.0, 1));
            testCase.verifyFalse(ec.isEmpty(), ...
                'EventCalendar should not be empty after scheduling one event.');
        end

        % --- Test 2 (continued): single event round-trip ---
        function testSingleEventRoundTrip(testCase)
            ec = sim.EventCalendar();
            ev = EventCalendarTest.makeEvent(42.5, 99);
            ev.type    = sim.EventCalendar.SIM_END;
            ev.payload = struct('info', 'test');

            ec.schedule(ev);
            out = ec.popNext();

            testCase.verifyEqual(out.time, 42.5, ...
                'Popped event time should match scheduled time.');
            testCase.verifyEqual(out.type, sim.EventCalendar.SIM_END, ...
                'Popped event type should match scheduled type.');
            testCase.verifyEqual(out.id, uint64(99), ...
                'Popped event id should match scheduled id.');
            testCase.verifyTrue(ec.isEmpty(), ...
                'Calendar should be empty after popping the only event.');
        end

        % --- Test 3: multiple events come out in non-decreasing time order ---
        function testMultipleEventsAreSorted(testCase)
            rng(42);  % fixed seed for reproducibility
            ec = sim.EventCalendar();

            n = 10;
            times = rand(1, n) * 1000;  % random times in [0, 1000)
            for k = 1:n
                ec.schedule(EventCalendarTest.makeEvent(times(k), k));
            end

            poppedTimes = zeros(1, n);
            for k = 1:n
                ev = ec.popNext();
                poppedTimes(k) = ev.time;
            end

            testCase.verifyTrue(ec.isEmpty(), ...
                'Calendar should be empty after popping all events.');

            % Verify non-decreasing order
            for k = 1:(n - 1)
                testCase.verifyLessThanOrEqual(poppedTimes(k), poppedTimes(k+1), ...
                    sprintf('Event %d (time=%.4f) should come before event %d (time=%.4f).', ...
                    k, poppedTimes(k), k+1, poppedTimes(k+1)));
            end
        end

        % --- Test 3 (extended): verify sorted order matches sort() ---
        function testMultipleEventsSortedMatchesSort(testCase)
            rng(7);
            ec = sim.EventCalendar();

            n = 10;
            times = rand(1, n) * 500;
            for k = 1:n
                ec.schedule(EventCalendarTest.makeEvent(times(k), k));
            end

            poppedTimes = zeros(1, n);
            for k = 1:n
                poppedTimes(k) = ec.popNext().time;
            end

            testCase.verifyEqual(poppedTimes, sort(times), 'AbsTol', 1e-12, ...
                'Popped times should match sorted input times.');
        end

        % --- Test 4: reschedule moves event to correct position ---
        function testRescheduleEarlier(testCase)
            % Schedule three events at t=10, t=20, t=30.
            % Reschedule the t=30 event to t=5.
            % Expected pop order: 5, 10, 20.
            ec = sim.EventCalendar();
            ec.schedule(EventCalendarTest.makeEvent(10.0, 1));
            ec.schedule(EventCalendarTest.makeEvent(20.0, 2));
            ec.schedule(EventCalendarTest.makeEvent(30.0, 3));

            ec.reschedule(uint64(3), 5.0);

            t1 = ec.popNext().time;
            t2 = ec.popNext().time;
            t3 = ec.popNext().time;

            testCase.verifyEqual(t1, 5.0,  'AbsTol', 1e-12, ...
                'First popped event should be the rescheduled one at t=5.');
            testCase.verifyEqual(t2, 10.0, 'AbsTol', 1e-12, ...
                'Second popped event should be at t=10.');
            testCase.verifyEqual(t3, 20.0, 'AbsTol', 1e-12, ...
                'Third popped event should be at t=20.');
        end

        function testRescheduleLater(testCase)
            % Schedule three events at t=10, t=20, t=30.
            % Reschedule the t=10 event to t=25.
            % Expected pop order: 20, 25, 30.
            ec = sim.EventCalendar();
            ec.schedule(EventCalendarTest.makeEvent(10.0, 1));
            ec.schedule(EventCalendarTest.makeEvent(20.0, 2));
            ec.schedule(EventCalendarTest.makeEvent(30.0, 3));

            ec.reschedule(uint64(1), 25.0);

            t1 = ec.popNext().time;
            t2 = ec.popNext().time;
            t3 = ec.popNext().time;

            testCase.verifyEqual(t1, 20.0, 'AbsTol', 1e-12, ...
                'First popped event should be at t=20.');
            testCase.verifyEqual(t2, 25.0, 'AbsTol', 1e-12, ...
                'Second popped event should be the rescheduled one at t=25.');
            testCase.verifyEqual(t3, 30.0, 'AbsTol', 1e-12, ...
                'Third popped event should be at t=30.');
        end

        function testRescheduleToSameTime(testCase)
            % Rescheduling to the same time should not break heap order.
            ec = sim.EventCalendar();
            ec.schedule(EventCalendarTest.makeEvent(10.0, 1));
            ec.schedule(EventCalendarTest.makeEvent(20.0, 2));

            ec.reschedule(uint64(1), 10.0);  % no-op in terms of order

            t1 = ec.popNext().time;
            t2 = ec.popNext().time;

            testCase.verifyEqual(t1, 10.0, 'AbsTol', 1e-12);
            testCase.verifyEqual(t2, 20.0, 'AbsTol', 1e-12);
        end

        % --- Test 5: popNext on empty calendar throws an error ---
        function testPopNextOnEmptyThrows(testCase)
            ec = sim.EventCalendar();
            testCase.verifyError(@() ec.popNext(), 'sim:EventCalendar:empty', ...
                'popNext on an empty calendar should throw sim:EventCalendar:empty.');
        end

        % --- Additional: reschedule with unknown id throws ---
        function testRescheduleUnknownIdThrows(testCase)
            ec = sim.EventCalendar();
            ec.schedule(EventCalendarTest.makeEvent(1.0, 1));
            testCase.verifyError(@() ec.reschedule(uint64(999), 2.0), ...
                'sim:EventCalendar:notFound', ...
                'reschedule with unknown id should throw sim:EventCalendar:notFound.');
        end

        % --- Additional: capacity doubling — schedule more than initial capacity ---
        function testCapacityDoubling(testCase)
            % Start with a tiny capacity of 4 and insert 20 events.
            ec = sim.EventCalendar(4);
            n = 20;
            for k = 1:n
                ec.schedule(EventCalendarTest.makeEvent(n - k + 1, k));
            end

            % Pop all and verify sorted order
            prev = -inf;
            for k = 1:n
                ev = ec.popNext();
                testCase.verifyGreaterThanOrEqual(ev.time, prev, ...
                    'Events should come out in non-decreasing time order after capacity doubling.');
                prev = ev.time;
            end
            testCase.verifyTrue(ec.isEmpty());
        end

        % --- Additional: event type constants are defined ---
        function testEventTypeConstants(testCase)
            testCase.verifyEqual(sim.EventCalendar.C2_MESSAGE_TX,      "C2_MESSAGE_TX");
            testCase.verifyEqual(sim.EventCalendar.C2_MESSAGE_RX,      "C2_MESSAGE_RX");
            testCase.verifyEqual(sim.EventCalendar.C2_MESSAGE_FAIL,    "C2_MESSAGE_FAIL");
            testCase.verifyEqual(sim.EventCalendar.OUTAGE_START,       "OUTAGE_START");
            testCase.verifyEqual(sim.EventCalendar.OUTAGE_END,         "OUTAGE_END");
            testCase.verifyEqual(sim.EventCalendar.BACKGROUND_REFRESH, "BACKGROUND_REFRESH");
            testCase.verifyEqual(sim.EventCalendar.AGENT_IDLE_CHECK,   "AGENT_IDLE_CHECK");
            testCase.verifyEqual(sim.EventCalendar.SIM_END,            "SIM_END");
        end

        % --- Additional: tie-breaking — equal times are all returned ---
        function testEqualTimesAllReturned(testCase)
            ec = sim.EventCalendar();
            for k = 1:5
                ec.schedule(EventCalendarTest.makeEvent(1.0, k));
            end

            times = zeros(1, 5);
            for k = 1:5
                times(k) = ec.popNext().time;
            end

            testCase.verifyTrue(all(times == 1.0), ...
                'All events with equal time should be returned.');
            testCase.verifyTrue(ec.isEmpty());
        end

    end

end
