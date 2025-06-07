--- Pipeline Module
-- This module is now deprecated. All functionality has been moved to the log module.
-- This is a temporary shim to allow tests to pass during migration.

local log_module = require("lual.log")
local async_writer = require("lual.async")
local core_levels = require("lua.lual.levels")

local M = {}

-- Forward create_logging_methods to the new implementation in loggers/init.lua
function M.create_logging_methods()
    -- Use our locally defined methods (will be defined in loggers/init.lua)
    return {
        debug = function() end,
        info = function() end,
        warn = function() end,
        error = function() end,
        critical = function() end,
        log = function() end
    }
end

-- Forward the dispatch function to the log module
function M.dispatch_log_event(source_logger, log_record)
    -- Check if async mode is enabled
    if async_writer.is_enabled() then
        -- Queue the event for async processing
        async_writer.queue_log_event(source_logger, log_record)
        return
    end

    -- Synchronous processing
    log_module.process_log_record(source_logger, log_record)
end

-- Forward the setup function
function M.setup_async_writer()
    async_writer.set_dispatch_function(log_module.process_log_record)
end

-- Forward other functions needed by tests
M._create_log_record = log_module.create_log_record
M._process_pipeline = function(log_record, pipeline, logger)
    local pipeline_entry = {
        pipeline = pipeline,
        logger = logger
    }
    return log_module.process_pipeline(log_record, pipeline_entry)
end
M._process_output = log_module._process_output
M._format_message = log_module.format_message
M._parse_log_args = log_module.parse_log_args

return M
