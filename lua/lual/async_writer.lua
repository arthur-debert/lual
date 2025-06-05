--- Async Writer Module
-- This module implements coroutine-based asynchronous logging functionality.
-- It manages a queue for log events and processes them in batches using a worker coroutine.

local M = {}

-- High-precision timing
local socket_ok, socket = pcall(require, "socket")
local function get_time()
    if socket_ok and socket.gettime then
        return socket.gettime() -- Returns microsecond precision (e.g., 1703123456.789)
    else
        -- Fallback for environments without LuaSocket
        return os.time() -- Still works for >= 1 second intervals
    end
end

-- Internal state
local _async_enabled = false
local _async_batch_size = 50
local _async_flush_interval = 1.0
local _log_queue = {}
local _worker_coroutine = nil
local _worker_status = "not_started" -- "not_started", "running", "yielded", "finished", "error"
local _flush_requested = false
local _error_handler = nil
local _last_flush_time = 0
local _dispatch_function = nil

-- Worker recovery state
local _worker_restarts = 0
local _max_restarts = 5
local _last_restart_time = 0
local _restart_backoff = 1.0 -- Seconds between restarts

-- Memory protection
local _max_queue_size = 10000            -- Configurable limit
local _queue_overflows = 0
local _overflow_strategy = "drop_oldest" -- "drop_oldest", "drop_newest", "block"

--- Sets the error handler function for async errors
-- @param handler function Function to call when async errors occur
function M.set_error_handler(handler)
    _error_handler = handler
end

--- Reports an async error
-- @param error_message string The error message
local function report_async_error(error_message)
    if _error_handler then
        local ok, err = pcall(_error_handler, error_message)
        if not ok then
            io.stderr:write(string.format("LUAL ASYNC ERROR (and error handler failed): %s\nHandler error: %s\n",
                error_message, err))
        end
    else
        io.stderr:write(string.format("LUAL ASYNC ERROR: %s\n", error_message))
    end
end

--- Checks if the worker coroutine is healthy
-- @return boolean True if worker is in a good state
local function is_worker_healthy()
    if not _worker_coroutine then
        return false
    end

    local status = coroutine.status(_worker_coroutine)
    return status == "suspended" or status == "running"
end

--- Restarts the worker coroutine with backoff and limits
-- @return boolean True if restart succeeded
local function restart_worker()
    local current_time = get_time()

    -- Implement restart backoff to prevent rapid restart loops
    if (current_time - _last_restart_time) < _restart_backoff then
        report_async_error("Worker restart too soon, backing off")
        return false
    end

    -- Check restart limits
    if _worker_restarts >= _max_restarts then
        report_async_error(string.format(
            "Worker restart limit reached (%d), disabling async logging",
            _max_restarts))
        _async_enabled = false
        return false
    end

    -- Create new worker
    _worker_coroutine = coroutine.create(worker_function)
    _worker_status = "running"
    _last_flush_time = current_time
    _worker_restarts = _worker_restarts + 1
    _last_restart_time = current_time

    report_async_error(string.format(
        "Worker coroutine restarted (restart #%d)", _worker_restarts))

    return true
end

--- Handles queue overflow using the configured strategy
-- @return boolean True if the new message should be added to the queue
local function handle_queue_overflow()
    _queue_overflows = _queue_overflows + 1

    if _overflow_strategy == "drop_oldest" then
        local dropped = table.remove(_log_queue, 1)
        report_async_error(string.format(
            "Queue overflow: dropped oldest message (level=%s, logger=%s)",
            dropped.record.level_name, dropped.logger.name))
    elseif _overflow_strategy == "drop_newest" then
        -- Don't add the new message
        report_async_error("Queue overflow: dropped newest message")
        return false -- Signal not to add
    elseif _overflow_strategy == "block" then
        -- Force immediate flush to make room
        report_async_error("Queue overflow: forcing immediate flush")
        M.flush()
    end

    return true
end

