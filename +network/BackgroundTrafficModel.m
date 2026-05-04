classdef BackgroundTrafficModel < handle
    % network.BackgroundTrafficModel  Manages periodic background traffic
    %                                 resampling for all links.
    %
    % At construction, validates the background traffic distribution
    % parameters for every link in the registry.  At each refresh interval
    % it draws a new load fraction from the configured distribution and
    % updates the link's effective bandwidth via LinkRegistry.refreshBackground.
    %
    % Typical usage:
    %
    %   btm = network.BackgroundTrafficModel(linkRegistry, eventCalendar);
    %   btm.scheduleAllInitialRefreshes(0);   % seed at t = 0
    %
    % When SimController processes a BACKGROUND_REFRESH event it calls:
    %   btm.resample(linkId, simTimeSec)
    %
    % Requirements: 3.1, 3.2, 3.3, 3.4, 3.5

    % -----------------------------------------------------------------
    % Private state
    % -----------------------------------------------------------------
    properties (Access = private)
        linkReg             % network.LinkRegistry reference
        eventCal            % sim.EventCalendar reference
        refreshIntervalSec  % double — seconds between background refreshes
        nextEventId         % uint64 counter for unique event IDs
    end

    % -----------------------------------------------------------------
    % Constructor
    % -----------------------------------------------------------------
    methods
        function btm = BackgroundTrafficModel(linkRegistry, eventCalendar, refreshIntervalSec)
            % BackgroundTrafficModel  Construct a BackgroundTrafficModel.
            %
            %   btm = network.BackgroundTrafficModel(linkRegistry, eventCalendar)
            %   btm = network.BackgroundTrafficModel(linkRegistry, eventCalendar, refreshIntervalSec)
            %
            %   linkRegistry       — network.LinkRegistry instance
            %   eventCalendar      — sim.EventCalendar instance
            %   refreshIntervalSec — (optional) seconds between refreshes;
            %                        defaults to 60 if not provided
            %
            % Validates background traffic distribution parameters for every
            % link on construction.  Throws error('netsim:link:invalidBgParams',
            % ...) identifying the link ID and invalid parameter if:
            %   - distribution is 'normal'    and std  <= 0
            %   - distribution is 'lognormal' and sigma <= 0
            %   - distribution is 'uniform'   and min  >  max
            %
            % Requirements: 3.5

            if nargin < 3 || isempty(refreshIntervalSec)
                refreshIntervalSec = 60;
            end

            btm.linkReg            = linkRegistry;
            btm.eventCal           = eventCalendar;
            btm.refreshIntervalSec = refreshIntervalSec;
            btm.nextEventId        = uint64(1);

            % Validate all link background traffic parameters
            ids = linkRegistry.getLinkIds();
            for k = 1:numel(ids)
                params = linkRegistry.getBackgroundTrafficParams(ids(k));
                network.BackgroundTrafficModel.validateParams(ids(k), params);
            end
        end
    end

    % -----------------------------------------------------------------
    % Public methods
    % -----------------------------------------------------------------
    methods (Access = public)

        function resample(btm, linkId, simTimeSec)
            % resample  Draw a new background load for a link and schedule
            %           the next BACKGROUND_REFRESH event.
            %
            %   btm.resample(linkId, simTimeSec)
            %
            %   linkId     — string link identifier
            %   simTimeSec — current simulation time in seconds
            %
            %   Calls linkRegistry.refreshBackground(linkId) to draw a new
            %   load fraction and update effective bandwidth, then schedules
            %   the next BACKGROUND_REFRESH event at
            %   simTimeSec + refreshIntervalSec.
            %
            % Requirements: 3.1, 3.2, 3.4

            % Draw new load and update effective bandwidth
            btm.linkReg.refreshBackground(linkId);

            % Schedule next refresh event
            btm.scheduleRefresh(linkId, simTimeSec + btm.refreshIntervalSec);
        end

        function scheduleAllInitialRefreshes(btm, startTimeSec)
            % scheduleAllInitialRefreshes  Schedule the first BACKGROUND_REFRESH
            %                              event for every link.
            %
            %   btm.scheduleAllInitialRefreshes(startTimeSec)
            %
            %   Schedules a BACKGROUND_REFRESH event for every link in the
            %   LinkRegistry at startTimeSec + refreshIntervalSec.
            %   Intended to be called once at simulation startup.
            %
            % Requirements: 3.4

            ids = btm.linkReg.getLinkIds();
            for k = 1:numel(ids)
                btm.scheduleRefresh(ids(k), startTimeSec + btm.refreshIntervalSec);
            end
        end

    end % methods (Access = public)

    % -----------------------------------------------------------------
    % Private helpers
    % -----------------------------------------------------------------
    methods (Access = private)

        function scheduleRefresh(btm, linkId, eventTimeSec)
            % scheduleRefresh  Insert a BACKGROUND_REFRESH event into the calendar.
            %
            %   btm.scheduleRefresh(linkId, eventTimeSec)

            ev.time    = eventTimeSec;
            ev.type    = sim.EventCalendar.BACKGROUND_REFRESH;
            ev.id      = btm.nextEventId;
            ev.payload = struct('linkId', string(linkId));

            btm.nextEventId = btm.nextEventId + uint64(1);
            btm.eventCal.schedule(ev);
        end

    end % methods (Access = private)

    % -----------------------------------------------------------------
    % Private static helpers
    % -----------------------------------------------------------------
    methods (Static, Access = private)

        function validateParams(linkId, params)
            % validateParams  Validate background traffic distribution params.
            %
            %   Throws error('netsim:link:invalidBgParams', ...) if:
            %     - distribution is 'normal'    and std  <= 0
            %     - distribution is 'lognormal' and sigma <= 0
            %     - distribution is 'uniform'   and min  >  max
            %
            % Requirements: 3.5

            if ~isfield(params, 'distribution')
                return;  % No distribution field — nothing to validate
            end

            distName = lower(string(params.distribution));

            switch distName
                case 'normal'
                    stdVal = network.BackgroundTrafficModel.getParam(params, 'std', NaN);
                    if isnan(stdVal) || stdVal <= 0
                        error('netsim:link:invalidBgParams', ...
                            'Link "%s": normal distribution requires std > 0 (got %g).', ...
                            string(linkId), stdVal);
                    end

                case 'lognormal'
                    sigmaVal = network.BackgroundTrafficModel.getParam(params, 'sigma', NaN);
                    if isnan(sigmaVal) || sigmaVal <= 0
                        error('netsim:link:invalidBgParams', ...
                            'Link "%s": lognormal distribution requires sigma > 0 (got %g).', ...
                            string(linkId), sigmaVal);
                    end

                case 'uniform'
                    minVal = network.BackgroundTrafficModel.getParam(params, 'min', NaN);
                    maxVal = network.BackgroundTrafficModel.getParam(params, 'max', NaN);
                    if ~isnan(minVal) && ~isnan(maxVal) && minVal > maxVal
                        error('netsim:link:invalidBgParams', ...
                            'Link "%s": uniform distribution requires min <= max (got min=%g, max=%g).', ...
                            string(linkId), minVal, maxVal);
                    end

                % Other distributions: no additional validation needed here
            end
        end

        function v = getParam(dist, fieldName, defaultVal)
            % getParam  Extract a parameter from a distribution struct.
            %
            %   Checks dist.params.<fieldName> first, then dist.<fieldName>,
            %   falling back to defaultVal if neither exists.

            if isfield(dist, 'params') && isstruct(dist.params) && ...
                    isfield(dist.params, fieldName)
                v = dist.params.(fieldName);
            elseif isfield(dist, fieldName)
                v = dist.(fieldName);
            else
                v = defaultVal;
            end
        end

    end % methods (Static, Access = private)

end % classdef
