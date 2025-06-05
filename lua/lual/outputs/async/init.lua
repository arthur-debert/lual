--- Generic Async Output Interface
-- This module provides a pluggable async interface that can work with different backends
-- (coroutines, libuv, lanes, etc.) while providing a consistent API.

local M = {}

-- Import shared utilities
local queue_module = require("lual.utils.queue")

-- Available backends
local BACKENDS = {
    coroutines = "lual.outputs.async.backends.coroutines"
}

--- Creates a new async writer with the specified backend
-- @param config table Configuration options including backend selection
-- @return table Async writer instance
function M.new(config)
    config = config or {}

    -- Select backend
    local backend_name = config.backend or "coroutines"
    local backend_module_path = BACKENDS[backend_name]

    if not backend_module_path then
        local available = {}
        for k in pairs(BACKENDS) do
            table.insert(available, k)
        end
        error("Unsupported async backend: " .. tostring(backend_name) ..
            ". Available backends: " .. table.concat(available, ", "))
    end

    -- Load the backend module
    local backend_module = require(backend_module_path)

    -- Create the async writer instance
    local writer = {
        -- Configuration
        backend_name = backend_name,
        batch_size = config.async_batch_size or 50,
        flush_interval = config.async_flush_interval or 1.0,
        enabled = config.async_enabled ~= false,

        -- Backend instance
        backend = nil,

        -- Shared queue for all backends
        queue = queue_module.new({
            max_size = config.max_queue_size or 10000,
            overflow_strategy = config.overflow_strategy or "drop_oldest",
            error_callback = function(msg)
                M._report_error("Queue: " .. msg)
            end
        }),

        -- Generic statistics
        stats = {
            messages_submitted = 0,
            messages_processed = 0,
            messages_dropped = 0,
            backend_errors = 0,
            start_time = os.time()
        }
    }

    -- Initialize backend
    if writer.enabled then
        writer.backend = backend_module.new({
            batch_size = writer.batch_size,
            flush_interval = writer.flush_interval,
            queue = writer.queue,
            stats = writer.stats,
            error_callback = M._report_error
        })
    end

    -- Add methods to the writer instance
    setmetatable(writer, { __index = M })

    return writer
end

--- Generic method to submit work for async processing
-- @param logger table The logger instance
-- @param log_record table The log record to process
-- @param dispatch_func function Optional function to process the log record (uses stored function if nil)
function M:submit(logger, log_record, dispatch_func)
    if not self.enabled then
        error("Async writer is not enabled")
    end

    self.stats.messages_submitted = self.stats.messages_submitted + 1

    -- Use stored dispatch function if none provided
    local actual_dispatch_func = dispatch_func or self.dispatch_function

    -- Create work item
    local work_item = {
        logger = logger,
        record = log_record,
        dispatch_func = actual_dispatch_func,
        submitted_at = os.time()
    }

    -- Submit to backend
    if self.backend then
        return self.backend:submit(work_item)
    else
        error("Backend not initialized")
    end
end

--- Generic flush method with timeout
-- @param timeout number Optional timeout in seconds (default: 5.0)
-- @return boolean True if all items were flushed, false if timeout occurred
function M:flush(timeout)
    if not self.enabled then
        return true -- Nothing to flush
    end

    if self.backend then
        return self.backend:flush(timeout or 5.0)
    end

    return true
end

--- Starts the async writer system
-- @param dispatch_func function The main dispatch function for processing log records
function M:start(dispatch_func)
    if not self.enabled then
        return
    end

    -- Store the dispatch function for use in submit
    self.dispatch_function = dispatch_func

    if self.backend then
        return self.backend:start(dispatch_func)
    end
end

--- Stops the async writer system
function M:stop()
    if self.backend then
        self.backend:stop()
    end
end

--- Gets comprehensive statistics from both generic and backend layers
-- @return table Combined statistics
function M:get_stats()
    local backend_stats = {}
    if self.backend and self.backend.get_stats then
        backend_stats = self.backend:get_stats()
    end

    local queue_stats = self.queue and self.queue:stats() or {}

    return {
        -- Generic stats
        enabled = self.enabled,
        backend = self.backend_name,
        messages_submitted = self.stats.messages_submitted,
        messages_processed = self.stats.messages_processed,
        messages_dropped = self.stats.messages_dropped,
        backend_errors = self.stats.backend_errors,
        uptime = os.time() - self.stats.start_time,

        -- Queue stats
        queue_size = queue_stats.size or 0,
        max_queue_size = queue_stats.max_size or 0,
        queue_overflows = queue_stats.overflows or 0,
        overflow_strategy = queue_stats.overflow_strategy or "unknown",

        -- Backend-specific stats
        backend_stats = backend_stats
    }
end

--- Checks if async processing is enabled
-- @return boolean True if enabled
function M:is_enabled()
    return self.enabled
end

--- Resets the async writer (for testing)
function M:reset()
    self:stop()

    if self.queue then
        self.queue:reset()
    end

    -- Reset stats
    self.stats = {
        messages_submitted = 0,
        messages_processed = 0,
        messages_dropped = 0,
        backend_errors = 0,
        start_time = os.time()
    }

    if self.backend and self.backend.reset then
        self.backend:reset()
    end
end

--- Internal error reporting function
-- @param message string Error message
function M._report_error(message)
    -- This could be enhanced to use a proper error handler
    io.stderr:write(string.format("ASYNC ERROR: %s\n", message))
end

return M
