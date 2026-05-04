classdef LinkRegistry < handle
    % LinkRegistry  Stores and manages all link state for the simulation.
    %
    % Uses struct-of-arrays storage for memory efficiency.  Each link has a
    % type (GEO_Satellite, LEO_Satellite, Fiber, or Line_Of_Sight), source
    % and destination node identifiers, latency/bandwidth/outage parameters,
    % and dynamic state (isActive, bgLoadFraction, effectiveBwBps, isCongested).
    %
    % On construction:
    %   - All node references are validated against the supplied NodeRegistry.
    %   - Fiber link latencies are computed from geographic distance.
    %   - GEO_Satellite latencies are clamped to >= 270 ms.
    %
    % Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 3.2, 3.3

    properties (Access = private)
        % Struct-of-arrays internal storage
        links   % struct with all link fields (see constructor)
        n       % number of links (scalar double)

        % Reference to the NodeRegistry (used for Fiber latency computation)
        nodeReg % network.NodeRegistry
    end

    methods (Access = public)

        % ------------------------------------------------------------------
        % Constructor
        % ------------------------------------------------------------------

        function obj = LinkRegistry(linkStructArray, nodeRegistry)
            % LinkRegistry  Construct a LinkRegistry from an array of link
            %               definition structs and a NodeRegistry.
            %
            %   lr = network.LinkRegistry(linkStructArray, nodeRegistry)
            %
            %   linkStructArray may be a struct array or cell array of structs.
            %   nodeRegistry is a network.NodeRegistry instance used to
            %   validate node references and compute Fiber link latencies.
            %
            %   Each link definition struct must have fields:
            %     id               (string)  — unique link identifier
            %     type             (string)  — 'GEO_Satellite', 'LEO_Satellite',
            %                                  'Fiber', or 'Line_Of_Sight'
            %     srcNodeId        (string)  — source node ID
            %     dstNodeId        (string)  — destination node ID
            %     nominalLatencyMs (double)  — nominal one-way latency in ms
            %     bandwidthBps     (double)  — total bandwidth in bits/second
            %     outageRate       (double)  — Poisson outage arrival rate
            %     outageDuration   (struct)  — {distribution, params}
            %     backgroundTraffic (struct) — {distribution, params}
            %     coverageRadiusM  (double)  — for LOS links; NaN otherwise
            %   Optional fields:
            %     congestionPenaltyMs (double) — default 0
            %
            % Requirements: 2.1, 2.2, 2.4, 2.7

            % Normalise input to a cell array of structs
            if isstruct(linkStructArray)
                nLinks = numel(linkStructArray);
                cellLinks = cell(nLinks, 1);
                for k = 1:nLinks
                    cellLinks{k} = linkStructArray(k);
                end
            elseif iscell(linkStructArray)
                cellLinks = linkStructArray(:);
                nLinks = numel(cellLinks);
            else
                error('netsim:link:invalidInput', ...
                    'linkStructArray must be a struct array or cell array of structs.');
            end

            obj.n       = nLinks;
            obj.nodeReg = nodeRegistry;

            % Pre-allocate struct-of-arrays
            obj.links.id                 = strings(nLinks, 1);
            obj.links.type               = strings(nLinks, 1);
            obj.links.srcNodeId          = strings(nLinks, 1);
            obj.links.dstNodeId          = strings(nLinks, 1);
            obj.links.nominalLatencyMs   = zeros(nLinks, 1);
            obj.links.bandwidthBps       = zeros(nLinks, 1);
            obj.links.outageRate         = zeros(nLinks, 1);
            obj.links.outageDuration     = cell(nLinks, 1);
            obj.links.backgroundTraffic  = cell(nLinks, 1);
            obj.links.coverageRadiusM    = nan(nLinks, 1);
            obj.links.congestionPenaltyMs = zeros(nLinks, 1);
            obj.links.isActive           = true(nLinks, 1);
            obj.links.bgLoadFraction     = zeros(nLinks, 1);
            obj.links.effectiveBwBps     = zeros(nLinks, 1);
            obj.links.isCongested        = false(nLinks, 1);

            % Populate arrays, validate, and compute derived values
            for k = 1:nLinks
                lk = cellLinks{k};

                obj.links.id(k)   = string(lk.id);
                obj.links.type(k) = string(lk.type);

                % Validate node references (Requirement 2.7)
                srcId = string(lk.srcNodeId);
                dstId = string(lk.dstNodeId);
                obj.links.srcNodeId(k) = srcId;
                obj.links.dstNodeId(k) = dstId;

                % Validate srcNodeId
                try
                    nodeRegistry.indexOf(srcId);
                catch
                    error('netsim:link:unknownNode', ...
                        'Link "%s": source node "%s" was not found in the NodeRegistry.', ...
                        string(lk.id), srcId);
                end

                % Validate dstNodeId
                try
                    nodeRegistry.indexOf(dstId);
                catch
                    error('netsim:link:unknownNode', ...
                        'Link "%s": destination node "%s" was not found in the NodeRegistry.', ...
                        string(lk.id), dstId);
                end

                % Bandwidth and outage parameters
                obj.links.bandwidthBps(k)      = lk.bandwidthBps;
                obj.links.outageRate(k)        = lk.outageRate;
                obj.links.outageDuration{k}    = lk.outageDuration;
                obj.links.backgroundTraffic{k} = lk.backgroundTraffic;

                % Coverage radius (NaN for non-LOS links)
                if isfield(lk, 'coverageRadiusM') && ~isempty(lk.coverageRadiusM)
                    obj.links.coverageRadiusM(k) = lk.coverageRadiusM;
                else
                    obj.links.coverageRadiusM(k) = NaN;
                end

                % Congestion penalty (optional, default 0)
                if isfield(lk, 'congestionPenaltyMs') && ~isempty(lk.congestionPenaltyMs)
                    obj.links.congestionPenaltyMs(k) = lk.congestionPenaltyMs;
                else
                    obj.links.congestionPenaltyMs(k) = 0;
                end

                % Compute / clamp nominal latency based on link type
                linkType = string(lk.type);
                if strcmpi(linkType, 'Fiber')
                    % Requirement 2.4: compute from geographic distance
                    srcPos = nodeRegistry.getPosition(srcId, 0);
                    dstPos = nodeRegistry.getPosition(dstId, 0);
                    distM  = network.GeoUtils.vincenty( ...
                        srcPos.lat, srcPos.lon, dstPos.lat, dstPos.lon);
                    % propagation speed = 200,000 km/s = 200,000,000 m/s
                    obj.links.nominalLatencyMs(k) = distM / 200000000 * 1000;
                elseif strcmpi(linkType, 'GEO_Satellite')
                    % Requirement 2.2: enforce >= 270 ms floor
                    obj.links.nominalLatencyMs(k) = max(lk.nominalLatencyMs, 270);
                else
                    % LEO_Satellite and Line_Of_Sight: use as-is
                    obj.links.nominalLatencyMs(k) = lk.nominalLatencyMs;
                end

                % Initialise dynamic state
                obj.links.isActive(k)       = true;
                obj.links.bgLoadFraction(k) = 0;
                obj.links.isCongested(k)    = false;
                % effectiveBwBps = bandwidthBps * (1 - 0) = bandwidthBps
                obj.links.effectiveBwBps(k) = lk.bandwidthBps;
            end
        end

        % ------------------------------------------------------------------
        % Public methods
        % ------------------------------------------------------------------

        function setOutage(obj, linkId, tf)
            % setOutage  Set or clear the outage state of a link.
            %
            %   lr.setOutage(linkId, tf)
            %
            %   tf = true  → link enters outage (isActive = false)
            %   tf = false → link exits outage  (isActive = true)
            %
            % Requirements: 4.1, 4.2, 4.3

            idx = obj.indexOf(linkId);
            obj.links.isActive(idx) = ~tf;
        end

        function setLOSActive(obj, linkId, tf)
            % setLOSActive  Set the LOS coverage state of a link.
            %
            %   lr.setLOSActive(linkId, tf)
            %
            %   tf = true  → mobile node is within coverage (isActive = true)
            %   tf = false → mobile node is outside coverage (isActive = false)
            %
            % Requirements: 2.5, 2.6

            idx = obj.indexOf(linkId);
            obj.links.isActive(idx) = tf;
        end

        function refreshBackground(obj, linkId)
            % refreshBackground  Sample a new background traffic load for a link.
            %
            %   lr.refreshBackground(linkId)
            %
            %   Draws a new bgLoadFraction from the link's backgroundTraffic
            %   distribution, updates effectiveBwBps, and sets isCongested.
            %   When congested, congestionPenaltyMs is applied to effective
            %   latency (via getEffectiveLatency).
            %
            % Requirements: 3.1, 3.2, 3.3, 3.4

            idx  = obj.indexOf(linkId);
            dist = obj.links.backgroundTraffic{idx};

            newLoad = network.LinkRegistry.sampleDistribution(dist);

            obj.links.bgLoadFraction(idx) = newLoad;

            % Effective bandwidth = max(0, B * (1 - load))
            bw = obj.links.bandwidthBps(idx);
            obj.links.effectiveBwBps(idx) = max(0, bw * (1 - newLoad));

            % Congestion when load >= 1.0
            obj.links.isCongested(idx) = (newLoad >= 1.0);
        end

        function bw = getEffectiveBandwidth(obj, linkId)
            % getEffectiveBandwidth  Return the current effective bandwidth.
            %
            %   bw = lr.getEffectiveBandwidth(linkId)
            %
            %   Returns effectiveBwBps for the link (0 when congested).
            %
            % Requirements: 3.2

            idx = obj.indexOf(linkId);
            bw  = obj.links.effectiveBwBps(idx);
        end

        function lat = getEffectiveLatency(obj, linkId)
            % getEffectiveLatency  Return the current effective latency.
            %
            %   lat = lr.getEffectiveLatency(linkId)
            %
            %   Returns nominalLatencyMs + congestionPenaltyMs when congested,
            %   or just nominalLatencyMs when not congested.
            %
            % Requirements: 3.3, 5.3

            idx = obj.indexOf(linkId);
            lat = obj.links.nominalLatencyMs(idx);
            if obj.links.isCongested(idx)
                lat = lat + obj.links.congestionPenaltyMs(idx);
            end
        end

        function idx = indexOf(obj, linkId)
            % indexOf  Return the integer index of a link in the internal arrays.
            %
            %   idx = lr.indexOf(linkId)
            %
            %   Throws error('netsim:link:notFound', ...) if linkId is not
            %   found in the registry.

            linkIdStr = string(linkId);
            matches   = find(obj.links.id == linkIdStr, 1);

            if isempty(matches)
                error('netsim:link:notFound', ...
                    'Link with ID "%s" was not found in the LinkRegistry.', ...
                    linkIdStr);
            end

            idx = matches;
        end

        function n = count(obj)
            % count  Return the number of links in the registry.
            %
            %   n = lr.count()

            n = obj.n;
        end

        function tf = isLinkActive(obj, linkId)
            % isLinkActive  Return whether the link is currently active.
            %
            %   tf = lr.isLinkActive(linkId)
            %
            %   Returns true when the link is not in outage and (for LOS
            %   links) the mobile node is within coverage.
            %
            % Requirements: 2.5, 4.4

            idx = obj.indexOf(linkId);
            tf  = obj.links.isActive(idx);
        end

        function params = getOutageParams(obj, linkId)
            % getOutageParams  Return outage parameters for a link.
            %
            %   params = lr.getOutageParams(linkId)
            %
            %   Returns a struct with fields:
            %     outageRate     (double)  — Poisson arrival rate (events/sec)
            %     outageDuration (struct)  — distribution spec {distribution, params/...}
            %
            % Requirements: 4.1, 4.2, 4.5

            idx = obj.indexOf(linkId);
            params.outageRate     = obj.links.outageRate(idx);
            params.outageDuration = obj.links.outageDuration{idx};
        end

        function ids = getLinkIds(obj)
            % getLinkIds  Return all link IDs as a string array.
            %
            %   ids = lr.getLinkIds()

            ids = obj.links.id;
        end

        function params = getBackgroundTrafficParams(obj, linkId)
            % getBackgroundTrafficParams  Return background traffic distribution
            %                             parameters for a link.
            %
            %   params = lr.getBackgroundTrafficParams(linkId)
            %
            %   Returns the backgroundTraffic distribution struct for the
            %   specified link.  The struct has at least a 'distribution'
            %   field and distribution-specific parameter fields.
            %
            % Requirements: 3.1, 3.5

            idx    = obj.indexOf(linkId);
            params = obj.links.backgroundTraffic{idx};
        end

        function ids = getActiveLinkIds(obj)
            % getActiveLinkIds  Return string array of IDs of currently active links.
            %
            %   ids = lr.getActiveLinkIds()
            %
            %   Returns a string array containing the IDs of all links for
            %   which isActive is true (not in outage and LOS coverage satisfied).
            %
            % Requirements: 6.1

            ids = obj.links.id(obj.links.isActive);
        end

        function info = getLinkInfo(obj, linkId)
            % getLinkInfo  Return a struct with key link properties.
            %
            %   info = lr.getLinkInfo(linkId)
            %
            %   Returns a struct with fields:
            %     srcNodeId        (string)  — source node identifier
            %     dstNodeId        (string)  — destination node identifier
            %     isActive         (logical) — whether the link is currently active
            %     effectiveLatencyMs (double) — current effective latency in ms
            %                                   (nominal + congestion penalty if congested)
            %
            % Requirements: 5.2, 5.3, 6.1, 6.2

            idx = obj.indexOf(linkId);
            info.srcNodeId          = obj.links.srcNodeId(idx);
            info.dstNodeId          = obj.links.dstNodeId(idx);
            info.isActive           = obj.links.isActive(idx);
            info.effectiveLatencyMs = obj.getEffectiveLatency(linkId);
        end

        function losLinks = getLOSLinkInfos(obj)
            % getLOSLinkInfos  Return a struct array of all Line_Of_Sight links.
            %
            %   losLinks = lr.getLOSLinkInfos()
            %
            %   Returns a struct array (one element per LOS link) with fields:
            %     id              (string)  — link identifier
            %     srcNodeId       (string)  — source node identifier
            %     dstNodeId       (string)  — destination node identifier
            %     coverageRadiusM (double)  — configured coverage radius in metres
            %     isActive        (logical) — current active state
            %
            %   Returns an empty struct array (0×1) if there are no LOS links.
            %
            % Requirements: 2.5, 2.6

            % Find indices of all Line_Of_Sight links.
            mask = strcmpi(obj.links.type, 'Line_Of_Sight');
            idxs = find(mask);

            if isempty(idxs)
                % Return empty struct array with the correct fields.
                proto.id              = "";
                proto.srcNodeId       = "";
                proto.dstNodeId       = "";
                proto.coverageRadiusM = NaN;
                proto.isActive        = false;
                losLinks = proto(false);   % 0×1 struct array
                return;
            end

            % Build struct array.
            nLOS = numel(idxs);
            losLinks = struct( ...
                'id',              cell(nLOS, 1), ...
                'srcNodeId',       cell(nLOS, 1), ...
                'dstNodeId',       cell(nLOS, 1), ...
                'coverageRadiusM', cell(nLOS, 1), ...
                'isActive',        cell(nLOS, 1));

            for k = 1:nLOS
                i = idxs(k);
                losLinks(k).id              = obj.links.id(i);
                losLinks(k).srcNodeId       = obj.links.srcNodeId(i);
                losLinks(k).dstNodeId       = obj.links.dstNodeId(i);
                losLinks(k).coverageRadiusM = obj.links.coverageRadiusM(i);
                losLinks(k).isActive        = obj.links.isActive(i);
            end
        end

    end % methods (Access = public)

    % ======================================================================
    % Private static helpers
    % ======================================================================
    methods (Static, Access = private)

        function val = sampleDistribution(dist)
            % sampleDistribution  Draw a sample from a background traffic
            %                     distribution specification struct.
            %
            %   val = sampleDistribution(dist)
            %
            %   dist must have a 'distribution' field (string) and a 'params'
            %   struct (or inline parameter fields).
            %
            %   Supported distributions:
            %     'uniform'   — params: min, max  (or fields min/max directly)
            %     'normal'    — params: mean, std  (clamped to [0, 1])
            %     'lognormal' — params: mu, sigma  (clamped to [0, 1])
            %
            % Requirements: 3.1

            distName = lower(string(dist.distribution));

            switch distName
                case 'uniform'
                    lo = network.LinkRegistry.getParam(dist, 'min', 0);
                    hi = network.LinkRegistry.getParam(dist, 'max', 1);
                    val = lo + (hi - lo) * rand();

                case 'normal'
                    mu  = network.LinkRegistry.getParam(dist, 'mean', 0.5);
                    sig = network.LinkRegistry.getParam(dist, 'std',  0.1);
                    val = mu + sig * randn();
                    val = max(0, min(1, val));  % clamp to [0, 1]

                case 'lognormal'
                    mu  = network.LinkRegistry.getParam(dist, 'mu',    0);
                    sig = network.LinkRegistry.getParam(dist, 'sigma', 0.5);
                    val = lognrnd(mu, sig);
                    val = max(0, min(1, val));  % clamp to [0, 1]

                otherwise
                    % Unknown distribution: return 0 (no background load)
                    warning('netsim:link:unknownDistribution', ...
                        'Unknown background traffic distribution "%s"; using 0.', ...
                        distName);
                    val = 0;
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
