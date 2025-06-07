--- Pipeline Module
-- This module implements the pipeline logic for log processing
--
-- Pipeline Structure:
--
-- Pipelines replace the previous direct outputs configuration. Each pipeline includes:
-- 1. A level threshold (when to activate the pipeline)
-- 2. One or more outputs (where to send the log)
-- 3. A presenter configuration (how to format the log)
-- 4. Optional transformers (how to modify the log data)
--
-- During the dispatch process, a logger iterates through its pipelines and checks each
-- pipeline's level threshold against the log event level. If the threshold is met,
-- the pipeline processes the event through its transformers, presenter, and outputs.
--
-- Usage example:
--
--   lual.config({
--     level = lual.DEBUG,  -- Root level is DEBUG
--     pipelines = {
--       {
--         level = lual.DEBUG,  -- Pipeline processes DEBUG and above
--         outputs = {
--           { type = lual.file, path = "app.log" }
--         },
--         presenter = { type = lual.json }
--       },
--       {
--         level = lual.WARNING,  -- Pipeline processes WARNING and above
--         outputs = {
--           { type = lual.console }
--         },
--         presenter = { type = lual.text }
--       }
--     }
--   })

local core_levels = require("lua.lual.levels")
local all_presenters = require("lual.pipelines.presenters.init")
local all_transformers = require("lual.pipelines.transformers.init")
local component_utils = require("lual.utils.component")
local async_writer = require("lual.async")
local log_module = require("lual.log")
local process = require("lual.log.process")

local M = {}

--- Implements the pipeline dispatch logic
-- This is the core of event processing for each logger L in the hierarchy
-- @param source_logger table The logger that originated the log event
-- @param log_record table The log record to process
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

--- Sets up the async writer with the dispatch function
-- This is called when async mode is enabled to provide the dispatch function
function M.setup_async_writer()
    -- Set the dispatch function for async processing
    async_writer.set_dispatch_function(log_module.process_log_record)
end

-- @return table Table of logging methods
function M.create_logging_methods()
    local methods = {}

    -- Helper function to create a log method for a specific level
    local function create_log_method(level_no, level_name)
        return function(self, ...)
            -- Check if logging is enabled for this level
            local effective_level = self:_get_effective_level()
            if level_no < effective_level then
                return -- Early exit if level not enabled
            end

            -- Parse arguments
            local msg_fmt, args, context = log_module.parse_log_args(...)

            -- Create log record
            local log_record = log_module.create_log_record(self, level_no, level_name, msg_fmt, args, context)

            M.dispatch_log_event(self, log_record)
        end
    end

    -- Create methods for each log level
    methods.debug = create_log_method(core_levels.definition.DEBUG, "DEBUG")
    methods.info = create_log_method(core_levels.definition.INFO, "INFO")
    methods.warn = create_log_method(core_levels.definition.WARNING, "WARNING")
    methods.error = create_log_method(core_levels.definition.ERROR, "ERROR")
    methods.critical = create_log_method(core_levels.definition.CRITICAL, "CRITICAL")

    -- Generic log method
    methods.log = function(self, level_arg, ...)
        local level_no
        local level_name

        -- Handle both numeric levels and custom level names
        if type(level_arg) == "number" then
            level_no = level_arg
            level_name = core_levels.get_level_name(level_no)
        elseif type(level_arg) == "string" then
            -- Check if it's a custom level name
            local custom_level_value = core_levels.get_custom_level_value(level_arg)
            if custom_level_value then
                level_no = custom_level_value
                level_name = level_arg:upper()
            else
                error("Unknown level name: " .. level_arg)
            end
        else
            error("Log level must be a number or string, got " .. type(level_arg))
        end

        -- Check if logging is enabled for this level
        local effective_level = self:_get_effective_level()
        if level_no < effective_level then
            return -- Early exit if level not enabled
        end

        -- Parse arguments
        local msg_fmt, args, context = log_module.parse_log_args(...)

        -- Create log record
        local log_record = log_module.create_log_record(self, level_no, level_name, msg_fmt, args, context)
        M.dispatch_log_event(self, log_record)
    end

    return methods
end

-- Expose internal functions for testing
M._create_log_record = log_module.create_log_record
M._process_pipeline = function(log_record, pipeline, logger)
    -- Wrap in a compatible format for the new process_pipeline function
    local pipeline_entry = {
        pipeline = pipeline,
        logger = logger
    }
    return process.process_pipeline(log_record, pipeline_entry)
end
M._process_output = log_module._process_output
M._format_message = log_module.format_message
M._parse_log_args = log_module.parse_log_args

return M
