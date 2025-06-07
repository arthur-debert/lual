-- Log Module
-- This module serves as the API namespace for log-related functionality

-- Note: For direct execution with 'lua', use require("lua.lual.*")
-- For LuaRocks installed modules or busted tests, use require("lual.*")
local log_record = require("lual.log.log_record")

-- Export the log module
local M = {
    -- Export the log record functions
    create_log_record = log_record.create_log_record,
    process_log_record = log_record.process_log_record,
    parse_log_args = log_record.parse_log_args,
    format_message = log_record.format_message,

    -- Expose internal functions needed by other modules
    _process_pipeline = log_record._process_pipeline,
    _process_output = log_record._process_output
}

return M
