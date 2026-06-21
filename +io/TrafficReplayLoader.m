classdef TrafficReplayLoader
    % io.TrafficReplayLoader  Load real-world traffic logs for replay.
    %
    % Parses traffic log files in JSON ('generic') or CSV ('native') format
    % and returns a struct array of replay events ready for scheduling
    % into the simulation EventCalendar.
    %
    % Supported event types:
    %   'message_transmission' — C2 message send/receive
    %   'authentication_exchange' — authentication request/response
    %   'data_access_attempt' — data read/write/ingest attempt
    %
    % Requirements: R48, R50

    methods (Static)

        function events = load(filePath, format)
            % load  Load a real-world traffic log file.
            %
            %   events = io.TrafficReplayLoader.load(filePath, format)
            %
            %   filePath — path to the traffic log file
            %   format   — 'generic' (JSON) or 'native' (CSV)
            %
            %   Returns struct array of replay events with fields:
            %     eventType     — 'message_transmission' | 'authentication_exchange'
            %                     | 'data_access_attempt'
            %     timeSec       — scheduled simulation time in seconds
            %     srcEntityId   — source entity identifier
            %     dstEntityId   — destination entity identifier (may be empty)
            %     payload       — struct with event-specific fields:
            %       For message_transmission:
            %         classification, sizeBytes, priority
            %       For authentication_exchange:
            %         credentialType, enclave, role
            %       For data_access_attempt:
            %         classification, enclave, operation, role
            %
            % Requirements: R48, R50

            if nargin < 2 || isempty(format)
                format = 'generic';
            end

            if ~isfile(filePath)
                error('netsim:io:trafficFileNotFound', ...
                    'Traffic log file not found: %s', filePath);
            end

            format = lower(char(format));

            switch format
                case 'generic'
                    events = io.TrafficReplayLoader.loadJson(filePath);
                case 'native'
                    events = io.TrafficReplayLoader.loadCsv(filePath);
                otherwise
                    error('netsim:io:unsupportedFormat', ...
                        'Unsupported traffic log format: %s. Use ''generic'' or ''native''.', ...
                        format);
            end
        end

    end % methods (Static)

    methods (Static, Access = private)

        function events = loadJson(filePath)
            % loadJson  Parse JSON traffic log (generic format).
            %
            %   Expected JSON structure:
            %   { "events": [
            %       { "eventType": "...", "timeSec": ..., "srcEntityId": "...",
            %         "dstEntityId": "...", "payload": { ... } },
            %       ...
            %   ] }

            try
                rawText = fileread(filePath);
                data = jsondecode(rawText);
            catch ME
                error('netsim:io:trafficParseError', ...
                    'Failed to parse JSON traffic log "%s": %s', ...
                    filePath, ME.message);
            end

            % Extract events array
            if isfield(data, 'events')
                rawEvents = data.events;
            elseif isstruct(data) && numel(data) > 1
                rawEvents = data;
            else
                rawEvents = data;
            end

            % Initialize output struct array
            events = struct('eventType', {}, 'timeSec', {}, ...
                'srcEntityId', {}, 'dstEntityId', {}, 'payload', {});

            if isempty(rawEvents)
                return;
            end

            nEvents = numel(rawEvents);
            for k = 1:nEvents
                if isstruct(rawEvents) && numel(rawEvents) >= k
                    raw = rawEvents(k);
                elseif iscell(rawEvents)
                    raw = rawEvents{k};
                else
                    continue;
                end

                evt = io.TrafficReplayLoader.parseRawEvent(raw);
                if ~isempty(evt)
                    events(end+1) = evt; %#ok<AGROW>
                end
            end
        end

        function events = loadCsv(filePath)
            % loadCsv  Parse CSV traffic log (native format).
            %
            %   Expected CSV columns:
            %     timeSec, eventType, srcEntityId, dstEntityId, classification,
            %     enclave, operation, role, sizeBytes, credentialType, priority

            try
                rawText = fileread(filePath);
            catch ME
                error('netsim:io:trafficParseError', ...
                    'Failed to read CSV traffic log "%s": %s', ...
                    filePath, ME.message);
            end

            lines = strsplit(rawText, {'\n', '\r\n'});
            % Remove empty trailing lines
            lines = lines(~cellfun(@isempty, lines));

            if numel(lines) < 2
                events = struct('eventType', {}, 'timeSec', {}, ...
                    'srcEntityId', {}, 'dstEntityId', {}, 'payload', {});
                return;
            end

            % Parse header
            headers = strsplit(strtrim(lines{1}), ',');
            headers = cellfun(@strtrim, headers, 'UniformOutput', false);

            % Map header names to column indices
            colMap = containers.Map(headers, num2cell(1:numel(headers)));

            % Initialize output
            events = struct('eventType', {}, 'timeSec', {}, ...
                'srcEntityId', {}, 'dstEntityId', {}, 'payload', {});

            for k = 2:numel(lines)
                line = strtrim(lines{k});
                if isempty(line)
                    continue;
                end

                cols = strsplit(line, ',');
                cols = cellfun(@strtrim, cols, 'UniformOutput', false);

                % Extract fields by column name
                evt.timeSec = 0;
                if colMap.isKey('timeSec') && numel(cols) >= colMap('timeSec')
                    val = str2double(cols{colMap('timeSec')});
                    if ~isnan(val)
                        evt.timeSec = val;
                    end
                end

                evt.eventType = 'data_access_attempt';
                if colMap.isKey('eventType') && numel(cols) >= colMap('eventType')
                    evt.eventType = cols{colMap('eventType')};
                end

                evt.srcEntityId = '';
                if colMap.isKey('srcEntityId') && numel(cols) >= colMap('srcEntityId')
                    evt.srcEntityId = cols{colMap('srcEntityId')};
                end

                evt.dstEntityId = '';
                if colMap.isKey('dstEntityId') && numel(cols) >= colMap('dstEntityId')
                    evt.dstEntityId = cols{colMap('dstEntityId')};
                end

                % Build payload based on event type
                evt.payload = io.TrafficReplayLoader.buildPayloadFromCsv(...
                    evt.eventType, cols, colMap);

                % Validate event type
                validTypes = {'message_transmission', 'authentication_exchange', ...
                    'data_access_attempt'};
                if ismember(evt.eventType, validTypes)
                    events(end+1) = evt; %#ok<AGROW>
                end
            end
        end

        function evt = parseRawEvent(raw)
            % parseRawEvent  Parse a single raw event struct from JSON.

            evt = struct();

            % Event type (required)
            if ~isfield(raw, 'eventType')
                evt = [];
                return;
            end
            eventType = char(raw.eventType);

            validTypes = {'message_transmission', 'authentication_exchange', ...
                'data_access_attempt'};
            if ~ismember(eventType, validTypes)
                evt = [];
                return;
            end

            evt.eventType = eventType;

            % Time
            evt.timeSec = 0;
            if isfield(raw, 'timeSec')
                evt.timeSec = double(raw.timeSec);
            end

            % Source entity
            evt.srcEntityId = '';
            if isfield(raw, 'srcEntityId')
                evt.srcEntityId = char(raw.srcEntityId);
            end

            % Destination entity
            evt.dstEntityId = '';
            if isfield(raw, 'dstEntityId')
                evt.dstEntityId = char(raw.dstEntityId);
            end

            % Payload
            if isfield(raw, 'payload') && isstruct(raw.payload)
                evt.payload = raw.payload;
            else
                % Build payload from top-level fields
                evt.payload = io.TrafficReplayLoader.buildPayloadFromRaw(eventType, raw);
            end
        end

        function payload = buildPayloadFromRaw(eventType, raw)
            % buildPayloadFromRaw  Build payload struct from raw event fields.

            payload = struct();

            switch eventType
                case 'message_transmission'
                    if isfield(raw, 'classification')
                        payload.classification = char(raw.classification);
                    end
                    if isfield(raw, 'sizeBytes')
                        payload.sizeBytes = double(raw.sizeBytes);
                    end
                    if isfield(raw, 'priority')
                        payload.priority = char(raw.priority);
                    end

                case 'authentication_exchange'
                    if isfield(raw, 'credentialType')
                        payload.credentialType = char(raw.credentialType);
                    end
                    if isfield(raw, 'enclave')
                        payload.enclave = char(raw.enclave);
                    end
                    if isfield(raw, 'role')
                        payload.role = char(raw.role);
                    end

                case 'data_access_attempt'
                    if isfield(raw, 'classification')
                        payload.classification = char(raw.classification);
                    end
                    if isfield(raw, 'enclave')
                        payload.enclave = char(raw.enclave);
                    end
                    if isfield(raw, 'operation')
                        payload.operation = char(raw.operation);
                    end
                    if isfield(raw, 'role')
                        payload.role = char(raw.role);
                    end
            end
        end

        function payload = buildPayloadFromCsv(eventType, cols, colMap)
            % buildPayloadFromCsv  Build payload struct from CSV columns.

            payload = struct();

            switch eventType
                case 'message_transmission'
                    if colMap.isKey('classification') && numel(cols) >= colMap('classification')
                        payload.classification = cols{colMap('classification')};
                    end
                    if colMap.isKey('sizeBytes') && numel(cols) >= colMap('sizeBytes')
                        val = str2double(cols{colMap('sizeBytes')});
                        if ~isnan(val)
                            payload.sizeBytes = val;
                        end
                    end
                    if colMap.isKey('priority') && numel(cols) >= colMap('priority')
                        payload.priority = cols{colMap('priority')};
                    end

                case 'authentication_exchange'
                    if colMap.isKey('credentialType') && numel(cols) >= colMap('credentialType')
                        payload.credentialType = cols{colMap('credentialType')};
                    end
                    if colMap.isKey('enclave') && numel(cols) >= colMap('enclave')
                        payload.enclave = cols{colMap('enclave')};
                    end
                    if colMap.isKey('role') && numel(cols) >= colMap('role')
                        payload.role = cols{colMap('role')};
                    end

                case 'data_access_attempt'
                    if colMap.isKey('classification') && numel(cols) >= colMap('classification')
                        payload.classification = cols{colMap('classification')};
                    end
                    if colMap.isKey('enclave') && numel(cols) >= colMap('enclave')
                        payload.enclave = cols{colMap('enclave')};
                    end
                    if colMap.isKey('operation') && numel(cols) >= colMap('operation')
                        payload.operation = cols{colMap('operation')};
                    end
                    if colMap.isKey('role') && numel(cols) >= colMap('role')
                        payload.role = cols{colMap('role')};
                    end
            end
        end

    end % methods (Static, Access = private)

end % classdef
