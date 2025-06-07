--- Level Configuration Handler
-- This module handles the 'level' configuration key

local core_levels = require("lua.lual.levels")

local M = {}

--- Validates level configuration
-- @param level number The level value to validate
-- @param full_config table The full configuration context
-- @return boolean, string True if valid, otherwise false and error message
function M.validate(level, full_config)
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

--- Applies level configuration
-- @param level number The level value to apply
-- @param current_config table The current full configuration
-- @return number The level value to store in configuration
function M.apply(level, current_config)
    return level
end

return M
