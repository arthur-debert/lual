--- Levels Configuration Handler
-- This module handles the 'custom_levels' configuration key

local core_levels = require("lua.lual.levels")

local M = {}

--- Validates custom levels configuration
-- @param custom_levels table Custom levels configuration to validate
-- @param full_config table The full configuration context
-- @return boolean, string True if valid, otherwise false and error message
function M.validate(custom_levels, full_config)
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

--- Applies custom levels configuration
-- @param custom_levels table The custom levels configuration to apply
-- @param current_config table The current full configuration
-- @return nil We don't store custom_levels in the config, just apply them
function M.apply(custom_levels, current_config)
    -- Apply custom levels to the core levels module
    core_levels.set_custom_levels(custom_levels)

    -- We don't return custom_levels to store in config since they're applied globally
    return nil
end

return M
