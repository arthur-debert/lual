-- Color formatter for lual.log inspired by the rich Python library
-- Provides colored terminal output using ANSI color codes

local unpack = unpack or table.unpack -- Ensure unpack is available

-- Define a table with ANSI color codes
local colors = {
    -- Foreground colors
    black = "\27[30m",
    red = "\27[31m",
    green = "\27[32m",
    yellow = "\27[33m",
    blue = "\27[34m",
    magenta = "\27[35m",
    cyan = "\27[36m",
    white = "\27[37m",
    -- Bright foreground colors
    bright_black = "\27[90m",
    bright_red = "\27[91m",
    bright_green = "\27[92m",
    bright_yellow = "\27[93m",
    bright_blue = "\27[94m",
    bright_magenta = "\27[95m",
    bright_cyan = "\27[96m",
    bright_white = "\27[97m",
    -- Special codes
    reset = "\27[0m",
    bold = "\27[1m",
    dim = "\27[2m",
    italic = "\27[3m",
    underline = "\27[4m",
}

-- Default level color mapping
local default_level_colors = {
    DEBUG = "blue",
    INFO = "green",
    WARNING = "yellow",
    ERROR = "red",
    CRITICAL = "bright_red",
    NONE = "white",
    -- Default for unknown levels
    default = "white"
}

-- Format a specific part of the log message with color
local function colorize(text, color_name)
    if not color_name or not colors[color_name] then
        return text
    end
    return colors[color_name] .. text .. colors.reset
end

-- Formatter that returns a colored text representation of the log record.
-- @param record (table) A table containing log record details
-- @param config (table) Configuration options for the formatter
-- @return (string) The formatted log message string with ANSI color codes.
local function color_formatter(record, config)
    config = config or {}
    local level_colors = config.level_colors or default_level_colors
    local timestamp_str = os.date("!%Y-%m-%d %H:%M:%S", record.timestamp)
    local msg_args = record.args or {}
    -- Make sure msg_args is a table for string.format to use
    if type(msg_args) ~= "table" then msg_args = {} end
    -- Use pcall to safely format the message
    local message
    local status, result = pcall(function()
        return string.format(record.message_fmt, unpack(msg_args))
    end)
    if status then
        message = result
    else
        -- If formatting fails, just use the message format as-is
        message = record.message_fmt
    end
    -- Get the appropriate color for this level
    local level_name = record.level_name or "UNKNOWN_LEVEL"
    local level_color = level_colors[level_name] or level_colors.default
    -- Colorize the logger name with a different color for visual separation
    local logger_name = record.logger_name or "UNKNOWN_LOGGER"
    return string.format("%s %s [%s] %s",
        colorize(timestamp_str, "dim"),
        colorize(level_name, level_color),
        colorize(logger_name, "cyan"),
        message
    )
end

return color_formatter