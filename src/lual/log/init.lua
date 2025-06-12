-- Log Module
-- This module serves as the API namespace for log-related functionality

-- Note: For direct execution with 'lua', use require("lual.*")
-- For LuaRocks installed modules or busted tests, use require("lual.*")
local log_record = require("lual.log.log_record")
local get_logger_tree = require("lual.log.get_logger_tree")
local get_pipelines = require("lual.log.get_pipelines")
local process = require("lual.log.process")

-- Export the log module
local M = {
    -- Export the log record functions
    create_log_record = log_record.create_log_record,
    process_log_record = log_record.process_log_record,
    parse_log_args = log_record.parse_log_args,
    format_message = log_record.format_message,

    -- Export the logger tree functions
    get_logger_tree = get_logger_tree.get_logger_tree,

    -- Export the pipeline filter functions
    get_eligible_pipelines = get_pipelines.get_eligible_pipelines,

    -- Export the pipeline processing functions
    process_pipeline = process.process_pipeline,
    process_pipelines = process.process_pipelines,

    -- Expose internal functions needed by other modules
    _process_pipeline = log_record._process_pipeline,
    _process_output = log_record._process_output
}

return M
