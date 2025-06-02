local unpack = unpack or table.unpack

--[[
High-Level API Draft for a Lua Logging Library

This outlines the main functions and their intended signatures.
No function bodies are implemented at this stage.
]]

-- Main Logging Module (e.g., 'log')
local log = {}

local core_levels = require("lua.lual.v2.levels")
-- V2 system is now the default
local v2_api = require("lual.v2")
local all_dispatchers = require("lual.dispatchers.init")   -- Require the new dispatchers init
local all_presenters = require("lual.presenters.init")     -- Require the new presenters init
local all_transformers = require("lual.transformers.init") -- Require the new transformers init

log.levels = core_levels.definition
log.logger = v2_api.logger          -- V2 API is now the default
log.dispatchers = all_dispatchers   -- Assign the dispatchers table
log.presenters = all_presenters     -- Assign the presenters table
log.transformers = all_transformers -- Assign the transformers table

-- =============================================================================
-- FLAT NAMESPACE CONSTANTS FOR QUICK ACCESS
-- =============================================================================

-- Level constants (flat namespace)
log.notset = core_levels.definition.NOTSET
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
-- NEW ROOT LOGGER CONFIGURATION API
-- =============================================================================

--- Creates and configures the root logger using the v2 system.
--- @param config table The root logger configuration
--- @return table The updated configuration
function log.config(config)
  return v2_api.config(config or {})
end

--- Gets the configuration of the root logger
--- @return table The root logger configuration
function log.get_config()
  return v2_api.get_config()
end

-- Add LEVELS mapping for external validation and use
log.LEVELS = {
  notset = core_levels.definition.NOTSET,
  debug = core_levels.definition.DEBUG,
  info = core_levels.definition.INFO,
  warning = core_levels.definition.WARNING,
  error = core_levels.definition.ERROR,
  critical = core_levels.definition.CRITICAL,
  none = core_levels.definition.NONE
}

-- =============================================================================
-- 1. Logger Creation / Retrieval
-- =============================================================================
-- The actual log.logger is now assigned from engine above.

--- Resets all logging configuration to defaults.
function log.reset_config()
  v2_api.reset_config()
  v2_api.reset_cache()
end

-- =============================================================================
-- Remove automatic initialization - root logger only created via lual.config({})
-- =============================================================================

-- =============================================================================
-- V2 API NAMESPACE
-- =============================================================================

-- Add the v2 namespace for the new API
log.v2 = require("lual.v2")

return log
