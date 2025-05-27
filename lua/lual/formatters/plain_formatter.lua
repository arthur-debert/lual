-- No need to define unpack since we're explicitly using table.unpack

--- Formatter that returns a plain text representation of the log record.
-- @param record (table) A table containing log record details
-- @return (string) The formatted log message string.
local function plain_formatter(record)
    local timestamp_str = os.date("!%Y-%m-%d %H:%M:%S", record.timestamp)
    local msg_args = record.args or {}
    if type(msg_args) ~= "table" or msg_args.n == nil then msg_args = {} end
    local message = string.format(record.message_fmt, table.unpack(msg_args)) -- Explicitly use table.unpack
    return string.format("%s %s [%s] %s",
        timestamp_str,
        record.level_name or "UNKNOWN_LEVEL",
        record.logger_name or "UNKNOWN_LOGGER",
        message
    )
end

return plain_formatter
