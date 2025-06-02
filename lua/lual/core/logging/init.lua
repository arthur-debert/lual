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

-- Root logger reference (only set when lual.config() is called)
local _root_logger = nil

-- =============================================================================
-- CACHE MANAGEMENT
-- =============================================================================

--- Updates a logger in the cache
-- @param name string The logger name
-- @param logger table The logger instance
local function update_cache(name, logger)
    _loggers_cache[name] = logger
end

--- Resets the logger cache and root logger
function M.reset_cache()
    _loggers_cache = {}
    _root_logger = nil
end

-- =============================================================================
-- ROOT LOGGER CONFIGURATION (NEW API)
-- =============================================================================

--- Creates and configures the root logger. This is the only way to enable a root logger.
--- @param config table The root logger configuration
--- @return table The root logger instance
function M.config_root_logger(config)
    -- Set default config for root logger
    local default_config = {
        level = "info",
        dispatchers = {},
        propagate = false -- Root logger doesn't propagate (no parent)
    }

    -- Process the configuration
    local canonical_config = config_module.process_config(config, default_config)
    canonical_config.parent = nil      -- Root logger has no parent
    canonical_config.propagate = false -- Root logger doesn't propagate

    -- Create the root logger
    _root_logger = factory.create_logger_from_config("_root", canonical_config)
    _loggers_cache["_root"] = _root_logger

    return _root_logger
end

--- Gets the root logger if it exists
--- @return table|nil The root logger or nil if not configured
function M.get_root_logger()
    return _root_logger
end

-- =============================================================================
-- HIERARCHY UTILITIES
-- =============================================================================

--- Determines the parent logger name based on hierarchical naming
--- @param logger_name string The logger name
--- @return string|nil The parent logger name or nil if this is a top-level logger
local function get_parent_name(logger_name)
    if logger_name == "_root" then
        return nil -- Root logger has no parent
    end

    -- Find the last dot to determine parent
    local parent_name = logger_name:match("(.+)%.[^%.]+$")

    -- If no dot found, parent is root (if root logger exists)
    if not parent_name then
        return _root_logger and "_root" or nil
    end

    return parent_name
end

--- Gets or creates a parent logger
--- @param parent_name string The parent logger name
--- @return table|nil The parent logger or nil
local function get_or_create_parent(parent_name)
    if not parent_name then
        return nil
    end

    -- If parent is already in cache, return it
    if _loggers_cache[parent_name] then
        return _loggers_cache[parent_name]
    end

    -- Create parent with default configuration
    return M._get_logger_simple(parent_name)
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
        local filename, _, _ = caller_info.get_caller_info(nil, true)
        if filename then
            logger_name = filename
        else
            logger_name = "_root"
        end
    end

    if _loggers_cache[logger_name] then
        return _loggers_cache[logger_name]
    end

    -- Determine parent based on hierarchical naming
    local parent_name = get_parent_name(logger_name)
    local parent_logger = nil

    if parent_name then
        parent_logger = get_or_create_parent(parent_name)
    end

    local new_logger = factory.create_simple_logger(logger_name, parent_logger)
    _loggers_cache[logger_name] = new_logger
    return new_logger
end

-- =============================================================================
-- CONFIG LOGGER API
-- =============================================================================

--- Creates a logger from a config table
-- This is the primary API for creating loggers. Can be called with:
-- 1. No arguments: lual.logger() - auto-named logger creation
-- 2. String name: lual.logger("name") - simple logger creation with name
-- 3. String name + config: lual.logger("name", {level="debug", ...}) - name from first param, config from second
-- 4. Config table: lual.logger({level="debug", dispatchers={...}}) - auto-named with configuration (name not allowed in config)
-- @param input_config (string|table|nil) The logger name or configuration
-- @param config_table (table|nil) Optional configuration table when first param is a string name
-- @return table The logger instance
function M.logger(input_config, config_table)
    -- Handle two-parameter form: logger("name", config_table)
    if type(input_config) == "string" and type(config_table) == "table" then
        local logger_name = input_config

        -- Define default config
        local default_config = {
            level = "info",
            dispatchers = {},
            propagate = true
        }

        -- Use the config module to process the input config
        local canonical_config = config_module.process_config(config_table, default_config)

        -- Continue with config processing...
        -- Check if logger already exists in cache and if its configuration matches
        if _loggers_cache[logger_name] then
            local cached_logger = _loggers_cache[logger_name]
            local cached_config = cached_logger:get_config()

            -- Compare key configuration fields to see if we can reuse the cached logger
            if cached_config.level == canonical_config.level and
                cached_config.propagate == canonical_config.propagate then
                -- For dispatchers, we'll do a simple length check for now
                -- A more sophisticated comparison could be added later if needed
                if #(cached_config.dispatchers or {}) == #(canonical_config.dispatchers or {}) then
                    return cached_logger
                end
            end
            -- If configuration doesn't match, we'll create a new logger and update the cache
        end

        -- Determine parent based on hierarchical naming
        local parent_name = get_parent_name(logger_name)
        local parent_logger = nil

        if parent_name then
            parent_logger = get_or_create_parent(parent_name)
        end

        canonical_config.parent = parent_logger

        local new_logger = factory.create_logger_from_config(logger_name, canonical_config)

        -- Cache the logger
        _loggers_cache[logger_name] = new_logger

        return new_logger
    end

    -- Handle simple cases: nil, empty string, or string name (single parameter)
    if input_config == nil or input_config == "" or type(input_config) == "string" then
        return M._get_logger_simple(input_config)
    end

    -- Handle table-based configuration (single parameter)
    if type(input_config) ~= "table" then
        error("logger() expects nil, string, or table argument, got " .. type(input_config))
    end

    -- Auto-generate logger name (defaults to "_root")
    local logger_name = "_root"

    -- Define default config
    local default_config = {
        level = "info",
        dispatchers = {},
        propagate = true
    }

    -- Use the config module to process the input config
    local canonical_config = config_module.process_config(input_config, default_config)

    -- Check if logger already exists in cache and if its configuration matches
    if _loggers_cache[logger_name] then
        local cached_logger = _loggers_cache[logger_name]
        local cached_config = cached_logger:get_config()

        -- Compare key configuration fields to see if we can reuse the cached logger
        if cached_config.level == canonical_config.level and
            cached_config.propagate == canonical_config.propagate then
            -- For dispatchers, we'll do a simple length check for now
            -- A more sophisticated comparison could be added later if needed
            if #(cached_config.dispatchers or {}) == #(canonical_config.dispatchers or {}) then
                return cached_logger
            end
        end
        -- If configuration doesn't match, we'll create a new logger and update the cache
    end

    -- Determine parent based on hierarchical naming
    local parent_name = get_parent_name(logger_name)
    local parent_logger = nil

    if parent_name then
        parent_logger = get_or_create_parent(parent_name)
    end

    canonical_config.parent = parent_logger

    local new_logger = factory.create_logger_from_config(logger_name, canonical_config)

    -- Cache the logger
    _loggers_cache[logger_name] = new_logger

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
