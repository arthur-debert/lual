--- Command Line Verbosity Configuration Schema
-- Schema definition for command-line driven logging level configuration

local M = {}

-- Command line verbosity configuration schema
M.command_line_schema = {
    fields = {
        mapping = { type = "table", required = false },
        auto_detect = { type = "boolean", required = false }
    }
}

return M
