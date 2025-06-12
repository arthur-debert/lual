--- Coroutine-based Async Backend
-- This backend uses Lua coroutines for async processing.
-- Note: Still subject to I/O blocking limitations.

local M = {}

-- High-precision timing
local socket_ok, socket = pcall(require, "socket")
local function get_time()
    if socket_ok and socket.gettime then
        return socket.gettime()
    else
        return os.time()
    end
end

--- Creates a new coroutine backend instance
-- @param config table Backend configuration
-- @return table Backend instance
function M.new(config)
    local backend = {
        -- Configuration
        batch_size = config.batch_size or 50,
        flush_interval = config.flush_interval or 1.0,
        queue = config.queue,
        stats = config.stats,
        error_callback = config.error_callback or function() end,

        -- Coroutine-specific state
        worker_coroutine = nil,
        worker_status = "not_started",
        flush_requested = false,
        last_flush_time = 0,
        dispatch_function = nil,

        -- Worker recovery
        worker_restarts = 0,
        max_restarts = 5,
        last_restart_time = 0,
        restart_backoff = 1.0
    }

    setmetatable(backend, { __index = M })
    return backend
end

--- Submits work to the coroutine backend
-- @param work_item table Work item containing logger, record, and dispatch_func
function M:submit(work_item)
    -- Health check and auto-recovery
    if not self:is_worker_healthy() then
        if not self:restart_worker() then
            -- Fallback to synchronous processing
            self.error_callback("Falling back to synchronous processing")
            if work_item.dispatch_func then
                local ok, err = pcall(work_item.dispatch_func, work_item.logger, work_item.record)
                if not ok then
                    self.error_callback("Synchronous fallback failed: " .. tostring(err))
                end
            end
            return false
        end
    end

    -- Add to queue (overflow handled by queue module)
    local success = self.queue:enqueue(work_item)
    if not success then
        self.stats.messages_dropped = self.stats.messages_dropped + 1
    end

    -- Resume worker if it's yielded
    if self.worker_coroutine and self.worker_status == "yielded" then
        self:resume_worker()
    end

    return success
end

--- Flushes all pending work with timeout
-- @param timeout number Timeout in seconds
-- @return boolean True if flushed successfully
function M:flush(timeout)
    self.flush_requested = true
    local start_time = get_time()
    local initial_queue_size = self.queue and self.queue:size() or 0
    local last_queue_size = initial_queue_size
    local stall_count = 0

    -- Keep resuming the worker until all messages are processed
    while self.queue and not self.queue:is_empty() and self.worker_coroutine and
        coroutine.status(self.worker_coroutine) == "suspended" do
        -- Check for overall timeout
        if (get_time() - start_time) >= timeout then
            self.error_callback(string.format(
                "Flush timeout after %.2fs: %d of %d messages remain in queue",
                timeout, self.queue:size(), initial_queue_size))
            break
        end

        -- Check for progress stall
        local current_queue_size = self.queue:size()
        if current_queue_size == last_queue_size then
            stall_count = stall_count + 1
            if stall_count >= 10 then
                self.error_callback(string.format(
                    "Flush stalled: queue size stuck at %d messages", current_queue_size))
                break
            end
        else
            stall_count = 0
            last_queue_size = current_queue_size
        end

        local ok, err = pcall(self.resume_worker, self)
        if not ok then
            self.error_callback("Error during flush resume: " .. tostring(err))
            break
        end
    end

    self.flush_requested = false

    -- Report final status
    if self.queue and not self.queue:is_empty() then
        self.error_callback(string.format(
            "Flush completed with %d messages remaining", self.queue:size()))
        return false
    end

    return true
end

--- Starts the coroutine backend
-- @param dispatch_func function Main dispatch function
function M:start(dispatch_func)
    self.dispatch_function = dispatch_func
    self.worker_coroutine = coroutine.create(function() self:worker_function() end)
    self.worker_status = "running"
    self.last_flush_time = get_time()
end

