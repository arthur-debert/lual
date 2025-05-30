--- Main logging engine module
-- This module provides the public API and orchestrates all logging components

local ingest = require("lual.ingest")
local core_levels = require("lual.core.levels")
local config_module = require("lual.config")
local prototype = require("lual.core.logging.prototype")
local factory = require("lual.core.logging.factory")
local management = require("lual.core.logging.management")

local M = {}

-- Logger cache
local _loggers_cache = {}

-- =============================================================================
-- CACHE MANAGEMENT
-- =============================================================================

--- Updates a logger in the cache
-- @param name string The logger name
-- @param logger table The logger instance
local function update_cache(name, logger)
    _loggers_cache[name] = logger
end

--- Resets the logger cache
function M.reset_cache()
    _loggers_cache = {}
end

-- =============================================================================
-- INITIALIZATION
-- =============================================================================

-- Set up dependency injection for the prototype module
prototype.set_ingest_dispatch(function(log_record)
    ingest.dispatch_log_event(log_record, M.logger, core_levels.definition)
end)

-- Add management methods to the logger prototype
management.add_management_methods(
    prototype.logger_prototype,
    factory.create_logger_from_config,
    update_cache
)

-- =============================================================================
-- SIMPLE LOGGER API
-- =============================================================================

--- Creates a simple logger with minimal configuration
-- @param name string|nil The logger name (auto-generated if nil)
-- @return table The logger instance
function M._get_logger_simple(name)
    local logger_name = name
    if name == nil or name == "" then
        -- Auto-generate logger name from caller's filename
        local caller_info = require("lual.core.caller_info")
        -- Use caller_info to automatically find the first non-lual file
        local filename, _ = caller_info.get_caller_info(nil, true)
        if filename then
            logger_name = filename
        else
            logger_name = "root"
        end
    end

    if _loggers_cache[logger_name] then
        return _loggers_cache[logger_name]
    end

    local new_logger = factory.create_simple_logger(logger_name, M._get_logger_simple)
    _loggers_cache[logger_name] = new_logger
    return new_logger
end

-- =============================================================================
-- CONFIG LOGGER API
-- =============================================================================

--- Creates a logger from a config table
-- This is the primary API for creating loggers. Can be called with:
-- 1. No arguments or string name: lual.logger() or lual.logger("name") - simple logger creation
-- 2. Config table: lual.logger({name="app", level="debug", dispatchers={...}}) - configuration
-- @param input_config (string|table|nil) The logger name or configuration
-- @return table The logger instance
function M.logger(input_config)
    -- Handle simple cases: nil, empty string, or string name
    if input_config == nil or input_config == "" or type(input_config) == "string" then
        return M._get_logger_simple(input_config)
    end

    -- Handle table-based configuration
    if type(input_config) ~= "table" then
        error("logger() expects nil, string, or table argument, got " .. type(input_config))
    end

    -- Define default config
    local default_config = {
        name = "root",
        level = "info",
        dispatchers = {},
        propagate = true,
        timezone = "local", -- Default to local time
    }

    -- Use the config module to process the input config
    local canonical_config = config_module.process_config(input_config, default_config)

    -- Check if logger already exists in cache and if its configuration matches
    if canonical_config.name and _loggers_cache[canonical_config.name] then
        local cached_logger = _loggers_cache[canonical_config.name]
        local cached_config = cached_logger:get_config()

        -- Compare key configuration fields to see if we can reuse the cached logger
        if cached_config.level == canonical_config.level and
            cached_config.timezone == canonical_config.timezone and
            cached_config.propagate == canonical_config.propagate then
            -- For dispatchers, we'll do a simple length check for now
            -- A more sophisticated comparison could be added later if needed
            if #(cached_config.dispatchers or {}) == #(canonical_config.dispatchers or {}) then
                return cached_logger
            end
        end
        -- If configuration doesn't match, we'll create a new logger and update the cache
    end

    local new_logger = factory.create_logger(input_config, default_config, M.logger)

    -- Cache the logger if it has a name
    if canonical_config.name then
        _loggers_cache[canonical_config.name] = new_logger
    end

    return new_logger
end

-- =============================================================================
-- PUBLIC API
-- =============================================================================

-- Backward compatibility alias - get_logger points to logger
M.get_logger = M.logger

-- Export factory function for backward compatibility
M.create_logger_from_config = factory.create_logger_from_config

-- Export config module functions for backward compatibility and testing
M.config = config_module

-- Export sub-modules for testing and advanced usage
M.prototype = prototype
M.factory = factory
M.management = management

return M
