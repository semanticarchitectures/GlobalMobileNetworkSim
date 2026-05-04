classdef EventCalendar < handle
    % sim.EventCalendar  Binary min-heap event calendar for the DES engine.
    %
    % Stores event structs keyed on event.time (double). The heap maintains
    % the min-heap property: parent.time <= children.time at all times.
    %
    % Event struct fields:
    %   time    (double)  - simulation time in seconds
    %   type    (string)  - event type constant (see EventCalendar.TYPE_*)
    %   id      (uint64)  - unique event identifier
    %   payload (struct)  - type-specific data
    %
    % Requirements: 8.1

    % -----------------------------------------------------------------
    % Event type string constants
    % -----------------------------------------------------------------
    properties (Constant)
        C2_MESSAGE_TX       = "C2_MESSAGE_TX"
        C2_MESSAGE_RX       = "C2_MESSAGE_RX"
        C2_MESSAGE_FAIL     = "C2_MESSAGE_FAIL"
        OUTAGE_START        = "OUTAGE_START"
        OUTAGE_END          = "OUTAGE_END"
        BACKGROUND_REFRESH  = "BACKGROUND_REFRESH"
        AGENT_IDLE_CHECK    = "AGENT_IDLE_CHECK"
        SIM_END             = "SIM_END"
    end

    % -----------------------------------------------------------------
    % Private heap storage
    % -----------------------------------------------------------------
    properties (Access = private)
        heap        % struct array — the heap nodes
        heapSize    % number of valid elements currently in the heap
        capacity    % current allocated capacity
    end

    % -----------------------------------------------------------------
    % Constructor
    % -----------------------------------------------------------------
    methods
        function ec = EventCalendar(initialCapacity)
            % EventCalendar  Construct an empty event calendar.
            %
            %   ec = sim.EventCalendar()
            %   ec = sim.EventCalendar(initialCapacity)
            %
            % initialCapacity (optional, default 64) sets the initial
            % heap array size. The array doubles when capacity is exceeded.

            if nargin < 1
                initialCapacity = 64;
            end
            ec.capacity  = max(1, initialCapacity);
            ec.heapSize  = 0;
            ec.heap      = sim.EventCalendar.makeEmptyEvent(ec.capacity);
        end
    end

    % -----------------------------------------------------------------
    % Public methods
    % -----------------------------------------------------------------
    methods

        function schedule(ec, event)
            % schedule  Insert an event into the heap.
            %
            %   ec.schedule(event)
            %
            % event must be a struct with at least the fields:
            %   time (double), type (string), id (uint64), payload (struct)

            % Grow if needed (double capacity)
            if ec.heapSize >= ec.capacity
                newCap   = ec.capacity * 2;
                newHeap  = sim.EventCalendar.makeEmptyEvent(newCap);
                for k = 1:ec.heapSize
                    newHeap(k) = ec.heap(k);
                end
                ec.heap     = newHeap;
                ec.capacity = newCap;
            end

            % Append at end and sift up
            ec.heapSize          = ec.heapSize + 1;
            ec.heap(ec.heapSize) = event;
            ec.siftUp(ec.heapSize);
        end

        function event = popNext(ec)
            % popNext  Remove and return the event with the smallest time.
            %
            %   event = ec.popNext()
            %
            % Throws an error if the calendar is empty.

            if ec.heapSize == 0
                error('sim:EventCalendar:empty', ...
                    'Cannot pop from an empty EventCalendar.');
            end

            event = ec.heap(1);

            % Move last element to root and sift down
            ec.heap(1)  = ec.heap(ec.heapSize);
            ec.heapSize = ec.heapSize - 1;
            if ec.heapSize > 0
                ec.siftDown(1);
            end
        end

        function tf = isEmpty(ec)
            % isEmpty  Return true if the calendar contains no events.
            %
            %   tf = ec.isEmpty()

            tf = (ec.heapSize == 0);
        end

        function n = eventCount(ec)
            % eventCount  Return the number of events currently in the calendar.
            %
            %   n = ec.eventCount()

            n = ec.heapSize;
        end

        function reschedule(ec, eventId, newTime)
            % reschedule  Update the time of a pending event and restore heap order.
            %
            %   ec.reschedule(eventId, newTime)
            %
            % eventId (uint64) — the id field of the event to update.
            % newTime (double) — the new simulation time for the event.
            %
            % Throws an error if no event with the given id is found.

            % Linear scan to find the event
            idx = 0;
            for k = 1:ec.heapSize
                if ec.heap(k).id == eventId
                    idx = k;
                    break;
                end
            end

            if idx == 0
                error('sim:EventCalendar:notFound', ...
                    'No event with id %d found in the EventCalendar.', eventId);
            end

            oldTime = ec.heap(idx).time;
            ec.heap(idx).time = newTime;

            % Restore heap order
            if newTime < oldTime
                ec.siftUp(idx);
            else
                ec.siftDown(idx);
            end
        end

    end

    % -----------------------------------------------------------------
    % Private heap maintenance methods
    % -----------------------------------------------------------------
    methods (Access = private)

        function siftUp(ec, idx)
            % siftUp  Bubble element at idx up until heap property is restored.

            while idx > 1
                parent = floor(idx / 2);
                if ec.heap(parent).time > ec.heap(idx).time
                    % Swap parent and child
                    tmp             = ec.heap(parent);
                    ec.heap(parent) = ec.heap(idx);
                    ec.heap(idx)    = tmp;
                    idx             = parent;
                else
                    break;
                end
            end
        end

        function siftDown(ec, idx)
            % siftDown  Push element at idx down until heap property is restored.

            while true
                left  = 2 * idx;
                right = 2 * idx + 1;
                smallest = idx;

                if left <= ec.heapSize && ...
                        ec.heap(left).time < ec.heap(smallest).time
                    smallest = left;
                end

                if right <= ec.heapSize && ...
                        ec.heap(right).time < ec.heap(smallest).time
                    smallest = right;
                end

                if smallest ~= idx
                    tmp                  = ec.heap(smallest);
                    ec.heap(smallest)    = ec.heap(idx);
                    ec.heap(idx)         = tmp;
                    idx                  = smallest;
                else
                    break;
                end
            end
        end

    end

    % -----------------------------------------------------------------
    % Static helpers
    % -----------------------------------------------------------------
    methods (Static, Access = private)

        function s = makeEmptyEvent(n)
            % makeEmptyEvent  Pre-allocate a struct array of n event slots.
            %
            % MATLAB requires a concrete struct to replicate; we build one
            % with the canonical event fields and then replicate it.

            proto.time    = 0.0;
            proto.type    = "";
            proto.id      = uint64(0);
            proto.payload = struct();

            s = repmat(proto, n, 1);
        end

    end

end
