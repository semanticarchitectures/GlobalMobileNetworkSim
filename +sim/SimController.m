classdef SimController < handle
    % sim.SimController  Discrete-event simulation controller.
    %
    % Owns the DES main loop and coordinates all subsystems.  Wires together
    % NodeRegistry, LinkRegistry, OutageEngine, BackgroundTrafficModel, and
    % RoutingEngine from the loaded scenario.
    %
    % Usage:
    %   scenario.simulationDurationSec = 3600;
    %   sc = sim.SimController(scenario);
    %   sc.run();
    %   state = sc.inspect();
    %
    % Requirements: 8.1, 8.2, 8.3, 8.4, 4.1, 4.2, 4.3, 4.4, 5.1, 5.2,
    %               5.3, 5.4, 5.5, 5.6, 6.3, 1.2, 2.5, 2.6

    % -----------------------------------------------------------------
    % Public properties
    % -----------------------------------------------------------------
    properties
        scenario        % loaded scenario struct
        eventCalendar   % sim.EventCalendar instance
        simTimeSec      % current simulation time (double, seconds)
        wallClockStart  % tic value recorded at run() entry
        isPaused        % logical pause flag
        isStopped       % logical stop flag
        eventLog        % growing struct array of event log entries
        nextEventId     % uint64 counter for unique event IDs (starts at 1)
        stats           % struct of accumulating statistics counters

        % Subsystems (empty [] when scenario has no nodes/links)
        nodeRegistry          % network.NodeRegistry
        linkRegistry          % network.LinkRegistry
        outageEngine          % network.OutageEngine
        bgTrafficModel        % network.BackgroundTrafficModel
        routingEngine         % network.RoutingEngine

        % Accumulated latencies of delivered C2 messages (for statistics)
        deliveredLatenciesMs  % double array
    end

    % -----------------------------------------------------------------
    % Constructor
    % -----------------------------------------------------------------
    methods
        function sc = SimController(scenario)
            % SimController  Construct a controller for the given scenario.
            %
            %   sc = sim.SimController(scenario)
            %
            % scenario must be a struct with at least the field:
            %   simulationDurationSec (double)
            %
            % If scenario also has 'nodes' and 'links' fields, the network
            % subsystems (NodeRegistry, LinkRegistry, OutageEngine,
            % BackgroundTrafficModel, RoutingEngine) are constructed.

            if ~isstruct(scenario)
                error('sim:SimController:invalidScenario', ...
                    'scenario must be a struct.');
            end
            if ~isfield(scenario, 'simulationDurationSec')
                error('sim:SimController:missingField', ...
                    'scenario must have a simulationDurationSec field.');
            end

            sc.scenario       = scenario;
            sc.eventCalendar  = sim.EventCalendar();
            sc.simTimeSec     = 0.0;
            sc.wallClockStart = [];
            sc.isPaused       = false;
            sc.isStopped      = false;
            sc.nextEventId    = uint64(1);

            % Initialise empty event log with the canonical field set.
            sc.eventLog = sim.SimController.makeEmptyLogEntry(0);

            % Initialise statistics counters.
            sc.stats = struct( ...
                'c2MessagesTx',       uint64(0), ...
                'c2MessagesRx',       uint64(0), ...
                'c2MessagesFail',     uint64(0), ...
                'outageStartCount',   uint64(0), ...
                'outageEndCount',     uint64(0), ...
                'bgRefreshCount',     uint64(0), ...
                'agentIdleCheckCount',uint64(0));

            % Initialise delivered latencies accumulator.
            sc.deliveredLatenciesMs = [];

            % Construct network subsystems if scenario has nodes and links.
            if isfield(scenario, 'nodes') && isfield(scenario, 'links') && ...
                    ~isempty(scenario.nodes) && ~isempty(scenario.links)
                sc.nodeRegistry  = network.NodeRegistry(scenario.nodes);
                sc.linkRegistry  = network.LinkRegistry(scenario.links, sc.nodeRegistry);
                sc.outageEngine  = network.OutageEngine(sc.linkRegistry, sc.eventCalendar);
                sc.bgTrafficModel = network.BackgroundTrafficModel(sc.linkRegistry, sc.eventCalendar);
                sc.routingEngine = network.RoutingEngine(sc.nodeRegistry, sc.linkRegistry);
            else
                sc.nodeRegistry   = [];
                sc.linkRegistry   = [];
                sc.outageEngine   = [];
                sc.bgTrafficModel = [];
                sc.routingEngine  = [];
            end
        end
    end

    % -----------------------------------------------------------------
    % Public control methods
    % -----------------------------------------------------------------
    methods

        function run(sc)
            % run  Start the DES main loop (blocking).
            %
            % Records wallClockStart, schedules a SIM_END event at
            % scenario.simulationDurationSec, then processes events until
            % SIM_END is dispatched or isStopped becomes true.

            sc.wallClockStart = tic;
            sc.isStopped      = false;
            sc.isPaused       = false;

            % Schedule the simulation-end sentinel event.
            endEvent.time    = sc.scenario.simulationDurationSec;
            endEvent.type    = sim.EventCalendar.SIM_END;
            endEvent.id      = sc.nextId();
            endEvent.payload = struct();
            sc.eventCalendar.schedule(endEvent);

            % Seed subsystem event chains if subsystems are initialised.
            if ~isempty(sc.outageEngine)
                sc.outageEngine.scheduleAllInitialOutages(0);
            end
            if ~isempty(sc.bgTrafficModel)
                sc.bgTrafficModel.scheduleAllInitialRefreshes(0);
            end

            % Schedule all C2 messages from scenario if present.
            if isfield(sc.scenario, 'c2Messages') && ...
                    ~isempty(sc.scenario.c2Messages)
                msgs = sc.scenario.c2Messages;
                % Support both struct array and cell array
                if isstruct(msgs)
                    nMsgs = numel(msgs);
                    for k = 1:nMsgs
                        sc.scheduleC2Message(msgs(k));
                    end
                elseif iscell(msgs)
                    for k = 1:numel(msgs)
                        sc.scheduleC2Message(msgs{k});
                    end
                end
            end

            % DES main loop.
            while ~sc.isStopped && ~sc.eventCalendar.isEmpty()
                event = sc.eventCalendar.popNext();

                % Advance simulation clock.
                sc.simTimeSec = event.time;

                % Update LOS link states before dispatching (Task 8.2).
                if ~isempty(sc.nodeRegistry) && ~isempty(sc.linkRegistry)
                    sc.updateLOSLinks();
                end

                % Dispatch to handler.
                sc.dispatch(event);

                % Honour pause flag: spin-wait until resumed or stopped.
                while sc.isPaused && ~sc.isStopped
                    pause(0.01);
                end
            end
        end

        function pause(sc)
            % pause  Set the pause flag so the loop spin-waits after the
            %        current event finishes.

            sc.isPaused = true;
        end

        function resume(sc)
            % resume  Clear the pause flag so the loop continues.

            sc.isPaused = false;
        end

        function stop(sc)
            % stop  Set the stop flag so the loop exits after the current
            %       event finishes (or immediately if paused).

            sc.isStopped = true;
        end

        function state = inspect(sc)
            % inspect  Return a snapshot of the current simulation state.
            %
            %   state = sc.inspect()
            %
            % Returns a struct with fields:
            %   simTimeSec        — current simulation time
            %   queuedEventCount  — number of events still in the calendar
            %   isPaused          — current pause flag
            %   isStopped         — current stop flag
            %   nodeCount         — number of nodes (0 if no nodeRegistry)
            %   linkCount         — number of links (0 if no linkRegistry)

            state.simTimeSec       = sc.simTimeSec;
            state.queuedEventCount = sc.eventCalendar.eventCount();
            state.isPaused         = sc.isPaused;
            state.isStopped        = sc.isStopped;

            if ~isempty(sc.nodeRegistry)
                state.nodeCount = sc.nodeRegistry.count();
            else
                state.nodeCount = 0;
            end

            if ~isempty(sc.linkRegistry)
                state.linkCount = sc.linkRegistry.count();
            else
                state.linkCount = 0;
            end
        end

        function n = eventCount(sc)
            % eventCount  Convenience wrapper — returns queued event count.

            n = sc.eventCalendar.eventCount();
        end

    end

    % -----------------------------------------------------------------
    % Private methods
    % -----------------------------------------------------------------
    methods (Access = private)

        function id = nextId(sc)
            % nextId  Return the next unique event ID and increment counter.

            id = sc.nextEventId;
            sc.nextEventId = sc.nextEventId + uint64(1);
        end

        function scheduleC2Message(sc, msg)
            % scheduleC2Message  Schedule a C2_MESSAGE_TX event from a
            %                    scenario c2Messages entry.

            ev.time    = msg.scheduledTimeSec;
            ev.type    = sim.EventCalendar.C2_MESSAGE_TX;
            ev.id      = sc.nextId();
            ev.payload = struct( ...
                'msgId',     string(msg.id), ...
                'srcNodeId', string(msg.srcNodeId), ...
                'dstNodeId', string(msg.dstNodeId), ...
                'sizeBytes', msg.sizeBytes);
            sc.eventCalendar.schedule(ev);
        end

        function dispatch(sc, event)
            % dispatch  Route an event to the appropriate handler.

            switch event.type
                case sim.EventCalendar.C2_MESSAGE_TX
                    sc.handleC2MessageTx(event);

                case sim.EventCalendar.C2_MESSAGE_RX
                    sc.handleC2MessageRx(event);

                case sim.EventCalendar.C2_MESSAGE_FAIL
                    sc.handleC2MessageFail(event);

                case sim.EventCalendar.OUTAGE_START
                    sc.handleOutageStart(event);

                case sim.EventCalendar.OUTAGE_END
                    sc.handleOutageEnd(event);

                case sim.EventCalendar.BACKGROUND_REFRESH
                    sc.handleBackgroundRefresh(event);

                case sim.EventCalendar.AGENT_IDLE_CHECK
                    sc.handleAgentIdleCheck(event);

                case sim.EventCalendar.SIM_END
                    sc.handleSimEnd(event);

                otherwise
                    % Unknown event type — log and continue.
                    sc.appendLog(event, '', '', '', '', NaN, ...
                        sprintf('unknown event type: %s', event.type));
            end
        end

        % --- Real handler implementations -----------------------------------

        function handleC2MessageTx(sc, event)
            % handleC2MessageTx  Process a C2_MESSAGE_TX event.
            %
            % Increments stats.c2MessagesTx.  Calls routingEngine.selectPath;
            % on success schedules C2_MESSAGE_RX; on failure schedules
            % C2_MESSAGE_FAIL.

            p      = event.payload;
            msgId  = sim.SimController.payloadField(p, 'msgId',    '');
            srcId  = sim.SimController.payloadField(p, 'srcNodeId','');
            dstId  = sim.SimController.payloadField(p, 'dstNodeId','');

            sc.stats.c2MessagesTx = sc.stats.c2MessagesTx + uint64(1);

            % If no routing engine, fail immediately.
            if isempty(sc.routingEngine)
                failPayload = struct( ...
                    'msgId',     msgId, ...
                    'srcNodeId', srcId, ...
                    'dstNodeId', dstId, ...
                    'reason',    'no routing engine');
                failEv.time    = sc.simTimeSec;
                failEv.type    = sim.EventCalendar.C2_MESSAGE_FAIL;
                failEv.id      = sc.nextId();
                failEv.payload = failPayload;
                sc.eventCalendar.schedule(failEv);
                sc.appendLog(event, '', msgId, srcId, dstId, NaN, 'no routing engine');
                return;
            end

            % Attempt to find a path.
            [path, latencyMs] = sc.routingEngine.selectPath(srcId, dstId, sc.simTimeSec);

            if isempty(path)
                % No route available — schedule a FAIL event.
                failPayload = struct( ...
                    'msgId',     msgId, ...
                    'srcNodeId', srcId, ...
                    'dstNodeId', dstId, ...
                    'reason',    'no available path');
                failEv.time    = sc.simTimeSec;
                failEv.type    = sim.EventCalendar.C2_MESSAGE_FAIL;
                failEv.id      = sc.nextId();
                failEv.payload = failPayload;
                sc.eventCalendar.schedule(failEv);
                sc.appendLog(event, '', msgId, srcId, dstId, NaN, 'no available path');
            else
                % Path found — schedule C2_MESSAGE_RX at delivery time.
                rxPayload = struct( ...
                    'msgId',     msgId, ...
                    'srcNodeId', srcId, ...
                    'dstNodeId', dstId, ...
                    'txTime',    sc.simTimeSec, ...
                    'latencyMs', latencyMs);
                rxEv.time    = sc.simTimeSec + latencyMs / 1000;
                rxEv.type    = sim.EventCalendar.C2_MESSAGE_RX;
                rxEv.id      = sc.nextId();
                rxEv.payload = rxPayload;
                sc.eventCalendar.schedule(rxEv);
                sc.appendLog(event, '', msgId, srcId, dstId, latencyMs, '');
            end
        end

        function handleC2MessageRx(sc, event)
            % handleC2MessageRx  Process a C2_MESSAGE_RX event.
            %
            % Increments stats.c2MessagesRx, appends latencyMs to
            % deliveredLatenciesMs, and logs the delivery.

            p         = event.payload;
            msgId     = sim.SimController.payloadField(p, 'msgId',    '');
            srcId     = sim.SimController.payloadField(p, 'srcNodeId','');
            dstId     = sim.SimController.payloadField(p, 'dstNodeId','');
            latencyMs = sim.SimController.payloadField(p, 'latencyMs', NaN);

            sc.stats.c2MessagesRx = sc.stats.c2MessagesRx + uint64(1);
            sc.deliveredLatenciesMs(end + 1) = latencyMs;
            sc.appendLog(event, '', msgId, srcId, dstId, latencyMs, '');
        end

        function handleC2MessageFail(sc, event)
            % handleC2MessageFail  Process a C2_MESSAGE_FAIL event.
            %
            % Increments stats.c2MessagesFail and logs the failure reason.

            p      = event.payload;
            msgId  = sim.SimController.payloadField(p, 'msgId',    '');
            srcId  = sim.SimController.payloadField(p, 'srcNodeId','');
            dstId  = sim.SimController.payloadField(p, 'dstNodeId','');
            reason = sim.SimController.payloadField(p, 'reason',   '');

            sc.stats.c2MessagesFail = sc.stats.c2MessagesFail + uint64(1);
            sc.appendLog(event, '', msgId, srcId, dstId, NaN, reason);
        end

        function handleOutageStart(sc, event)
            % handleOutageStart  Process an OUTAGE_START event.
            %
            % Updates LinkRegistry, invalidates routing cache, and schedules
            % the outage end via OutageEngine.

            p      = event.payload;
            linkId = sim.SimController.payloadField(p, 'linkId', '');

            sc.stats.outageStartCount = sc.stats.outageStartCount + uint64(1);

            if ~isempty(sc.linkRegistry)
                sc.linkRegistry.setOutage(linkId, true);
            end
            if ~isempty(sc.routingEngine)
                sc.routingEngine.invalidateCache(linkId);
            end
            if ~isempty(sc.outageEngine)
                sc.outageEngine.scheduleOutageEnd(linkId, sc.simTimeSec);
            end

            sc.appendLog(event, linkId, '', '', '', NaN, '');
        end

        function handleOutageEnd(sc, event)
            % handleOutageEnd  Process an OUTAGE_END event.
            %
            % Restores link in LinkRegistry, invalidates routing cache, and
            % schedules the next outage via OutageEngine.

            p      = event.payload;
            linkId = sim.SimController.payloadField(p, 'linkId', '');

            sc.stats.outageEndCount = sc.stats.outageEndCount + uint64(1);

            if ~isempty(sc.linkRegistry)
                sc.linkRegistry.setOutage(linkId, false);
            end
            if ~isempty(sc.routingEngine)
                sc.routingEngine.invalidateCache(linkId);
            end
            if ~isempty(sc.outageEngine)
                sc.outageEngine.scheduleNextOutage(linkId, sc.simTimeSec);
            end

            sc.appendLog(event, linkId, '', '', '', NaN, '');
        end

        function handleBackgroundRefresh(sc, event)
            % handleBackgroundRefresh  Process a BACKGROUND_REFRESH event.
            %
            % Calls bgTrafficModel.resample to draw a new load fraction and
            % schedule the next refresh.

            p      = event.payload;
            linkId = sim.SimController.payloadField(p, 'linkId', '');

            sc.stats.bgRefreshCount = sc.stats.bgRefreshCount + uint64(1);

            if ~isempty(sc.bgTrafficModel)
                sc.bgTrafficModel.resample(linkId, sc.simTimeSec);
            end

            sc.appendLog(event, linkId, '', '', '', NaN, '');
        end

        function handleAgentIdleCheck(sc, event)
            p       = event.payload;
            agentId = sim.SimController.payloadField(p, 'agentId', '');
            sc.appendLog(event, '', agentId, '', '', NaN, '');
            sc.stats.agentIdleCheckCount = ...
                sc.stats.agentIdleCheckCount + uint64(1);
        end

        function handleSimEnd(sc, event)
            sc.appendLog(event, '', '', '', '', NaN, '');
            sc.isStopped = true;
        end

        % --- LOS link update (Task 8.2) -------------------------------------

        function updateLOSLinks(sc)
            % updateLOSLinks  Update positions of mobile nodes and check LOS
            %                 link visibility for all Line_Of_Sight links.
            %
            % Called at the start of each event dispatch when nodeRegistry
            % and linkRegistry are both present.
            %
            % Requirements: 1.2, 2.5, 2.6

            % Batch-update all mobile/satellite node positions.
            sc.nodeRegistry.updatePositions(sc.simTimeSec);

            % Check each LOS link.
            losLinks = sc.linkRegistry.getLOSLinkInfos();
            for k = 1:numel(losLinks)
                lk = losLinks(k);

                % Get current positions of both endpoints.
                srcPos = sc.nodeRegistry.getPosition(lk.srcNodeId, sc.simTimeSec);
                dstPos = sc.nodeRegistry.getPosition(lk.dstNodeId, sc.simTimeSec);

                % Use the mobile node's altitude for the horizon check.
                % Determine which endpoint is mobile (non-zero altitude or
                % Mobile type).  Use the higher altitude as the mobile side.
                mobileAltM = max(srcPos.altM, dstPos.altM);
                if mobileAltM <= 0
                    % Both at ground level — use src as mobile reference.
                    mobileAltM = srcPos.altM;
                end

                % Check visibility.
                newActive = network.GeoUtils.isLOSVisible( ...
                    srcPos.lat, srcPos.lon, mobileAltM, ...
                    dstPos.lat, dstPos.lon, lk.coverageRadiusM);

                % Update link state if changed.
                if newActive ~= lk.isActive
                    sc.linkRegistry.setLOSActive(lk.id, newActive);
                    if ~isempty(sc.routingEngine)
                        sc.routingEngine.invalidateCache(lk.id);
                    end
                end
            end
        end

        % --- Log helper ------------------------------------------------------

        function appendLog(sc, event, linkId, msgId, srcNodeId, dstNodeId, ...
                latencyMs, reason)
            % appendLog  Append one entry to sc.eventLog.

            entry.eventId    = sc.nextId();
            entry.simTimeSec = sc.simTimeSec;
            entry.eventType  = event.type;
            entry.linkId     = linkId;
            entry.msgId      = msgId;
            entry.srcNodeId  = srcNodeId;
            entry.dstNodeId  = dstNodeId;
            entry.latencyMs  = latencyMs;
            entry.reason     = reason;

            if isempty(sc.eventLog)
                sc.eventLog = entry;
            else
                sc.eventLog(end + 1) = entry;
            end
        end

    end

    % -----------------------------------------------------------------
    % Static helpers
    % -----------------------------------------------------------------
    methods (Static, Access = private)

        function s = makeEmptyLogEntry(n)
            % makeEmptyLogEntry  Return a 0×1 or n×1 struct array with the
            % canonical event-log field set.

            proto.eventId    = uint64(0);
            proto.simTimeSec = 0.0;
            proto.eventType  = "";
            proto.linkId     = '';
            proto.msgId      = '';
            proto.srcNodeId  = '';
            proto.dstNodeId  = '';
            proto.latencyMs  = NaN;
            proto.reason     = '';

            if n == 0
                % Return an empty struct with the right fields.
                s = proto;
                s = s(false);   % 0×1 struct array
            else
                s = repmat(proto, n, 1);
            end
        end

        function val = payloadField(payload, fieldName, defaultVal)
            % payloadField  Safely read a field from a payload struct.

            if isfield(payload, fieldName)
                val = payload.(fieldName);
            else
                val = defaultVal;
            end
        end

    end

end
