local unpack = unpack or table.unpack

--[[
High-Level API Draft for a Lua Logging Library

This outlines the main functions and their intended signatures.
No function bodies are implemented at this stage.
]]

-- Main Logging Module (e.g., 'log')
local log = {}

local core_levels = require("lual.core.levels")
local engine = require("lual.core.engine")
local all_outputs = require("lual.outputs.init")       -- Require the new outputs init
local all_formatters = require("lual.formatters.init") -- Require the new formatters init

log.levels = core_levels.definition
log.get_logger = engine.get_logger
log.outputs = all_outputs       -- Assign the outputs table
log.formatters = all_formatters -- Assign the formatters table

-- Removed _loggers_cache and the entire log.get_logger function body
-- as well as the new_logger table definition and its methods.
-- These are now in core.engine.lua

-- =============================================================================
-- 1. Logger Creation / Retrieval
-- =============================================================================
-- The actual log.get_logger is now assigned from engine above.

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

--- Adds a output and its associated formatter to a logger or pattern.
-- @param logger_name_pattern (string) The logger name or pattern.
-- @param output_func (function) The output function.
-- @param formatter_func (function) The formatter function for this output.
-- @param output_config (table, optional) Configuration specific to the output (e.g., filepath for file output).
function log.add_output(logger_name_pattern, output_func, formatter_func, output_config)
  local target_logger = log.get_logger(logger_name_pattern)
  if target_logger and target_logger.add_output then
    target_logger:add_output(output_func, formatter_func, output_config)
  end
end

--- Removes all outputs for a given logger or pattern.
-- @param logger_name_pattern (string) The logger name or pattern.
function log.remove_outputs(logger_name_pattern)
  local target_logger = log.get_logger(logger_name_pattern)
  if target_logger then
    target_logger.outputs = {}
  end
end

--- Resets all logging configuration to defaults.
function log.reset_config()
  engine.reset_cache()
  log.init_default_config()
end

-- =============================================================================
-- 4. Output Definitions (Function Signatures) - REMOVED
-- =============================================================================
-- log.outputs = {} -- This line is removed
-- All function log.outputs.console_output(...) etc. are removed.

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
  if root_logger then
    root_logger.outputs = {} -- Clear existing default outputs
    if root_logger.set_level then
      root_logger:set_level(log.levels.INFO)
    end
    if root_logger.add_output and log.outputs and log.outputs.console_output and log.formatters and log.formatters.plain_formatter then
      root_logger:add_output(
        log.outputs.console_output,
        log.formatters.plain_formatter,
        { stream = io.stdout }
      )
    end
  end
end

log.init_default_config()

return log
