local unpack = unpack or table.unpack

--[[
High-Level API Draft for a Lua Logging Library

This outlines the main functions and their intended signatures.
No function bodies are implemented at this stage.
]]

-- Main Logging Module (e.g., 'log')
local log = {}

-- local ingest = require("lual.ingest") -- No longer directly needed here for logger methods
local core_levels = require("lual.core.levels")
local logger_class = require("lual.core.logger_class")

log.levels = core_levels.definition
log.get_logger = logger_class.get_logger

-- Removed _loggers_cache and the entire log.get_logger function body
-- as well as the new_logger table definition and its methods.
-- These are now in core.logger_class.lua

-- =============================================================================
-- 1. Logger Creation / Retrieval
-- =============================================================================
-- The actual log.get_logger is now assigned from logger_class above.

-- =============================================================================
-- 2. Core Logging Functions (Convenience on the main 'log' module)
--    These would typically use the root logger or a default logger.
-- =============================================================================

--- Logs a message with DEBUG severity.
-- @param logger_name (string) The name of the logger to use.
-- @param message (string) The message to log.
-- @param ... (any) Additional arguments to be formatted into the message (optional).
function log.debug(logger_name, message, ...)
  local target_logger = log.get_logger(logger_name)
  target_logger:debug(message, ...)
end

--- Logs a message with INFO severity.
-- @param logger_name (string) The name of the logger to use.
-- @param message (string) The message to log.
-- @param ... (any) Additional arguments to be formatted into the message (optional).
function log.info(logger_name, message, ...)
  local target_logger = log.get_logger(logger_name)
  target_logger:info(message, ...)
end

--- Logs a message with WARNING severity.
-- @param logger_name (string) The name of the logger to use.
-- @param message (string) The message to log.
-- @param ... (any) Additional arguments to be formatted into the message (optional).
function log.warn(logger_name, message, ...)
  local target_logger = log.get_logger(logger_name)
  target_logger:warn(message, ...)
end

--- Logs a message with ERROR severity.
-- @param logger_name (string) The name of the logger to use.
-- @param message (string) The message to log.
-- @param ... (any) Additional arguments to be formatted into the message (optional).
function log.error(logger_name, message, ...)
  local target_logger = log.get_logger(logger_name)
  target_logger:error(message, ...)
end

--- Logs a message with CRITICAL severity.
-- @param logger_name (string) The name of the logger to use.
-- @param message (string) The message to log.
-- @param ... (any) Additional arguments to be formatted into the message (optional).
function log.critical(logger_name, message, ...)
  local target_logger = log.get_logger(logger_name)
  target_logger:critical(message, ...)
end

-- =============================================================================
-- 3. Configuration
-- =============================================================================

--- Sets the logging level for a specific logger or a pattern.
-- @param logger_name_pattern (string) The logger name or pattern (e.g., "my.module", "engine.gas.*", "*").
-- @param level (number or string) The log level (e.g., log.levels.INFO or "INFO").
function log.set_level(logger_name_pattern, level)
  -- This function needs to be implemented to find matching loggers (possibly from _loggers_cache if made accessible)
  -- For now, it's a placeholder. A full implementation might iterate _loggers_cache or use a more complex pattern matching.
  -- This is a global configuration affecting potentially multiple loggers.
  local target_logger = log.get_logger(logger_name_pattern) -- Simplified: assumes exact name for now
  if target_logger and target_logger.set_level then
    local actual_level = level
    if type(level) == "string" then
      actual_level = log.levels[level:upper()]
    end
    if actual_level then
      target_logger:set_level(actual_level)
    else
      io.stderr:write("Unknown level: " .. tostring(level) .. "\n")
    end
  end
end

--- Adds a handler and its associated formatter to a logger or pattern.
-- @param logger_name_pattern (string) The logger name or pattern.
-- @param handler_func (function) The handler function.
-- @param formatter_func (function) The formatter function for this handler.
-- @param handler_config (table, optional) Configuration specific to the handler (e.g., filepath for file handler).
function log.add_handler(logger_name_pattern, handler_func, formatter_func, handler_config)
  -- Similar to set_level, this is a global config. Simplified for now.
  local target_logger = log.get_logger(logger_name_pattern)
  if target_logger and target_logger.add_handler then
    target_logger:add_handler(handler_func, formatter_func, handler_config)
  end
end

