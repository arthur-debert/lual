--- Configuration API
-- This module provides the new simplified configuration API for the _root logger

local core_levels = require("lua.lual.levels")
local table_utils = require("lual.utils.table")
local component_utils = require("lual.utils.component")
local all_dispatchers = require("lual.dispatchers.init")
local all_presenters = require("lual.presenters.init")

local M = {}

-- Helper function to create default dispatchers
local function create_default_dispatchers()
    -- Return a default console dispatcher with text presenter as specified in the design doc
    return {
        {
            func = all_dispatchers.console_dispatcher,
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

    -- Validate dispatchers if present
    if config_table.dispatchers then
        if type(config_table.dispatchers) ~= "table" then
            return false,
                "Invalid type for 'dispatchers': expected table, got " ..
                type(config_table.dispatchers) .. ". Array of dispatcher functions or configuration tables"
        end

        -- Validate each dispatcher
        for i, disp in ipairs(config_table.dispatchers) do
            if type(disp) ~= "function" and type(disp) ~= "table" then
                return false,
                    "dispatchers[" ..
                    i ..
                    "] must be a function, a table with dispatcher_func, or a table with type property (string or function), got " ..
                    type(disp)
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
        elseif key == "dispatchers" then
            -- Validate that dispatchers is an array of functions or valid config tables
            if not (#value >= 0) then -- Basic array check
                return false, "dispatchers must be an array (table with numeric indices)"
            end
            for i, dispatcher in ipairs(value) do
                -- Simply check if it's a function or table - component normalization will do detailed validation
                if type(dispatcher) ~= "function" and type(dispatcher) ~= "table" then
                    return false, string.format(
                        "dispatchers[%d] must be a function or a table, got %s",
                        i,
                        type(dispatcher)
                    )
                end

                -- Validate dispatcher level if present
                if type(dispatcher) == "table" and dispatcher.level ~= nil then
                    if type(dispatcher.level) ~= "number" then
                        return false,
                            string.format("dispatchers[%d].level must be a number, got %s", i, type(dispatcher.level))
                    end

                    -- Verify it's a valid level constant
                    local valid_level = false
                    for _, level_value in pairs(core_levels.definition) do
                        if dispatcher.level == level_value then
                            valid_level = true
                            break
                        end
                    end

                    if not valid_level then
                        local valid_levels_list = {}
                        for level_name, level_val in pairs(core_levels.definition) do
                            table.insert(valid_levels_list, string.format("%s(%d)", level_name, level_val))
                        end
                        table.sort(valid_levels_list)
                        return false,
                            string.format(
                                "Invalid dispatcher level value %d in dispatchers[%d]. Valid levels are: %s",
                                dispatcher.level, i, table.concat(valid_levels_list, ", "))
                    end
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
            -- Store dispatchers in internal format
            _root_logger_config[key] = {}
            for i, disp in ipairs(value) do
                if type(disp) == "function" then
                    -- Function dispatcher - wrap in table
                    table.insert(_root_logger_config[key], {
                        func = disp,
                        config = {}
                    })
                elseif type(disp) == "table" then
                    -- Special case for spy objects or tables with direct level
                    if disp.level and not (disp.config and disp.config.level) then
                        if not disp.config then
                            disp.config = {}
                        end
                        disp.config.level = disp.level
                    end

                    -- Table format - use as-is
                    table.insert(_root_logger_config[key], disp)
                end
            end
        else
            _root_logger_config[key] = value
        end
    end

    -- Return a copy with raw functions for dispatchers (for backward compatibility)
    local config_copy = table_utils.deepcopy(_root_logger_config)

    if config_copy.dispatchers then
        local raw_dispatchers = {}
        for _, disp in ipairs(config_copy.dispatchers) do
            -- Extract the function from the normalized dispatcher
            if disp.func then
                table.insert(raw_dispatchers, disp.func)
            end
        end
        config_copy.dispatchers = raw_dispatchers
    end
    return config_copy
end

--- Gets the current _root logger configuration
-- @return table A copy of the current _root logger configuration
function M.get_config()
    -- Return a deep copy of the internal configuration
    local config_copy = table_utils.deepcopy(_root_logger_config)

    -- Convert dispatchers to raw functions for backward compatibility
    if config_copy.dispatchers then
        local raw_dispatchers = {}
        for _, disp in ipairs(config_copy.dispatchers) do
            -- Extract the function from the normalized dispatcher
            if disp.func then
                table.insert(raw_dispatchers, disp.func)
            elseif disp.dispatcher_func then
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
