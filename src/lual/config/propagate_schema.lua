--- Propagate Configuration Schema
-- Schema definition for propagate configuration validation

local M = {}

-- Propagate configuration schema
M.propagate_schema = {
    fields = {
        propagate = {
            type = "boolean",
            required = true
        }
    },
    on_extra_keys = "error"
}

return M
