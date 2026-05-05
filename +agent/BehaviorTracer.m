classdef BehaviorTracer < handle
    % BehaviorTracer  Records Agent_Actions in time order for a single agent.
    %
    % Usage:
    %   bt = agent.BehaviorTracer(agentId, role)
    %   bt.record(simTimeSec, triggerEventId, actionType, targetAgentId, msgId)
    %   trace = bt.getTrace()
    %   bt.exportCSV(filePath)
    %
    % The internal trace is a MATLAB table with columns:
    %   simTimeSec    (double)  — simulation time of the action
    %   agentId       (string)  — agent identifier (fixed at construction)
    %   role          (string)  — role name (fixed at construction)
    %   actionType    (string)  — action descriptor, e.g. 'SEND_STATUS'
    %   targetAgentId (string)  — target agent ID, or "" if none
    %   msgId         (string)  — message ID, or "" if none
    %
    % triggerEventId (uint64) is accepted by record() for internal reference
    % but is NOT included in the CSV export or the returned table.
    %
    % Requirements: 13.3, 16.2

    properties (Access = private)
        % Fixed agent metadata
        AgentId  (1,1) string
        Role     (1,1) string

        % Internal trace table
        Trace    table

        % Parallel storage for triggerEventId (not exported)
        TriggerEventIds  uint64
    end

    methods

        % ------------------------------------------------------------------
        % Constructor
        % ------------------------------------------------------------------
        function bt = BehaviorTracer(agentId, role)
            % BehaviorTracer  Construct a new tracer for the given agent.
            %
            %   bt = agent.BehaviorTracer(agentId, role)
            %
            % Parameters:
            %   agentId — unique agent identifier (string)
            %   role    — role name, e.g. 'Aircrew' (string)

            bt.AgentId = string(agentId);
            bt.Role    = string(role);

            % Initialise an empty table with the required schema
            bt.Trace = table( ...
                double.empty(0,1), ...
                string.empty(0,1), ...
                string.empty(0,1), ...
                string.empty(0,1), ...
                string.empty(0,1), ...
                string.empty(0,1), ...
                'VariableNames', {'simTimeSec','agentId','role', ...
                                  'actionType','targetAgentId','msgId'});

            bt.TriggerEventIds = uint64.empty(0,1);
        end

        % ------------------------------------------------------------------
        % record
        % ------------------------------------------------------------------
        function record(bt, simTimeSec, triggerEventId, actionType, ...
                        targetAgentId, msgId)
            % record  Append one action to the trace.
            %
            %   bt.record(simTimeSec, triggerEventId, actionType, ...
            %             targetAgentId, msgId)
            %
            % Parameters:
            %   simTimeSec    — simulation time (double, seconds)
            %   triggerEventId — event that triggered this action (uint64);
            %                    stored internally but not exported
            %   actionType    — action descriptor string
            %   targetAgentId — target agent ID string ('' if none)
            %   msgId         — message ID string ('' if none)

            newRow = table( ...
                double(simTimeSec), ...
                bt.AgentId, ...
                bt.Role, ...
                string(actionType), ...
                string(targetAgentId), ...
                string(msgId), ...
                'VariableNames', {'simTimeSec','agentId','role', ...
                                  'actionType','targetAgentId','msgId'});

            bt.Trace = [bt.Trace; newRow];
            bt.TriggerEventIds(end+1, 1) = uint64(triggerEventId);
        end

        % ------------------------------------------------------------------
        % getTrace
        % ------------------------------------------------------------------
        function trace = getTrace(bt)
            % getTrace  Return the full trace as a MATLAB table.
            %
            %   trace = bt.getTrace()
            %
            % Returns a table with columns:
            %   simTimeSec, agentId, role, actionType, targetAgentId, msgId

            trace = bt.Trace;
        end

        % ------------------------------------------------------------------
        % exportCSV
        % ------------------------------------------------------------------
        function exportCSV(bt, filePath)
            % exportCSV  Write the trace to a CSV file.
            %
            %   bt.exportCSV(filePath)
            %
            % The CSV file has the canonical header:
            %   simTimeSec,agentId,role,actionType,targetAgentId,msgId
            %
            % An empty trace produces a file containing the header only.
            % Uses fopen/fprintf/fclose for writing.

            fid = fopen(filePath, 'w');
            if fid == -1
                error('netsim:agent:behaviorTracerError', ...
                    'Cannot open file for writing: %s', filePath);
            end

            % Write header
            fprintf(fid, 'simTimeSec,agentId,role,actionType,targetAgentId,msgId\n');

            % Write data rows
            for i = 1:height(bt.Trace)
                fprintf(fid, '%g,%s,%s,%s,%s,%s\n', ...
                    bt.Trace.simTimeSec(i), ...
                    bt.Trace.agentId(i), ...
                    bt.Trace.role(i), ...
                    bt.Trace.actionType(i), ...
                    bt.Trace.targetAgentId(i), ...
                    bt.Trace.msgId(i));
            end

            fclose(fid);
        end

    end % methods

end % classdef
