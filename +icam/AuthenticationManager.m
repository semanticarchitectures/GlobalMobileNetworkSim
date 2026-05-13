classdef AuthenticationManager < handle
    % AuthenticationManager  Tracks authentication state between entity pairs.
    %
    % Uses containers.Map keyed on a canonical pair string:
    %   min(A,B) + '|' + max(A,B)   (lexicographic sort, order-independent)
    %
    % Each map entry is a struct with fields:
    %   authenticated    (logical)  — true after recordSuccess
    %   authTimeSec      (double)   — simulation time of successful auth (0 if not yet)
    %   retryCount       (uint32)   — number of failed attempts so far
    %   pendingExchangeId (uint64)  — id of the pending AUTH_TIMEOUT event (0 if none)
    %
    % Requirements: 19.1, 19.2, 19.3, 19.4, 19.5, 19.6

    properties (Access = private)
        pairMap         % containers.Map: canonical key → auth state struct
        maxRetries      % uint32 — maximum number of retry attempts
        authLatencySec  % double — latency between AUTH_REQUEST and AUTH_RESPONSE
        retryLimitSec   % double — timeout window for a single exchange attempt
        nextEventId     % uint64 — monotonically increasing event id counter
    end

    methods (Access = public)

        % ------------------------------------------------------------------
        % Constructor
        % ------------------------------------------------------------------

        function obj = AuthenticationManager(maxRetries, authLatencySec, retryLimitSec)
            % AuthenticationManager  Construct an AuthenticationManager.
            %
            %   am = icam.AuthenticationManager()
            %   am = icam.AuthenticationManager(maxRetries, authLatencySec, retryLimitSec)
            %
            %   Defaults:
            %     maxRetries     = 3
            %     authLatencySec = 0.5
            %     retryLimitSec  = 30
            %
            % Requirements: 19.1

            if nargin < 1 || isempty(maxRetries)
                maxRetries = 3;
            end
            if nargin < 2 || isempty(authLatencySec)
                authLatencySec = 0.5;
            end
            if nargin < 3 || isempty(retryLimitSec)
                retryLimitSec = 30;
            end

            obj.maxRetries     = uint32(maxRetries);
            obj.authLatencySec = authLatencySec;
            obj.retryLimitSec  = retryLimitSec;
            obj.pairMap        = containers.Map('KeyType', 'char', 'ValueType', 'any');
            obj.nextEventId    = uint64(1);
        end

        % ------------------------------------------------------------------
        % Public methods
        % ------------------------------------------------------------------

        function tf = isAuthenticated(obj, entityIdA, entityIdB)
            % isAuthenticated  Return true if the pair has a successful authentication.
            %
            %   tf = am.isAuthenticated(entityIdA, entityIdB)
            %
            %   Returns false if no exchange has been initiated or if the
            %   exchange has not yet completed successfully.
            %
            % Requirements: 19.1, 19.3

            key = obj.canonicalKey(entityIdA, entityIdB);
            if ~obj.pairMap.isKey(key)
                tf = false;
                return;
            end
            entry = obj.pairMap(key);
            tf = entry.authenticated;
        end

        function initiateExchange(obj, entityIdA, entityIdB, simTimeSec, eventCalendar)
            % initiateExchange  Schedule AUTH_REQUEST, AUTH_RESPONSE, AUTH_TIMEOUT.
            %
            %   am.initiateExchange(entityIdA, entityIdB, simTimeSec, eventCalendar)
            %
            %   Schedules three events into eventCalendar:
            %     AUTH_REQUEST  at simTimeSec
            %     AUTH_RESPONSE at simTimeSec + authLatencySec
            %     AUTH_TIMEOUT  at simTimeSec + retryLimitSec
            %
            %   The AUTH_TIMEOUT event id is stored in the pair entry so that
            %   recordSuccess can reference it (cancellation is not implemented
            %   in the base EventCalendar, but the id is available for future use).
            %
            % Requirements: 19.2, 19.3

            key = obj.canonicalKey(entityIdA, entityIdB);

            % Ensure entry exists
            if ~obj.pairMap.isKey(key)
                entry = obj.makeEntry();
            else
                entry = obj.pairMap(key);
            end

            exchangeId = obj.nextEventId;
            obj.nextEventId = obj.nextEventId + uint64(1);

            % Build payload
            payload.srcEntityId  = char(entityIdA);
            payload.dstEntityId  = char(entityIdB);
            payload.exchangeId   = exchangeId;

            % AUTH_REQUEST
            reqEvent.time    = simTimeSec;
            reqEvent.type    = sim.EventCalendar.AUTH_REQUEST;
            reqEvent.id      = obj.nextEventId;
            reqEvent.payload = payload;
            obj.nextEventId  = obj.nextEventId + uint64(1);
            eventCalendar.schedule(reqEvent);

            % AUTH_RESPONSE
            respPayload = payload;
            respPayload.success = false;   % will be updated by handler
            respEvent.time    = simTimeSec + obj.authLatencySec;
            respEvent.type    = sim.EventCalendar.AUTH_RESPONSE;
            respEvent.id      = obj.nextEventId;
            respEvent.payload = respPayload;
            obj.nextEventId   = obj.nextEventId + uint64(1);
            eventCalendar.schedule(respEvent);

            % AUTH_TIMEOUT
            timeoutEventId = obj.nextEventId;
            obj.nextEventId = obj.nextEventId + uint64(1);
            timeoutEvent.time    = simTimeSec + obj.retryLimitSec;
            timeoutEvent.type    = sim.EventCalendar.AUTH_TIMEOUT;
            timeoutEvent.id      = timeoutEventId;
            timeoutEvent.payload = payload;
            eventCalendar.schedule(timeoutEvent);

            % Store pending exchange id
            entry.pendingExchangeId = timeoutEventId;
            obj.pairMap(key) = entry;
        end

        function recordSuccess(obj, entityIdA, entityIdB, simTimeSec)
            % recordSuccess  Mark the pair as successfully authenticated.
            %
            %   am.recordSuccess(entityIdA, entityIdB, simTimeSec)
            %
            %   Sets authenticated = true and stores authTimeSec.
            %   Clears pendingExchangeId (AUTH_TIMEOUT cancellation is the
            %   caller's responsibility via EventCalendar.reschedule if needed).
            %
            % Requirements: 19.3, 19.4

            key = obj.canonicalKey(entityIdA, entityIdB);

            if ~obj.pairMap.isKey(key)
                entry = obj.makeEntry();
            else
                entry = obj.pairMap(key);
            end

            entry.authenticated     = true;
            entry.authTimeSec       = simTimeSec;
            entry.pendingExchangeId = uint64(0);
            obj.pairMap(key) = entry;
        end

        function recordFailure(obj, entityIdA, entityIdB, reason, simTimeSec, eventCalendar)
            % recordFailure  Record a failed authentication attempt.
            %
            %   am.recordFailure(entityIdA, entityIdB, reason, simTimeSec, eventCalendar)
            %
            %   Increments retryCount. If retryCount < maxRetries, re-schedules
            %   AUTH_REQUEST (via initiateExchange). If retryCount >= maxRetries,
            %   the pair is left in a failed state (authenticated remains false).
            %
            %   reason      (char/string) — failure reason string
            %   simTimeSec  (double)      — current simulation time for retry scheduling
            %   eventCalendar             — sim.EventCalendar instance for retry events
            %
            % Requirements: 19.5, 19.6

            key = obj.canonicalKey(entityIdA, entityIdB);

            if ~obj.pairMap.isKey(key)
                entry = obj.makeEntry();
            else
                entry = obj.pairMap(key);
            end

            entry.retryCount = entry.retryCount + uint32(1);
            obj.pairMap(key) = entry;

            % Re-schedule if retries remain
            if entry.retryCount < obj.maxRetries
                if nargin >= 5 && ~isempty(simTimeSec) && ...
                        nargin >= 6 && ~isempty(eventCalendar)
                    obj.initiateExchange(entityIdA, entityIdB, simTimeSec, eventCalendar);
                end
            end
            % If retryCount >= maxRetries, leave authenticated = false (failed state)
        end

        function entry = getPairState(obj, entityIdA, entityIdB)
            % getPairState  Return the raw state struct for a pair (for testing).
            %
            %   entry = am.getPairState(entityIdA, entityIdB)
            %
            %   Returns empty struct if no entry exists.

            key = obj.canonicalKey(entityIdA, entityIdB);
            if obj.pairMap.isKey(key)
                entry = obj.pairMap(key);
            else
                entry = obj.makeEntry();
            end
        end

    end % methods (Access = public)

    % ======================================================================
    % Private helpers
    % ======================================================================
    methods (Access = private)

        function key = canonicalKey(~, entityIdA, entityIdB)
            % canonicalKey  Build the order-independent canonical pair key.
            %
            %   key = canonicalKey(entityIdA, entityIdB)
            %
            %   Returns  first(A,B) + '|' + second(A,B)  using lexicographic sort.
            %   Uses MATLAB's sort on a cell array of strings to determine order.

            a = char(entityIdA);
            b = char(entityIdB);
            sorted = sort({a, b});   % lexicographic sort of cell array
            key = [sorted{1} '|' sorted{2}];
        end

        function entry = makeEntry(~)
            % makeEntry  Create a default (unauthenticated) pair state struct.

            entry.authenticated     = false;
            entry.authTimeSec       = 0.0;
            entry.retryCount        = uint32(0);
            entry.pendingExchangeId = uint64(0);
        end

    end % methods (Access = private)

end % classdef
