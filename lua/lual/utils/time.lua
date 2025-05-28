--- Time utility functions for lual logging
-- Provides timezone-aware timestamp formatting

local M = {}

--- Formats a timestamp according to the specified timezone
-- @param timestamp (number) Unix timestamp
-- @param timezone (string) Either "local" or "utc"
-- @param format (string, optional) Date format string, defaults to "%Y-%m-%d %H:%M:%S"
-- @return (string) Formatted timestamp string
function M.format_timestamp(timestamp, timezone, format)
    format = format or "%Y-%m-%d %H:%M:%S"
    timezone = timezone or "local"

    if string.lower(timezone) == "utc" then
        return os.date("!" .. format, timestamp)
    else
        return os.date(format, timestamp)
    end
end

--- Formats a timestamp for ISO 8601 format according to the specified timezone
-- @param timestamp (number) Unix timestamp
-- @param timezone (string) Either "local" or "utc"
-- @return (string) ISO 8601 formatted timestamp string
function M.format_iso_timestamp(timestamp, timezone)
    timezone = timezone or "local"

    if string.lower(timezone) == "utc" then
        return os.date("!%Y-%m-%dT%H:%M:%SZ", timestamp)
    else
        -- For local time, we don't add the Z suffix as it's not UTC
        -- We could add timezone offset but that's complex in pure Lua
        return os.date("%Y-%m-%dT%H:%M:%S", timestamp)
    end
end

return M
