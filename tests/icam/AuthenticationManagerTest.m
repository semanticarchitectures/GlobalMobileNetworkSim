classdef AuthenticationManagerTest < matlab.unittest.TestCase
    % AuthenticationManagerTest  Unit tests for icam.AuthenticationManager.
    %
    % Covers:
    %   1. isAuthenticated returns false before any exchange
    %   2. isAuthenticated returns true after recordSuccess
    %   3. initiateExchange schedules AUTH_REQUEST, AUTH_RESPONSE, AUTH_TIMEOUT events
    %   4. Canonical pair key is order-independent (A|B same as B|A)
    %   5. recordFailure increments retry counter
    %
    % Requirements: 19.1, 19.2, 19.3, 19.4, 19.5, 19.6

    % ======================================================================
    % Test 1: isAuthenticated returns false before any exchange
    % ======================================================================
    methods (Test)

        function testIsAuthenticatedFalseBeforeExchange(testCase)
            % isAuthenticated should return false when no exchange has been initiated.
            %
            % Requirements: 19.1, 19.3

            am = icam.AuthenticationManager();
            tf = am.isAuthenticated('EntityA', 'EntityB');
            testCase.verifyFalse(tf, ...
                'isAuthenticated should return false before any exchange');
        end

        function testIsAuthenticatedFalseForUnknownPair(testCase)
            % isAuthenticated should return false for a pair that has never
            % been seen, even if other pairs exist.
            %
            % Requirements: 19.1

            am = icam.AuthenticationManager();
            ec = sim.EventCalendar();
            am.initiateExchange('EntityA', 'EntityB', 0.0, ec);

            % Different pair — should still be false
            tf = am.isAuthenticated('EntityC', 'EntityD');
            testCase.verifyFalse(tf, ...
                'isAuthenticated should return false for an unknown pair');
        end

        % ======================================================================
        % Test 2: isAuthenticated returns true after recordSuccess
        % ======================================================================

        function testIsAuthenticatedTrueAfterRecordSuccess(testCase)
            % isAuthenticated should return true after recordSuccess is called.
            %
            % Requirements: 19.3, 19.4

            am = icam.AuthenticationManager();
            am.recordSuccess('EntityA', 'EntityB', 10.0);
            tf = am.isAuthenticated('EntityA', 'EntityB');
            testCase.verifyTrue(tf, ...
                'isAuthenticated should return true after recordSuccess');
        end

        function testIsAuthenticatedFalseBeforeSuccessAfterInitiate(testCase)
            % isAuthenticated should remain false after initiateExchange but
            % before recordSuccess.
            %
            % Requirements: 19.1, 19.3

            am = icam.AuthenticationManager();
            ec = sim.EventCalendar();
            am.initiateExchange('EntityA', 'EntityB', 0.0, ec);

            tf = am.isAuthenticated('EntityA', 'EntityB');
            testCase.verifyFalse(tf, ...
                'isAuthenticated should be false after initiate but before success');
        end

        % ======================================================================
        % Test 3: initiateExchange schedules AUTH_REQUEST, AUTH_RESPONSE, AUTH_TIMEOUT
        % ======================================================================

        function testInitiateExchangeSchedulesThreeEvents(testCase)
            % initiateExchange should schedule exactly 3 events into the calendar.
            %
            % Requirements: 19.2

            am = icam.AuthenticationManager(3, 0.5, 30.0);
            ec = sim.EventCalendar();

            am.initiateExchange('EntityA', 'EntityB', 100.0, ec);

            testCase.verifyEqual(ec.eventCount(), 3, ...
                'initiateExchange should schedule exactly 3 events');
        end

        function testInitiateExchangeSchedulesAuthRequest(testCase)
            % initiateExchange should schedule an AUTH_REQUEST event at simTimeSec.
            %
            % Requirements: 19.2

            am = icam.AuthenticationManager(3, 0.5, 30.0);
            ec = sim.EventCalendar();

            am.initiateExchange('EntityA', 'EntityB', 100.0, ec);

            % Pop events in time order and find AUTH_REQUEST
            found = false;
            while ~ec.isEmpty()
                ev = ec.popNext();
                if strcmp(ev.type, sim.EventCalendar.AUTH_REQUEST)
                    testCase.verifyEqual(ev.time, 100.0, ...
                        'AUTH_REQUEST should be scheduled at simTimeSec');
                    found = true;
                end
            end
            testCase.verifyTrue(found, 'AUTH_REQUEST event should be scheduled');
        end

        function testInitiateExchangeSchedulesAuthResponse(testCase)
            % initiateExchange should schedule an AUTH_RESPONSE event at
            % simTimeSec + authLatencySec.
            %
            % Requirements: 19.2

            authLatency = 0.5;
            am = icam.AuthenticationManager(3, authLatency, 30.0);
            ec = sim.EventCalendar();

            simTime = 100.0;
            am.initiateExchange('EntityA', 'EntityB', simTime, ec);

            found = false;
            while ~ec.isEmpty()
                ev = ec.popNext();
                if strcmp(ev.type, sim.EventCalendar.AUTH_RESPONSE)
                    testCase.verifyEqual(ev.time, simTime + authLatency, ...
                        'AUTH_RESPONSE should be at simTimeSec + authLatencySec');
                    found = true;
                end
            end
            testCase.verifyTrue(found, 'AUTH_RESPONSE event should be scheduled');
        end

        function testInitiateExchangeSchedulesAuthTimeout(testCase)
            % initiateExchange should schedule an AUTH_TIMEOUT event at
            % simTimeSec + retryLimitSec.
            %
            % Requirements: 19.2

            retryLimit = 30.0;
            am = icam.AuthenticationManager(3, 0.5, retryLimit);
            ec = sim.EventCalendar();

            simTime = 100.0;
            am.initiateExchange('EntityA', 'EntityB', simTime, ec);

            found = false;
            while ~ec.isEmpty()
                ev = ec.popNext();
                if strcmp(ev.type, sim.EventCalendar.AUTH_TIMEOUT)
                    testCase.verifyEqual(ev.time, simTime + retryLimit, ...
                        'AUTH_TIMEOUT should be at simTimeSec + retryLimitSec');
                    found = true;
                end
            end
            testCase.verifyTrue(found, 'AUTH_TIMEOUT event should be scheduled');
        end

        function testInitiateExchangeEventPayloadsContainEntityIds(testCase)
            % Events scheduled by initiateExchange should carry srcEntityId
            % and dstEntityId in their payloads.
            %
            % Requirements: 19.2

            am = icam.AuthenticationManager();
            ec = sim.EventCalendar();

            am.initiateExchange('EntityA', 'EntityB', 0.0, ec);

            while ~ec.isEmpty()
                ev = ec.popNext();
                testCase.verifyTrue(isfield(ev.payload, 'srcEntityId'), ...
                    'Event payload should have srcEntityId');
                testCase.verifyTrue(isfield(ev.payload, 'dstEntityId'), ...
                    'Event payload should have dstEntityId');
            end
        end

        % ======================================================================
        % Test 4: Canonical pair key is order-independent
        % ======================================================================

        function testCanonicalKeyOrderIndependentSuccess(testCase)
            % recordSuccess(A, B) should be visible via isAuthenticated(B, A).
            %
            % Requirements: 19.3

            am = icam.AuthenticationManager();
            am.recordSuccess('EntityA', 'EntityB', 5.0);

            % Query in reverse order
            tf = am.isAuthenticated('EntityB', 'EntityA');
            testCase.verifyTrue(tf, ...
                'isAuthenticated(B,A) should return true after recordSuccess(A,B)');
        end

        function testCanonicalKeyOrderIndependentInitiate(testCase)
            % initiateExchange(A, B) state should be visible via isAuthenticated(B, A).
            %
            % Requirements: 19.3

            am = icam.AuthenticationManager();
            ec = sim.EventCalendar();
            am.initiateExchange('EntityA', 'EntityB', 0.0, ec);
            am.recordSuccess('EntityB', 'EntityA', 1.0);

            tf = am.isAuthenticated('EntityA', 'EntityB');
            testCase.verifyTrue(tf, ...
                'Order-independent key: success recorded as (B,A) visible as (A,B)');
        end

        function testCanonicalKeySymmetry(testCase)
            % getPairState should return the same entry regardless of argument order.
            %
            % Requirements: 19.3

            am = icam.AuthenticationManager();
            am.recordSuccess('Alpha', 'Beta', 42.0);

            stateAB = am.getPairState('Alpha', 'Beta');
            stateBA = am.getPairState('Beta', 'Alpha');

            testCase.verifyTrue(stateAB.authenticated, ...
                'State (A,B) should be authenticated');
            testCase.verifyTrue(stateBA.authenticated, ...
                'State (B,A) should be authenticated (same entry)');
            testCase.verifyEqual(stateAB.authTimeSec, stateBA.authTimeSec, ...
                'authTimeSec should be identical regardless of argument order');
        end

        % ======================================================================
        % Test 5: recordFailure increments retry counter
        % ======================================================================

        function testRecordFailureIncrementsRetryCount(testCase)
            % recordFailure should increment retryCount by 1.
            %
            % Requirements: 19.5

            am = icam.AuthenticationManager(3, 0.5, 30.0);

            am.recordFailure('EntityA', 'EntityB', 'timeout', [], []);

            state = am.getPairState('EntityA', 'EntityB');
            testCase.verifyEqual(state.retryCount, uint32(1), ...
                'retryCount should be 1 after one recordFailure call');
        end

        function testRecordFailureIncrementsRetryCountMultipleTimes(testCase)
            % Multiple recordFailure calls should accumulate retryCount.
            %
            % Requirements: 19.5

            am = icam.AuthenticationManager(5, 0.5, 30.0);

            am.recordFailure('EntityA', 'EntityB', 'timeout', [], []);
            am.recordFailure('EntityA', 'EntityB', 'timeout', [], []);
            am.recordFailure('EntityA', 'EntityB', 'timeout', [], []);

            state = am.getPairState('EntityA', 'EntityB');
            testCase.verifyEqual(state.retryCount, uint32(3), ...
                'retryCount should be 3 after three recordFailure calls');
        end

        function testRecordFailureReschedulesWhenRetriesRemain(testCase)
            % recordFailure should re-schedule AUTH_REQUEST when retryCount < maxRetries.
            %
            % Requirements: 19.5, 19.6

            am = icam.AuthenticationManager(3, 0.5, 30.0);
            ec = sim.EventCalendar();

            % First failure — retryCount becomes 1, which is < maxRetries(3)
            am.recordFailure('EntityA', 'EntityB', 'timeout', 10.0, ec);

            % Should have scheduled 3 new events (AUTH_REQUEST, AUTH_RESPONSE, AUTH_TIMEOUT)
            testCase.verifyEqual(ec.eventCount(), 3, ...
                'recordFailure should re-schedule 3 events when retries remain');
        end

        function testRecordFailureDoesNotRescheduleAtMaxRetries(testCase)
            % recordFailure should NOT re-schedule when retryCount reaches maxRetries.
            %
            % Requirements: 19.6

            am = icam.AuthenticationManager(2, 0.5, 30.0);
            ec = sim.EventCalendar();

            % First failure: retryCount = 1 < maxRetries(2) → reschedules
            am.recordFailure('EntityA', 'EntityB', 'timeout', 10.0, ec);
            % Drain the calendar
            while ~ec.isEmpty(); ec.popNext(); end

            % Second failure: retryCount = 2 >= maxRetries(2) → no reschedule
            am.recordFailure('EntityA', 'EntityB', 'timeout', 20.0, ec);

            testCase.verifyEqual(ec.eventCount(), 0, ...
                'recordFailure should not reschedule when retryCount >= maxRetries');
        end

        function testRecordFailureDoesNotSetAuthenticated(testCase)
            % recordFailure should leave authenticated = false.
            %
            % Requirements: 19.5

            am = icam.AuthenticationManager(3, 0.5, 30.0);
            am.recordFailure('EntityA', 'EntityB', 'timeout', [], []);

            tf = am.isAuthenticated('EntityA', 'EntityB');
            testCase.verifyFalse(tf, ...
                'isAuthenticated should remain false after recordFailure');
        end

        % ======================================================================
        % Additional: default constructor parameters
        % ======================================================================

        function testDefaultConstructorParameters(testCase)
            % Default constructor should use maxRetries=3, authLatencySec=0.5,
            % retryLimitSec=30.
            %
            % Requirements: 19.1

            am = icam.AuthenticationManager();
            ec = sim.EventCalendar();

            am.initiateExchange('A', 'B', 0.0, ec);

            % Find AUTH_RESPONSE and AUTH_TIMEOUT times
            respTime    = NaN;
            timeoutTime = NaN;
            while ~ec.isEmpty()
                ev = ec.popNext();
                if strcmp(ev.type, sim.EventCalendar.AUTH_RESPONSE)
                    respTime = ev.time;
                elseif strcmp(ev.type, sim.EventCalendar.AUTH_TIMEOUT)
                    timeoutTime = ev.time;
                end
            end

            testCase.verifyEqual(respTime, 0.5, ...
                'Default authLatencySec should be 0.5');
            testCase.verifyEqual(timeoutTime, 30.0, ...
                'Default retryLimitSec should be 30');
        end

    end % methods (Test)

end % classdef