--- Worker coroutine function
local function worker_function()
    while true do
        local current_time = get_time() -- Now has sub-second precision
        local should_process = false

        -- Determine if we should process the queue
        if _flush_requested then
            should_process = true
            _flush_requested = false
        elseif #_log_queue >= _async_batch_size then
            should_process = true
        elseif #_log_queue > 0 and (current_time - _last_flush_time) >= _async_flush_interval then
            should_process = true
        end

        if should_process and #_log_queue > 0 then
            -- Process batch
            local batch_size = math.min(#_log_queue, _async_batch_size)
            local batch = {}

            -- Extract batch from queue
            for i = 1, batch_size do
                table.insert(batch, table.remove(_log_queue, 1))
            end

            -- Process each record in the batch
            for _, log_data in ipairs(batch) do
                local ok, err = pcall(function()
                    if _dispatch_function then
                        _dispatch_function(log_data.logger, log_data.record)
                    else
                        report_async_error("No dispatch function set for async processing")
                    end
                end)
                if not ok then
                    report_async_error("Error processing log record: " .. tostring(err))
                end
            end

            _last_flush_time = current_time -- Update with precise time
        end

        -- Yield control back to the application
        coroutine.yield()
    end
end

--- Starts the async writer system
-- @param config table Configuration options
-- @param dispatch_func function Function to call for processing log events
function M.start(config, dispatch_func)
    config = config or {}

    _async_enabled = config.async_enabled ~= false -- Default to true if not specified
    _async_batch_size = config.async_batch_size or 50
    _async_flush_interval = config.async_flush_interval or 1.0
    _max_queue_size = config.max_queue_size or 10000
    _overflow_strategy = config.overflow_strategy or "drop_oldest"
    _dispatch_function = dispatch_func

    if _async_enabled then
        _log_queue = {}
        _worker_coroutine = coroutine.create(worker_function)
        _worker_status = "running"
        _last_flush_time = get_time() -- Initialize with precise time
    end
end

--- Sets the dispatch function for async processing
-- @param dispatch_func function Function to call for processing log events
function M.set_dispatch_function(dispatch_func)
    _dispatch_function = dispatch_func
end

--- Stops the async writer system and flushes remaining messages
function M.stop()
    if _async_enabled and _worker_coroutine then
        -- Process remaining messages
        M.flush()

        _async_enabled = false
        _worker_coroutine = nil
        _worker_status = "not_started"
        _log_queue = {}
    end
end

--- Checks if async mode is enabled
-- @return boolean True if async mode is enabled
function M.is_enabled()
    return _async_enabled
end

--- Adds a log event to the async queue
-- @param logger table The logger that generated the event
-- @param log_record table The log record to queue
function M.queue_log_event(logger, log_record)
    if not _async_enabled then
        error("Async writer is not enabled")
    end

    -- Health check and auto-recovery
    if not is_worker_healthy() then
        if not restart_worker() then
            -- Fallback to synchronous processing
            report_async_error("Falling back to synchronous processing for this message")
            if _dispatch_function then
                local ok, err = pcall(_dispatch_function, logger, log_record)
                if not ok then
                    report_async_error("Synchronous fallback failed: " .. tostring(err))
                end
            end
            return
        end
    end

    -- Check queue size limit
    if #_log_queue >= _max_queue_size then
        if not handle_queue_overflow() then
            return -- Message dropped
        end
    end

    -- Add to queue
    table.insert(_log_queue, {
        logger = logger,
        record = log_record
    })

    -- Resume worker if it's yielded
    if _worker_coroutine and _worker_status == "yielded" then
        M.resume_worker()
    end
end

--- Resumes the worker coroutine
function M.resume_worker()
    if not _worker_coroutine then
        return false
    end

    local status = coroutine.status(_worker_coroutine)
    if status ~= "suspended" then
        if status == "dead" then
            report_async_error("Attempted to resume dead worker")
            restart_worker()
        end
        return false
    end

    local ok, err = coroutine.resume(_worker_coroutine)
    if not ok then
        _worker_status = "error"
        report_async_error("Worker coroutine error: " .. tostring(err))
        restart_worker()
        return false
    end

    -- Update status based on coroutine state
    local new_status = coroutine.status(_worker_coroutine)
    if new_status == "suspended" then
        _worker_status = "yielded"
    elseif new_status == "dead" then
        _worker_status = "finished"
        report_async_error("Worker coroutine finished unexpectedly")
        restart_worker()
    end

    return true
end

--- Flushes all queued log events immediately
function M.flush()
    if not _async_enabled then
        return -- Nothing to flush if async is not enabled
    end

    _flush_requested = true
    local timeout = 5.0 -- Configurable timeout
    local start_time = get_time()
    local initial_queue_size = #_log_queue
    local last_queue_size = initial_queue_size
    local stall_count = 0

    -- Keep resuming the worker until all messages are processed
    while #_log_queue > 0 and _worker_coroutine and
        coroutine.status(_worker_coroutine) == "suspended" do
        -- Check for overall timeout
        if (get_time() - start_time) >= timeout then
            report_async_error(string.format(
                "Flush timeout after %.2fs: %d of %d messages remain in queue",
                timeout, #_log_queue, initial_queue_size))
            break
        end

        -- Check for progress stall (queue not shrinking)
        if #_log_queue == last_queue_size then
            stall_count = stall_count + 1
            if stall_count >= 10 then -- 10 attempts without progress
                report_async_error(string.format(
                    "Flush stalled: queue size stuck at %d messages", #_log_queue))
                break
            end
        else
            stall_count = 0 -- Reset on progress
            last_queue_size = #_log_queue
        end

        local ok, err = pcall(M.resume_worker)
        if not ok then
            report_async_error("Error during flush resume: " .. tostring(err))
            break
        end
    end

    _flush_requested = false

    -- Report final status
    if #_log_queue > 0 then
        report_async_error(string.format(
            "Flush completed with %d messages remaining", #_log_queue))
    end
end

--- Gets current queue statistics
-- @return table Statistics about the async queue
function M.get_stats()
    return {
        enabled = _async_enabled,
        queue_size = #_log_queue,
        batch_size = _async_batch_size,
        flush_interval = _async_flush_interval,
        worker_status = _worker_status,
        last_flush_time = _last_flush_time,
        max_queue_size = _max_queue_size,
        overflow_strategy = _overflow_strategy,
        queue_overflows = _queue_overflows,
        worker_restarts = _worker_restarts
    }
end

--- Resets the async writer (for testing)
function M.reset()
    M.stop()
    _async_enabled = false
    _async_batch_size = 50
    _async_flush_interval = 1.0
    _log_queue = {}
    _worker_coroutine = nil
    _worker_status = "not_started"
    _flush_requested = false
    _error_handler = nil
    _last_flush_time = 0
    _dispatch_function = nil

    -- Reset worker recovery state
    _worker_restarts = 0
    _last_restart_time = 0

    -- Reset memory protection state
    _max_queue_size = 10000
    _queue_overflows = 0
    _overflow_strategy = "drop_oldest"
end

return M
