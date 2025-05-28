-- Color formatter for lual.log inspired by the rich Python library
-- Provides colored terminal dispatcher using ANSI color codes

local unpack = unpack or table.unpack -- Ensure unpack is available
local time_utils = require("lual.utils.time")

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

--- Factory that creates a color formatter function
-- @param config (table, optional) Configuration for the color formatter
-- @return function The formatter function with schema attached
local function color_formatter_factory(config)
    config = config or {}

    -- Validate level_colors if provided
    if config.level_colors then
        if type(config.level_colors) ~= "table" then
            error("Color formatter 'level_colors' must be a table")
        end
    end

    local level_colors = config.level_colors or default_level_colors

    -- Create the actual formatter function
    local function formatter_func(record)
        local timestamp_str = time_utils.format_timestamp(record.timestamp, record.timezone)
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

    -- Create a callable table with schema
    local formatter_with_schema = {
        schema = {
            level_colors = {
                type = "table",
                required = false,
                description = "Custom color mapping for log levels"
            }
        }
    }

    -- Make it callable
    setmetatable(formatter_with_schema, {
        __call = function(_, record)
            return formatter_func(record)
        end
    })

    return formatter_with_schema
end

return color_formatter_factory
