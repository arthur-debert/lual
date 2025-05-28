-- No need to define unpack since we're explicitly using table.unpack

local time_utils = require("lual.utils.time")

--- Factory that creates a text formatter function
-- @param config (table, optional) Configuration for the text formatter
-- @return function The formatter function with schema attached
local function text_formatter_factory(config)
    config = config or {}

    -- Create the actual formatter function
    local function formatter_func(record)
        local timestamp_str = time_utils.format_timestamp(record.timestamp, record.timezone)
        local msg_args = record.args or {}
        if type(msg_args) ~= "table" then msg_args = {} end -- Ensure msg_args is a table

        local message
        if record.message_fmt and type(record.message_fmt) == "string" then
            message = string.format(record.message_fmt, table.unpack(msg_args)) -- Explicitly use table.unpack
        elseif record.context and type(record.context) == "table" then
            -- For context-only logs, create a simple representation of the context
            local context_parts = {}
            for k, v in pairs(record.context) do
                table.insert(context_parts, string.format("%s=%s", tostring(k), tostring(v)))
            end
            message = "{" .. table.concat(context_parts, ", ") .. "}"
        else
            message = ""
        end

        return string.format("%s %s [%s] %s",
            timestamp_str,
            record.level_name or "UNKNOWN_LEVEL",
            record.logger_name or "UNKNOWN_LOGGER",
            message
        )
    end

    -- Create a callable table with schema
    local formatter_with_schema = {
        schema = {} -- text formatter has no config options currently
    }

    -- Make it callable
    setmetatable(formatter_with_schema, {
        __call = function(_, record)
            return formatter_func(record)
        end
    })

    return formatter_with_schema
end

return text_formatter_factory
