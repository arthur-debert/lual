--- Live Level Configuration Schema
-- Schema definition for live log level changes through environment variables

local M = {}

-- Live level configuration schema
M.live_level_schema = {
    fields = {
        env_var = { type = "string", required = false },
        check_interval = { type = "number", required = false, min = 1 },
        enabled = { type = "boolean", required = false }
    }
}

return M
