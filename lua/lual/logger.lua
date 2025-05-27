--[[
High-Level API Draft for a Lua Logging Library

This outlines the main functions and their intended signatures.
No function bodies are implemented at this stage.
]]

-- Main Logging Module (e.g., 'log')
local log = {}

local ingest = require("lual.ingest") -- Require the ingest module

local _loggers_cache = {}
local _level_names_cache = {} -- Cache for level number to name mapping

-- Helper function to get level name from level number
local function get_level_name(level_no)
  if _level_names_cache[level_no] then
    return _level_names_cache[level_no]
  end
  for name, number in pairs(log.levels) do
    if number == level_no then
      _level_names_cache[level_no] = name
      return name
    end
  end
  return "UNKNOWN_LEVEL_NO_" .. tostring(level_no)
end

-- =============================================================================
-- 1. Logger Creation / Retrieval
-- =============================================================================

--- Returns a logger instance. If a logger with the given name already exists,
--- it's returned; otherwise, a new one is created.
-- @param name (string) The name of the logger (e.g., "my.module", "engine.gas").
--                      If nil or empty, returns the root logger.
-- @return (table) The logger object.
function log.get_logger(name)
  local logger_name = name
  if name == nil or name == "" then
    logger_name = "root"
  end

  if _loggers_cache[logger_name] then
    return _loggers_cache[logger_name]
  end

  local parent_logger = nil
  if logger_name ~= "root" then
    local parent_name_end = string.match(logger_name, "(.+)%.[^%.]+$")
    local parent_name
    if parent_name_end then
      parent_name = parent_name_end
    else
      parent_name = "root"
    end
    parent_logger = log.get_logger(parent_name) -- Recursive call to ensure parent exists
  end

  local new_logger = {
    name = logger_name,
    level = log.levels.INFO, -- Default level
    handlers = {},
    propagate = true,
    parent = parent_logger,

    debug = function(self, message_fmt, ...)
      self:log(log.levels.DEBUG, message_fmt, ...)
    end,
    info = function(self, message_fmt, ...)
      self:log(log.levels.INFO, message_fmt, ...)
    end,
    warn = function(self, message_fmt, ...)
      self:log(log.levels.WARNING, message_fmt, ...)
    end,
    error = function(self, message_fmt, ...)
      self:log(log.levels.ERROR, message_fmt, ...)
    end,
    critical = function(self, message_fmt, ...)
      self:log(log.levels.CRITICAL, message_fmt, ...)
    end,
    log = function(self, level_no, message_fmt, ...)
      if not self:is_enabled_for(level_no) then
        return
      end

      local info = debug.getinfo(3, "Sl") -- Check stack level carefully
      local filename = info.short_src
      if filename and string.sub(filename, 1, 1) == "@" then
        filename = string.sub(filename, 2)
      end

      local log_record = {
        level_no = level_no,
        level_name = get_level_name(level_no),
        message_fmt = message_fmt,
        args = table.pack(...), -- Use table.pack for varargs
        timestamp = os.time(),
        logger_name = self.name,
        source_logger_name = self.name, -- Initially the same as logger_name
        filename = filename,
        lineno = info.currentline
      }
      
      -- Ensure _G.log.dispatch_log_event is available or handle its absence
      -- Call the refactored dispatch_log_event from the ingest module
      ingest.dispatch_log_event(log_record, log.get_logger, log.levels)
    end,
    set_level = function(self, level)
      -- To be implemented: self.level = level (actual implementation in a later task)
      self.level = level -- Basic assignment for now
    end,
    add_handler = function(self, handler_func, formatter_func, handler_config)
      table.insert(self.handlers, {
        handler_func = handler_func,
        formatter_func = formatter_func,
        handler_config = handler_config or {} -- Ensure handler_config is at least an empty table
      })
    end,
    is_enabled_for = function(self, message_level_no)
      -- Ensure self.level is valid; NONE (100) means nothing is enabled unless message_level_no is also NONE
      if self.level == log.levels.NONE then
          return message_level_no == log.levels.NONE
      end
      return message_level_no >= self.level
    end,
    get_effective_handlers = function(self)
      local effective_handlers = {}
      local current_logger = self

      while current_logger do
        -- Add handlers from the current logger, along with its context
        for _, handler_item in ipairs(current_logger.handlers or {}) do
          -- Ensure handler_item has the expected structure from add_handler
          -- (e.g., handler_item = {handler_func=..., formatter_func=..., handler_config=...})
          table.insert(effective_handlers, {
            handler_func = handler_item.handler_func,
            formatter_func = handler_item.formatter_func,
            handler_config = handler_item.handler_config,
            owner_logger_name = current_logger.name,
            owner_logger_level = current_logger.level
          })
        end

        if not current_logger.propagate or not current_logger.parent then
          break -- Stop propagation if propagate is false or no parent
        end
        current_logger = current_logger.parent
      end
      return effective_handlers
    end
  }

  _loggers_cache[logger_name] = new_logger
  return new_logger
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
-- Moved _loggers_cache definition to the top. log.levels is defined here.
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
  local message = string.format(record.message_fmt, unpack(record.args or {}))
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
