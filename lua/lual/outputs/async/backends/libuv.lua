--- libuv-based Async Backend
-- This backend uses libuv's event loop for true async processing.
-- Requires the 'luv' library for libuv bindings.

local M = {}

-- Try to load luv, gracefully handle missing dependency
local luv_ok, uv = pcall(require, "luv")
if not luv_ok then
    error("libuv backend requires 'luv' library. Install with: luarocks install luv")
end

-- High-precision timing using libuv
local function get_time()
    return uv.hrtime() / 1e9 -- Convert nanoseconds to seconds
end

--- Creates a new libuv backend instance
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

        -- libuv-specific state
        timer_handle = nil,
        idle_handle = nil,
        worker_status = "not_started",
        flush_requested = false,
        last_flush_time = 0,
        dispatch_function = nil,

        -- Worker recovery
        worker_restarts = 0,
        max_restarts = 5,
        last_restart_time = 0,
        restart_backoff = 1.0,

        -- Event loop integration
        is_running = false,
        shutdown_requested = false
    }

    setmetatable(backend, { __index = M })
    return backend
end

--- Submits work to the libuv backend
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

    -- Trigger immediate processing if we have work
    if success and self.idle_handle then
        self.idle_handle:start(function() self:process_queue() end)
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

    -- Run the event loop until queue is empty or timeout
    local timeout_timer = uv.new_timer()
    local timeout_reached = false

    timeout_timer:start(math.floor(timeout * 1000), 0, function()
        timeout_reached = true
        timeout_timer:stop()
        timeout_timer:close()
        uv.stop() -- Stop the run loop
    end)

    -- Process until queue is empty or timeout
    while self.queue and not self.queue:is_empty() and not timeout_reached do
        -- Process any pending work
        self:process_queue()

        -- Run event loop for a short time
        uv.run("nowait")

        -- Small yield to prevent tight loop
        if self.queue and not self.queue:is_empty() then
            uv.sleep(1) -- Sleep 1ms
        end
    end

    -- Clean up timeout timer if it hasn't fired
    if not timeout_reached then
        timeout_timer:stop()
        timeout_timer:close()
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

--- Starts the libuv backend
-- @param dispatch_func function Main dispatch function
function M:start(dispatch_func)
    if self.is_running then
        return
    end

    self.dispatch_function = dispatch_func
    self.worker_status = "running"
    self.last_flush_time = get_time()
    self.is_running = true
    self.shutdown_requested = false

    -- Create timer for periodic batch processing
    self.timer_handle = uv.new_timer()
    self.timer_handle:start(
        math.floor(self.flush_interval * 1000), -- Initial delay in ms
        math.floor(self.flush_interval * 1000), -- Repeat interval in ms
        function()
            if not self.shutdown_requested then
                self:process_queue()
            end
        end
    )

    -- Create idle handle for immediate processing when work arrives
    self.idle_handle = uv.new_idle()
    -- Note: idle handle is started on demand in submit()
end

--- Stops the libuv backend
function M:stop()
    if not self.is_running then
        return
    end

    self.shutdown_requested = true

    -- Flush remaining work with timeout
    self:flush(5.0)

    -- Stop and close handles
    if self.timer_handle then
        self.timer_handle:stop()
        self.timer_handle:close()
        self.timer_handle = nil
    end

    if self.idle_handle then
        self.idle_handle:stop()
        self.idle_handle:close()
        self.idle_handle = nil
    end

    self.worker_status = "not_started"
    self.is_running = false
end

--- Gets backend-specific statistics
-- @return table Backend statistics
function M:get_stats()
    return {
        worker_status = self.worker_status,
        worker_restarts = self.worker_restarts,
        last_flush_time = self.last_flush_time,
        flush_interval = self.flush_interval,
        batch_size = self.batch_size,
        is_running = self.is_running,
        libuv_version = uv.version_string()
    }
end

--- Resets the backend (for testing)
function M:reset()
    self:stop()
    self.worker_restarts = 0
    self.last_restart_time = 0
    self.worker_status = "not_started"
    self.flush_requested = false
    self.shutdown_requested = false
end

--- Process the queue in batches
function M:process_queue()
    if not self.queue or self.queue:is_empty() or self.shutdown_requested then
        -- Stop idle handle if no work
        if self.idle_handle then
            self.idle_handle:stop()
        end
        return
    end

    local current_time = get_time()
    local should_process = false

    -- Determine if we should process the queue
    if self.flush_requested then
        should_process = true
        self.flush_requested = false
    elseif self.queue:size() >= self.batch_size then
        should_process = true
    elseif self.queue:size() > 0 and
        (current_time - self.last_flush_time) >= self.flush_interval then
        should_process = true
    end

    if should_process then
        -- Process batch using queue module
        local batch = self.queue:extract_batch(self.batch_size)

        -- Process each record in the batch
        for _, work_item in ipairs(batch) do
            if work_item.dispatch_func then
                local ok, err = pcall(work_item.dispatch_func, work_item.logger, work_item.record)
                if ok then
                    self.stats.messages_processed = self.stats.messages_processed + 1
                else
                    self.stats.backend_errors = self.stats.backend_errors + 1
                    self.error_callback("Error processing log record: " .. tostring(err))
                end
            else
                self.error_callback("No dispatch function in work item")
                self.stats.backend_errors = self.stats.backend_errors + 1
            end
        end

        self.last_flush_time = current_time
    end

    -- Continue processing if there's more work
    if not self.queue:is_empty() and self.idle_handle then
        -- Keep idle handle running for continuous processing
        self.idle_handle:start(function() self:process_queue() end)
    elseif self.idle_handle then
        -- Stop idle handle when done
        self.idle_handle:stop()
    end
end

--- Checks if worker is healthy
-- @return boolean True if worker is healthy
function M:is_worker_healthy()
    return self.is_running and
        self.timer_handle and
        self.idle_handle and
        not self.shutdown_requested
end

--- Restarts the worker
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

    -- Stop current worker
    self:stop()

    -- Restart worker
    if self.dispatch_function then
        self:start(self.dispatch_function)
        self.worker_restarts = self.worker_restarts + 1
        self.last_restart_time = current_time

        self.error_callback(string.format("libuv worker restarted (restart #%d)", self.worker_restarts))
        return true
    else
        self.error_callback("Cannot restart worker: no dispatch function")
        return false
    end
end

return M
