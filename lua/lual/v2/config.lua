--- V2 Configuration API
-- This module provides the new simplified configuration API for the _root logger

local core_levels = require("lua.lual.v2.levels")

local M = {}

-- Internal state for the _root logger
local _root_logger_config = {
    level = core_levels.definition.WARNING, -- Default to WARNING as per design
    dispatchers = {},                       -- Empty by default
    propagate = true                        -- Root propagates by default (though it has no parent)
}

-- Valid configuration keys and their expected types
local VALID_CONFIG_KEYS = {
    level = { type = "number", description = "Logging level (use lual.DEBUG, lual.INFO, etc.)" },
    dispatchers = { type = "table", description = "Array of dispatcher functions" },
    propagate = { type = "boolean", description = "Whether to propagate messages (always true for root)" }
}

--- Validates a configuration table
-- @param config_table table The configuration to validate
-- @return boolean, string True if valid, or false with error message
local function validate_config(config_table)
    if type(config_table) ~= "table" then
        return false, "Configuration must be a table, got " .. type(config_table)
    end

    -- Check for unknown keys
    for key, value in pairs(config_table) do
        if not VALID_CONFIG_KEYS[key] then
            local valid_keys = {}
            for valid_key, _ in pairs(VALID_CONFIG_KEYS) do
                table.insert(valid_keys, valid_key)
            end
            table.sort(valid_keys)
            return false, string.format(
                "Unknown configuration key '%s'. Valid keys are: %s",
                tostring(key),
                table.concat(valid_keys, ", ")
            )
        end

        -- Type validation
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
        elseif key == "dispatchers" then
            -- Validate that dispatchers is an array of functions
            if not (#value >= 0) then -- Basic array check
                return false, "dispatchers must be an array (table with numeric indices)"
            end
            for i, dispatcher in ipairs(value) do
                if type(dispatcher) ~= "function" then
                    return false, string.format(
                        "dispatchers[%d] must be a function, got %s",
                        i,
                        type(dispatcher)
                    )
                end
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
        _root_logger_config[key] = value
    end

    -- Return a copy of the current configuration
    local config_copy = {}
    for key, value in pairs(_root_logger_config) do
        if type(value) == "table" then
            -- Deep copy arrays
            config_copy[key] = {}
            for i, item in ipairs(value) do
                config_copy[key][i] = item
            end
        else
            config_copy[key] = value
        end
    end

    return config_copy
end

--- Gets the current _root logger configuration
-- @return table A copy of the current _root logger configuration
function M.get_config()
    local config_copy = {}
    for key, value in pairs(_root_logger_config) do
        if type(value) == "table" then
            -- Deep copy arrays
            config_copy[key] = {}
            for i, item in ipairs(value) do
                config_copy[key][i] = item
            end
        else
            config_copy[key] = value
        end
    end
    return config_copy
end

--- Resets the _root logger configuration to defaults
function M.reset_config()
    _root_logger_config = {
        level = core_levels.definition.WARNING,
        dispatchers = {},
        propagate = true
    }
end

return M
