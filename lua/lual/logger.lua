local unpack = unpack or table.unpack

--[[
High-Level API Draft for a Lua Logging Library

This outlines the main functions and their intended signatures.
]]

-- Main Logging Module (e.g., 'log')
local log = {}

local core_levels = require("lua.lual.levels")
local config_module = require("lual.config")
local dispatch_module = require("lual.dispatch")
local table_utils = require("lual.utils.table")
local caller_info = require("lual.utils.caller_info")
local all_dispatchers = require("lual.dispatchers.init")   -- Require the new dispatchers init
local all_presenters = require("lual.presenters.init")     -- Require the new presenters init
local all_transformers = require("lual.transformers.init") -- Require the new transformers init

-- Logger cache
local _logger_cache = {}

-- Logger prototype
local logger_prototype = {}

--- Gets the effective level for this logger, resolving NOTSET by inheritance
-- This implements the logic from step 2.5:
-- - If self.level is not lual.NOTSET, return self.level
-- - Else, if self is _root, return _root.level (it must have an explicit level)
-- - Else, recursively call self.parent:_get_effective_level()
function logger_prototype:_get_effective_level()
  -- Special case: if this is the _root logger, always use the current config level
  -- This ensures _root always reflects the current configuration
  if self.name == "_root" then
    local root_config = config_module.get_config()
    return root_config.level
  end

  -- If this logger has an explicit level (not NOTSET), use it
  if self.level ~= core_levels.definition.NOTSET then
    return self.level
  end

  -- Recursively call parent's _get_effective_level()
  if self.parent then
    return self.parent:_get_effective_level()
  end

  -- Fallback - this shouldn't normally happen in a well-formed hierarchy
  -- But return INFO as a safe default
  return core_levels.definition.INFO
end

--- Imperative API: Set the level for this logger
-- @param level number The new level
function logger_prototype:set_level(level)
  if type(level) ~= "number" then
    error("Level must be a number, got " .. type(level))
  end

  -- Validate that level is a known level value
  local valid_level = false
  for _, level_value in pairs(core_levels.definition) do
    if level == level_value then
      valid_level = true
      break
    end
  end
  if not valid_level then
    error("Invalid level value: " .. level)
  end

  self.level = level
end

--- Imperative API: Add a dispatcher to this logger
-- @param dispatcher_func function The dispatcher function
-- @param config table|nil Optional dispatcher configuration
function logger_prototype:add_dispatcher(dispatcher_func, config)
  if type(dispatcher_func) ~= "function" then
    error("Dispatcher must be a function, got " .. type(dispatcher_func))
  end

  table.insert(self.dispatchers, {
    dispatcher_func = dispatcher_func,
    config = config or {}
  })
end

--- Imperative API: Set propagate flag for this logger
-- @param propagate boolean Whether to propagate
function logger_prototype:set_propagate(propagate)
  if type(propagate) ~= "boolean" then
    error("Propagate must be a boolean, got " .. type(propagate))
  end

  self.propagate = propagate
end

--- Get configuration of this logger
-- @return table The logger configuration
function logger_prototype:get_config()
  return {
    name = self.name,
    level = self.level,
    dispatchers = self.dispatchers,
    propagate = self.propagate,
    parent_name = self.parent and self.parent.name or nil
  }
end

-- Add logging methods from the dispatch system (Step 2.7)
local logging_methods = dispatch_module.create_logging_methods()
for method_name, method_func in pairs(logging_methods) do
  logger_prototype[method_name] = method_func
end

-- Forward declarations
local create_root_logger_instance
local get_parent_name_from_hierarchical
local get_or_create_parent_logger
local _get_or_create_logger_internal

-- Define get_parent_name_from_hierarchical
get_parent_name_from_hierarchical = function(logger_name)
  if logger_name == "_root" then return nil end
  local match = logger_name:match("(.+)%.[^%.]+$")
  return match or "_root" -- Always return "_root" for top-level loggers
end

