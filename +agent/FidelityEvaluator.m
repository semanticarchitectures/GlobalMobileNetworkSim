classdef FidelityEvaluator < handle
    % FidelityEvaluator  Compares a BehaviorTrace against a Reference_Behavior
    % specification and computes a Fidelity_Score.
    %
    % Usage:
    %   fe = agent.FidelityEvaluator(referenceBehavior)
    %   result = fe.evaluate(behaviorTrace, eventLog, roleName)
    %
    % Constructor parameters:
    %   referenceBehavior — struct loaded by io.ScenarioLoader.loadReferenceBehavior()
    %     Fields:
    %       scenarioName  (string)
    %       roles         — struct array, each with:
    %                         role         (string)
    %                         ordering     ('strict' or 'unordered')
    %                         actions      — struct array with:
    %                                          actionType      (string)
    %                                          triggerEvent    (string)
    %                                          expectedTimeSec (double)
    %
    % evaluate() parameters:
    %   behaviorTrace — MATLAB table from agent.BehaviorTracer.getTrace()
    %                   Columns: simTimeSec, agentId, role, actionType,
    %                            targetAgentId, msgId
    %   eventLog      — struct array from SimController.eventLog
    %                   Used to identify C2_MESSAGE_FAIL events near expected times
    %   roleName      — string: which role's reference behavior to evaluate against
    %
    % Returns a struct with fields:
    %   fidelityScore   (double in [0,1])
    %   missingActions  (struct array: actionType, expectedTimeSec, reason)
    %   extraActions    (struct array: actionType, observedTimeSec)
    %   deviations      (struct array: actionType, expectedTimeSec,
    %                                  observedTimeSec, deviationSec)
    %
    % Requirements: 15.1, 15.2, 15.3, 15.4

    properties (Access = private)
        ReferenceBehavior  struct
    end

    % Time window (seconds) for matching a C2_MESSAGE_FAIL event to a
    % missing action's expectedTimeSec.
    properties (Constant, Access = private)
        NETWORK_FAIL_WINDOW_SEC = 5.0
    end

    methods

        % ------------------------------------------------------------------
        % Constructor
        % ------------------------------------------------------------------
        function fe = FidelityEvaluator(referenceBehavior)
            % FidelityEvaluator  Construct evaluator with a reference behavior.
            %
            %   fe = agent.FidelityEvaluator(referenceBehavior)

            if nargin < 1 || ~isstruct(referenceBehavior)
                error('netsim:agent:fidelityEvaluatorError', ...
                    'referenceBehavior must be a struct.');
            end
            fe.ReferenceBehavior = referenceBehavior;
        end

        % ------------------------------------------------------------------
        % evaluate
        % ------------------------------------------------------------------
        function result = evaluate(fe, behaviorTrace, eventLog, roleName)
            % evaluate  Compare a behavior trace against the reference for roleName.
            %
            %   result = fe.evaluate(behaviorTrace, eventLog, roleName)
            %
            % Parameters:
            %   behaviorTrace — table with columns: simTimeSec, agentId, role,
            %                   actionType, targetAgentId, msgId
            %   eventLog      — struct array (may be empty); each element has at
            %                   least fields: type (string), simTimeSec (double)
            %   roleName      — string identifying the role to evaluate
            %
            % Returns struct with fidelityScore, missingActions, extraActions,
            % deviations.

            roleName = string(roleName);

            % --- Locate the reference role entry ---
            roleEntry = fe.findRoleEntry(roleName);

            if isempty(roleEntry)
                % Role not found — return NaN score with empty arrays
                result = fe.buildResult(NaN, ...
                    fe.emptyMissingActions(), ...
                    fe.emptyExtraActions(), ...
                    fe.emptyDeviations());
                return;
            end

            ordering = string(roleEntry.ordering);

            % --- Extract required actions from reference ---
            refActions = fe.extractRefActions(roleEntry);
            % refActions: struct array with fields actionType, expectedTimeSec

            % --- Extract observed actions from trace ---
            obsActions = fe.extractObsActions(behaviorTrace);
            % obsActions: struct array with fields actionType, simTimeSec

            % --- Handle empty reference ---
            if isempty(refActions)
                result = fe.buildResult(1.0, ...
                    fe.emptyMissingActions(), ...
                    fe.computeExtraActions(refActions, obsActions), ...
                    fe.emptyDeviations());
                return;
            end

            % --- Compute score and matched/missing sets ---
            if strcmp(ordering, 'strict')
                [fidelityScore, matchedIdx, missingRefIdx, deviations] = ...
                    fe.evaluateStrict(refActions, obsActions);
            else
                [fidelityScore, matchedIdx, missingRefIdx, deviations] = ...
                    fe.evaluateUnordered(refActions, obsActions);
            end

            % Clamp to [0, 1]
            fidelityScore = max(0.0, min(1.0, fidelityScore));

            % --- Build missingActions with network-constrained annotation ---
            missingActions = fe.buildMissingActions( ...
                refActions, missingRefIdx, eventLog);

            % --- Build extraActions ---
            extraActions = fe.computeExtraActions(refActions, obsActions);

            result = fe.buildResult(fidelityScore, missingActions, ...
                extraActions, deviations);
        end

    end % methods (public)

    % ======================================================================
    % Private helpers
    % ======================================================================
    methods (Access = private)

        % ------------------------------------------------------------------
        % findRoleEntry
        % ------------------------------------------------------------------
        function roleEntry = findRoleEntry(fe, roleName)
            % findRoleEntry  Return the role struct matching roleName, or [].

            roles = fe.ReferenceBehavior.roles;

            if isstruct(roles)
                nRoles = numel(roles);
                for k = 1:nRoles
                    if string(roles(k).role) == roleName
                        roleEntry = roles(k);
                        return;
                    end
                end
            elseif iscell(roles)
                for k = 1:numel(roles)
                    if string(roles{k}.role) == roleName
                        roleEntry = roles{k};
                        return;
                    end
                end
            end

            roleEntry = [];
        end

        % ------------------------------------------------------------------
        % extractRefActions
        % ------------------------------------------------------------------
        function refActions = extractRefActions(~, roleEntry)
            % extractRefActions  Return struct array with actionType and
            % expectedTimeSec from the role entry's actions list.

            actions = roleEntry.actions;

            if isstruct(actions)
                n = numel(actions);
                if n == 0
                    refActions = struct('actionType', {}, 'expectedTimeSec', {});
                    return;
                end
                refActions(n) = struct('actionType', '', 'expectedTimeSec', 0);
                for k = 1:n
                    refActions(k).actionType     = string(actions(k).actionType);
                    refActions(k).expectedTimeSec = double(actions(k).expectedTimeSec);
                end
            elseif iscell(actions)
                n = numel(actions);
                if n == 0
                    refActions = struct('actionType', {}, 'expectedTimeSec', {});
                    return;
                end
                refActions(n) = struct('actionType', '', 'expectedTimeSec', 0);
                for k = 1:n
                    refActions(k).actionType     = string(actions{k}.actionType);
                    refActions(k).expectedTimeSec = double(actions{k}.expectedTimeSec);
                end
            else
                refActions = struct('actionType', {}, 'expectedTimeSec', {});
            end
        end

        % ------------------------------------------------------------------
        % extractObsActions
        % ------------------------------------------------------------------
        function obsActions = extractObsActions(~, behaviorTrace)
            % extractObsActions  Return struct array with actionType and
            % simTimeSec from the behavior trace table.

            if isempty(behaviorTrace) || height(behaviorTrace) == 0
                obsActions = struct('actionType', {}, 'simTimeSec', {});
                return;
            end

            n = height(behaviorTrace);
            obsActions(n) = struct('actionType', '', 'simTimeSec', 0);
            for k = 1:n
                obsActions(k).actionType = string(behaviorTrace.actionType(k));
                obsActions(k).simTimeSec = double(behaviorTrace.simTimeSec(k));
            end
        end

        % ------------------------------------------------------------------
        % evaluateStrict
        % ------------------------------------------------------------------
        function [score, matchedIdx, missingRefIdx, deviations] = ...
                evaluateStrict(~, refActions, obsActions)
            % evaluateStrict  Compute fidelity using Longest Common Subsequence.
            %
            % Returns:
            %   score        — matched / numel(refActions)
            %   matchedIdx   — indices into refActions that were matched
            %   missingRefIdx — indices into refActions that were NOT matched
            %   deviations   — struct array for matched actions with timing info

            nRef = numel(refActions);
            nObs = numel(obsActions);

            % Build string arrays for LCS
            refTypes = strings(1, nRef);
            for k = 1:nRef
                refTypes(k) = refActions(k).actionType;
            end

            obsTypes = strings(1, nObs);
            for k = 1:nObs
                obsTypes(k) = obsActions(k).actionType;
            end

            % Compute LCS length table (standard DP)
            dp = zeros(nRef + 1, nObs + 1);
            for i = 1:nRef
                for j = 1:nObs
                    if refTypes(i) == obsTypes(j)
                        dp(i+1, j+1) = dp(i, j) + 1;
                    else
                        dp(i+1, j+1) = max(dp(i, j+1), dp(i+1, j));
                    end
                end
            end

            matched = dp(nRef+1, nObs+1);
            score   = matched / nRef;

            % Backtrack to find which ref indices were matched and to which obs
            matchedRefIdx = zeros(1, matched);
            matchedObsIdx = zeros(1, matched);
            i = nRef; j = nObs; ptr = matched;
            while i > 0 && j > 0
                if refTypes(i) == obsTypes(j)
                    matchedRefIdx(ptr) = i;
                    matchedObsIdx(ptr) = j;
                    ptr = ptr - 1;
                    i = i - 1;
                    j = j - 1;
                elseif dp(i, j+1) >= dp(i+1, j)
                    i = i - 1;
                else
                    j = j - 1;
                end
            end

            matchedIdx   = matchedRefIdx;
            missingRefIdx = setdiff(1:nRef, matchedRefIdx);

            % Build deviations for matched actions
            deviations = fe_buildDeviations(refActions, obsActions, ...
                matchedRefIdx, matchedObsIdx);
        end

        % ------------------------------------------------------------------
        % evaluateUnordered
        % ------------------------------------------------------------------
        function [score, matchedIdx, missingRefIdx, deviations] = ...
                evaluateUnordered(~, refActions, obsActions)
            % evaluateUnordered  Compute fidelity using set intersection.
            %
            % Each required action type is matched if it appears anywhere in
            % the observed actions (first occurrence used for timing).

            nRef = numel(refActions);

            % Build a map from actionType -> first observed simTimeSec
            obsTypeMap = containers.Map('KeyType', 'char', 'ValueType', 'double');
            for k = 1:numel(obsActions)
                key = char(obsActions(k).actionType);
                if ~isKey(obsTypeMap, key)
                    obsTypeMap(key) = obsActions(k).simTimeSec;
                end
            end

            matchedIdx   = [];
            missingRefIdx = [];

            for k = 1:nRef
                key = char(refActions(k).actionType);
                if isKey(obsTypeMap, key)
                    matchedIdx(end+1) = k; %#ok<AGROW>
                else
                    missingRefIdx(end+1) = k; %#ok<AGROW>
                end
            end

            matched = numel(matchedIdx);
            score   = matched / nRef;

            % Build deviations for matched actions (timing comparison)
            deviations = struct('actionType', {}, 'expectedTimeSec', {}, ...
                'observedTimeSec', {}, 'deviationSec', {});
            for ki = 1:numel(matchedIdx)
                k   = matchedIdx(ki);
                key = char(refActions(k).actionType);
                expT = refActions(k).expectedTimeSec;
                obsT = obsTypeMap(key);
                dev  = obsT - expT;
                entry.actionType      = refActions(k).actionType;
                entry.expectedTimeSec = expT;
                entry.observedTimeSec = obsT;
                entry.deviationSec    = dev;
                deviations(end+1) = entry; %#ok<AGROW>
            end
        end

        % ------------------------------------------------------------------
        % buildMissingActions
        % ------------------------------------------------------------------
        function missingActions = buildMissingActions(fe, refActions, ...
                missingRefIdx, eventLog)
            % buildMissingActions  Build the missingActions struct array.
            %
            % For each missing action, check if a C2_MESSAGE_FAIL event exists
            % in eventLog within NETWORK_FAIL_WINDOW_SEC of expectedTimeSec.
            % If so, annotate reason as 'network-constrained', else 'agent-failure'.

            missingActions = struct('actionType', {}, ...
                'expectedTimeSec', {}, 'reason', {});

            if isempty(missingRefIdx)
                return;
            end

            % Pre-extract C2_MESSAGE_FAIL times from eventLog for efficiency
            failTimes = fe.extractFailTimes(eventLog);

            for ki = 1:numel(missingRefIdx)
                k    = missingRefIdx(ki);
                expT = refActions(k).expectedTimeSec;

                if fe.hasNetworkFailNear(failTimes, expT)
                    reason = 'network-constrained';
                else
                    reason = 'agent-failure';
                end

                entry.actionType      = refActions(k).actionType;
                entry.expectedTimeSec = expT;
                entry.reason          = reason;
                missingActions(end+1) = entry; %#ok<AGROW>
            end
        end

        % ------------------------------------------------------------------
        % extractFailTimes
        % ------------------------------------------------------------------
        function failTimes = extractFailTimes(fe, eventLog)
            % extractFailTimes  Return vector of simTimeSec for C2_MESSAGE_FAIL
            % events in eventLog.

            failTimes = double.empty(0, 1);

            if isempty(eventLog)
                return;
            end

            % eventLog may be a struct array or cell array
            if isstruct(eventLog)
                n = numel(eventLog);
                for k = 1:n
                    ev = eventLog(k);
                    if isfield(ev, 'type') && isfield(ev, 'simTimeSec')
                        if string(ev.type) == "C2_MESSAGE_FAIL"
                            failTimes(end+1) = double(ev.simTimeSec); %#ok<AGROW>
                        end
                    elseif isfield(ev, 'eventType') && isfield(ev, 'simTimeSec')
                        if string(ev.eventType) == "C2_MESSAGE_FAIL"
                            failTimes(end+1) = double(ev.simTimeSec); %#ok<AGROW>
                        end
                    end
                end
            elseif iscell(eventLog)
                for k = 1:numel(eventLog)
                    ev = eventLog{k};
                    if isfield(ev, 'type') && isfield(ev, 'simTimeSec')
                        if string(ev.type) == "C2_MESSAGE_FAIL"
                            failTimes(end+1) = double(ev.simTimeSec); %#ok<AGROW>
                        end
                    end
                end
            end
        end

        % ------------------------------------------------------------------
        % hasNetworkFailNear
        % ------------------------------------------------------------------
        function tf = hasNetworkFailNear(fe, failTimes, expectedTimeSec)
            % hasNetworkFailNear  Return true if any failTime is within
            % NETWORK_FAIL_WINDOW_SEC of expectedTimeSec.

            if isempty(failTimes)
                tf = false;
                return;
            end
            tf = any(abs(failTimes - expectedTimeSec) <= fe.NETWORK_FAIL_WINDOW_SEC);
        end

        % ------------------------------------------------------------------
        % computeExtraActions
        % ------------------------------------------------------------------
        function extraActions = computeExtraActions(~, refActions, obsActions)
            % computeExtraActions  Return observed actions not in the required set.

            extraActions = struct('actionType', {}, 'observedTimeSec', {});

            if isempty(obsActions)
                return;
            end

            % Build set of required action types
            reqSet = strings(1, numel(refActions));
            for k = 1:numel(refActions)
                reqSet(k) = refActions(k).actionType;
            end

            for k = 1:numel(obsActions)
                at = obsActions(k).actionType;
                if ~any(reqSet == at)
                    entry.actionType      = at;
                    entry.observedTimeSec = obsActions(k).simTimeSec;
                    extraActions(end+1) = entry; %#ok<AGROW>
                end
            end
        end

        % ------------------------------------------------------------------
        % buildResult
        % ------------------------------------------------------------------
        function result = buildResult(~, fidelityScore, missingActions, ...
                extraActions, deviations)
            result.fidelityScore  = fidelityScore;
            result.missingActions = missingActions;
            result.extraActions   = extraActions;
            result.deviations     = deviations;
        end

        % ------------------------------------------------------------------
        % Empty struct array helpers
        % ------------------------------------------------------------------
        function s = emptyMissingActions(~)
            s = struct('actionType', {}, 'expectedTimeSec', {}, 'reason', {});
        end

        function s = emptyExtraActions(~)
            s = struct('actionType', {}, 'observedTimeSec', {});
        end

        function s = emptyDeviations(~)
            s = struct('actionType', {}, 'expectedTimeSec', {}, ...
                'observedTimeSec', {}, 'deviationSec', {});
        end

    end % methods (Access = private)

end % classdef

% =========================================================================
% Module-level helper (not a method — avoids 'fe' scoping issue in nested
% calls from evaluateStrict)
% =========================================================================
function deviations = fe_buildDeviations(refActions, obsActions, ...
    matchedRefIdx, matchedObsIdx)
% fe_buildDeviations  Build deviations struct array for strict-ordering matches.

deviations = struct('actionType', {}, 'expectedTimeSec', {}, ...
    'observedTimeSec', {}, 'deviationSec', {});

for ki = 1:numel(matchedRefIdx)
    ri  = matchedRefIdx(ki);
    oi  = matchedObsIdx(ki);
    expT = refActions(ri).expectedTimeSec;
    obsT = obsActions(oi).simTimeSec;
    dev  = obsT - expT;

    entry.actionType      = refActions(ri).actionType;
    entry.expectedTimeSec = expT;
    entry.observedTimeSec = obsT;
    entry.deviationSec    = dev;
    deviations(end+1) = entry; %#ok<AGROW>
end
end
