--- Configuration API
-- This module provides the new simplified configuration API for the _root logger

local core_levels = require("lua.lual.levels")
local table_utils = require("lual.utils.table")
local component_utils = require("lual.utils.component")
local all_outputs = require("lual.outputs.init")
local all_presenters = require("lual.presenters.init")

local M = {}

-- Helper function to create default outputs
local function create_default_outputs()
    -- Return a default console output with text presenter as specified in the design doc
    return {
        {
            func = all_outputs.console_output,
            config = { presenter = all_presenters.text() }
        }
    }
end

-- Default configuration with console output
local _root_logger_config = {
    level = core_levels.definition.WARNING,
    propagate = true,
    outputs = {}
}

-- Initialize with a default console output
local function initialize_default_config()
    -- Initialize with the console output
    local console_output = require("lual.outputs.console_output")
    local component_utils = require("lual.utils.component")

    -- Create a normalized output
    local normalized = component_utils.normalize_component(
        console_output,
        component_utils.DISPATCHER_DEFAULTS
    )

    -- Add it to the default config
    _root_logger_config.outputs = { normalized }
end

-- Call initialization
initialize_default_config()

-- Table of valid config keys and their expected types/descriptions
local VALID_CONFIG_KEYS = {
    level = { type = "number", description = "Logging level (use lual.DEBUG, lual.INFO, etc.)" },
    outputs = { type = "table", description = "Array of output functions or configuration tables" },
    propagate = { type = "boolean", description = "Whether to propagate messages (always true for root)" }
}

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

    -- Validate outputs if present
    if config_table.outputs then
        if type(config_table.outputs) ~= "table" then
            return false,
                "Invalid type for 'outputs': expected table, got " ..
                type(config_table.outputs) .. ". Array of output functions or configuration tables"
        end

        -- Validate each output
        for i, disp in ipairs(config_table.outputs) do
            -- Simple validation here - detailed validation happens in component.normalize_component
            if type(disp) ~= "function" and type(disp) ~= "table" then
                return false,
                    "outputs[" ..
                    i .. "] must be a function or a table with function as first element, got " .. type(disp)
            end

            -- Validate table format if it's a table
            if type(disp) == "table" and #disp == 0 and not component_utils.is_callable(disp) then
                return false, "outputs[" .. i .. "] must be a function or a table with function as first element"
            end
        end
    end

    -- Check for unknown keys using table_utils.key_diff
    local key_diff = table_utils.key_diff(VALID_CONFIG_KEYS, config_table)
    if #key_diff.added_keys > 0 then
        local valid_keys = {}
        for valid_key, _ in pairs(VALID_CONFIG_KEYS) do
            table.insert(valid_keys, valid_key)
        end
        table.sort(valid_keys)
        return false, string.format(
            "Unknown configuration key '%s'. Valid keys are: %s",
            tostring(key_diff.added_keys[1]),
            table.concat(valid_keys, ", ")
        )
    end

    -- Type validation
    for key, value in pairs(config_table) do
        local expected_spec = VALID_CONFIG_KEYS[key]
        local expected_type = expected_spec.type
        local actual_type = type(value)

        if actual_type ~= expected_type then
            return false, string.format(
                "Invalid type for '%s': expected %s, got %s. %s",
                key,
                expected_type,
                actual_type,
                expected_spec.description
            )
        end

        -- Additional validation for specific keys
        if key == "level" then
            -- Validate that level is a known level value
            local valid_level = false
            for _, level_value in pairs(core_levels.definition) do
                if value == level_value then
                    valid_level = true
                    break
                end
            end
            if not valid_level then
                local valid_levels = {}
                for level_name, level_value in pairs(core_levels.definition) do
                    table.insert(valid_levels, string.format("%s(%d)", level_name, level_value))
                end
                table.sort(valid_levels)
                return false, string.format(
                    "Invalid level value %d. Valid levels are: %s",
                    value,
                    table.concat(valid_levels, ", ")
                )
            end
            -- Root logger cannot be set to NOTSET
            if value == core_levels.definition.NOTSET then
                return false, "Root logger level cannot be set to NOTSET"
            end
        end
    end

    return true
end

--- Updates the _root logger configuration with the provided settings
-- @param config_table table Configuration updates to apply
-- @return table The updated _root logger configuration
function M.config(config_table)
    -- Validate the configuration
    local valid, error_msg = validate_config(config_table)
    if not valid then
        error("Invalid configuration: " .. error_msg)
    end

    -- Update _root logger configuration with provided values
    for key, value in pairs(config_table) do
        if key == "outputs" then
            -- Normalize the outputs using the component system
            _root_logger_config[key] = component_utils.normalize_components(value, component_utils.DISPATCHER_DEFAULTS)
        else
            _root_logger_config[key] = value
        end
    end

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
    -- Reset to defaults
    _root_logger_config = {
        level = core_levels.definition.WARNING,
        propagate = true,
        outputs = {}
    }

    -- Re-initialize with default output
    initialize_default_config()

    return table_utils.deepcopy(_root_logger_config)
end

return M
