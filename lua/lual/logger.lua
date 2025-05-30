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
local all_dispatchers = require("lual.dispatchers.init")   -- Require the new dispatchers init
local all_presenters = require("lual.presenters.init")     -- Require the new presenters init
local all_transformers = require("lual.transformers.init") -- Require the new transformers init

log.levels = core_levels.definition
log.logger = engine.logger          -- Primary API for creating loggers
log.logger = engine.logger          -- Backward compatibility alias
log.dispatchers = all_dispatchers   -- Assign the dispatchers table
log.presenters = all_presenters     -- Assign the presenters table
log.transformers = all_transformers -- Assign the transformers table

-- =============================================================================
-- FLAT NAMESPACE CONSTANTS FOR QUICK ACCESS
-- =============================================================================

-- Level constants (flat namespace)
log.debug = core_levels.definition.DEBUG
log.info = core_levels.definition.INFO
log.warning = core_levels.definition.WARNING
log.error = core_levels.definition.ERROR
log.critical = core_levels.definition.CRITICAL
log.none = core_levels.definition.NONE

-- Dispatcher constants (string identifiers for config API)
log.console = "console"
log.file = "file"

-- Presenter constants (string identifiers for config API)
log.text = "text"
log.color = "color"
log.json = "json"

-- Timezone constants
log.local_time = "local"
log.utc = "utc"

-- Transformer constants
log.noop = "noop"

-- =============================================================================
-- BACKWARD COMPATIBILITY: lib namespace (deprecated)
-- =============================================================================

-- Keep lib namespace for backward compatibility but mark as deprecated
log.lib = {
  -- dispatcher shortcuts
  console = all_dispatchers.console_dispatcher,
  file = all_dispatchers.file_dispatcher,
  syslog = all_dispatchers.syslog_dispatcher,

  -- PRESENTER shortcuts (call factories with default config for backward compatibility)
  text = all_presenters.text(),
  color = all_presenters.color(),
  json = all_presenters.json(),

  -- TRANSFORMER shortcuts (call factories with default config for backward compatibility)
  noop = all_transformers.noop_transformer()
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
-- 4. dispatcher Definitions (Function Signatures) - REMOVED
-- =============================================================================
-- log.dispatchers = {} -- This line is removed
-- All function log.dispatchers.console_dispatcher(...) etc. are removed.

-- =============================================================================
-- 5. PRESENTER Definitions (Function Signatures) - REMOVED
-- =============================================================================
-- log.presenters = {} -- This line is removed
-- All function log.presenters.text(...) etc. are removed.

-- =============================================================================
-- Initialization (Example: Set up a default root logger)
-- =============================================================================
function log.init_default_config()
  local root_logger = log.logger("root")
  if root_logger then
    root_logger.dispatchers = {} -- Clear existing default dispatchers
    if root_logger.set_level then
      root_logger:set_level(log.levels.INFO)
    end
    if root_logger.add_dispatcher and log.dispatchers and log.dispatchers.console_dispatcher and log.presenters and log.presenters.text then
      root_logger:add_dispatcher(
        log.dispatchers.console_dispatcher,
        log.presenters.text,
        { stream = io.stdout }
      )
    end
  end
end

log.init_default_config()

return log
