classdef EventArchiver < handle
    % EVENTARCHIVER Buffered event sink that flushes to a SimulationStore.
    %
    % Buffers simulation events in memory and flushes them to the
    % SimulationStore when either the event count reaches the configured
    % threshold or the simulation time interval since the last flush
    % exceeds the configured limit.
    %
    % Usage:
    %   store = data.SimulationStore('data/archive.h5');
    %   archiver = data.EventArchiver(store, "run-uuid-1");
    %   archiver.archive(eventStruct);
    %   archiver.finalize();
    %
    % Requirements: R26

    properties (SetAccess = private)
        eventsArchived (1,1) uint64 = uint64(0)
        eventsLost     (1,1) uint64 = uint64(0)
    end

    properties (Access = private)
        Store           % data.SimulationStore handle
        RunId    (1,1) string
        FlushEventThreshold (1,1) double = 1000
        FlushTimeIntervalSec (1,1) double = 60
        Buffer          % struct array of buffered events
        BufferCount (1,1) double = 0
        LastFlushSimTime (1,1) double = 0
    end

    methods
        function obj = EventArchiver(store, runId, config)
            % EVENTARCHIVER Construct an EventArchiver instance.
            %
            % Args:
            %   store (data.SimulationStore): Handle to the archive store.
            %   runId (string): Unique run identifier for this simulation.
            %   config (struct, optional): Configuration with fields:
            %       flushEventThreshold (double) - flush after N events (default 1000)
            %       flushTimeIntervalSec (double) - flush after N sim seconds (default 60)

            arguments
                store
                runId (1,1) string
                config (1,1) struct = struct()
            end

            obj.Store = store;
            obj.RunId = runId;

            if isfield(config, 'flushEventThreshold')
                obj.FlushEventThreshold = config.flushEventThreshold;
            end
            if isfield(config, 'flushTimeIntervalSec')
                obj.FlushTimeIntervalSec = config.flushTimeIntervalSec;
            end

            % Initialize empty buffer
            obj.Buffer = struct([]);
            obj.BufferCount = 0;
            obj.LastFlushSimTime = 0;
        end

        function archive(obj, event)
            % ARCHIVE Buffer a single event struct.
            %
            % Appends the event to the internal buffer. Automatically
            % triggers a flush when the buffer reaches the configured
            % event threshold OR when the event's simTimeSec exceeds
            % the last flush time by the configured time interval.
            %
            % Args:
            %   event (struct): Event struct with fields such as eventId,
            %       simTimeSec, eventType, linkId, msgId, srcNodeId,
            %       dstNodeId, latencyMs, reason.

            arguments
                obj
                event (1,1) struct
            end

            % Append event to buffer
            obj.BufferCount = obj.BufferCount + 1;
            if obj.BufferCount == 1
                obj.Buffer = event;
            else
                obj.Buffer(obj.BufferCount) = event;
            end

            % Check flush conditions
            shouldFlush = false;

            % Condition 1: buffer size reached threshold
            if obj.BufferCount >= obj.FlushEventThreshold
                shouldFlush = true;
            end

            % Condition 2: simulation time interval exceeded
            if isfield(event, 'simTimeSec') && ...
                    (event.simTimeSec - obj.LastFlushSimTime) >= obj.FlushTimeIntervalSec
                shouldFlush = true;
            end

            if shouldFlush
                obj.flush();
            end
        end

        function flush(obj)
            % FLUSH Write all buffered events to the SimulationStore.
            %
            % Writes the buffer contents via store.writeEvents(runId, buffer)
            % and clears the buffer. If the write fails (e.g., disk full),
            % logs a warning with the run ID and events-lost count but does
            % NOT halt or error.

            if obj.BufferCount == 0
                return;
            end

            eventsToWrite = obj.Buffer;
            numEvents = obj.BufferCount;

            % Record the last event's simTimeSec for time-interval tracking
            if isfield(eventsToWrite, 'simTimeSec') && numEvents > 0
                obj.LastFlushSimTime = eventsToWrite(numEvents).simTimeSec;
            end

            % Clear buffer before write (so new events during write are buffered)
            obj.Buffer = struct([]);
            obj.BufferCount = 0;

            try
                obj.Store.writeEvents(obj.RunId, eventsToWrite);
                obj.eventsArchived = obj.eventsArchived + uint64(numEvents);
            catch ME
                % Log warning but do NOT halt the simulation
                obj.eventsLost = obj.eventsLost + uint64(numEvents);
                warning('netsim:data:flushFailed', ...
                    'EventArchiver flush failed for run "%s": %d events lost. Reason: %s', ...
                    obj.RunId, numEvents, ME.message);
            end
        end

        function finalize(obj)
            % FINALIZE Flush any remaining buffered events.
            %
            % Called at simulation end to ensure all events are written
            % to the store.

            obj.flush();
        end
    end
end
