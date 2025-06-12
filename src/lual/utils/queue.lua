--- Queue Module
-- This module implements a high-performance circular buffer queue with overflow protection.
-- It supports configurable overflow strategies and provides O(1) operations for enqueue/dequeue.

local M = {}

--- Creates a new queue instance
-- @param config table Configuration options
-- @return table Queue instance
function M.new(config)
    config = config or {}

    local queue = {
        -- Queue state
        _items = {},
        _start = 1,
        _end = 0,

        -- Configuration
        _max_size = config.max_size or 1024,
        _overflow_strategy = config.overflow_strategy or "drop_oldest",
        _error_callback = config.error_callback,

        -- Statistics
        _overflows = 0
    }

    --- Gets the current queue size
    -- @return number Current number of items in queue
    function queue.size(self)
        return self._end - self._start + 1
    end

    --- Checks if the queue is empty
    -- @return boolean True if queue is empty
    function queue.is_empty(self)
        return self._start > self._end
    end

    function queue.is_full(self)
        return self:size() >= self._max_size
    end

    function queue.capacity(self)
        return self._max_size
    end

    --- Gets the overflow count
    -- @return number Number of overflow events that have occurred
    function queue.overflow_count(self)
        return self._overflows
    end

    --- Gets queue statistics
    -- @return table Statistics about the queue
    function queue.stats(self)
        return {
            size = self:size(),
            max_size = self._max_size,
            overflow_strategy = self._overflow_strategy,
            overflows = self._overflows,
            is_empty = self:is_empty()
        }
    end

    --- Handles queue overflow using the configured strategy
    -- @return boolean True if the new item should be added to the queue
    local function handle_overflow(self)
        self._overflows = self._overflows + 1

        if self._overflow_strategy == "drop_oldest" then
            local dropped = self._items[self._start]
            self._items[self._start] = nil -- Allow GC
            self._start = self._start + 1

            if self._error_callback then
                self._error_callback("Queue overflow: dropped oldest item")
            end

            return true -- Add the new item
        elseif self._overflow_strategy == "drop_newest" then
            if self._error_callback then
                self._error_callback("Queue overflow: dropped newest item")
            end
            return false -- Don't add the new item
        elseif self._overflow_strategy == "block" then
            if self._error_callback then
                self._error_callback("Queue overflow: blocking not implemented in queue module")
            end
            return false -- Don't add the new item
        elseif self._overflow_strategy == "error" then
            error("Queue: Queue overflow")
        end

        return true
    end

    --- Adds an item to the queue
    -- @param item any The item to add
    -- @return boolean True if item was added, false if dropped due to overflow
    function queue.enqueue(self, item)
        -- Check size limit
        if self:size() >= self._max_size then
            if not handle_overflow(self) then
                return false -- Item dropped
            end
        end

        -- Add to circular buffer
        self._end = self._end + 1
        self._items[self._end] = item

        return true
    end

    --- Removes and returns an item from the front of the queue
    -- @return any The item from the front of the queue, or nil if empty
    function queue.dequeue(self)
        if self:is_empty() then
            return nil
        end

        local item = self._items[self._start]
        self._items[self._start] = nil -- Allow GC
        self._start = self._start + 1

        -- Reset indices when queue is empty for efficiency
        if self._start > self._end then
            self._start = 1
            self._end = 0
        end

        return item
    end

    -- Alias for backwards compatibility or stylistic preference
    queue.push = queue.enqueue
    queue.pop = queue.dequeue

    --- Extracts a batch of items from the queue efficiently
    -- @param batch_size number Maximum number of items to extract
    -- @return table Array of items
    function queue.extract_batch(self, batch_size)
        local available = self:size()
        local actual_batch_size = math.min(available, batch_size)
        local batch = {}

        for i = 1, actual_batch_size do
            table.insert(batch, self._items[self._start])
            self._items[self._start] = nil -- Allow GC
            self._start = self._start + 1
        end

        -- Reset indices when queue is empty
        if self._start > self._end then
            self._start = 1
            self._end = 0
        end

        return batch
    end

    --- Peeks at the front item without removing it
    -- @return any The front item, or nil if empty
    function queue.peek(self)
        if self:is_empty() then
            return nil
        end
        return self._items[self._start]
    end

    --- Clears all items from the queue
    function queue.clear(self)
        self._items = {}
        self._start = 1
        self._end = 0
    end

    --- Resets the queue to initial state
    function queue.reset(self)
        self:clear()
        self._overflows = 0
    end

    return queue
end

return M
