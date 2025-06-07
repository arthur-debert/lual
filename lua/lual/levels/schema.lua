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
        }
    }
end

return M