-- Define _get_or_create_logger_internal
_get_or_create_logger_internal = function(requested_name_or_nil, config_data)
  local final_name
  if requested_name_or_nil and requested_name_or_nil ~= "" then
    final_name = requested_name_or_nil
  else
    local _, _, auto_module_path = caller_info.get_caller_info(4)
    final_name = (auto_module_path and auto_module_path ~= "") and auto_module_path or "anonymous"
  end

  if _logger_cache[final_name] then
    return _logger_cache[final_name]
  end

  local new_logger = {}
  for k, v in pairs(logger_prototype) do new_logger[k] = v end
  new_logger.name = final_name

  -- Update parent logic here
  if final_name == "_root" then
    new_logger.parent = nil
  else
    local parent_name_hierarchical = get_parent_name_from_hierarchical(final_name)
    new_logger.parent = get_or_create_parent_logger(parent_name_hierarchical) -- Use the helper
  end

  -- Set level based on config or defaults
  if config_data.level ~= nil then
    new_logger.level = config_data.level
  else
    -- Default level is NOTSET for all loggers except _root
    new_logger.level = final_name == "_root" and core_levels.definition.WARNING or core_levels.definition.NOTSET
  end

  new_logger.dispatchers = {}
  if config_data.dispatchers then
    for _, item in ipairs(config_data.dispatchers) do
      if type(item) == "function" then
        table.insert(new_logger.dispatchers, { dispatcher_func = item, config = {} })
      elseif type(item) == "table" then
        if type(item.dispatcher_func) == "function" then
          table.insert(new_logger.dispatchers, item)
        elseif type(item.type) == "string" then
          -- Convert type-based dispatcher to internal format
          local dispatcher = all_dispatchers[item.type]
          if dispatcher then
            table.insert(new_logger.dispatchers, {
              dispatcher_func = dispatcher,
              config = item.config or {}
            })
          end
        end
      end
    end
  end

  if config_data.propagate ~= nil then
    new_logger.propagate = config_data.propagate
  else
    new_logger.propagate = true
  end

  _logger_cache[final_name] = new_logger
  return new_logger
end

-- Define get_or_create_parent_logger
get_or_create_parent_logger = function(parent_name_str)
  if not parent_name_str then return nil end
  -- Special case: if parent is _root, create it from config
  if parent_name_str == "_root" then
    if _logger_cache["_root"] then
      return _logger_cache["_root"]
    else
      -- Create _root logger from config
      local root_logger = create_root_logger_instance()
      _logger_cache["_root"] = root_logger
      return root_logger
    end
  end
  -- Parents are created with default configuration via the main factory.
  return _get_or_create_logger_internal(parent_name_str, {})
end

-- Define create_root_logger_instance
create_root_logger_instance = function()       -- Renamed from create_root_logger if that was the old name
  local main_conf = config_module.get_config() -- Get current global defaults
  local root_config_for_logger = {
    level = main_conf.level,
    dispatchers = main_conf.dispatchers or {}, -- Use dispatchers directly from config
    propagate = main_conf.propagate
  }
  -- Convert raw function dispatchers to internal format
  if root_config_for_logger.dispatchers then
    local converted_dispatchers = {}
    for _, disp_fn in ipairs(root_config_for_logger.dispatchers) do
      if type(disp_fn) == "function" then
        table.insert(converted_dispatchers, { dispatcher_func = disp_fn, config = {} })
      elseif type(disp_fn) == "table" and type(disp_fn.dispatcher_func) == "function" then
        table.insert(converted_dispatchers, disp_fn)
      end
    end
    root_config_for_logger.dispatchers = converted_dispatchers
  end
  -- Use the new internal factory to get or create _root
  return _get_or_create_logger_internal("_root", root_config_for_logger)
end

function log.reset_cache()
  _logger_cache = {}
end

-- Expose create_root_logger_instance for testing or internal advanced use if needed.
-- The old log.create_root_logger might have been used by tests.
log.create_root_logger = create_root_logger_instance

-- Configuration validation for non-root loggers
local VALID_LOGGER_CONFIG_KEYS = {
  level = { type = "number", description = "Logging level (use lual.DEBUG, lual.INFO, etc.)" },
  dispatchers = { type = "table", description = "Array of dispatcher functions or dispatcher config tables" },
  propagate = { type = "boolean", description = "Whether to propagate messages to parent loggers" }
}

