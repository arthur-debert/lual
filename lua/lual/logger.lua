local unpack = unpack or table.unpack

--[[
High-Level API Draft for a Lua Logging Library

This outlines the main functions and their intended signatures.
No function bodies are implemented at this stage.
]]

-- Main Logging Module (e.g., 'log')
local log = {}

local core_levels = require("lual.core.levels")
local engine = require("lual.core.logging")
local all_outputs = require("lual.outputs.init")       -- Require the new outputs init
local all_formatters = require("lual.formatters.init") -- Require the new formatters init

log.levels = core_levels.definition
log.logger = engine.logger      -- Primary API for creating loggers
log.logger = engine.logger      -- Backward compatibility alias
log.outputs = all_outputs       -- Assign the outputs table
log.formatters = all_formatters -- Assign the formatters table

-- Add convenient shortcuts for outputs and formatters
log.lib = {
  -- Output shortcuts
  console = all_outputs.console_output,
  file = all_outputs.file_output,
  syslog = all_outputs.syslog_output,

  -- Formatter shortcuts
  text = all_formatters.text,
  color = all_formatters.color,
  json = all_formatters.json
}

-- Add LEVELS mapping for external validation and use
log.LEVELS = {
  debug = core_levels.definition.DEBUG,
  info = core_levels.definition.INFO,
  warning = core_levels.definition.WARNING,
  error = core_levels.definition.ERROR,
  critical = core_levels.definition.CRITICAL,
  none = core_levels.definition.NONE
}

-- Removed _loggers_cache and the entire log.logger function body
-- as well as the new_logger table definition and its methods.
-- These are now in core.engine.lua

-- =============================================================================
-- 1. Logger Creation / Retrieval
-- =============================================================================
-- The actual log.logger is now assigned from engine above.

-- =============================================================================
-- 2. Core Logging Functions (Convenience on the main 'log' module) - REMOVED
--    These facade functions mixed logger names with logging parameters
-- =============================================================================

-- =============================================================================
-- 3. Configuration - REMOVED FACADE FUNCTIONS
-- =============================================================================

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
-- All function log.formatters.text(...) etc. are removed.

-- =============================================================================
-- Initialization (Example: Set up a default root logger)
-- =============================================================================
function log.init_default_config()
  local root_logger = log.logger("root")
  if root_logger then
    root_logger.outputs = {} -- Clear existing default outputs
    if root_logger.set_level then
      root_logger:set_level(log.levels.INFO)
    end
    if root_logger.add_output and log.outputs and log.outputs.console_output and log.formatters and log.formatters.text then
      root_logger:add_output(
        log.outputs.console_output,
        log.formatters.text,
        { stream = io.stdout }
      )
    end
  end
end

log.init_default_config()

return log
