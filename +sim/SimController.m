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
        wallClockDurationSec  % wall-clock duration of the run (set at SIM_END)
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

        % Agent layer (empty [] when scenario has no agents or no llmClient)
        agentRegistry         % agent.AgentRegistry (or [])
        fidelityEvaluator     % agent.FidelityEvaluator (or [])

        % ICAM layer (empty [] when scenario has no entities/policyDefinitionFile)
        icamController        % icam.ICAMController (or [])

        % Per-run evaluation results (struct array, populated at SIM_END)
        % Each element: agentId, role, fidelityScore, missingActions,
        %               extraActions, deviations
        evalResults           % struct array (empty until handleSimEnd)

        % Run identification (set at run() start)
        runId           % string UUID for this run
        runTimestamp    % ISO-8601 timestamp string for this run

        % Position update interval for NODE_POSITION events (seconds; 0 = disabled)
        positionUpdateIntervalSec  % double (default 0)

        % Accumulated latencies of delivered C2 messages (for statistics)
        deliveredLatenciesMs  % double array
    end

    % -----------------------------------------------------------------
    % Private properties
    % -----------------------------------------------------------------
    properties (Access = private)
        % Per-link statistics (containers.Map: linkId -> struct)
        % Each entry has:
        %   c2MessagesRouted   (uint64)  — C2 messages routed through this link
        %   outageDurationSec  (double)  — accumulated total outage duration
        %   outageStartTimeSec (double)  — sim time when current outage started (NaN if not in outage)
        %   bgLoadSamples      (double array) — background load fraction samples
        linkStats
    end

    % -----------------------------------------------------------------
    % Constructor
    % -----------------------------------------------------------------
    methods
        function sc = SimController(scenario, llmClient)
            % SimController  Construct a controller for the given scenario.
            %
            %   sc = sim.SimController(scenario)
            %   sc = sim.SimController(scenario, llmClient)
            %
            % scenario must be a struct with at least the field:
            %   simulationDurationSec (double)
            %
            % llmClient (optional) — agent.LLMClient instance.  When provided
            %   and the scenario has an 'agents' field, an AgentRegistry is
            %   constructed.  When omitted, agentRegistry is left empty.
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

            sc.scenario              = scenario;
            sc.eventCalendar         = sim.EventCalendar();
            sc.simTimeSec            = 0.0;
            sc.wallClockStart        = [];
            sc.wallClockDurationSec  = NaN;
            sc.isPaused              = false;
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

            % Position update interval (default 0 = disabled).
            sc.positionUpdateIntervalSec = 0;

            % Initialise delivered latencies accumulator.
            sc.deliveredLatenciesMs = [];

            % Initialise agent-layer properties.
            sc.agentRegistry     = [];
            sc.fidelityEvaluator = [];
            sc.evalResults       = struct( ...
                'agentId', {}, 'role', {}, 'fidelityScore', {}, ...
                'missingActions', {}, 'extraActions', {}, 'deviations', {});
            sc.runId        = '';
            sc.runTimestamp = '';

            % Construct network subsystems if scenario has nodes and links.
            if isfield(scenario, 'nodes') && isfield(scenario, 'links') && ...
                    ~isempty(scenario.nodes) && ~isempty(scenario.links)
                sc.nodeRegistry  = network.NodeRegistry(scenario.nodes);
                sc.linkRegistry  = network.LinkRegistry(scenario.links, sc.nodeRegistry);
                sc.outageEngine  = network.OutageEngine(sc.linkRegistry, sc.eventCalendar);
                sc.bgTrafficModel = network.BackgroundTrafficModel(sc.linkRegistry, sc.eventCalendar);
                sc.routingEngine = network.RoutingEngine(sc.nodeRegistry, sc.linkRegistry);

                % Initialise per-link statistics map.
                sc.linkStats = containers.Map('KeyType', 'char', 'ValueType', 'any');
                linkIds = sc.linkRegistry.getLinkIds();
                for k = 1:numel(linkIds)
                    lkId = char(linkIds(k));
                    entry.c2MessagesRouted   = uint64(0);
                    entry.outageDurationSec  = 0.0;
                    entry.outageStartTimeSec = NaN;
                    entry.bgLoadSamples      = double.empty(1, 0);
                    sc.linkStats(lkId) = entry;
                end
            else
                sc.nodeRegistry   = [];
                sc.linkRegistry   = [];
                sc.outageEngine   = [];
                sc.bgTrafficModel = [];
                sc.routingEngine  = [];
                sc.linkStats      = containers.Map('KeyType', 'char', 'ValueType', 'any');
            end

            % Construct agent layer if scenario has agents and llmClient is provided.
            if nargin >= 2 && ~isempty(llmClient) && ...
                    isfield(scenario, 'agents') && ~isempty(scenario.agents)
                sc.agentRegistry = agent.AgentRegistry( ...
                    scenario.agents, sc.nodeRegistry, llmClient, sc.eventCalendar);
            end

            % Construct FidelityEvaluator if scenario has a referenceBehavior.
            if isfield(scenario, 'referenceBehavior') && ...
                    ~isempty(scenario.referenceBehavior)
                sc.fidelityEvaluator = agent.FidelityEvaluator(scenario.referenceBehavior);
            end

            % Construct ICAM layer if scenario has entities or policyDefinitionFile.
            sc.icamController = [];
            if ~isempty(sc.nodeRegistry) && ...
                    (isfield(scenario, 'entities') || isfield(scenario, 'policyDefinitionFile'))
                ic = icam.ICAMController();
                ic.initialize(scenario, sc.nodeRegistry, sc.eventCalendar);
                sc.icamController = ic;
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

            % Assign a unique run identifier and ISO-8601 timestamp.
            try
                sc.runId = char(java.util.UUID.randomUUID());
            catch
                sc.runId = sprintf('run-%s', datestr(now, 'yyyymmddHHMMSSFFF')); %#ok<TNOW1,DATST>
            end
            sc.runTimestamp = datestr(now, 'yyyy-mm-ddTHH:MM:SS'); %#ok<TNOW1,DATST>

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

            % Schedule NODE_POSITION events if interval is configured.
            if sc.positionUpdateIntervalSec > 0 && ~isempty(sc.nodeRegistry)
                sc.scheduleNextPositionUpdate(0);
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
            %   nodes             — struct array with id, lat, lon, altM per node
            %   links             — struct array with id, isActive, effectiveBwBps per link
            %   queuedC2Messages  — count of C2_MESSAGE_TX events still in calendar
            %
            % Requirements: 8.3

            state.simTimeSec       = sc.simTimeSec;
            state.queuedEventCount = sc.eventCalendar.eventCount();
            state.isPaused         = sc.isPaused;
            state.isStopped        = sc.isStopped;

            % Node count and positions
            if ~isempty(sc.nodeRegistry)
                state.nodeCount = sc.nodeRegistry.count();
                nNodes = sc.nodeRegistry.count();
                nodeSnap(nNodes) = struct('id','','lat',0,'lon',0,'altM',0);
                for k = 1:nNodes
                    nid = sc.nodeRegistry.getIdByIndex(k);
                    pos = sc.nodeRegistry.getPosition(nid, sc.simTimeSec);
                    nodeSnap(k).id   = char(nid);
                    nodeSnap(k).lat  = pos.lat;
                    nodeSnap(k).lon  = pos.lon;
                    nodeSnap(k).altM = pos.altM;
                end
                state.nodes = nodeSnap;
            else
                state.nodeCount = 0;
                state.nodes = struct('id',{},'lat',{},'lon',{},'altM',{});
            end

            % Link count and states
            if ~isempty(sc.linkRegistry)
                state.linkCount = sc.linkRegistry.count();
                linkIds = sc.linkRegistry.getLinkIds();
                nLinks  = numel(linkIds);
                linkSnap(nLinks) = struct('id','','isActive',false,'effectiveBwBps',0);
                for k = 1:nLinks
                    lid = char(linkIds(k));
                    linkSnap(k).id             = lid;
                    linkSnap(k).isActive       = sc.linkRegistry.isLinkActive(lid);
                    linkSnap(k).effectiveBwBps = sc.linkRegistry.getEffectiveBandwidth(lid);
                end
                state.links = linkSnap;
            else
                state.linkCount = 0;
                state.links = struct('id',{},'isActive',{},'effectiveBwBps',{});
            end

            % Count queued C2_MESSAGE_TX events (approximate — counts all
            % events of that type still in the calendar is not directly
            % accessible; report total queued events instead)
            state.queuedC2Messages = 0;  % placeholder; full count requires calendar scan
        end

        function n = eventCount(sc)
            % eventCount  Convenience wrapper — returns queued event count.

            n = sc.eventCalendar.eventCount();
        end

        function report = buildStatsReport(sc)
            % buildStatsReport  Build a Statistics_Report struct matching §4.3.
            %
            %   report = sc.buildStatsReport()
            %
            % Returns a struct with fields:
            %   scenarioName        — from scenario.scenarioName or 'unnamed'
            %   simStartTimeSec     — always 0
            %   simEndTimeSec       — current simTimeSec
            %   wallClockDurationSec — wall-clock run duration (NaN if not run)
            %   c2Messages          — struct: scheduled, delivered, failed
            %   latency             — struct: meanMs, medianMs, p95Ms
            %   perLink             — struct array, one per link
            %   agentFidelity       — struct: mean, min, max (placeholder NaN)
            %
            % Requirements: 9.1, 9.2, 9.3

            % Scenario name
            if isfield(sc.scenario, 'scenarioName') && ...
                    ~isempty(sc.scenario.scenarioName)
                report.scenarioName = sc.scenario.scenarioName;
            else
                report.scenarioName = 'unnamed';
            end

            % Timing
            report.simStartTimeSec    = 0;
            report.simEndTimeSec      = sc.simTimeSec;
            report.wallClockDurationSec = sc.wallClockDurationSec;

            % C2 message counts
            report.c2Messages.scheduled = double(sc.stats.c2MessagesTx);
            report.c2Messages.delivered = double(sc.stats.c2MessagesRx);
            report.c2Messages.failed    = double(sc.stats.c2MessagesFail);

            % Latency statistics
            lats = sc.deliveredLatenciesMs;
            if isempty(lats)
                report.latency.meanMs   = NaN;
                report.latency.medianMs = NaN;
                report.latency.p95Ms    = NaN;
            else
                report.latency.meanMs   = mean(lats);
                report.latency.medianMs = median(lats);
                report.latency.p95Ms    = prctile(lats, 95);
            end

            % Per-link statistics
            if ~isempty(sc.linkRegistry)
                linkIds = sc.linkRegistry.getLinkIds();
                nLinks  = numel(linkIds);
                % Pre-build a struct array
                perLinkProto.linkId                  = '';
                perLinkProto.meanEffectiveBwBps       = NaN;
                perLinkProto.meanBgLoadFraction       = NaN;
                perLinkProto.totalC2MessagesRouted    = 0;
                perLinkProto.totalOutageDurationSec   = 0;
                perLinkProto.outageFraction           = 0;
                perLink = repmat(perLinkProto, nLinks, 1);

                for k = 1:nLinks
                    lkId = char(linkIds(k));
                    perLink(k).linkId = lkId;

                    % Mean effective bandwidth from registry
                    perLink(k).meanEffectiveBwBps = ...
                        sc.linkRegistry.getEffectiveBandwidth(lkId);

                    % Per-link accumulated stats
                    if sc.linkStats.isKey(lkId)
                        entry = sc.linkStats(lkId);

                        % Mean background load fraction
                        if isempty(entry.bgLoadSamples)
                            perLink(k).meanBgLoadFraction = NaN;
                        else
                            perLink(k).meanBgLoadFraction = mean(entry.bgLoadSamples);
                        end

                        perLink(k).totalC2MessagesRouted  = double(entry.c2MessagesRouted);
                        perLink(k).totalOutageDurationSec = entry.outageDurationSec;

                        % Outage fraction
                        if sc.simTimeSec > 0
                            perLink(k).outageFraction = ...
                                entry.outageDurationSec / sc.simTimeSec;
                        else
                            perLink(k).outageFraction = 0;
                        end
                    end
                end
                report.perLink = perLink;
            else
                report.perLink = struct( ...
                    'linkId', {}, ...
                    'meanEffectiveBwBps', {}, ...
                    'meanBgLoadFraction', {}, ...
                    'totalC2MessagesRouted', {}, ...
                    'totalOutageDurationSec', {}, ...
                    'outageFraction', {});
            end

            % Agent fidelity — use actual evalResults if available, else NaN.
            if ~isempty(sc.evalResults) && numel(sc.evalResults) > 0
                scores = [sc.evalResults.fidelityScore];
                scores = scores(~isnan(scores));
                if ~isempty(scores)
                    report.agentFidelity.mean = mean(scores);
                    report.agentFidelity.min  = min(scores);
                    report.agentFidelity.max  = max(scores);
                else
                    report.agentFidelity.mean = NaN;
                    report.agentFidelity.min  = NaN;
                    report.agentFidelity.max  = NaN;
                end
            else
                report.agentFidelity.mean = NaN;
                report.agentFidelity.min  = NaN;
                report.agentFidelity.max  = NaN;
            end

            % ICAM statistics block — included when icamController is present.
            if ~isempty(sc.icamController)
                report.icam = sc.icamController.buildICAMReport();
            end
        end

        function report = buildEvalReport(sc)
            % buildEvalReport  Build an Evaluation_Report struct matching §4.4.
            %
            %   report = sc.buildEvalReport()
            %
            % Returns a struct with fields:
            %   runId        — UUID string assigned at run() start
            %   timestamp    — ISO-8601 timestamp string
            %   scenarioName — from scenario.scenarioName or 'unnamed'
            %   agents       — struct array, each with:
            %                    agentId, role, fidelityScore,
            %                    missingActions, extraActions, deviations
            %
            % Requirements: 15.1, 15.3, 16.1, 16.3

            report.runId     = sc.runId;
            report.timestamp = sc.runTimestamp;

            if isfield(sc.scenario, 'scenarioName') && ...
                    ~isempty(sc.scenario.scenarioName)
                report.scenarioName = sc.scenario.scenarioName;
            else
                report.scenarioName = 'unnamed';
            end

            % Build agents array from evalResults.
            if isempty(sc.evalResults) || numel(sc.evalResults) == 0
                report.agents = struct( ...
                    'agentId', {}, 'role', {}, 'fidelityScore', {}, ...
                    'missingActions', {}, 'extraActions', {}, 'deviations', {});
            else
                report.agents = sc.evalResults;
            end
        end

    end
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

                case sim.EventCalendar.NODE_POSITION
                    sc.handleNodePosition(event);

                case sim.EventCalendar.AGENT_IDLE_CHECK
                    sc.handleAgentIdleCheck(event);

                case sim.EventCalendar.AUTH_REQUEST
                    if ~isempty(sc.icamController)
                        sc.icamController.handleAuthRequest(event);
                    end

                case sim.EventCalendar.AUTH_RESPONSE
                    if ~isempty(sc.icamController)
                        sc.icamController.handleAuthResponse(event);
                    end

                case sim.EventCalendar.AUTH_TIMEOUT
                    if ~isempty(sc.icamController)
                        sc.icamController.handleAuthTimeout(event);
                    end

                case sim.EventCalendar.CERT_RENEWAL_REQUEST
                    if ~isempty(sc.icamController)
                        sc.icamController.handleCertRenewal(event);
                    end

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

            % ICAM gate: check send permission
            if ~isempty(sc.icamController)
                % Determine entity IDs from node IDs (use node ID as entity ID if no entity registry)
                srcEntityId = srcId;  % simplified: use nodeId as entityId
                dstEntityId = dstId;
                enclaveId = 'default';
                icamDecision = sc.icamController.checkSend(srcEntityId, dstEntityId, char(msgId), enclaveId, sc.simTimeSec);
                if strcmp(icamDecision, 'deny')
                    % Record access-denied event and discard message
                    sc.stats.c2MessagesFail = sc.stats.c2MessagesFail + uint64(1);
                    sc.appendLog(event, '', msgId, srcId, dstId, NaN, 'access-denied');
                    return;
                end
                % 'pending' means auth exchange initiated — still route the message
                % (simplified: don't block on pending, just proceed)
            end

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

                % Accumulate per-link C2 message routed counts.
                if ~isempty(sc.linkRegistry) && numel(path) >= 2
                    for hop = 1:(numel(path) - 1)
                        hopSrc = path{hop};
                        hopDst = path{hop + 1};
                        lkId = sc.linkRegistry.getLinksBetweenNodes(hopSrc, hopDst);
                        if ~isempty(lkId) && sc.linkStats.isKey(lkId)
                            entry = sc.linkStats(lkId);
                            entry.c2MessagesRouted = entry.c2MessagesRouted + uint64(1);
                            sc.linkStats(lkId) = entry;
                        end
                    end
                end
            end
        end

        function handleC2MessageRx(sc, event)
            % handleC2MessageRx  Process a C2_MESSAGE_RX event.
            %
            % Increments stats.c2MessagesRx, appends latencyMs to
            % deliveredLatenciesMs, logs the delivery, and delivers the
            % message to the destination agent if one is bound to the
            % destination node.
            %
            % The simulation clock pauses implicitly while the LLM processes
            % the message because LLMClient.complete() is synchronous.
            %
            % Requirements: 12.2, 12.3, 12.4, 13.1, 13.2, 13.5

            p         = event.payload;
            msgId     = sim.SimController.payloadField(p, 'msgId',    '');
            srcId     = sim.SimController.payloadField(p, 'srcNodeId','');
            dstId     = sim.SimController.payloadField(p, 'dstNodeId','');
            latencyMs = sim.SimController.payloadField(p, 'latencyMs', NaN);

            sc.stats.c2MessagesRx = sc.stats.c2MessagesRx + uint64(1);
            sc.deliveredLatenciesMs(end + 1) = latencyMs;
            sc.appendLog(event, '', msgId, srcId, dstId, latencyMs, '');

            % Deliver to agent bound to the destination node (if any).
            if ~isempty(sc.agentRegistry)
                agentIds = sc.agentRegistry.getAgentIds();
                for k = 1:numel(agentIds)
                    agId = agentIds(k);
                    % Check if this agent is bound to the destination node.
                    % We do this by checking the agent's nodeId via the
                    % scenario agents definition.
                    agentNodeId = sc.getAgentNodeId_(agId);
                    if string(agentNodeId) == string(dstId)
                        % Build a c2Message struct for the agent.
                        c2Msg.srcNodeId = srcId;
                        c2Msg.msgId     = msgId;
                        c2Msg.txTime    = sim.SimController.payloadField(p, 'txTime', sc.simTimeSec);
                        c2Msg.latencyMs = latencyMs;
                        try
                            sc.agentRegistry.deliver(agId, c2Msg, sc.simTimeSec);
                        catch ME
                            warning('netsim:sim:agentDeliverError', ...
                                'Agent delivery failed for "%s": %s', agId, ME.message);
                        end
                        break;  % Each message delivered to at most one agent
                    end
                end
            end
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

            % Record outage start time for duration accumulation.
            lkIdChar = char(linkId);
            if ~isempty(lkIdChar) && sc.linkStats.isKey(lkIdChar)
                entry = sc.linkStats(lkIdChar);
                entry.outageStartTimeSec = sc.simTimeSec;
                sc.linkStats(lkIdChar) = entry;
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

            % Accumulate outage duration.
            lkIdChar = char(linkId);
            if ~isempty(lkIdChar) && sc.linkStats.isKey(lkIdChar)
                entry = sc.linkStats(lkIdChar);
                if ~isnan(entry.outageStartTimeSec)
                    duration = sc.simTimeSec - entry.outageStartTimeSec;
                    entry.outageDurationSec  = entry.outageDurationSec + duration;
                    entry.outageStartTimeSec = NaN;
                    sc.linkStats(lkIdChar) = entry;
                end
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

            % Collect background load sample after resample.
            lkIdChar = char(linkId);
            if ~isempty(lkIdChar) && ~isempty(sc.linkRegistry) && ...
                    sc.linkStats.isKey(lkIdChar)
                frac  = sc.linkRegistry.getBgLoadFraction(linkId);
                entry = sc.linkStats(lkIdChar);
                entry.bgLoadSamples(end + 1) = frac;
                sc.linkStats(lkIdChar) = entry;
            end

            % Background refresh is not logged to the event log to reduce noise.
            % The resample still happens internally and affects link bandwidth.
        end

        function handleAgentIdleCheck(sc, event)
            % handleAgentIdleCheck  Process an AGENT_IDLE_CHECK event.
            %
            % Calls agentRegistry.checkIdle() which invokes the LLM for a
            % role-appropriate status check-in and schedules the next idle
            % check event.  The simulation clock pauses implicitly because
            % LLMClient.complete() is synchronous (blocking).
            %
            % Requirements: 12.5, 13.4

            p       = event.payload;
            agentId = sim.SimController.payloadField(p, 'agentId', '');
            sc.appendLog(event, '', agentId, '', '', NaN, '');
            sc.stats.agentIdleCheckCount = ...
                sc.stats.agentIdleCheckCount + uint64(1);

            % Delegate to AgentRegistry if available.
            if ~isempty(sc.agentRegistry) && ~isempty(agentId)
                try
                    sc.agentRegistry.checkIdle(agentId, sc.simTimeSec);
                catch ME
                    warning('netsim:sim:agentIdleCheckError', ...
                        'Agent idle check failed for "%s": %s', agentId, ME.message);
                end
            end
        end

        function handleSimEnd(sc, event)
            sc.appendLog(event, '', '', '', '', NaN, '');
            if ~isempty(sc.wallClockStart)
                sc.wallClockDurationSec = toc(sc.wallClockStart);
            end

            % Check for expired ICAM credentials at simulation end.
            if ~isempty(sc.icamController)
                sc.icamController.checkExpiredCredentials(sc.simTimeSec);
            end

            % Run fidelity evaluation for each agent if both registries exist.
            if ~isempty(sc.agentRegistry) && ~isempty(sc.fidelityEvaluator)
                agentIds = sc.agentRegistry.getAgentIds();
                for k = 1:numel(agentIds)
                    agId = agentIds(k);
                    tracer = sc.agentRegistry.getTracer(agId);
                    trace  = tracer.getTrace();

                    % Determine the agent's role name from the registry.
                    tracerInfo = sc.agentRegistry.getAllTracers();
                    roleName = '';
                    for ti = 1:numel(tracerInfo)
                        if string(tracerInfo(ti).agentId) == string(agId)
                            roleName = tracerInfo(ti).role;
                            break;
                        end
                    end

                    % Evaluate fidelity.
                    result = sc.fidelityEvaluator.evaluate( ...
                        trace, sc.eventLog, roleName);

                    % Accumulate into evalResults.
                    entry.agentId        = agId;
                    entry.role           = roleName;
                    entry.fidelityScore  = result.fidelityScore;
                    entry.missingActions = result.missingActions;
                    entry.extraActions   = result.extraActions;
                    entry.deviations     = result.deviations;
                    sc.evalResults(end + 1) = entry;
                end
            end

            sc.isStopped = true;
        end

        % --- Agent node lookup helper ----------------------------------------

        function nodeId = getAgentNodeId_(sc, agentId)
            % getAgentNodeId_  Return the nodeId bound to the given agent.
            %
            % Looks up the agent definition in scenario.agents by agentId.
            % Returns '' if not found.

            nodeId = '';
            if ~isfield(sc.scenario, 'agents') || isempty(sc.scenario.agents)
                return;
            end
            agents = sc.scenario.agents;
            if isstruct(agents)
                for k = 1:numel(agents)
                    if string(agents(k).id) == string(agentId)
                        nodeId = char(agents(k).nodeId);
                        return;
                    end
                end
            elseif iscell(agents)
                for k = 1:numel(agents)
                    ag = agents{k};
                    if string(ag.id) == string(agentId)
                        nodeId = char(ag.nodeId);
                        return;
                    end
                end
            end
        end

        % --- NODE_POSITION handler ------------------------------------------

        function handleNodePosition(sc, event)
            % handleNodePosition  Record positions of all mobile nodes and
            % schedule the next NODE_POSITION event.
            if isempty(sc.nodeRegistry)
                return;
            end
            % Record one log entry per mobile node
            nNodes = sc.nodeRegistry.count();
            for k = 1:nNodes
                nid = sc.nodeRegistry.getIdByIndex(k);
                pos = sc.nodeRegistry.getPosition(nid, sc.simTimeSec);
                posEntry.eventId    = sc.nextId();
                posEntry.simTimeSec = sc.simTimeSec;
                posEntry.eventType  = sim.EventCalendar.NODE_POSITION;
                posEntry.linkId     = char(nid);
                posEntry.msgId      = sprintf('%.4f', pos.lat);
                posEntry.srcNodeId  = sprintf('%.4f', pos.lon);
                posEntry.dstNodeId  = sprintf('%.1f', pos.altM);
                posEntry.latencyMs  = NaN;
                posEntry.reason     = '';
                if isempty(sc.eventLog)
                    sc.eventLog = posEntry;
                else
                    sc.eventLog(end+1) = posEntry;
                end
            end
            % Schedule next position update
            sc.scheduleNextPositionUpdate(sc.simTimeSec);
        end

        function scheduleNextPositionUpdate(sc, currentTimeSec)
            % scheduleNextPositionUpdate  Schedule the next NODE_POSITION event.
            nextTime = currentTimeSec + sc.positionUpdateIntervalSec;
            if nextTime >= sc.scenario.simulationDurationSec
                return;
            end
            ev.time    = nextTime;
            ev.type    = sim.EventCalendar.NODE_POSITION;
            ev.id      = sc.nextId();
            ev.payload = struct();
            sc.eventCalendar.schedule(ev);
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
