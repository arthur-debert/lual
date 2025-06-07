--- Configuration API
-- This module provides the main configuration API functions

-- Note: For direct execution with 'lua', use require("lua.lual.*")
-- For LuaRocks installed modules or busted tests, use require("lual.*")
local registry = require("lual.config.registry")
local defaults = require("lual.config.defaults")
local validation = require("lual.config.validation")
local table_utils = require("lual.utils.table")

local M = {}

-- Current root logger configuration state
local _root_logger_config = {}

-- Register subsystem handlers
local function register_handlers()
    local levels_handlers = require("lual.levels.config").create_handlers()
    registry.register("level", levels_handlers.level)
    registry.register("custom_levels", levels_handlers.custom_levels)
    registry.register("propagate", require("lual.config.propagate"))
    registry.register("pipelines", require("lual.pipelines.config"))
    registry.register("async", require("lual.async.config"))
end

-- Initialize the config system
local function initialize()
    register_handlers()
    _root_logger_config = defaults.create_default_config()
end

-- Call initialization
initialize()

--- Updates the _root logger configuration with the provided settings
-- @param config_table table Configuration updates to apply
-- @return table The updated _root logger configuration
function M.config(config_table)
    -- Handle custom levels first if present (must be done before other validation)
    if config_table.custom_levels then
        local levels_handler = registry.get_handler("custom_levels")
        local valid, error_msg = levels_handler.validate(config_table.custom_levels, config_table)
        if not valid then
            error("Invalid configuration: " .. error_msg)
        end
        levels_handler.apply(config_table.custom_levels, _root_logger_config)
    end

    -- Validate the configuration (after custom levels are set)
    local valid, error_msg = validation.validate_config_structure(config_table, registry)
    if not valid then
        error("Invalid configuration: " .. error_msg)
    end

    -- Normalize configuration using registry
    local normalized_config = registry.normalize(config_table)

    -- Apply configuration using registry
    _root_logger_config = registry.apply(normalized_config, _root_logger_config)

    return table_utils.deepcopy(_root_logger_config)
end

--- Gets the current _root logger configuration
-- @return table A copy of the current _root logger configuration
function M.get_config()
    -- Return a deep copy of the internal configuration
    return table_utils.deepcopy(_root_logger_config)
end

--- Resets the _root logger configuration to defaults
function M.reset_config()
    -- Stop async writer if running
    local async_writer = require("lual.async")
    async_writer.stop()

    -- Reset to defaults
    _root_logger_config = defaults.create_default_config()

    return table_utils.deepcopy(_root_logger_config)
end

--- Reset registry (for testing)
function M.reset_registry()
    registry.reset()
    register_handlers()
end

return M
