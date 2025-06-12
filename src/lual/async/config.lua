--- Async Configuration Handler
-- This module handles the 'async' configuration key
--
-- ARCHITECTURE NOTE: This module demonstrates PROPER separation of concerns:
-- 1. validate() - PURE VALIDATION (no side effects, uses schemer)
-- 2. apply() - SIDE EFFECTS (starts/stops async writer)
-- This is the correct pattern: validation is pure, side effects happen in apply()

-- Note: For direct execution with 'lua', use require("lual.*")
-- For LuaRocks installed modules or busted tests, use require("lual.*")
local async_writer = require("lual.async")
local schemer = require("lual.utils.schemer")
local async_schema_module = require("lual.async.schema")

local M = {}

--- Validates async configuration
-- PURE VALIDATION: No side effects, only validates configuration structure
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
-- SIDE EFFECTS: This is where it's appropriate to start/stop services
-- This function may modify global state (async writer) - this is correct!
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
