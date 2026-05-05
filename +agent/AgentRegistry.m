classdef AgentRegistry < handle
    % AgentRegistry  Manages all LLM-driven agents and their bindings to
    %                network nodes.
    %
    % Usage:
    %   ar = agent.AgentRegistry(agentDefs, nodeRegistry, llmClient, eventCalendar)
    %   ar.deliver(agentId, c2Message, simTimeSec)
    %   ar.checkIdle(agentId, simTimeSec)
    %   bt = ar.getTracer(agentId)
    %   result = ar.getAllTracers()
    %   ids = ar.getAgentIds()
    %   n  = ar.count()
    %
    % Constructor validates that each agent's nodeId exists in the
    % NodeRegistry, loads the role definition file, creates a BehaviorTracer,
    % and schedules an initial AGENT_IDLE_CHECK event for each agent.
    %
    % Requirements: 12.1, 12.2, 12.3, 12.4, 12.5, 13.1, 13.2, 13.3,
    %               13.4, 13.5, 11.5

    % ======================================================================
    % Private properties
    % ======================================================================
    properties (Access = private)
        % containers.Map: agentId (string) -> agent state struct
        %   Fields per agent:
        %     id              (string)
        %     nodeId          (string)
        %     role            (struct)  — from RoleLoader.load()
        %     idleTimeoutSec  (double)
        %     tracer          (agent.BehaviorTracer)
        %     lastMsgTimeSec  (double)  — sim time of last received message
        %     nextEventId     (uint64)  — counter for generated event IDs
        Agents          % containers.Map keyed by agentId

        % Shared subsystem references
        NodeRegistry    % network.NodeRegistry
        LLMClient       % agent.LLMClient
        EventCalendar   % sim.EventCalendar

        % Monotonically increasing event ID counter (shared across agents)
        NextEventId     (1,1) uint64
    end

    % ======================================================================
    % Constructor
    % ======================================================================
    methods

        function ar = AgentRegistry(agentDefs, nodeRegistry, llmClient, eventCalendar)
            % AgentRegistry  Construct the registry from agent definitions.
            %
            %   ar = agent.AgentRegistry(agentDefs, nodeRegistry, llmClient, eventCalendar)
            %
            % Parameters:
            %   agentDefs     — struct array or cell array of agent definition
            %                   structs, each with fields:
            %                     id                (string)
            %                     nodeId            (string)
            %                     roleDefinitionFile (string)
            %                     idleTimeoutSec    (double)
            %   nodeRegistry  — network.NodeRegistry instance
            %   llmClient     — agent.LLMClient instance
            %   eventCalendar — sim.EventCalendar instance
            %
            % Throws netsim:agent:unknownNode if any agent's nodeId is not
            % found in nodeRegistry.

            ar.NodeRegistry  = nodeRegistry;
            ar.LLMClient     = llmClient;
            ar.EventCalendar = eventCalendar;
            ar.NextEventId   = uint64(1);
            ar.Agents        = containers.Map('KeyType', 'char', 'ValueType', 'any');

            % Normalise agentDefs to a cell array
            if isstruct(agentDefs)
                nAgents = numel(agentDefs);
                cellDefs = cell(nAgents, 1);
                for k = 1:nAgents
                    cellDefs{k} = agentDefs(k);
                end
            elseif iscell(agentDefs)
                cellDefs = agentDefs(:);
                nAgents  = numel(cellDefs);
            else
                error('netsim:agent:invalidInput', ...
                    'agentDefs must be a struct array or cell array of structs.');
            end

            % Process each agent definition
            for k = 1:nAgents
                def = cellDefs{k};

                agentId        = string(def.id);
                nodeId         = string(def.nodeId);
                roleFile       = string(def.roleDefinitionFile);
                idleTimeoutSec = double(def.idleTimeoutSec);

                % Validate that the node exists in the NodeRegistry
                try
                    nodeRegistry.indexOf(nodeId);
                catch
                    error('netsim:agent:unknownNode', ...
                        'Agent "%s": node "%s" not found', agentId, nodeId);
                end

                % Load the role definition
                role = agent.RoleLoader.load(char(roleFile));

                % Create a BehaviorTracer for this agent
                tracer = agent.BehaviorTracer(agentId, role.name);

                % Build the agent state struct
                agentState.id             = agentId;
                agentState.nodeId         = nodeId;
                agentState.role           = role;
                agentState.idleTimeoutSec = idleTimeoutSec;
                agentState.tracer         = tracer;
                agentState.lastMsgTimeSec = -Inf;  % never received a message

                ar.Agents(char(agentId)) = agentState;

                % Schedule the initial AGENT_IDLE_CHECK event at t = idleTimeoutSec
                idleEvent.time    = idleTimeoutSec;
                idleEvent.type    = sim.EventCalendar.AGENT_IDLE_CHECK;
                idleEvent.id      = ar.NextEventId;
                idleEvent.payload = struct('agentId', agentId);
                ar.NextEventId    = ar.NextEventId + uint64(1);

                eventCalendar.schedule(idleEvent);
            end
        end

    end % constructor methods

    % ======================================================================
    % Public methods
    % ======================================================================
    methods (Access = public)

        function response = deliver(ar, agentId, c2Message, simTimeSec)
            % deliver  Deliver a C2 message to an agent and invoke the LLM.
            %
            %   response = ar.deliver(agentId, c2Message, simTimeSec)
            %
            % Parameters:
            %   agentId     — string: target agent identifier
            %   c2Message   — struct with fields (all optional except srcNodeId):
            %                   srcNodeId  (string)
            %                   msgId      (string, optional)
            %                   txTime     (double, optional)
            %                   content    (string, optional)
            %   simTimeSec  — double: current simulation time
            %
            % Behaviour:
            %   1. Builds a system prompt from the agent's role fullMarkdown.
            %   2. Formats c2Message as a readable user message string.
            %   3. Calls llmClient.complete(systemPrompt, userMessage).
            %   4. Parses the LLM response — treats the entire response as a
            %      single action of type 'LLM_RESPONSE'.
            %   5. Records an 'LLM_RESPONSE' action in the agent's BehaviorTracer.
            %   6. Returns the LLM response struct.
            %
            % Returns:
            %   response — struct with fields: content, finishReason, usageTokens
            %
            % Requirements: 12.2, 12.3, 13.1, 13.2, 13.3, 13.5

            agentIdStr = string(agentId);
            agentState = ar.getAgentState_(agentIdStr);

            % Extract message fields with defaults
            srcNodeId = "";
            if isfield(c2Message, 'srcNodeId')
                srcNodeId = string(c2Message.srcNodeId);
            end

            msgId = "";
            if isfield(c2Message, 'msgId')
                msgId = string(c2Message.msgId);
            end

            txTime = simTimeSec;
            if isfield(c2Message, 'txTime')
                txTime = double(c2Message.txTime);
            end

            content = "";
            if isfield(c2Message, 'content') && ~isempty(c2Message.content)
                content = string(c2Message.content);
            end

            % Build system prompt from role's full Markdown
            systemPrompt = agentState.role.fullMarkdown;

            % Build user message describing the incoming C2 message
            if strlength(content) > 0
                userMessage = sprintf( ...
                    'Incoming message from %s at t=%.3fs: %s', ...
                    srcNodeId, simTimeSec, content);
            else
                userMessage = sprintf( ...
                    'Incoming message from %s at t=%.3fs', ...
                    srcNodeId, simTimeSec);
            end

            % Call LLM (synchronous, blocks until response)
            try
                response = ar.LLMClient.complete(systemPrompt, userMessage);
            catch ME
                % Log LLM failure as an action and rethrow
                agentState.tracer.record(simTimeSec, uint64(0), 'LLM_FAILURE', ...
                    srcNodeId, msgId);
                agentState.lastMsgTimeSec = simTimeSec;
                ar.Agents(char(agentIdStr)) = agentState;
                rethrow(ME);
            end

            % Parse the LLM response — treat the entire response as a single
            % action of type 'LLM_RESPONSE'
            agentState.tracer.record(simTimeSec, uint64(0), 'LLM_RESPONSE', ...
                '', msgId);

            % Update last message time and persist state
            agentState.lastMsgTimeSec = simTimeSec;
            ar.Agents(char(agentIdStr)) = agentState;
        end

        function checkIdle(ar, agentId, simTimeSec)
            % checkIdle  Handle an AGENT_IDLE_CHECK event: call the LLM for
            %            a role-appropriate status check-in and record the
            %            action in the BehaviorTracer.
            %
            %   ar.checkIdle(agentId, simTimeSec)
            %
            % Parameters:
            %   agentId    — string: agent identifier
            %   simTimeSec — double: current simulation time
            %
            % Behaviour:
            %   1. Builds a system prompt from the agent's role fullMarkdown.
            %   2. Sends a fixed idle user message to the LLM.
            %   3. Records an 'IDLE_CHECKIN' action in the BehaviorTracer.
            %   4. Schedules the next AGENT_IDLE_CHECK event at
            %      simTimeSec + idleTimeoutSec.
            %
            % Requirements: 12.5, 13.3

            agentIdStr = string(agentId);
            agentState = ar.getAgentState_(agentIdStr);

            % Build system prompt from role's full Markdown
            systemPrompt = agentState.role.fullMarkdown;

            % Fixed idle user message
            userMessage = 'No messages received. Generate a role-appropriate status check-in.';

            % Call LLM (synchronous, blocks until response)
            try
                ar.LLMClient.complete(systemPrompt, userMessage);
            catch
                % On LLM failure, still record the idle check-in attempt
                % and schedule the next event — do not halt the simulation
            end

            % Record the IDLE_CHECKIN action in the BehaviorTracer
            agentState.tracer.record(simTimeSec, uint64(0), 'IDLE_CHECKIN', ...
                '', '');
            ar.Agents(char(agentIdStr)) = agentState;

            % Schedule the next AGENT_IDLE_CHECK event
            nextIdleEvent.time    = simTimeSec + agentState.idleTimeoutSec;
            nextIdleEvent.type    = sim.EventCalendar.AGENT_IDLE_CHECK;
            nextIdleEvent.id      = ar.NextEventId;
            nextIdleEvent.payload = struct('agentId', agentIdStr);
            ar.NextEventId        = ar.NextEventId + uint64(1);

            ar.EventCalendar.schedule(nextIdleEvent);
        end

        function bt = getTracer(ar, agentId)
            % getTracer  Return the BehaviorTracer for the given agent.
            %
            %   bt = ar.getTracer(agentId)
            %
            % Parameters:
            %   agentId — string: agent identifier
            %
            % Returns:
            %   bt — agent.BehaviorTracer instance

            agentState = ar.getAgentState_(string(agentId));
            bt = agentState.tracer;
        end

        function result = getAllTracers(ar)
            % getAllTracers  Return a struct array with tracer info for all agents.
            %
            %   result = ar.getAllTracers()
            %
            % Returns a struct array where each element has fields:
            %   agentId — string: agent identifier
            %   role    — string: role name
            %   tracer  — agent.BehaviorTracer instance

            keyList = keys(ar.Agents);
            n = numel(keyList);

            if n == 0
                result = struct('agentId', {}, 'role', {}, 'tracer', {});
                return;
            end

            % Pre-allocate with first element, then fill
            firstState = ar.Agents(keyList{1});
            result(n).agentId = firstState.id;
            result(n).role    = firstState.role.name;
            result(n).tracer  = firstState.tracer;

            for k = 1:n
                agentState     = ar.Agents(keyList{k});
                result(k).agentId = agentState.id;
                result(k).role    = agentState.role.name;
                result(k).tracer  = agentState.tracer;
            end
        end

        function ids = getAgentIds(ar)
            % getAgentIds  Return a string array of all agent IDs.
            %
            %   ids = ar.getAgentIds()

            keyList = keys(ar.Agents);
            ids = string(keyList(:));
        end

        function n = count(ar)
            % count  Return the number of agents in the registry.
            %
            %   n = ar.count()

            n = ar.Agents.Count;
        end

    end % public methods

    % ======================================================================
    % Private helpers
    % ======================================================================
    methods (Access = private)

        function agentState = getAgentState_(ar, agentId)
            % getAgentState_  Retrieve the agent state struct for the given ID.
            %
            % Throws netsim:agent:unknownAgent if the agent is not found.

            agentIdStr = char(string(agentId));
            if ~ar.Agents.isKey(agentIdStr)
                error('netsim:agent:unknownAgent', ...
                    'Agent "%s" not found in AgentRegistry.', agentIdStr);
            end
            agentState = ar.Agents(agentIdStr);
        end

    end % private methods

end % classdef
