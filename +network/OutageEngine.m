classdef OutageEngine < handle
    % network.OutageEngine  Generates stochastic outage events for all links.
    %
    % Outage inter-arrival times are drawn from an exponential distribution
    % parameterised by each link's outageRate (Poisson process).  Outage
    % durations are sampled from the per-link outageDuration distribution
    % (exponential, lognormal, or fixed).
    %
    % Typical usage:
    %
    %   oe = network.OutageEngine(linkRegistry, eventCalendar);
    %   oe.scheduleAllInitialOutages(0);   % seed the chain at t = 0
    %
    % When SimController processes an OUTAGE_START event it calls:
    %   oe.scheduleOutageEnd(linkId, outageStartTimeSec)
    %
    % When SimController processes an OUTAGE_END event it calls:
    %   oe.scheduleNextOutage(linkId, outageEndTimeSec)
    %
    % Requirements: 4.1, 4.2, 4.3, 4.4, 4.5

    % -----------------------------------------------------------------
    % Private state
    % -----------------------------------------------------------------
    properties (Access = private)
        linkReg     % network.LinkRegistry reference
        eventCal    % sim.EventCalendar reference
        nextEventId % uint64 counter for unique event IDs
    end

    % -----------------------------------------------------------------
    % Constructor
    % -----------------------------------------------------------------
    methods
        function oe = OutageEngine(linkRegistry, eventCalendar)
            % OutageEngine  Construct an OutageEngine.
            %
            %   oe = network.OutageEngine(linkRegistry, eventCalendar)
            %
            %   linkRegistry  — network.LinkRegistry instance
            %   eventCalendar — sim.EventCalendar instance

            oe.linkReg     = linkRegistry;
            oe.eventCal    = eventCalendar;
            oe.nextEventId = uint64(1);
        end
    end

    % -----------------------------------------------------------------
    % Public methods
    % -----------------------------------------------------------------
    methods (Access = public)

        function scheduleNextOutage(oe, linkId, currentTimeSec)
            % scheduleNextOutage  Schedule the next OUTAGE_START for a link.
            %
            %   oe.scheduleNextOutage(linkId, currentTimeSec)
            %
            %   Draws an inter-arrival time from Exp(1/outageRate) and
            %   schedules an OUTAGE_START event at currentTimeSec + dt.
            %
            %   The event payload contains: linkId (string).
            %
            % Requirements: 4.1

            params = oe.linkReg.getOutageParams(linkId);
            rate   = params.outageRate;

            % Draw inter-arrival time from exponential distribution.
            % exprnd(mean) where mean = 1/rate.
            if rate <= 0
                % Zero or negative rate means no outages — do not schedule.
                return;
            end
            dt = exprnd(1 / rate);

            ev.time    = currentTimeSec + dt;
            ev.type    = sim.EventCalendar.OUTAGE_START;
            ev.id      = oe.nextEventId;
            ev.payload = struct('linkId', string(linkId));

            oe.nextEventId = oe.nextEventId + uint64(1);
            oe.eventCal.schedule(ev);
        end

        function scheduleOutageEnd(oe, linkId, outageStartTimeSec)
            % scheduleOutageEnd  Schedule the OUTAGE_END for an active outage.
            %
            %   oe.scheduleOutageEnd(linkId, outageStartTimeSec)
            %
            %   Samples an outage duration from the link's configured
            %   outageDuration distribution and schedules an OUTAGE_END
            %   event at outageStartTimeSec + duration.
            %
            %   The event payload contains: linkId (string).
            %
            % Requirements: 4.2, 4.5

            params   = oe.linkReg.getOutageParams(linkId);
            duration = network.OutageEngine.sampleDuration(params.outageDuration);

            ev.time    = outageStartTimeSec + duration;
            ev.type    = sim.EventCalendar.OUTAGE_END;
            ev.id      = oe.nextEventId;
            ev.payload = struct('linkId', string(linkId));

            oe.nextEventId = oe.nextEventId + uint64(1);
            oe.eventCal.schedule(ev);
        end

        function scheduleAllInitialOutages(oe, currentTimeSec)
            % scheduleAllInitialOutages  Seed the outage chain for every link.
            %
            %   oe.scheduleAllInitialOutages(currentTimeSec)
            %
            %   Calls scheduleNextOutage for every link in the LinkRegistry.
            %   Intended to be called once at simulation startup.
            %
            % Requirements: 4.1

            ids = oe.linkReg.getLinkIds();
            for k = 1:numel(ids)
                oe.scheduleNextOutage(ids(k), currentTimeSec);
            end
        end

    end % methods (Access = public)

    % -----------------------------------------------------------------
    % Private static helpers
    % -----------------------------------------------------------------
    methods (Static, Access = private)

        function duration = sampleDuration(outageDuration)
            % sampleDuration  Draw a duration sample from an outageDuration spec.
            %
            %   duration = sampleDuration(outageDuration)
            %
            %   outageDuration is a struct with at least a 'distribution'
            %   (or 'type') field and distribution-specific parameters.
            %
            %   Supported distributions:
            %     'exponential' — exprnd(mean)
            %                     mean from outageDuration.mean, .meanSec,
            %                     or .params.mean
            %     'lognormal'   — lognrnd(mu, sigma)
            %                     mu/sigma from outageDuration.mu/.sigma
            %                     or .params.mu/.params.sigma
            %     'fixed'       — constant value from outageDuration.value
            %                     or .params.value
            %
            % Requirements: 4.5

            % Determine distribution name — accept 'distribution' or 'type'
            if isfield(outageDuration, 'distribution')
                distName = lower(string(outageDuration.distribution));
            elseif isfield(outageDuration, 'type')
                distName = lower(string(outageDuration.type));
            else
                distName = "exponential";
            end

            switch distName
                case 'exponential'
                    meanVal  = network.OutageEngine.getParam(outageDuration, ...
                        {'mean', 'meanSec'}, 60);
                    duration = exprnd(meanVal);

                case 'lognormal'
                    mu    = network.OutageEngine.getParam(outageDuration, {'mu'},    0);
                    sigma = network.OutageEngine.getParam(outageDuration, {'sigma'}, 1);
                    duration = lognrnd(mu, sigma);

                case 'fixed'
                    duration = network.OutageEngine.getParam(outageDuration, ...
                        {'value', 'meanSec', 'mean'}, 60);

                otherwise
                    warning('netsim:outage:unknownDistribution', ...
                        'Unknown outageDuration distribution "%s"; using 60 s.', ...
                        distName);
                    duration = 60;
            end

            % Ensure non-negative duration
            duration = max(0, duration);
        end

        function v = getParam(dist, fieldNames, defaultVal)
            % getParam  Extract a parameter from a distribution struct.
            %
            %   Checks dist.params.<name> first, then dist.<name> for each
            %   name in fieldNames (cell array of strings), falling back to
            %   defaultVal if none found.

            % Check params sub-struct first
            if isfield(dist, 'params') && isstruct(dist.params)
                for k = 1:numel(fieldNames)
                    if isfield(dist.params, fieldNames{k})
                        v = dist.params.(fieldNames{k});
                        return;
                    end
                end
            end

            % Check top-level fields
            for k = 1:numel(fieldNames)
                if isfield(dist, fieldNames{k})
                    v = dist.(fieldNames{k});
                    return;
                end
            end

            % Fall back to default
            v = defaultVal;
        end

    end % methods (Static, Access = private)

end % classdef
