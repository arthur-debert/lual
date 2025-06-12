--- Async Configuration Schema
-- Schema definition for async configuration validation

local M = {}

-- Async configuration schema
M.async_schema = {
    fields = {
        enabled = {
            type = "boolean",
            required = false,
            default = false
        },
        backend = {
            type = "string",
            required = false,
            values = { "coroutines", "libuv" },
            default = "coroutines"
        },
        batch_size = {
            type = "number",
            required = false,
            min = 1,
            default = 100
        },
        flush_interval = {
            type = "number",
            required = false,
            min = 0.001, -- Greater than 0
            default = 1.0
        },
        max_queue_size = {
            type = "number",
            required = false,
            min = 1,
            default = 1000
        },
        overflow_strategy = {
            type = "string",
            required = false,
            values = { "drop_oldest", "drop_newest", "block" },
            default = "drop_oldest"
        }
    },
    on_extra_keys = "error"
}

return M
