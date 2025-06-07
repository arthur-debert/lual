--- Configuration API (Modular)
-- This module provides the configuration API using the registry system for delegation

local registry = require("lual.config.registry")
local table_utils = require("lual.utils.table")
local core_levels = require("lua.lual.levels")

local M = {}

-- Default configuration
local _root_logger_config = {
    level = core_levels.definition.WARNING,
    propagate = true,
    pipelines = {}
}

-- Register subsystem handlers
local function register_handlers()
    registry.register("level", require("lual.config.level"))
    registry.register("propagate", require("lual.config.propagate"))
    registry.register("pipelines", require("lual.config.pipelines"))
    registry.register("custom_levels", require("lual.config.custom_levels"))
    registry.register("async", require("lual.config.async"))
end

-- Initialize handlers
register_handlers()

-- Helper function to create default pipelines
local function create_default_pipelines()
    -- Return a default pipeline with console output and text presenter
    return {
        {
            level = core_levels.definition.WARNING,
            outputs = {
                {
                    func = require("lual.pipeline.outputs.console"),
                    config = {}
                }
            },
            presenter = require("lual.pipeline.presenters.text")()
        }
    }
end

-- Initialize with a default console output pipeline
local function initialize_default_config()
    -- Initialize with the console output pipeline
    local console = require("lual.pipeline.outputs.console")
    local text_presenter = require("lual.pipeline.presenters.text")
    local component_utils = require("lual.utils.component")

    -- Create a normalized output
    local normalized_output = component_utils.normalize_component(
        console,
        component_utils.DISPATCHER_DEFAULTS
    )

    -- Create a default pipeline with the normalized output
    local default_pipeline = {
        level = core_levels.definition.WARNING,
        outputs = { normalized_output },
        presenter = text_presenter()
    }

    -- Add it to the default config
    _root_logger_config.pipelines = { default_pipeline }
end

-- Call initialization
initialize_default_config()

--- Validates the configuration structure
-- @param config_table table Configuration to validate
-- @return boolean, string True if valid, otherwise false and error message
local function validate_config(config_table)
    if config_table == nil then
        return false, "Configuration must be a table, got nil"
    end

    if type(config_table) ~= "table" then
        return false, "Configuration must be a table, got " .. type(config_table)
    end

    -- Reject outputs key entirely - no backward compatibility
    if config_table.outputs then
        return false, "'outputs' is no longer supported. Use 'pipelines' instead."
    end

    -- Check for unknown keys
    local registered_keys = registry.get_registered_keys()
    local valid_keys = {}
    for _, key in ipairs(registered_keys) do
        valid_keys[key] = true
    end

    for key, _ in pairs(config_table) do
        if not valid_keys[key] then
            local valid_key_list = {}
            for valid_key, _ in pairs(valid_keys) do
                table.insert(valid_key_list, valid_key)
            end
            table.sort(valid_key_list)
            return false, string.format(
                "Unknown configuration key '%s'",
                tostring(key)
            )
        end
    end

    -- Validate using registry
    local valid, error_msg = registry.validate(config_table)
    if not valid then
        return false, error_msg
    end

    return true
end

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
    local valid, error_msg = validate_config(config_table)
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
    _root_logger_config = {
        level = core_levels.definition.WARNING,
        propagate = true,
        pipelines = {}
    }

    -- Re-initialize with default output
    initialize_default_config()

    return table_utils.deepcopy(_root_logger_config)
end

--- Reset registry (for testing)
function M.reset_registry()
    registry.reset()
    register_handlers()
end

return M
