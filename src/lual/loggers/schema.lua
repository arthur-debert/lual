--- Logger Configuration Schema
-- Schema definition for logger configuration validation

local core_levels = require("lual.levels")
local schemer = require("lual.utils.schemer")

local M = {}

-- Logger configuration schema
M.logger_schema = {
    fields = {
        level = {
            type = "number",
            required = false,
            values = schemer.enum(core_levels.definition)
        },
        pipelines = {
            type = "table",
            required = false
        },
        propagate = {
            type = "boolean",
            required = false
        }
    },
    on_extra_keys = "error"
}

return M
