--- Levels Configuration Handler
-- This module handles both 'level' and 'custom_levels' configuration keys

local core_levels = require("lua.lual.levels")

local M = {}

--- Validates level configuration
-- @param level number The level value to validate
-- @param full_config table The full configuration context
-- @return boolean, string True if valid, otherwise false and error message
local function validate_level(level, full_config)
    if type(level) ~= "number" then
        return false,
            "Invalid type for 'level': expected number, got " ..
            type(level) .. ". Logging level (use lual.DEBUG, lual.INFO, etc.)"
    end

    -- Get all levels (built-in + custom) for validation
    local all_levels = core_levels.get_all_levels()
    local valid_level = false
    for _, level_value in pairs(all_levels) do
        if level == level_value then
            valid_level = true
            break
        end
    end
    if not valid_level then
        local valid_levels = {}
        for level_name, level_value in pairs(all_levels) do
            table.insert(valid_levels, string.format("%s(%d)", level_name, level_value))
        end
        table.sort(valid_levels)
        return false, string.format(
            "Invalid level value %d. Valid levels are: %s",
            level,
            table.concat(valid_levels, ", ")
        )
    end

    -- Root logger cannot be set to NOTSET
    if level == core_levels.definition.NOTSET then
        return false, "Root logger level cannot be set to NOTSET"
    end

    return true
end

--- Validates custom levels configuration
-- @param custom_levels table Custom levels configuration to validate
-- @param full_config table The full configuration context
-- @return boolean, string True if valid, otherwise false and error message
local function validate_custom_levels(custom_levels, full_config)
    if type(custom_levels) ~= "table" then
        return false, "custom_levels must be a table"
    end

    -- Validate each custom level
    for name, value in pairs(custom_levels) do
        local name_valid, name_error = core_levels.validate_custom_level_name(name)
        if not name_valid then
            return false, "Invalid custom level name '" .. tostring(name) .. "': " .. name_error
        end

        local value_valid, value_error = core_levels.validate_custom_level_value(value, true) -- exclude current customs
        if not value_valid then
            return false, "Invalid custom level value for '" .. name .. "': " .. value_error
        end
    end

    -- Check for duplicate values
    local seen_values = {}
    for name, value in pairs(custom_levels) do
        if seen_values[value] then
            return false,
                "Duplicate level value " .. value .. " for levels '" .. seen_values[value] .. "' and '" .. name .. "'"
        end
        seen_values[value] = name
    end

    return true
end

--- Creates handlers for both level-related config keys
-- @return table Table with handlers for 'level' and 'custom_levels'
function M.create_handlers()
    local handlers = {}

    -- Handler for 'level' config key
    handlers.level = {
        validate = function(level, full_config)
            return validate_level(level, full_config)
        end,
        apply = function(level, current_config)
            return level
        end
    }

    -- Handler for 'custom_levels' config key
    handlers.custom_levels = {
        validate = function(custom_levels, full_config)
            return validate_custom_levels(custom_levels, full_config)
        end,
        apply = function(custom_levels, current_config)
            -- Apply custom levels to the core levels module
            core_levels.set_custom_levels(custom_levels)

            -- We don't return custom_levels to store in config since they're applied globally
            return nil
        end
    }

    return handlers
end

return M
