local unpack = unpack or table.unpack

--[[
High-Level API Draft for a Lua Logging Library

This outlines the main functions and their intended signatures.
No function bodies are implemented at this stage.
]]

-- Main Logging Module (e.g., 'log')
local log = {}

local core_levels = require("lual.core.levels")
local logger_class = require("lual.core.logger_class")
local all_handlers = require("lual.handlers.init")     -- Require the new handlers init
local all_formatters = require("lual.formatters.init") -- Require the new formatters init

log.levels = core_levels.definition
log.get_logger = logger_class.get_logger
log.handlers = all_handlers     -- Assign the handlers table
log.formatters = all_formatters -- Assign the formatters table

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
  local target_logger = log.get_logger(logger_name_pattern)
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
-- 4. Handler Definitions (Function Signatures) - REMOVED
-- =============================================================================
-- log.handlers = {} -- This line is removed
-- All function log.handlers.stream_handler(...) etc. are removed.

-- =============================================================================
-- 5. Formatter Definitions (Function Signatures) - REMOVED
-- =============================================================================
-- log.formatters = {} -- This line is removed
-- All function log.formatters.plain_formatter(...) etc. are removed.

-- =============================================================================
-- Initialization (Example: Set up a default root logger)
-- =============================================================================
function log.init_default_config()
  local root_logger = log.get_logger("root")
  if root_logger and root_logger.set_level then
    root_logger:set_level(log.levels.INFO)
  end
  if root_logger and root_logger.add_handler and log.handlers and log.handlers.stream_handler and log.formatters and log.formatters.plain_formatter then
    root_logger:add_handler(
      log.handlers.stream_handler,
      log.formatters.plain_formatter,
      { stream = io.stdout }
    )
  end
end

log.init_default_config()

return log