--- Stops the coroutine backend
function M:stop()
    if self.worker_coroutine then
        self:flush(5.0) -- Flush with 5 second timeout
        self.worker_coroutine = nil
        self.worker_status = "not_started"
    end
end

--- Gets backend-specific statistics
-- @return table Backend statistics
function M:get_stats()
    return {
        worker_status = self.worker_status,
        worker_restarts = self.worker_restarts,
        last_flush_time = self.last_flush_time,
        flush_interval = self.flush_interval,
        batch_size = self.batch_size
    }
end

--- Resets the backend (for testing)
function M:reset()
    self:stop()
    self.worker_restarts = 0
    self.last_restart_time = 0
    self.worker_status = "not_started"
end

--- Worker coroutine main function
function M:worker_function()
    while true do
        local current_time = get_time()
        local should_process = false

        -- Determine if we should process the queue
        if self.flush_requested then
            should_process = true
            self.flush_requested = false
        elseif self.queue and self.queue:size() >= self.batch_size then
            should_process = true
        elseif self.queue and self.queue:size() > 0 and
            (current_time - self.last_flush_time) >= self.flush_interval then
            should_process = true
        end

        if should_process and self.queue and not self.queue:is_empty() then
            -- Process batch using queue module
            local batch = self.queue:extract_batch(self.batch_size)

            -- Process each record in the batch
            for _, work_item in ipairs(batch) do
                local ok, err = pcall(function()
                    if work_item.dispatch_func then
                        work_item.dispatch_func(work_item.logger, work_item.record)
                        self.stats.messages_processed = self.stats.messages_processed + 1
                    else
                        self.error_callback("No dispatch function in work item")
                    end
                end)
                if not ok then
                    self.stats.backend_errors = self.stats.backend_errors + 1
                    self.error_callback("Error processing log record: " .. tostring(err))
                end
            end

            self.last_flush_time = current_time
        end

        -- Yield control back to the application
        coroutine.yield()
    end
end

--- Checks if worker is healthy
-- @return boolean True if worker is healthy
function M:is_worker_healthy()
    if not self.worker_coroutine then
        return false
    end
    local status = coroutine.status(self.worker_coroutine)
    return status == "suspended" or status == "running"
end

--- Restarts the worker coroutine
-- @return boolean True if restart succeeded
function M:restart_worker()
    local current_time = get_time()

    -- Implement restart backoff
    if (current_time - self.last_restart_time) < self.restart_backoff then
        self.error_callback("Worker restart too soon, backing off")
        return false
    end

    -- Check restart limits
    if self.worker_restarts >= self.max_restarts then
        self.error_callback(string.format(
            "Worker restart limit reached (%d)", self.max_restarts))
        return false
    end

    -- Create new worker
    self.worker_coroutine = coroutine.create(function() self:worker_function() end)
    self.worker_status = "running"
    self.last_flush_time = current_time
    self.worker_restarts = self.worker_restarts + 1
    self.last_restart_time = current_time

    self.error_callback(string.format("Worker coroutine restarted (restart #%d)", self.worker_restarts))
    return true
end

--- Resumes the worker coroutine
-- @return boolean True if resume succeeded
function M:resume_worker()
    if not self.worker_coroutine then
        return false
    end

    local status = coroutine.status(self.worker_coroutine)
    if status ~= "suspended" then
        if status == "dead" then
            self.error_callback("Attempted to resume dead worker")
            self:restart_worker()
        end
        return false
    end

    local ok, err = coroutine.resume(self.worker_coroutine)
    if not ok then
        self.worker_status = "error"
        self.error_callback("Worker coroutine error: " .. tostring(err))
        self:restart_worker()
        return false
    end

    -- Update status
    local new_status = coroutine.status(self.worker_coroutine)
    if new_status == "suspended" then
        self.worker_status = "yielded"
    elseif new_status == "dead" then
        self.worker_status = "finished"
        self.error_callback("Worker coroutine finished unexpectedly")
        self:restart_worker()
    end

    return true
end

return M
