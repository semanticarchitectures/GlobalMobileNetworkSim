classdef MissionVideoGenerator < handle
    % io.MissionVideoGenerator  Produces animated MP4 videos from simulation
    % event logs containing NODE_POSITION data.
    %
    % Renders node positions over time on a geographic map using Natural
    % Earth coastline/border data and MATLAB's geoaxes/geoplot/geoscatter
    % functions (no Mapping Toolbox dependency).
    %
    % Usage:
    %   vg = io.MissionVideoGenerator(outputDir, scenarioName);
    %   vg = io.MissionVideoGenerator(outputDir, scenarioName, config);
    %   vg.generate(eventLogCsvPath);
    %   vg.generate(eventLogCsvPath, scenarioStruct);
    %
    % Requirements: 7.1, 7.2, 7.4, 7.5, 7.6, 8.1, 8.3, 8.4, 8.6

    % -----------------------------------------------------------------
    % Properties
    % -----------------------------------------------------------------
    properties (Access = private)
        outputDir       % string — output directory path
        scenarioName    % string — scenario name for filename construction
        config          % struct — validated configuration
        coastlineLat    % double vector — NaN-separated coastline latitudes
        coastlineLon    % double vector — NaN-separated coastline longitudes
        boundaryLat     % double vector — NaN-separated boundary latitudes
        boundaryLon     % double vector — NaN-separated boundary longitudes
    end

    % -----------------------------------------------------------------
    % Constructor
    % -----------------------------------------------------------------
    methods
        function obj = MissionVideoGenerator(outputDir, scenarioName, config)
            % MissionVideoGenerator  Construct a video generator for the given output directory.
            %
            %   vg = io.MissionVideoGenerator(outputDir, scenarioName)
            %   vg = io.MissionVideoGenerator(outputDir, scenarioName, config)
            %
            %   outputDir    — directory where the MP4 will be written;
            %                  created if it does not already exist.
            %   scenarioName — used for output filename construction
            %                  (e.g., 'DragonCartImproved' → DragonCartImproved_mission_video.mp4)
            %   config       — optional struct with fields: frameRate,
            %                  speedupFactor, resolution, outputDir, showLinks

            if nargin < 2
                error('netsim:io:invalidConfig', ...
                    'MissionVideoGenerator requires outputDir and scenarioName arguments.');
            end

            obj.scenarioName = char(scenarioName);

            % Validate and apply config with defaults
            if nargin < 3 || isempty(config)
                config = struct();
            end
            obj.config = obj.validateConfig(config);

            % Use the outputDir argument (constructor arg takes precedence)
            obj.outputDir = char(outputDir);

            % Create output directory if it does not exist
            if ~exist(obj.outputDir, 'dir')
                [success, msg] = mkdir(obj.outputDir);
                if ~success
                    error('netsim:io:fileWriteError', ...
                        'Cannot create output directory: %s. Reason: %s', ...
                        obj.outputDir, msg);
                end
            end

            % Load basemap data (download or load from cache)
            obj.loadBasemapData();
        end
    end

    % -----------------------------------------------------------------
    % Public methods (placeholder for future tasks)
    % -----------------------------------------------------------------
    methods (Access = public)
        function generate(obj, eventLogCsvPath, scenarioStruct)
            % generate  Main entry point — parses CSV, renders frames, writes MP4.
            %
            %   vg.generate(eventLogCsvPath)
            %   vg.generate(eventLogCsvPath, scenarioStruct)
            %
            %   eventLogCsvPath  — path to the event log CSV containing NODE_POSITION rows
            %   scenarioStruct   — optional loaded scenario struct for trajectory/link data
            %
            % Requirements: 4.1, 4.2, 4.3, 4.4, 4.5, 4.6, 4.7, 4.8, 7.3

            if nargin < 3
                scenarioStruct = [];
            end

            % Parse position data from CSV
            posLog = obj.parsePositionLog(eventLogCsvPath);

            % Group by timestamp into snapshots
            snapshots = obj.groupByTimestamp(posLog);

            % Write the video using the assembled snapshots
            obj.writeVideo(snapshots, scenarioStruct);
        end

        function outputPath = buildOutputPath(obj)
            % buildOutputPath  Construct the full output MP4 file path.
            %
            %   outputPath = vg.buildOutputPath()
            %
            %   Returns fullfile(outputDir, [scenarioName, '_mission_video.mp4'])

            outputPath = fullfile(obj.outputDir, [obj.scenarioName, '_mission_video.mp4']);
        end
    end

    % -----------------------------------------------------------------
    % Private methods
    % -----------------------------------------------------------------
    methods (Access = private)

        function writeVideo(obj, snapshots, scenarioStruct)
            % writeVideo  Render all frames and write MP4 video file.
            %
            %   obj.writeVideo(snapshots, scenarioStruct)
            %
            %   Opens a VideoWriter with MPEG-4 profile, creates a figure,
            %   computes geographic bounds, renders frames sequentially, and
            %   writes the output MP4. Implements try/catch cleanup to ensure
            %   resources are released on error.
            %
            %   snapshots      — struct array from groupByTimestamp
            %   scenarioStruct — optional scenario struct (may be [])
            %
            % Requirements: 4.1, 4.2, 4.3, 4.4, 4.5, 4.6, 4.7, 4.8, 7.3

            % Determine simulation duration from last snapshot
            simulationDurationSec = snapshots(end).simTimeSec;

            % Calculate frame timing
            frameRate = obj.config.frameRate;
            speedupFactor = obj.config.speedupFactor;
            timeStepSec = speedupFactor / frameRate;  % sim seconds per frame
            totalFrames = ceil((simulationDurationSec / speedupFactor) * frameRate);

            % Build output file path
            outputPath = obj.buildOutputPath();

            % Compute geographic bounds from all snapshots
            [latLim, lonLim] = obj.computeBounds(snapshots, 2);

            % Initialize resources
            fig = [];
            vw = [];
            currentFrame = 0;

            try
                % Create figure
                fig = obj.createFigure();
                ax = geoaxes(fig);
                ax.Basemap = 'none';

                % Set geographic limits
                geolimits(ax, latLim, lonLim);

                % Open VideoWriter
                vw = VideoWriter(outputPath, 'MPEG-4');
                vw.FrameRate = frameRate;
                open(vw);

                % Render frames sequentially
                for frameIdx = 1:totalFrames
                    currentFrame = frameIdx;
                    simTimeSec = (frameIdx - 1) * timeStepSec;

                    % Find the nearest snapshot at or before this time
                    snapshotIdx = find([snapshots.simTimeSec] <= simTimeSec, 1, 'last');
                    if isempty(snapshotIdx)
                        snapshotIdx = 1;
                    end
                    snapshot = snapshots(snapshotIdx);

                    % Render the frame (respects showLinks via obj.config)
                    if obj.config.showLinks
                        obj.renderFrame(fig, ax, snapshot, simTimeSec, scenarioStruct, snapshots);
                    else
                        obj.renderFrame(fig, ax, snapshot, simTimeSec, [], snapshots);
                    end

                    % Reset geographic limits after render (renderFrame may clear axes)
                    geolimits(ax, latLim, lonLim);

                    % Capture frame and write to video
                    frame = getframe(fig);
                    writeVideo(vw, frame);
                end

                % Close VideoWriter on success
                close(vw);

                % Release figure resources
                if isvalid(fig)
                    close(fig);
                    delete(fig);
                end

            catch ME
                % Cleanup: close VideoWriter if open
                if ~isempty(vw)
                    try
                        close(vw);
                    catch
                        % Ignore close errors during cleanup
                    end
                end

                % Cleanup: delete partial MP4 file if it exists
                if exist(outputPath, 'file')
                    delete(outputPath);
                end

                % Cleanup: close and delete figure
                if ~isempty(fig) && isvalid(fig)
                    close(fig);
                    delete(fig);
                end

                % Re-throw with frame number context
                error('netsim:io:videoRenderError', ...
                    'Video rendering failed at frame %d of %d. Reason: %s', ...
                    currentFrame, totalFrames, ME.message);
            end
        end

        function loadBasemapData(obj)
            % loadBasemapData  Download or load cached Natural Earth basemap data.
            %
            %   Downloads Natural Earth 110m coastline and admin-0 boundary
            %   GeoJSON files from GitHub. Caches to data/ directory.
            %   Loads from cache if files already exist.
            %
            %   Requirements: 2.1, 2.2, 2.3

            coastlineUrl = 'https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_110m_coastline.geojson';
            boundaryUrl  = 'https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_110m_admin_0_boundary_lines_land.geojson';

            coastlineCacheFile = fullfile('data', 'ne_110m_coastline.geojson');
            boundaryCacheFile  = fullfile('data', 'ne_110m_admin_0_boundary.geojson');

            [obj.coastlineLat, obj.coastlineLon] = obj.downloadAndParseGeoJSON(coastlineUrl, coastlineCacheFile);
            [obj.boundaryLat, obj.boundaryLon]   = obj.downloadAndParseGeoJSON(boundaryUrl, boundaryCacheFile);
        end

        function [lat, lon] = downloadAndParseGeoJSON(obj, url, cacheFilename)
            % downloadAndParseGeoJSON  Download GeoJSON from URL or load from cache.
            %
            %   [lat, lon] = obj.downloadAndParseGeoJSON(url, cacheFilename)
            %
            %   If cacheFilename exists on disk, loads from cache. Otherwise
            %   downloads from url using webread with 30-second timeout and
            %   caches the result. Handles corrupted cache by deleting and
            %   re-downloading.
            %
            %   Throws netsim:io:downloadError on network failure.
            %   Requirements: 2.1, 2.2, 2.3, 2.5, 2.6

            geojsonStruct = [];

            % Try loading from cache first
            if exist(cacheFilename, 'file')
                try
                    rawText = fileread(cacheFilename);
                    geojsonStruct = jsondecode(rawText);
                    % Handle double-encoded JSON (legacy cache files)
                    if ischar(geojsonStruct)
                        geojsonStruct = jsondecode(geojsonStruct);
                    end
                catch
                    % Corrupted cache — delete and re-download
                    delete(cacheFilename);
                    geojsonStruct = [];
                end
            end

            % Download if not loaded from cache
            if isempty(geojsonStruct)
                try
                    opts = weboptions('Timeout', 30);
                    rawText = webread(url, opts);
                catch ME
                    error('netsim:io:downloadError', ...
                        'Failed to download GeoJSON from URL: %s. Reason: %s', ...
                        url, ME.message);
                end

                % Parse the downloaded text
                geojsonStruct = jsondecode(rawText);

                % Cache the raw downloaded text to disk
                try
                    % Ensure data directory exists
                    cacheDir = fileparts(cacheFilename);
                    if ~exist(cacheDir, 'dir')
                        mkdir(cacheDir);
                    end
                    fid = fopen(cacheFilename, 'w');
                    if fid == -1
                        % Non-fatal: caching failure doesn't prevent operation
                    else
                        fwrite(fid, rawText);
                        fclose(fid);
                    end
                catch
                    % Non-fatal: caching failure doesn't prevent operation
                end
            end

            % Parse the GeoJSON struct into NaN-separated lat/lon vectors
            [lat, lon] = obj.parseGeoJSON(geojsonStruct);
        end

        function [lat, lon] = parseGeoJSON(~, geojsonStruct)
            % parseGeoJSON  Extract coordinates from GeoJSON into NaN-separated vectors.
            %
            %   [lat, lon] = obj.parseGeoJSON(geojsonStruct)
            %
            %   Parses a GeoJSON FeatureCollection and extracts all geometry
            %   coordinates into NaN-separated lat/lon vectors suitable for
            %   geoplot. Handles LineString, MultiLineString, Polygon, and
            %   MultiPolygon geometry types.
            %
            %   Requirements: 2.4

            features = geojsonStruct.features;
            numFeatures = numel(features);

            % Pre-allocate cell arrays for collecting segments
            latCells = {};
            lonCells = {};

            for i = 1:numFeatures
                geom = features(i).geometry;
                geomType = geom.type;
                coords = geom.coordinates;

                switch geomType
                    case 'LineString'
                        % coords is Nx2 or Nx3 array [lon, lat, ...]
                        if iscell(coords)
                            coordMat = cell2mat(coords);
                        else
                            coordMat = coords;
                        end
                        latCells{end+1} = coordMat(:, 2)'; %#ok<AGROW>
                        lonCells{end+1} = coordMat(:, 1)'; %#ok<AGROW>

                    case 'MultiLineString'
                        % coords is a cell array of line segments
                        for j = 1:numel(coords)
                            segment = coords{j};
                            if iscell(segment)
                                segMat = cell2mat(segment);
                            else
                                segMat = segment;
                            end
                            latCells{end+1} = segMat(:, 2)'; %#ok<AGROW>
                            lonCells{end+1} = segMat(:, 1)'; %#ok<AGROW>
                        end

                    case 'Polygon'
                        % coords is a cell array of rings (first is exterior)
                        for j = 1:numel(coords)
                            ring = coords{j};
                            if iscell(ring)
                                ringMat = cell2mat(ring);
                            else
                                ringMat = ring;
                            end
                            latCells{end+1} = ringMat(:, 2)'; %#ok<AGROW>
                            lonCells{end+1} = ringMat(:, 1)'; %#ok<AGROW>
                        end

                    case 'MultiPolygon'
                        % coords is a cell array of polygons
                        for j = 1:numel(coords)
                            polygon = coords{j};
                            for k = 1:numel(polygon)
                                ring = polygon{k};
                                if iscell(ring)
                                    ringMat = cell2mat(ring);
                                else
                                    ringMat = ring;
                                end
                                latCells{end+1} = ringMat(:, 2)'; %#ok<AGROW>
                                lonCells{end+1} = ringMat(:, 1)'; %#ok<AGROW>
                            end
                        end

                    otherwise
                        % Skip unsupported geometry types (e.g., Point)
                end
            end

            % Concatenate with NaN separators between segments
            if isempty(latCells)
                lat = [];
                lon = [];
            else
                numSegments = numel(latCells);
                totalLen = sum(cellfun(@numel, latCells)) + (numSegments - 1);
                lat = zeros(1, totalLen);
                lon = zeros(1, totalLen);
                idx = 1;
                for i = 1:numSegments
                    segLen = numel(latCells{i});
                    lat(idx:idx+segLen-1) = latCells{i};
                    lon(idx:idx+segLen-1) = lonCells{i};
                    idx = idx + segLen;
                    if i < numSegments
                        lat(idx) = NaN;
                        lon(idx) = NaN;
                        idx = idx + 1;
                    end
                end
            end
        end

        function posLog = parsePositionLog(obj, csvPath) %#ok<INUSD>
            % parsePositionLog  Read CSV event log and extract NODE_POSITION entries.
            %
            %   posLog = obj.parsePositionLog(csvPath)
            %
            %   Reads the CSV file at csvPath using the header row to identify
            %   columns. Extracts only rows where eventType equals "NODE_POSITION"
            %   and maps columns: linkId -> nodeId, msgId -> lat (numeric),
            %   srcNodeId -> lon (numeric), dstNodeId -> altM (numeric),
            %   simTimeSec -> simTimeSec (numeric).
            %
            %   Skips rows with non-numeric lat/lon/altM values.
            %
            %   Throws:
            %     netsim:io:fileReadError   - if CSV file does not exist or cannot be read
            %     netsim:io:noPositionData  - if zero NODE_POSITION rows found
            %
            %   Returns:
            %     posLog - struct array with fields: nodeId, lat, lon, altM, simTimeSec
            %
            % Requirements: 5.1, 5.2, 5.3, 5.4, 5.5, 5.6

            % Validate file exists
            if ~exist(csvPath, 'file')
                error('netsim:io:fileReadError', ...
                    'Cannot read event log file: %s. Reason: file does not exist.', csvPath);
            end

            try
                fid = fopen(csvPath, 'r');
                if fid == -1
                    error('netsim:io:fileReadError', ...
                        'Cannot read event log file: %s. Reason: unable to open file.', csvPath);
                end
                cleanupFid = onCleanup(@() fclose(fid));

                % Read header line to identify column indices
                headerLine = fgetl(fid);
                if ~ischar(headerLine)
                    error('netsim:io:fileReadError', ...
                        'Cannot read event log file: %s. Reason: file is empty.', csvPath);
                end

                headers = strsplit(headerLine, ',');
                % Find required column indices
                colSimTimeSec = find(strcmp(headers, 'simTimeSec'), 1);
                colEventType  = find(strcmp(headers, 'eventType'), 1);
                colLinkId     = find(strcmp(headers, 'linkId'), 1);
                colMsgId      = find(strcmp(headers, 'msgId'), 1);
                colSrcNodeId  = find(strcmp(headers, 'srcNodeId'), 1);
                colDstNodeId  = find(strcmp(headers, 'dstNodeId'), 1);

                if isempty(colSimTimeSec) || isempty(colEventType) || ...
                   isempty(colLinkId) || isempty(colMsgId) || ...
                   isempty(colSrcNodeId) || isempty(colDstNodeId)
                    error('netsim:io:fileReadError', ...
                        'Cannot read event log file: %s. Reason: missing required columns.', csvPath);
                end

                numCols = max([colSimTimeSec, colEventType, colLinkId, ...
                               colMsgId, colSrcNodeId, colDstNodeId]);

                % Read remaining lines and parse NODE_POSITION rows
                posLog = struct('nodeId', {}, 'lat', {}, 'lon', {}, ...
                                'altM', {}, 'simTimeSec', {});
                entryCount = 0;

                while ~feof(fid)
                    line = fgetl(fid);
                    if ~ischar(line) || isempty(line)
                        continue;
                    end

                    fields = strsplit(line, ',', 'CollapseDelimiters', false);
                    if numel(fields) < numCols
                        continue;
                    end

                    % Filter: only NODE_POSITION events
                    if ~strcmp(strtrim(fields{colEventType}), 'NODE_POSITION')
                        continue;
                    end

                    % Parse numeric fields; skip row if non-numeric
                    latVal  = str2double(fields{colMsgId});
                    lonVal  = str2double(fields{colSrcNodeId});
                    altVal  = str2double(fields{colDstNodeId});
                    timeVal = str2double(fields{colSimTimeSec});

                    if isnan(latVal) || isnan(lonVal) || isnan(altVal)
                        continue;  % Skip rows with non-numeric lat/lon/altM
                    end

                    % Add valid entry
                    entryCount = entryCount + 1;
                    posLog(entryCount).nodeId     = strtrim(fields{colLinkId});
                    posLog(entryCount).lat        = latVal;
                    posLog(entryCount).lon        = lonVal;
                    posLog(entryCount).altM       = altVal;
                    posLog(entryCount).simTimeSec = timeVal;
                end

            catch ME
                if strcmp(ME.identifier, 'netsim:io:fileReadError') || ...
                   strcmp(ME.identifier, 'netsim:io:noPositionData')
                    rethrow(ME);
                end
                error('netsim:io:fileReadError', ...
                    'Cannot read event log file: %s. Reason: %s', csvPath, ME.message);
            end

            % Check if any NODE_POSITION rows were found
            if entryCount == 0
                error('netsim:io:noPositionData', ...
                    'No NODE_POSITION data found in event log: %s. Ensure positionUpdateIntervalSec > 0 when running the simulation.', csvPath);
            end
        end

        function snapshots = groupByTimestamp(obj, posLog) %#ok<INUSD>
            % groupByTimestamp  Group position log entries by simulation timestamp.
            %
            %   snapshots = obj.groupByTimestamp(posLog)
            %
            %   Groups entries by simTimeSec into snapshots sorted in ascending
            %   order. Each snapshot contains simTimeSec and a struct array of
            %   positions (one per nodeId at that timestamp).
            %
            %   Returns:
            %     snapshots - struct array with fields:
            %       .simTimeSec - the timestamp value
            %       .positions  - struct array with fields: nodeId, lat, lon, altM
            %
            % Requirements: 5.3, 5.4

            % Extract unique timestamps and sort ascending
            allTimes = [posLog.simTimeSec];
            uniqueTimes = unique(allTimes);
            uniqueTimes = sort(uniqueTimes, 'ascend');

            numSnapshots = numel(uniqueTimes);
            snapshots = struct('simTimeSec', cell(1, numSnapshots), ...
                              'positions', cell(1, numSnapshots));

            for i = 1:numSnapshots
                t = uniqueTimes(i);
                snapshots(i).simTimeSec = t;

                % Find all entries at this timestamp
                mask = (allTimes == t);
                entries = posLog(mask);

                % Build positions struct array (without simTimeSec field)
                numEntries = numel(entries);
                positions = struct('nodeId', cell(1, numEntries), ...
                                   'lat', cell(1, numEntries), ...
                                   'lon', cell(1, numEntries), ...
                                   'altM', cell(1, numEntries));
                for j = 1:numEntries
                    positions(j).nodeId = entries(j).nodeId;
                    positions(j).lat    = entries(j).lat;
                    positions(j).lon    = entries(j).lon;
                    positions(j).altM   = entries(j).altM;
                end

                snapshots(i).positions = positions;
            end
        end

        function fig = createFigure(obj)
            % createFigure  Create an invisible figure with configured resolution.
            %
            %   fig = obj.createFigure()
            %
            %   Creates a MATLAB figure with 'Visible' set to 'off' and
            %   dimensions matching the configured resolution (default 1920x1080).
            %
            % Requirements: 3.1, 4.5

            res = obj.config.resolution;
            fig = figure('Visible', 'off', ...
                         'Position', [100 100 res(1) res(2)], ...
                         'Color', 'w');
        end

        function renderFrame(obj, fig, ax, snapshot, simTimeSec, scenarioStruct, snapshots) %#ok<INUSD>
            % renderFrame  Render a single video frame on the given axes.
            %
            %   obj.renderFrame(fig, ax, snapshot, simTimeSec, scenarioStruct, snapshots)
            %
            %   Completely redraws the frame each time: clears all axes
            %   children, redraws basemap, renders historical position
            %   traces, then shows current node markers and labels only
            %   at the current position.
            %
            %   snapshot       — struct with .simTimeSec and .positions
            %   simTimeSec     — current frame simulation time
            %   scenarioStruct — optional scenario struct (may be empty [])
            %   snapshots      — full snapshots array for interpolation
            %
            % Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7, 3.8, 3.9

            % Fully clear the axes — delete all children to prevent stacking
            delete(ax.Children);
            hold(ax, 'on');

            % Render coastline and boundary basemap
            if ~isempty(obj.coastlineLat)
                geoplot(ax, obj.coastlineLat, obj.coastlineLon, '-', ...
                    'Color', [0.4 0.4 0.4], 'LineWidth', 0.5, ...
                    'HandleVisibility', 'off');
            end
            if ~isempty(obj.boundaryLat)
                geoplot(ax, obj.boundaryLat, obj.boundaryLon, '-', ...
                    'Color', [0.6 0.6 0.6], 'LineWidth', 0.3, ...
                    'HandleVisibility', 'off');
            end

            % Determine node positions for this frame via interpolation
            positions = snapshot.positions;
            nodeIds = {};
            nodeLats = [];
            nodeLons = [];
            for i = 1:numel(positions)
                % Try interpolation for smooth motion
                pos = obj.interpolatePosition(snapshots, positions(i).nodeId, simTimeSec);
                if isempty(pos)
                    continue;  % Graceful skip (Req 3.8)
                end
                nodeIds{end+1} = positions(i).nodeId; %#ok<AGROW>
                nodeLats(end+1) = pos.lat; %#ok<AGROW>
                nodeLons(end+1) = pos.lon; %#ok<AGROW>
            end

            % Render historical position traces (thin line showing path
            % from first snapshot up to current time)
            for i = 1:numel(nodeIds)
                nId = nodeIds{i};
                traceLats = [];
                traceLons = [];
                for s = 1:numel(snapshots)
                    if snapshots(s).simTimeSec > simTimeSec
                        break;
                    end
                    sPositions = snapshots(s).positions;
                    for j = 1:numel(sPositions)
                        if strcmp(sPositions(j).nodeId, nId)
                            traceLats(end+1) = sPositions(j).lat; %#ok<AGROW>
                            traceLons(end+1) = sPositions(j).lon; %#ok<AGROW>
                            break;
                        end
                    end
                end
                % Only draw trace if there are at least 2 points
                if numel(traceLats) >= 2
                    % Choose trace color based on node type
                    marker = obj.getNodeMarker(nId, scenarioStruct);
                    switch marker
                        case '^'
                            traceCol = [1.0 0.4 0.4];  % light red for mobile
                        case 'p'
                            traceCol = [0.9 0.8 0.3];  % gold for satellite
                        otherwise
                            traceCol = [0.4 0.4 0.8];  % blue-grey for stationary
                    end
                    geoplot(ax, traceLats, traceLons, '-', ...
                        'Color', [traceCol 0.6], 'LineWidth', 1.5, ...
                        'HandleVisibility', 'off');
                end
            end

            % Render node markers by type using geoscatter
            % Group nodes by marker type for legend
            stationaryIdx = [];
            mobileIdx = [];
            satelliteIdx = [];
            for i = 1:numel(nodeIds)
                marker = obj.getNodeMarker(nodeIds{i}, scenarioStruct);
                switch marker
                    case 'o'
                        stationaryIdx(end+1) = i; %#ok<AGROW>
                    case '^'
                        mobileIdx(end+1) = i; %#ok<AGROW>
                    case 'p'
                        satelliteIdx(end+1) = i; %#ok<AGROW>
                end
            end

            % Plot each group with legend entry
            if ~isempty(stationaryIdx)
                geoscatter(ax, nodeLats(stationaryIdx), nodeLons(stationaryIdx), ...
                    60, 'b', 'o', 'filled', 'DisplayName', 'Stationary');
            end
            if ~isempty(mobileIdx)
                geoscatter(ax, nodeLats(mobileIdx), nodeLons(mobileIdx), ...
                    60, 'r', '^', 'filled', 'DisplayName', 'Mobile');
            end
            if ~isempty(satelliteIdx)
                geoscatter(ax, nodeLats(satelliteIdx), nodeLons(satelliteIdx), ...
                    80, [0.9 0.7 0], 'p', 'filled', 'DisplayName', 'Satellite');
            end

            % Display node ID labels offset 1° lon right, 0.5° lat above
            for i = 1:numel(nodeIds)
                text(ax, nodeLats(i) + 0.5, nodeLons(i) + 1, nodeIds{i}, ...
                    'FontSize', 8, 'HandleVisibility', 'off');
            end

            % Render communication links if showLinks is enabled
            if obj.config.showLinks && ~isempty(scenarioStruct) && isfield(scenarioStruct, 'links')
                % Define link type colors
                linkColors = struct( ...
                    'LEO_Satellite', [0.2 0.6 1.0], ...
                    'GEO_Satellite', [0.8 0.2 0.8], ...
                    'Fiber',         [0.0 0.8 0.0], ...
                    'Line_Of_Sight', [1.0 0.5 0.0]);

                % Track which link types have been plotted (for legend)
                plottedLinkTypes = {};

                links = scenarioStruct.links;
                for i = 1:numel(links)
                    lnk = links(i);
                    srcId = lnk.srcNodeId;
                    dstId = lnk.dstNodeId;

                    % Find positions of src and dst in current frame
                    srcIdx = find(strcmp(nodeIds, srcId), 1);
                    dstIdx = find(strcmp(nodeIds, dstId), 1);

                    if isempty(srcIdx) || isempty(dstIdx)
                        continue;  % Skip links where either node is not visible
                    end

                    linkType = lnk.type;
                    if isfield(linkColors, linkType)
                        col = linkColors.(linkType);
                    else
                        col = [0.5 0.5 0.5];
                    end

                    % Determine display name for legend
                    if ismember(linkType, plottedLinkTypes)
                        dispName = '';
                        handleVis = 'off';
                    else
                        dispName = strrep(linkType, '_', ' ');
                        handleVis = 'on';
                        plottedLinkTypes{end+1} = linkType; %#ok<AGROW>
                    end

                    geoplot(ax, [nodeLats(srcIdx) nodeLats(dstIdx)], ...
                            [nodeLons(srcIdx) nodeLons(dstIdx)], '-', ...
                            'Color', col, 'LineWidth', 1.2, ...
                            'DisplayName', dispName, ...
                            'HandleVisibility', handleVis);
                end
            end

            % Display simulation time as HH:MM:SS in top-right corner
            timeStr = obj.formatSimTime(simTimeSec);
            % Use text annotation in axes coordinates (top-right)
            latLim = ax.LatitudeLimits;
            lonLim = ax.LongitudeLimits;
            text(ax, latLim(2) - 0.3, lonLim(2) - 0.5, timeStr, ...
                'FontSize', 12, 'FontWeight', 'bold', ...
                'HorizontalAlignment', 'right', ...
                'HandleVisibility', 'off');

            % Add legend
            legend(ax, 'Location', 'southwest', 'FontSize', 7);

            hold(ax, 'off');
            drawnow;
        end

        function marker = getNodeMarker(obj, nodeId, scenarioStruct)
            % getNodeMarker  Return marker character based on node type.
            %
            %   marker = obj.getNodeMarker(nodeId, scenarioStruct)
            %
            %   Returns:
            %     'o' — circle for Stationary nodes
            %     '^' — triangle for Mobile nodes with waypoint trajectories
            %     'p' — pentagram for satellite nodes (Mobile with keplerElements)
            %
            %   If scenarioStruct is empty or node not found, defaults to 'o'.
            %
            % Requirements: 3.2

            marker = 'o';  % Default: Stationary / unknown

            if isempty(scenarioStruct) || ~isfield(scenarioStruct, 'nodes')
                return;
            end

            nodeDef = obj.findNodeDef(nodeId, scenarioStruct);
            if isempty(nodeDef)
                return;
            end

            % Determine marker based on type and trajectory/kepler info
            if strcmp(nodeDef.type, 'Stationary')
                marker = 'o';
            elseif strcmp(nodeDef.type, 'Mobile')
                % Check for keplerElements (satellite)
                if isfield(nodeDef, 'keplerElements') && ...
                        ~isempty(nodeDef.keplerElements) && ...
                        isstruct(nodeDef.keplerElements)
                    marker = 'p';  % Pentagram for satellite
                else
                    marker = '^';  % Triangle for Mobile with waypoints
                end
            end
        end

        function pos = interpolatePosition(obj, snapshots, nodeId, targetTime) %#ok<INUSL>
            % interpolatePosition  Linearly interpolate position between snapshots.
            %
            %   pos = obj.interpolatePosition(snapshots, nodeId, targetTime)
            %
            %   Finds the two nearest snapshots bracketing targetTime for the
            %   given nodeId and linearly interpolates lat, lon, altM.
            %
            %   Returns:
            %     pos — struct with fields: lat, lon, altM
            %           Empty [] if node position cannot be computed.
            %
            % Requirements: 3.8

            pos = [];

            if isempty(snapshots)
                return;
            end

            % Find all snapshots containing this nodeId
            times = [];
            lats = [];
            lons = [];
            alts = [];

            for i = 1:numel(snapshots)
                positions = snapshots(i).positions;
                for j = 1:numel(positions)
                    if strcmp(positions(j).nodeId, nodeId)
                        times(end+1) = snapshots(i).simTimeSec; %#ok<AGROW>
                        lats(end+1) = positions(j).lat; %#ok<AGROW>
                        lons(end+1) = positions(j).lon; %#ok<AGROW>
                        alts(end+1) = positions(j).altM; %#ok<AGROW>
                        break;
                    end
                end
            end

            if isempty(times)
                return;  % Node not found in any snapshot
            end

            % Sort by time
            [times, sortIdx] = sort(times);
            lats = lats(sortIdx);
            lons = lons(sortIdx);
            alts = alts(sortIdx);

            % Handle edge cases
            if targetTime <= times(1)
                pos = struct('lat', lats(1), 'lon', lons(1), 'altM', alts(1));
                return;
            end
            if targetTime >= times(end)
                pos = struct('lat', lats(end), 'lon', lons(end), 'altM', alts(end));
                return;
            end

            % Find bracketing snapshots
            idx = find(times <= targetTime, 1, 'last');
            if idx >= numel(times)
                pos = struct('lat', lats(end), 'lon', lons(end), 'altM', alts(end));
                return;
            end

            t0 = times(idx);
            t1 = times(idx + 1);
            dt = t1 - t0;

            if dt == 0
                alpha = 0;
            else
                alpha = (targetTime - t0) / dt;
            end

            interpLat = lats(idx) + alpha * (lats(idx+1) - lats(idx));
            interpLon = lons(idx) + alpha * (lons(idx+1) - lons(idx));
            interpAlt = alts(idx) + alpha * (alts(idx+1) - alts(idx));

            pos = struct('lat', interpLat, 'lon', interpLon, 'altM', interpAlt);
        end

        function timeStr = formatSimTime(~, simTimeSec)
            % formatSimTime  Convert simulation seconds to HH:MM:SS string.
            %
            %   timeStr = obj.formatSimTime(simTimeSec)
            %
            %   Converts a non-negative number of seconds into a formatted
            %   time string in HH:MM:SS format.
            %
            % Requirements: 3.4

            hours   = floor(simTimeSec / 3600);
            minutes = floor(mod(simTimeSec, 3600) / 60);
            seconds = floor(mod(simTimeSec, 60));
            timeStr = sprintf('%02d:%02d:%02d', hours, minutes, seconds);
        end

        function [latLim, lonLim] = computeBounds(obj, snapshots, padding) %#ok<INUSL>
            % computeBounds  Compute lat/lon limits from all positions with padding.
            %
            %   [latLim, lonLim] = obj.computeBounds(snapshots, padding)
            %
            %   Scans all positions across all snapshots to find min/max
            %   lat and lon, then extends by padding degrees in each direction.
            %   Default padding is 2 degrees if not specified.
            %
            %   Returns:
            %     latLim — [minLat-padding, maxLat+padding]
            %     lonLim — [minLon-padding, maxLon+padding]
            %
            % Requirements: 3.5

            if nargin < 3 || isempty(padding)
                padding = 2;
            end

            allLats = [];
            allLons = [];

            for i = 1:numel(snapshots)
                positions = snapshots(i).positions;
                for j = 1:numel(positions)
                    allLats(end+1) = positions(j).lat; %#ok<AGROW>
                    allLons(end+1) = positions(j).lon; %#ok<AGROW>
                end
            end

            if isempty(allLats)
                % Default bounds if no positions
                latLim = [-90 90];
                lonLim = [-180 180];
                return;
            end

            minLat = min(allLats);
            maxLat = max(allLats);
            minLon = min(allLons);
            maxLon = max(allLons);

            latLim = [minLat - padding, maxLat + padding];
            lonLim = [minLon - padding, maxLon + padding];

            % Clamp to valid geographic ranges
            latLim(1) = max(latLim(1), -90);
            latLim(2) = min(latLim(2), 90);
            lonLim(1) = max(lonLim(1), -180);
            lonLim(2) = min(lonLim(2), 180);
        end

        function nodeDef = findNodeDef(~, nodeId, scenarioStruct)
            % findNodeDef  Find a node definition by ID in the scenario struct.
            %
            %   nodeDef = obj.findNodeDef(nodeId, scenarioStruct)
            %
            %   Returns the node struct from scenarioStruct.nodes matching
            %   the given nodeId, or [] if not found.

            nodeDef = [];
            if isempty(scenarioStruct) || ~isfield(scenarioStruct, 'nodes')
                return;
            end
            nodes = scenarioStruct.nodes;
            for i = 1:numel(nodes)
                if strcmp(nodes(i).id, nodeId)
                    nodeDef = nodes(i);
                    return;
                end
            end
        end

        function validConfig = validateConfig(~, config)
            % validateConfig  Validate configuration struct and apply defaults.
            %
            %   Checks frameRate, speedupFactor, resolution, showLinks.
            %   Throws netsim:io:invalidConfig with field name and constraint
            %   for any invalid value.

            % Apply defaults
            validConfig = struct();
            validConfig.frameRate     = 30;
            validConfig.speedupFactor = 60;
            validConfig.resolution    = [1920 1080];
            validConfig.showLinks     = true;

            % Override with user-provided values and validate
            if isfield(config, 'frameRate')
                fr = config.frameRate;
                if ~isnumeric(fr) || ~isscalar(fr) || fr ~= floor(fr) || fr < 1 || fr > 120
                    error('netsim:io:invalidConfig', ...
                        'Invalid field "frameRate": must be an integer in the range 1 to 120.');
                end
                validConfig.frameRate = fr;
            end

            if isfield(config, 'speedupFactor')
                sf = config.speedupFactor;
                if ~isnumeric(sf) || ~isscalar(sf) || sf < 0.1 || sf > 1000
                    error('netsim:io:invalidConfig', ...
                        'Invalid field "speedupFactor": must be a number in the range 0.1 to 1000.');
                end
                validConfig.speedupFactor = sf;
            end

            if isfield(config, 'resolution')
                res = config.resolution;
                if ~isnumeric(res) || ~isequal(size(res), [1 2]) || ...
                        any(res ~= floor(res)) || ...
                        res(1) < 1 || res(1) > 7680 || ...
                        res(2) < 1 || res(2) > 4320
                    error('netsim:io:invalidConfig', ...
                        'Invalid field "resolution": must be a 1x2 integer array where width is in the range 1 to 7680 and height is in the range 1 to 4320.');
                end
                validConfig.resolution = res;
            end

            if isfield(config, 'showLinks')
                sl = config.showLinks;
                if ~islogical(sl) || ~isscalar(sl)
                    error('netsim:io:invalidConfig', ...
                        'Invalid field "showLinks": must be a logical (true/false) value.');
                end
                validConfig.showLinks = sl;
            end
        end

    end % methods (private)

end % classdef
