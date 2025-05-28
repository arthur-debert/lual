local dkjson = require("dkjson")
local time_utils = require("lual.utils.time")

--- Formatter that returns a JSON representation of the log record.
-- @param record (table) A table containing log record details
-- @param config (table) Optional configuration for JSON formatting
-- @return (string) The formatted log message as a JSON string.
local function json(record, config)
    config = config or {}

    -- Prepare the JSON object
    local json_record = {
        timestamp = record.timestamp,
        timestamp_iso = time_utils.format_iso_timestamp(record.timestamp, record.timezone),
        timezone = record.timezone or "local",
        level = record.level_name or "UNKNOWN_LEVEL",
        logger = record.logger_name or "UNKNOWN_LOGGER",
        message_fmt = record.message_fmt,
        args = record.args or {},
    }

    -- Format the actual message
    local msg_args = record.args or {}
    if type(msg_args) ~= "table" then
        msg_args = {}
    end

    -- Use pcall to safely format the message
    local status, formatted_message = pcall(function()
        return string.format(record.message_fmt, table.unpack(msg_args))
    end)

    if status then
        json_record.message = formatted_message
    else
        -- If formatting fails, just use the message format as-is
        json_record.message = record.message_fmt
        json_record.format_error = "Failed to format message with provided arguments"
    end

    -- Add caller info if available
    if record.caller_info then
        json_record.caller_info = record.caller_info
    end

    -- Add any extra fields from the record
    for key, value in pairs(record) do
        if not json_record[key] and key ~= "level_name" and key ~= "logger_name" then
            json_record[key] = value
        end
    end

    -- Configure JSON encoding options
    local encode_options = {
        indent = config.pretty and true or false,
        exception = function(reason, value, state, defaultmessage)
            -- Handle non-serializable values gracefully
            return string.format("\"[non-serializable: %s]\"", type(value))
        end
    }

    local json_string, err = dkjson.encode(json_record, encode_options)
    if not json_string then
        -- Fallback if JSON encoding fails
        return string.format('{"error":"JSON encoding failed: %s","original_message":"%s"}',
            err or "unknown error",
            (record.message_fmt or ""):gsub('"', '\\"'))
    end

    return json_string
end

return json
