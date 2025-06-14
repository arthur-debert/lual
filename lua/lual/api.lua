-- Public API for lual logger
-- This module provides the main entry points for the logging library

-- Note: For direct execution with 'lua', use require("lual.*")
-- For LuaRocks installed modules or busted tests, use require("lual.*")
local loggers_module = require("lual.loggers")
local config_module = require("lual.config")
local constants = require("lual.constants")
local core_levels = require("lual.levels")
local async_writer = require("lual.async")
local logger_config = require("lual.loggers.config")

-- Import the standalone debug module
local debug_module = require("lual.debug")

local M = {}

-- Main public API to get or create a logger.
function M.logger(arg1, arg2)
    local name_input = nil
    local config_input = {}

    if type(arg1) == "string" then
        name_input = arg1
        if type(arg2) == "table" then
            config_input = arg2
        elseif arg2 ~= nil then
            error("Invalid 2nd arg: expected table (config) or nil, got " .. type(arg2))
        end
    elseif type(arg1) == "table" then
        config_input = arg1
        if arg2 ~= nil then error("Invalid 2nd arg: config table as 1st arg means no 2nd arg, got " .. type(arg2)) end
    elseif arg1 == nil then
        if type(arg2) == "table" then
            config_input = arg2
        elseif arg2 ~= nil then
            error("Invalid 2nd arg: expected table (config) or nil, got " .. type(arg2))
        end
    elseif arg1 ~= nil then
        error("Invalid 1st arg: expected name (string), config (table), or nil, got " .. type(arg1))
    end

    if name_input ~= nil then
        if name_input == "" then error("Logger name cannot be an empty string.") end
        if name_input ~= "_root" and name_input:sub(1, 1) == "_" then
            error("Logger names starting with '_' are reserved (except '_root'). Name: " .. name_input)
        end
    end

    -- Validate configuration using the validation function for backward compatibility
    local ok, err_msg = logger_config.validate_logger_config_table(config_input)
    if not ok then error("Invalid logger configuration: " .. err_msg) end

    -- Connect log.logger to the internal factory
    return loggers_module._get_or_create_logger_internal(name_input, config_input)
end

-- Resets the logger cache (for testing)
function M.reset_cache()
    loggers_module.reset_cache()
end

-- Gets all levels (built-in + custom)
-- @return table All available levels
function M.get_levels()
    return core_levels.get_all_levels()
end

-- Sets custom levels (replaces all existing custom levels)
-- @param custom_levels table Custom levels as name = value pairs
function M.set_levels(custom_levels)
    core_levels.set_custom_levels(custom_levels)
end

-- Configuration API
-- Creates and configures the root logger using the new system.
-- @param config table The root logger configuration
-- @return table The updated configuration
function M.config(config)
    return config_module.config(config)
end

-- Gets the configuration of the root logger
-- @return table The root logger configuration
function M.get_config()
    return config_module.get_config()
end

-- Resets all logging configuration to defaults.
function M.reset_config()
    config_module.reset_config()
    M.reset_cache()
end

-- Flushes all queued async log events immediately.
-- This function will block until all currently queued log events have been processed.
-- If async logging is not enabled, this function does nothing.
function M.flush()
    async_writer.flush()
end

-- Sets the command line verbosity configuration
-- @param verbosity_config table Configuration for command line verbosity mapping
-- @return table The updated root logger configuration
function M.set_command_line_verbosity(verbosity_config)
    if type(verbosity_config) ~= "table" then
        error("Command line verbosity config must be a table")
    end

    return config_module.config({
        command_line_verbosity = verbosity_config
    })
end

-- Sets up live log level changes through environment variables
-- @param env_var_name string Name of the environment variable to watch
-- @param check_interval number How often to check (in log calls)
-- @return table The updated root logger configuration
function M.set_live_level(env_var_name, check_interval)
    if not env_var_name or type(env_var_name) ~= "string" then
        error("Environment variable name must be a string")
    end

    local config = {
        env_var = env_var_name,
        enabled = true
    }

    if check_interval ~= nil then
        if type(check_interval) ~= "number" then
            error("Check interval must be a number")
        end
        config.check_interval = check_interval
    end

    return config_module.config({
        live_level = config
    })
end

-- Expose internal functions for testing
M.create_root_logger = loggers_module.create_root_logger

-- Internal debug functionality (not part of public API)
-- Delegate to the standalone debug module
M._INTERNAL_DEBUG = debug_module._INTERNAL_DEBUG
M._debug_print = debug_module._debug_print
M._set_internal_debug = debug_module._set_internal_debug

-- Copy all constants from constants module to public API
for key, value in pairs(constants) do
    M[key] = value
end

return M