--- Validates a logger configuration table (renamed from validate_logger_config)
-- @param config_table table The configuration to validate
-- @return boolean, string True if valid, or false with error message
local function validate_logger_config_table(config_table)
  if type(config_table) ~= "table" then
    return false, "Configuration must be a table, got " .. type(config_table)
  end

  local key_diff = table_utils.key_diff(VALID_LOGGER_CONFIG_KEYS, config_table)
  if #key_diff.added_keys > 0 then
    local valid_keys_list = {}
    for valid_key, _ in pairs(VALID_LOGGER_CONFIG_KEYS) do table.insert(valid_keys_list, valid_key) end
    table.sort(valid_keys_list)
    return false,
        string.format("Unknown configuration key '%s'. Valid keys are: %s", tostring(key_diff.added_keys[1]),
          table.concat(valid_keys_list, ", "))
  end

  for key, value in pairs(config_table) do
    local expected_spec = VALID_LOGGER_CONFIG_KEYS[key]
    local expected_type = expected_spec.type
    local actual_type = type(value)
    if actual_type ~= expected_type then
      return false,
          string.format("Invalid type for '%s': expected %s, got %s. %s", key, expected_type, actual_type,
            expected_spec.description)
    end
    if key == "level" then
      local valid_level = false
      for _, level_value in pairs(core_levels.definition) do
        if value == level_value then
          valid_level = true
          break
        end
      end
      if not valid_level then
        local valid_levels_list = {}
        for level_name, level_val in pairs(core_levels.definition) do
          table.insert(valid_levels_list,
            string.format("%s(%d)", level_name, level_val))
        end
        table.sort(valid_levels_list)
        return false,
            string.format("Invalid level value %d. Valid levels are: %s", value, table.concat(valid_levels_list, ", "))
      end
    elseif key == "dispatchers" then
      if not (#value >= 0) then return false, "'dispatchers' must be an array (table with numeric indices)" end
      for i, dispatcher_item in ipairs(value) do
        if not (type(dispatcher_item) == "function" or
              (type(dispatcher_item) == "table" and
                (type(dispatcher_item.dispatcher_func) == "function" or type(dispatcher_item.type) == "string"))) then
          return false,
              string.format(
                "dispatchers[%d] must be a function, a table with dispatcher_func, or a table with type, got %s", i,
                type(dispatcher_item))
        end
      end
    end
  end
  return true
end

--- Determines the parent logger name based on hierarchical naming
-- @param logger_name string The logger name
-- @return string|nil The parent logger name or nil if this is a top-level logger
local function get_parent_name(logger_name)
  if logger_name == "_root" then
    return nil -- Root logger has no parent
  end

  -- Find the last dot to determine parent
  local parent_name = logger_name:match("(.+)%.[^%.]+$")

  -- If no dot found, parent is _root
  if not parent_name then
    return "_root"
  end

  return parent_name
end

--- Gets or creates a parent logger
-- @param parent_name string The parent logger name
-- @return table|nil The parent logger or nil
local function get_or_create_parent(parent_name)
  if not parent_name then
    return nil
  end

  -- Special case: if parent is _root, create it from config
  if parent_name == "_root" then
    if _logger_cache["_root"] then
      return _logger_cache["_root"]
    else
      -- Create _root logger from config
      local root_logger = create_root_logger_instance()
      _logger_cache["_root"] = root_logger
      return root_logger
    end
  end

  -- If parent is already in cache, return it
  if _logger_cache[parent_name] then
    return _logger_cache[parent_name]
  end

  -- Create parent with default configuration
  return log.logger(parent_name)
end

-- Restore log.logger with argument parsing from Step 1
--- Main public API to get or create a logger.
function log.logger(arg1, arg2)
  local name_input = nil
  local config_input = {}

  if type(arg1) == "string" then
    name_input = arg1
    if type(arg2) == "table" then
      config_input = arg2
    elseif arg2 ~= nil then
      error("Invalid 2nd arg: expected table (config) or nil, got " .. type(arg2))
    end
  elseif type(arg1) == "table" then
    config_input = arg1
    if arg2 ~= nil then error("Invalid 2nd arg: config table as 1st arg means no 2nd arg, got " .. type(arg2)) end
  elseif arg1 == nil then
    if type(arg2) == "table" then
      config_input = arg2
    elseif arg2 ~= nil then
      error("Invalid 2nd arg: expected table (config) or nil, got " .. type(arg2))
    end
  elseif arg1 ~= nil then
    error("Invalid 1st arg: expected name (string), config (table), or nil, got " .. type(arg1))
  end

  if name_input ~= nil then
    if name_input == "" then error("Logger name cannot be an empty string.") end
    if name_input ~= "_root" and name_input:sub(1, 1) == "_" then
      error("Logger names starting with '_' are reserved (except '_root'). Name: " .. name_input)
    end
  end

  local ok, err_msg = validate_logger_config_table(config_input)
  if not ok then error("Invalid logger configuration: " .. err_msg) end

  -- Connect log.logger to the internal factory
  return _get_or_create_logger_internal(name_input, config_input)
end

--- Resets the logger cache (for testing)
function log.reset_cache()
  _logger_cache = {}
end

-- Expose internal functions for testing
-- log.create_logger = create_logger -- REMOVE THIS LINE
log.create_root_logger = create_root_logger_instance

-- =============================================================================
-- EXPOSED MODULES AND FLAT NAMESPACE CONSTANTS
-- =============================================================================

log.levels = core_levels.definition
log.dispatchers = all_dispatchers   -- Assign the dispatchers table
log.presenters = all_presenters     -- Assign the presenters table
log.transformers = all_transformers -- Assign the transformers table

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
-- ROOT LOGGER CONFIGURATION API
-- =============================================================================

--- Creates and configures the root logger using the new system.
--- @param config table The root logger configuration
--- @return table The updated configuration
function log.config(config)
  return config_module.config(config)
end

--- Gets the configuration of the root logger
--- @return table The root logger configuration
function log.get_config()
  return config_module.get_config()
end

--- Resets all logging configuration to defaults.
function log.reset_config()
  config_module.reset_config()
  log.reset_cache()
  -- Comments about _root re-creation are fine. No active code needed here for _root.
end

return log
