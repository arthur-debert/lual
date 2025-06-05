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
    if success and self.idle_handle and not self.idle_handle:is_active() then
        local ok, err = pcall(function()
            self.idle_handle:start(function()
                local process_ok, process_err = pcall(self.process_queue, self)
                if not process_ok then
                    self.error_callback("Idle callback error: " .. tostring(process_err))
                end
            end)
        end)
        if not ok then
            self.error_callback("Failed to start idle handle: " .. tostring(err))
        end
    end

    return success
end

--- Flushes all pending work with timeout
-- @param timeout number Timeout in seconds
-- @return boolean True if flushed successfully
function M:flush(timeout)
    if not self.queue then
        return true
    end

    self.flush_requested = true
    local start_time = get_time()
    local initial_queue_size = self.queue:size()

    -- If queue is already empty, return immediately
    if initial_queue_size == 0 then
        self.flush_requested = false
        return true
    end

    -- Process all pending work immediately
    while not self.queue:is_empty() do
        -- Check timeout
        if (get_time() - start_time) >= timeout then
            self.error_callback(string.format(
                "Flush timeout after %.2fs: %d of %d messages remain in queue",
                timeout, self.queue:size(), initial_queue_size))
            break
        end

        -- Process the queue
        self:process_queue()

        -- If queue is still not empty after processing, something is wrong
        if not self.queue:is_empty() then
            -- Small delay to prevent tight loop, but much shorter than before
            if uv.sleep then
                uv.sleep(1) -- 1ms delay
            end
        end
    end

    self.flush_requested = false

    -- Report final status
    if not self.queue:is_empty() then
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
    if self.timer_handle then
        local ok, err = pcall(function()
            self.timer_handle:start(
                math.floor(self.flush_interval * 1000), -- Initial delay in ms
                math.floor(self.flush_interval * 1000), -- Repeat interval in ms
                function()
                    if not self.shutdown_requested then
                        local process_ok, process_err = pcall(self.process_queue, self)
                        if not process_ok then
                            self.error_callback("Timer callback error: " .. tostring(process_err))
                        end
                    end
                end
            )
        end)
        if not ok then
            self.error_callback("Failed to start timer: " .. tostring(err))
            self.timer_handle = nil
        end
    end

    -- Create idle handle for immediate processing when work arrives
    self.idle_handle = uv.new_idle()
    if not self.idle_handle then
        self.error_callback("Failed to create idle handle")
    end
    -- Note: idle handle is started on demand in submit()
end

--- Stops the libuv backend
function M:stop()
    if not self.is_running then
        return
    end

    self.shutdown_requested = true

    -- Flush remaining work with timeout (balanced for responsiveness and robustness)
    self:flush(1.0)

    -- Stop and close handles
    if self.timer_handle then
        local ok, err = pcall(self.timer_handle.stop, self.timer_handle)
        if not ok then
            self.error_callback("Failed to stop timer: " .. tostring(err))
        end
        ok, err = pcall(self.timer_handle.close, self.timer_handle)
        if not ok then
            self.error_callback("Failed to close timer: " .. tostring(err))
        end
        self.timer_handle = nil
    end

    if self.idle_handle then
        local ok, err = pcall(self.idle_handle.stop, self.idle_handle)
        if not ok then
            self.error_callback("Failed to stop idle handle: " .. tostring(err))
        end
        ok, err = pcall(self.idle_handle.close, self.idle_handle)
        if not ok then
            self.error_callback("Failed to close idle handle: " .. tostring(err))
        end
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
        if self.idle_handle and self.idle_handle:is_active() then
            local ok, err = pcall(self.idle_handle.stop, self.idle_handle)
            if not ok then
                self.error_callback("Failed to stop idle handle: " .. tostring(err))
            end
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
    if not self.queue:is_empty() and self.idle_handle and not self.idle_handle:is_active() then
        -- Start idle handle for continuous processing
        local ok, err = pcall(function()
            self.idle_handle:start(function()
                local process_ok, process_err = pcall(self.process_queue, self)
                if not process_ok then
                    self.error_callback("Idle callback error: " .. tostring(process_err))
                end
            end)
        end)
        if not ok then
            self.error_callback("Failed to start idle handle: " .. tostring(err))
        end
    elseif self.queue:is_empty() and self.idle_handle and self.idle_handle:is_active() then
        -- Stop idle handle when done
        local ok, err = pcall(self.idle_handle.stop, self.idle_handle)
        if not ok then
            self.error_callback("Failed to stop idle handle: " .. tostring(err))
        end
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
