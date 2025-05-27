--- Output that writes log messages to a stream (e.g., io.stdout, io.stderr).
-- @param record (table) A table containing log record details
-- @param config (table, optional) Output-specific configuration.
local function console_output(record, config)
    local stream = io.stdout
    if config and config.stream then
        stream = config.stream
    end

    local success, err = pcall(function()
        stream:write(record.message)
        stream:write("\n") -- Add a newline after the message for better readability
        stream:flush()     -- Ensure the message is written immediately
    end)

    if not success then
        local error_message = string.format("Error writing to stream: %s\n", tostring(err))
        io.stderr:write(error_message)
    end
end

return console_output
