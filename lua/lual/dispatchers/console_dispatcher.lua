--- dispatcher that writes log messages to a stream (e.g., io.stdout, io.stderr).
-- @param record (table|string) A table containing log record details or a string message
-- @param config (table, optional) dispatcher-specific configuration.
local function console_dispatcher(record, config)
    local stream = io.stdout
    if config and config.stream then
        stream = config.stream
    end

    local success, err = pcall(function()
        -- Handle both string messages and record tables
        local message
        if type(record) == "string" then
            message = record
        else
            -- First try the message field for backward compatibility
            message = record.message or record.presented_message or record.formatted_message or record.message_fmt
            -- Add timestamp and level if available
            if record.timestamp and record.level_name then
                local timestamp = os.date("%Y-%m-%d %H:%M:%S", record.timestamp)
                message = string.format("%s %s [%s] %s",
                    timestamp,
                    record.level_name,
                    record.logger_name,
                    message)
            end
        end

        stream:write(message)
        stream:write("\n") -- Add a newline after the message for better readability
        stream:flush()     -- Ensure the message is written immediately
    end)

    if not success then
        local error_message = string.format("Error writing to stream: %s\n", tostring(err))
        io.stderr:write(error_message)
    end
end

return console_dispatcher
