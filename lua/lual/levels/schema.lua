--- Levels Configuration Schema
-- Schema definitions for 'level' and 'custom_levels' configuration keys

local core_levels = require("lual.levels")
local schemer = require("lual.utils.schemer")

local M = {}

-- Level validation schema (dynamic for custom levels)
function M.get_level_schema()
    return {
        fields = {
            level = { type = "number", values = schemer.enum(core_levels.get_all_levels()) }
        },
        on_extra_keys = "error"
    }
end

-- Custom levels validation schema
function M.get_custom_levels_schema()
    -- Custom validator to check that all values are numbers >= 1
    local function validate_level_values(custom_levels)
        for name, value in pairs(custom_levels) do
            if type(value) ~= "number" then
                return false, "Level value for '" .. name .. "' must be a number, got " .. type(value)
            end
            if value < 1 then
                return false, "Level value for '" .. name .. "' must be at least 1, got " .. value
            end
        end
        return true
    end

    return {
        type = "table",
        unique_values = true, -- Ensure no duplicate level values
        custom_validator = validate_level_values
    }
end

return M
