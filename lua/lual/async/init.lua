--- Async Writer Module (Backward Compatibility Layer)
-- This module provides backward compatibility with the original async_writer API
-- while using the new generic async interface under the hood.

local M = {}

-- Import the new generic async interface
local async = require("lual.async.core")

-- Module state for backward compatibility
local _writer_instance = nil
local _error_handler = nil

--- Sets the error handler function for async errors
-- @param handler function Function to call when async errors occur
function M.set_error_handler(handler)
    _error_handler = handler
end

--- Reports an async error (backward compatibility)
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

--- Starts the async writer system
-- @param config table Configuration options
-- @param dispatch_func function Function to call for processing log events
function M.start(config, dispatch_func)
    if _writer_instance then
        _writer_instance:stop()
    end

    -- The config is now passed directly to the generic async interface
    -- which handles both old and new config formats
    _writer_instance = async.new(config)

    -- Start the writer
    if _writer_instance:is_enabled() then
        _writer_instance:start(dispatch_func)
    end
end

--- Sets the dispatch function for async processing
-- @param dispatch_func function Function to call for processing log events
function M.set_dispatch_function(dispatch_func)
    if _writer_instance then
        _writer_instance:start(dispatch_func)
    end
end

--- Stops the async writer system and flushes remaining messages
function M.stop()
    if _writer_instance then
        _writer_instance:stop()
        _writer_instance = nil
    end
end

--- Checks if async mode is enabled
-- @return boolean True if async mode is enabled
function M.is_enabled()
    return _writer_instance and _writer_instance:is_enabled() or false
end

--- Adds a log event to the async queue
-- @param logger table The logger that generated the event
-- @param log_record table The log record to queue
function M.queue_log_event(logger, log_record)
    if not _writer_instance then
        error("Async writer is not started")
    end

    if not _writer_instance:is_enabled() then
        error("Async writer is not enabled")
    end

    -- The dispatch function is now stored in the backend and will be used automatically
    return _writer_instance:submit(logger, log_record, nil)
end

--- Resumes the worker coroutine (backward compatibility)
function M.resume_worker()
    if not _writer_instance then
        return false
    end

    if not _writer_instance:is_enabled() then
        return false
    end

    -- For backward compatibility, trigger the backend to resume if it supports it
    if _writer_instance.backend and _writer_instance.backend.resume_worker then
        return _writer_instance.backend:resume_worker()
    end

    return true
end

--- Flushes all queued log events immediately
function M.flush()
    if not _writer_instance then
        return
    end

    return _writer_instance:flush(5.0)
end

--- Gets current queue statistics
-- @return table Statistics about the async queue (backward compatible format)
function M.get_stats()
    if not _writer_instance then
        return {
            enabled = false,
            queue_size = 0,
            batch_size = 50,
            flush_interval = 1.0,
            worker_status = "not_started",
            last_flush_time = 0,
            max_queue_size = 0,
            overflow_strategy = "unknown",
            queue_overflows = 0,
            worker_restarts = 0
        }
    end

    local stats = _writer_instance:get_stats()
    local backend_stats = stats.backend_stats or {}

    -- Convert to backward compatible format
    return {
        enabled = stats.enabled,
        queue_size = stats.queue_size,
        batch_size = _writer_instance.batch_size,
        flush_interval = _writer_instance.flush_interval,
        worker_status = backend_stats.worker_status or "unknown",
        last_flush_time = backend_stats.last_flush_time or 0,
        max_queue_size = stats.max_queue_size,
        overflow_strategy = stats.overflow_strategy,
        queue_overflows = stats.queue_overflows,
        worker_restarts = backend_stats.worker_restarts or 0
    }
end

--- Resets the async writer (for testing)
function M.reset()
    if _writer_instance then
        _writer_instance:reset()
        _writer_instance = nil
    end
    _error_handler = nil
end

return M
