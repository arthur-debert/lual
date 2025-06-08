--- Levels Configuration Schema
-- Schema definitions for 'level' and 'custom_levels' configuration keys

local core_levels = require("lual.levels")
local schemer = require("lual.utils.schemer")

local M = {}

-- Level validation schema (dynamic for custom levels)
function M.get_level_schema()
    return {
        fields = {
            level = {
                type = "number",
                values = schemer.enum(core_levels.get_all_levels()),
                not_allowed_values = { core_levels.definition.NOTSET } -- Root logger cannot be NOTSET
            }
        },
        on_extra_keys = "error"
    }
end

-- Custom levels validation schema
function M.get_custom_levels_schema()
    -- Build list of built-in level values that custom levels cannot use
    local forbidden_values = {}
    for _, value in pairs(core_levels.definition) do
        table.insert(forbidden_values, value)
    end

    -- Since schemer's main validate function only works with field-based schemas,
    -- we need to wrap our table validation in a field structure
    return {
        fields = {
            custom_levels = {
                type = "table",
                unique_values = true, -- Ensure no duplicate level values (declarative!)
                custom_validator = function(custom_levels)
                    -- Validate each key-value pair with streamlined logic inspired by declarative validation
                    for name, value in pairs(custom_levels) do
                        -- Key validation - consolidated and simplified
                        if type(name) ~= "string" then
                            return false, "Level name must be a string, got " .. type(name)
                        end
                        if name == "" then -- equivalent to not_allowed_values = {""}
                            return false, "Level name cannot be empty"
                        end
                        if not name:match("^[a-z][a-z0-9_]*$") then -- pattern validation
                            return false,
                                "Level name '" ..
                                name ..
                                "' must be a valid Lua identifier starting with a lowercase letter (no underscores at start - reserved)"
                        end

                        -- Value validation - using declarative concepts (type, min, max, not_allowed_values)
                        if type(value) ~= "number" then
                            return false, "Level value for '" .. name .. "' must be a number, got " .. type(value)
                        end
                        if value ~= math.floor(value) then
                            return false, "Level value for '" .. name .. "' must be an integer, got " .. tostring(value)
                        end
                        if value <= 10 then -- min = 11 equivalent
                            return false,
                                "Level value for '" .. name .. "' must be greater than 10 (DEBUG level), got " .. value
                        end
                        if value >= 40 then -- max = 39 equivalent
                            return false,
                                "Level value for '" .. name .. "' must be less than 40 (ERROR level), got " .. value
                        end

                        -- not_allowed_values check for built-in conflicts
                        for _, forbidden_value in ipairs(forbidden_values) do
                            if value == forbidden_value then
                                return false,
                                "Level value '" ..
                                    value ..
                                    "' for '" .. name .. "' is a forbidden value (conflicts with built-in level)"
                            end
                        end
                    end
                    return true
                end
            }
        },
        on_extra_keys = "error"
    }
end

return M
