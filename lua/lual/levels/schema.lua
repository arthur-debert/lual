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
    -- Get built-in level values that custom levels cannot use
    local builtin_values = {}
    for _, value in pairs(core_levels.definition) do
        builtin_values[value] = true -- Use hash for O(1) lookup
    end

    -- Custom validator to check that all values are numbers >= 1 and don't conflict with built-ins
    local function validate_level_values(custom_levels)
        for name, value in pairs(custom_levels) do
            if type(value) ~= "number" then
                return false, "Level value for '" .. name .. "' must be a number, got " .. type(value)
            end
            if value < 1 then
                return false, "Level value for '" .. name .. "' must be at least 1, got " .. value
            end
            -- Check for built-in level conflicts using schemer's forbidden value concept
            if builtin_values[value] then
                return false,
                    "Level value '" ..
                    value .. "' for '" .. name .. "' is a forbidden value (conflicts with built-in level)"
            end
        end
        return true
    end

    -- Custom validator for level names (validates all keys in the table)
    local function validate_level_names(custom_levels)
        for name, value in pairs(custom_levels) do
            if type(name) ~= "string" then
                return false, "Level name must be a string, got " .. type(name)
            end

            if name == "" then
                return false, "Level name cannot be empty"
            end

            -- Must be lowercase
            if name ~= name:lower() then
                return false, "Level name '" .. name .. "' must be lowercase"
            end

            -- Must be valid Lua identifier starting with letter (not underscore)
            -- This combines the two original rules into one precise pattern
            if not name:match("^[a-z][a-z0-9_]*$") then
                return false,
                    "Level name '" ..
                    name ..
                    "' must be a valid Lua identifier starting with a lowercase letter (no underscores at start - reserved)"
            end
        end
        return true
    end

    return {
        type = "table",
        unique_values = true, -- Ensure no duplicate level values
        custom_validator = function(custom_levels)
            -- Validate names first
            local name_valid, name_error = validate_level_names(custom_levels)
            if not name_valid then
                return false, name_error
            end

            -- Then validate values (including built-in conflicts)
            local value_valid, value_error = validate_level_values(custom_levels)
            if not value_valid then
                return false, value_error
            end

            return true
        end
    }
end

return M
