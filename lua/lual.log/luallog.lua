--[[
High-Level API Draft for a Lua Logging Library

This outlines the main functions and their intended signatures.
No function bodies are implemented at this stage.
]]

-- Main Logging Module (e.g., 'log')
local log = {}

-- =============================================================================
-- 1. Logger Creation / Retrieval
-- =============================================================================

--- Returns a logger instance. If a logger with the given name already exists,
--- it's returned; otherwise, a new one is created.
-- @param name (string) The name of the logger (e.g., "my.module", "engine.gas").
--                      If nil or empty, returns the root logger.
-- @return (table) The logger object.
function log.get_logger(name)
  -- Logger object would internally have methods like:
  -- logger:debug(message, ...)
  -- logger:info(message, ...)
  -- logger:warn(message, ...)
  -- logger:error(message, ...)
  -- logger:critical(message, ...)
  -- logger:set_level(level)
  -- logger:add_handler(handler_func, formatter_func) -- Simplified: handler takes formatter
  -- logger:set_propagate(boolean) -- Whether to pass messages to parent logger's handlers
end

-- =============================================================================
-- 2. Core Logging Functions (Convenience on the main 'log' module)
--    These would typically use the root logger or a default logger.
-- =============================================================================

--- Logs a message with DEBUG severity.
-- @param logger_name (string) The name of the logger to use.
-- @param message (string) The message to log.
-- @param ... (any) Additional arguments to be formatted into the message (optional).
function log.debug(logger_name, message, ...) end

--- Logs a message with INFO severity.
-- @param logger_name (string) The name of the logger to use.
-- @param message (string) The message to log.
-- @param ... (any) Additional arguments to be formatted into the message (optional).
function log.info(logger_name, message, ...) end

--- Logs a message with WARNING severity.
-- @param logger_name (string) The name of the logger to use.
-- @param message (string) The message to log.
-- @param ... (any) Additional arguments to be formatted into the message (optional).
function log.warn(logger_name, message, ...) end

--- Logs a message with ERROR severity.
-- @param logger_name (string) The name of the logger to use.
-- @param message (string) The message to log.
-- @param ... (any) Additional arguments to be formatted into the message (optional).
function log.error(logger_name, message, ...) end

--- Logs a message with CRITICAL severity.
-- @param logger_name (string) The name of the logger to use.
-- @param message (string) The message to log.
-- @param ... (any) Additional arguments to be formatted into the message (optional).
function log.critical(logger_name, message, ...) end

-- =============================================================================
-- 3. Configuration
-- =============================================================================

-- Log Levels (Constants)
log.levels = {
  DEBUG = 10,
  INFO = 20,
  WARNING = 30,
  ERROR = 40,
  CRITICAL = 50,
  NONE = 100 -- To disable logging for a specific logger
}

--- Sets the logging level for a specific logger or a pattern.
-- @param logger_name_pattern (string) The logger name or pattern (e.g., "my.module", "engine.gas.*", "*").
-- @param level (number or string) The log level (e.g., log.levels.INFO or "INFO").
function log.set_level(logger_name_pattern, level) end

--- Adds a handler and its associated formatter to a logger or pattern.
-- @param logger_name_pattern (string) The logger name or pattern.
-- @param handler_func (function) The handler function.
-- @param formatter_func (function) The formatter function for this handler.
-- @param handler_config (table, optional) Configuration specific to the handler (e.g., filepath for file handler).
function log.add_handler(logger_name_pattern, handler_func, formatter_func, handler_config) end

--- Removes all handlers for a given logger or pattern.
-- @param logger_name_pattern (string) The logger name or pattern.
function log.remove_handlers(logger_name_pattern) end

--- Resets all logging configuration to defaults.
function log.reset_config() end

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
  -- Implementation would write record.message to the specified stream.
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
  -- Example output: "2023-03-15 10:00:00 INFO [my.module] User john.doe logged in from 192.168.1.100"
  -- Would use string.format(record.message_fmt, unpack(record.args or {}))
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
  -- log.set_level("*", log.levels.INFO)
  -- log.add_handler("*", log.handlers.stream_handler, log.formatters.plain_formatter)
end

-- log.init_default_config() -- Call this to set up defaults when the module is loaded.

return log
