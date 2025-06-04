--- Configuration API
-- This module provides the new simplified configuration API for the _root logger

local core_levels = require("lua.lual.levels")
local table_utils = require("lual.utils.table")
local all_dispatchers = require("lual.dispatchers.init")
local all_presenters = require("lual.presenters.init")

local M = {}

-- Helper function to create default dispatchers
local function create_default_dispatchers()
    -- Return a default console dispatcher with text presenter as specified in the design doc
    return {
        {
            dispatcher_func = all_dispatchers.console_dispatcher,
            config = { presenter = all_presenters.text() }
        }
    }
end

-- Internal state for the _root logger
local _root_logger_config = {
    level = core_levels.definition.WARNING,     -- Default to WARNING as per design
    dispatchers = create_default_dispatchers(), -- Default console dispatcher
    propagate = true                            -- Root propagates by default (though it has no parent)
}

-- Valid configuration keys and their expected types
local VALID_CONFIG_KEYS = {
    level = { type = "number", description = "Logging level (use lual.DEBUG, lual.INFO, etc.)" },
    dispatchers = { type = "table", description = "Array of dispatcher functions or configuration tables" },
    propagate = { type = "boolean", description = "Whether to propagate messages (always true for root)" }
}

--- Validates a configuration table
-- @param config_table table The configuration to validate
-- @return boolean, string True if valid, or false with error message
local function validate_config(config_table)
    if type(config_table) ~= "table" then
        return false, "Configuration must be a table, got " .. type(config_table)
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
        elseif key == "dispatchers" then
            -- Validate that dispatchers is an array of functions or valid config tables
            if not (#value >= 0) then -- Basic array check
                return false, "dispatchers must be an array (table with numeric indices)"
            end
            for i, dispatcher in ipairs(value) do
                if not (
                        type(dispatcher) == "function" or
                        (type(dispatcher) == "table" and (
                            type(dispatcher.dispatcher_func) == "function" or
                            type(dispatcher.type) == "function" or
                            type(dispatcher.type) == "string"
                        ))
                    ) then
                    return false, string.format(
                        "dispatchers[%d] must be a function, a table with dispatcher_func, or a table with type property (string or function), got %s",
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
        if key == "dispatchers" then
            -- Store dispatchers in internal format but return raw functions
            _root_logger_config[key] = {}
            for _, disp in ipairs(value) do
                if type(disp) == "function" then
                    table.insert(_root_logger_config[key], { dispatcher_func = disp, config = {} })
                elseif type(disp) == "table" then
                    if type(disp.dispatcher_func) == "function" then
                        table.insert(_root_logger_config[key], disp)
                    elseif type(disp.type) == "function" then
                        -- Handle the case where disp.type is a function reference
                        table.insert(_root_logger_config[key], {
                            dispatcher_func = disp.type,
                            config = disp.config or {}
                        })
                    elseif type(disp.type) == "string" then
                        -- Legacy case: look up the function by name
                        -- This is handled elsewhere and is just a placeholder
                        table.insert(_root_logger_config[key], disp)
                    end
                end
            end
        else
            _root_logger_config[key] = value
        end
    end

    -- Return a copy with raw functions for dispatchers
    local config_copy = table_utils.deepcopy(_root_logger_config)
    if config_copy.dispatchers then
        local raw_dispatchers = {}
        for _, disp in ipairs(config_copy.dispatchers) do
            if disp.dispatcher_func then
                table.insert(raw_dispatchers, disp.dispatcher_func)
            end
        end
        config_copy.dispatchers = raw_dispatchers
    end
    return config_copy
end

--- Gets the current _root logger configuration
-- @return table A copy of the current _root logger configuration
function M.get_config()
    local config_copy = table_utils.deepcopy(_root_logger_config)
    if config_copy.dispatchers then
        local raw_dispatchers = {}
        for _, disp in ipairs(config_copy.dispatchers) do
            if disp.dispatcher_func then
                table.insert(raw_dispatchers, disp.dispatcher_func)
            end
        end
        config_copy.dispatchers = raw_dispatchers
    end
    return config_copy
end

--- Resets the _root logger configuration to defaults
function M.reset_config()
    _root_logger_config = {
        level = core_levels.definition.WARNING,
        dispatchers = create_default_dispatchers(), -- Default console dispatcher
        propagate = true
    }
end

return M
