--- File Output Configuration Schema
-- Schema definition for file output configuration validation

local M = {}

-- File output configuration schema
M.file_schema = {
    fields = {
        path = {
            type = "string",
            required = true
        }
    },
    on_extra_keys = "ignore" -- Allow additional config for future extensions
}

return M
