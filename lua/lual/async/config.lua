--- Async Configuration Handler
-- This module handles the 'async' configuration key

-- Note: For direct execution with 'lua', use require("lual.*")
-- For LuaRocks installed modules or busted tests, use require("lual.*")
local async_writer = require("lual.async")
local schemer = require("lual.utils.schemer")
local async_schema_module = require("lual.async.schema")

local M = {}

--- Validates async configuration
-- @param async_config table The async configuration to validate
-- @param full_config table The full configuration context
-- @return boolean, string True if valid, otherwise false and error message
function M.validate(async_config, full_config)
    if type(async_config) ~= "table" then
        return false, "Invalid type for 'async': expected table, got " .. type(async_config) .. ". Async configuration"
    end

    -- Use schemer for validation (includes type checking, enums, ranges, unknown keys)
    local errors = schemer.validate(async_config, async_schema_module.async_schema)
    if errors then
        return false, errors.error
    end

    return true
end

--- Applies async configuration changes
-- @param async_config table The async configuration to apply
-- @param current_config table The current full configuration
-- @return table The async configuration to store
function M.apply(async_config, current_config)
    -- Handle async configuration - start/stop async writer as needed
    if async_config.enabled ~= nil then
        if async_config.enabled then
            async_writer.start({ async = async_config }, nil)
            -- Setup the dispatch function using the log module
            local log_module = require("lual.log")
            async_writer.set_dispatch_function(log_module.process_log_record)
        else
            -- Stop async writer
            async_writer.stop()
        end
    end

    return async_config
end

return M