--- Removes all handlers for a given logger or pattern.
-- @param logger_name_pattern (string) The logger name or pattern.
function log.remove_handlers(logger_name_pattern)
  local target_logger = log.get_logger(logger_name_pattern)
  if target_logger then
    target_logger.handlers = {}
  end
end

--- Resets all logging configuration to defaults.
function log.reset_config()
  logger_class.reset_cache()
  log.init_default_config()
end

-- =============================================================================
-- 4. Handler Definitions (Function Signatures)
-- =============================================================================

log.handlers = {}

--- Handler that writes log messages to a stream (e.g., io.stdout, io.stderr).
-- @param record (table) A table containing log record details:
--                      {
--                        level_name = "INFO",
--                        level_no = 20,
--                        logger_name = "my.module",
--                        message = "Formatted log message", -- Already formatted by a formatter
--                        timestamp = 1678886400, -- Example timestamp
--                        raw_message = "Original message with %s", -- Before formatting with '...'
--                        args = {...} -- Original '...' arguments
--                      }
-- @param config (table, optional) Handler-specific configuration. For stream_handler,
--                                  this could specify the stream (e.g., { stream = io.stderr }).
--                                  Defaults to io.stdout.
function log.handlers.stream_handler(record, config)
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
    -- Fallback to printing an error message to io.stderr if writing to the stream failed
    local error_message = string.format("Error writing to stream: %s\n", tostring(err))
    io.stderr:write(error_message)
    -- Optionally, could re-raise the error or handle it in a more sophisticated way
  end
end

--- Handler that writes log messages to a file.
-- @param record (table) The log record (see stream_handler for structure).
-- @param config (table) Handler-specific configuration. Must include:
--                     { filepath = "path/to/logfile.log", mode = "a" }
--                     mode defaults to "a" (append).
function log.handlers.file_handler(record, config)
  -- Implementation would open/append record.message to the specified file.
  -- Needs to handle file opening/closing, errors, etc.
end

-- =============================================================================
-- 5. Formatter Definitions (Function Signatures)
-- =============================================================================

log.formatters = {}

--- Formatter that returns a plain text representation of the log record.
-- @param record (table) A table containing log record details (similar to handler's input,
--                      but `message` here is the raw message before `...` args are applied):
--                      {
--                        level_name = "INFO",
--                        level_no = 20,
--                        logger_name = "my.module",
--                        message_fmt = "User %s logged in from %s", -- The message string with format specifiers
--                        args = {"john.doe", "192.168.1.100"}, -- The arguments for string.format
--                        timestamp = 1678886400,
--                        -- Potentially other fields like filename, lineno if captured
--                      }
-- @return (string) The formatted log message string.
function log.formatters.plain_formatter(record)
  local timestamp_str = os.date("!%Y-%m-%d %H:%M:%S", record.timestamp)
  local msg_args = record.args or {}
  -- Ensure unpack has something to work with, even if empty
  if type(msg_args) ~= "table" or msg_args.n == nil then msg_args = {} end
  local message = string.format(record.message_fmt, unpack(msg_args))
  return string.format("%s %s [%s] %s",
    timestamp_str,
    record.level_name or "UNKNOWN_LEVEL",
    record.logger_name or "UNKNOWN_LOGGER",
    message
  )
end

--- Formatter that returns a colorized text representation of the log record (using ANSI escape codes).
-- @param record (table) The log record (see plain_formatter for structure).
-- @return (string) The colorized formatted log message string.
function log.formatters.color_formatter(record)
  -- Example output: Similar to plain_formatter but with ANSI colors for level, logger name, etc.
end

-- =============================================================================
-- Initialization (Example: Set up a default root logger)
-- =============================================================================
function log.init_default_config()
  local root_logger = log.get_logger("root") -- Get the root logger

  -- Set its level to INFO
  if root_logger and root_logger.set_level then
    root_logger:set_level(log.levels.INFO)
  end

  -- Add a stream handler to it that uses io.stdout and the plain_formatter
  if root_logger and root_logger.add_handler and log.handlers and log.handlers.stream_handler and log.formatters and log.formatters.plain_formatter then
    root_logger:add_handler(
      log.handlers.stream_handler,
      log.formatters.plain_formatter,
      { stream = io.stdout } -- Explicitly set stdout
    )
  end
end

log.init_default_config() -- Call this to set up defaults when the module is loaded.

return log
