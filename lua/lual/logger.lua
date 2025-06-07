local unpack = unpack or table.unpack

--[[
High-Level API Draft for a Lua Logging Library

This outlines the main functions and their intended signatures.
]]

-- Main Logging Module (e.g., 'log')
local log = {}

local core_levels = require("lua.lual.levels")
local config_module = require("lual.config")
local pipeline_module = require("lual.pipeline")
local table_utils = require("lual.utils.table")
local caller_info = require("lual.utils.caller_info")
local all_outputs = require("lual.outputs.init")           -- Require the new outputs init
local all_presenters = require("lual.presenters.init")     -- Require the new presenters init
local all_transformers = require("lual.transformers.init") -- Require the new transformers init
local component_utils = require("lual.utils.component")
local async_writer = require("lual.async")

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

--- Imperative API: Add a pipeline to this logger
-- @param pipeline table Pipeline configuration
function logger_prototype:add_pipeline(pipeline)
  if type(pipeline) ~= "table" then
    error("Pipeline must be a table, got " .. type(pipeline))
  end

  -- Validate required fields
  if not pipeline.outputs then
    error("Pipeline must have an outputs field")
  end

  if not pipeline.presenter then
    error("Pipeline must have a presenter field")
  end

  -- Create a normalized pipeline with normalized outputs
  local normalized_pipeline = {
    level = pipeline.level,
    presenter = pipeline.presenter,
    transformers = pipeline.transformers
  }

  -- Normalize the outputs
  normalized_pipeline.outputs = component_utils.normalize_components(
    pipeline.outputs,
    component_utils.DISPATCHER_DEFAULTS
  )

  -- Add to the logger's pipelines
  table.insert(self.pipelines, normalized_pipeline)
end

--- Imperative API: Add a output to this logger
-- @param output_func function The output function
-- @param config table|nil Optional output configuration
function logger_prototype:add_output(output_func, config)
  if type(output_func) ~= "function" then
    error("Output must be a function, got " .. type(output_func))
  end

  -- Create a pipeline with the output and a default text presenter
  local pipeline = {
    outputs = { output_func },
    presenter = all_presenters.text()
  }

  -- Add to the logger's pipelines
  table.insert(self.pipelines, pipeline)

  -- Print deprecation warning
  io.stderr:write("WARNING: add_output() is deprecated. Use add_pipeline() instead.\n")
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
  -- Return a deep copy of the current configuration
  local config = {
    name = self.name,
    level = self.level,
    pipelines = table_utils.deepcopy(self.pipelines),
    propagate = self.propagate,
    parent_name = self.parent and self.parent.name or nil
  }

  return config
end

-- Add logging methods from the pipeline system
local logging_methods = pipeline_module.create_logging_methods()
for method_name, method_func in pairs(logging_methods) do
  logger_prototype[method_name] = method_func
end

-- Set up metamethod for custom level method dispatch
logger_prototype.__index = function(self, key)
  -- First check if it's a regular method
  if logger_prototype[key] then
    return logger_prototype[key]
  end

  -- Then check if it's a custom level name
  if core_levels.is_custom_level(key) then
    local level_no = core_levels.get_custom_level_value(key)
    return function(self_inner, ...)
      -- Check if logging is enabled for this level
      local effective_level = self_inner:_get_effective_level()
      if level_no < effective_level then
        return -- Early exit if level not enabled
      end

      -- Parse arguments
      local msg_fmt, args, context = pipeline_module._parse_log_args(...)

      -- Create log record
      local log_record = pipeline_module._create_log_record(self_inner, level_no, key:upper(), msg_fmt, args, context)
      pipeline_module.dispatch_log_event(self_inner, log_record)
    end
  end

  -- Return nil if not found
  return nil
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

-- Create a helper function to convert flat output config to internal format
-- This is shared with config.lua to ensure consistent behavior
-- @param disp table The output configuration with flat properties
-- @return table The internal output entry with config nested properly
local function convert_flat_output_config(disp)
  -- Use the component_utils.normalize_component to handle conversion consistently
  return component_utils.normalize_component(disp, component_utils.DISPATCHER_DEFAULTS)
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

  -- Set the metatable to enable custom level method dispatch
  setmetatable(new_logger, logger_prototype)

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

  new_logger.pipelines = {}
  if config_data.pipelines then
    for _, pipeline in ipairs(config_data.pipelines) do
      -- Create a normalized pipeline
      local normalized_pipeline = {
        level = pipeline.level,
        presenter = pipeline.presenter,
        transformers = pipeline.transformers
      }

      -- Normalize outputs within the pipeline
      normalized_pipeline.outputs = component_utils.normalize_components(
        pipeline.outputs, component_utils.DISPATCHER_DEFAULTS
      )

      table.insert(new_logger.pipelines, normalized_pipeline)
    end
  end

  -- No backward compatibility - reject outputs configuration
  if config_data.outputs then
    error("'outputs' configuration is no longer supported. Use 'pipelines' instead.")
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
    pipelines = {}, -- Start with an empty array
    propagate = main_conf.propagate
  }

  -- If we have pipelines in the config, use them
  if main_conf.pipelines and #main_conf.pipelines > 0 then
    -- Copy the pipelines as is - they're already normalized by config.config()
    root_config_for_logger.pipelines = table_utils.deepcopy(main_conf.pipelines)
  else
    -- If no pipelines are configured, add a default pipeline with console output
    local default_console = all_outputs.console_output
    local normalized_output = component_utils.normalize_component(default_console,
      component_utils.DISPATCHER_DEFAULTS)

    -- Create a default pipeline
    local default_pipeline = {
      level = core_levels.definition.WARNING,
      outputs = { normalized_output },
      presenter = all_presenters.text()
    }

    root_config_for_logger.pipelines = { default_pipeline }
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
  pipelines = { type = "table", description = "Array of pipeline configurations" },
  propagate = { type = "boolean", description = "Whether to propagate messages to parent loggers" }
}

--- Validates a logger configuration table (renamed from validate_logger_config)
-- @param config_table table The configuration to validate
-- @return boolean, string True if valid, or false with error message
local function validate_logger_config_table(config_table)
  if type(config_table) ~= "table" then
    return false, "Configuration must be a table, got " .. type(config_table)
  end

  -- Reject outputs key entirely - no backward compatibility
  if config_table.outputs then
    return false, "'outputs' is no longer supported. Use 'pipelines' instead."
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

--- Gets all levels (built-in + custom)
-- @return table All available levels
function log.get_levels()
  return core_levels.get_all_levels()
end

--- Sets custom levels (replaces all existing custom levels)
-- @param custom_levels table Custom levels as name = value pairs
function log.set_levels(custom_levels)
  core_levels.set_custom_levels(custom_levels)
end

-- Expose internal functions for testing
-- log.create_logger = create_logger -- REMOVE THIS LINE
log.create_root_logger = create_root_logger_instance

-- =============================================================================
-- EXPOSED MODULES AND FLAT NAMESPACE CONSTANTS
-- =============================================================================

log.levels = core_levels.definition
log.outputs = all_outputs           -- Assign the outputs table
log.presenters = all_presenters     -- Assign the presenters table
log.transformers = all_transformers -- Assign the transformers table

-- Configuration API
log.config = config_module.config
log.get_config = config_module.get_config
log.reset_config = config_module.reset_config

-- Level constants (flat namespace)
log.notset = core_levels.definition.NOTSET
log.debug = core_levels.definition.DEBUG
log.info = core_levels.definition.INFO
log.warning = core_levels.definition.WARNING
log.error = core_levels.definition.ERROR
log.critical = core_levels.definition.CRITICAL
log.none = core_levels.definition.NONE

-- output constants (function references for config API)
log.console = all_outputs.console_output
log.file = all_outputs.file_output

-- Presenter constants (function references for config API)
log.text = all_presenters.text
log.color = all_presenters.color
log.json = all_presenters.json

-- Timezone constants (still use strings for these)
log.local_time = "local"
log.utc = "utc"

-- Transformer constants
log.noop = all_transformers.noop_transformer

-- Async constants
log.async = {
  -- Backend constants
  coroutines = "coroutines",
  libuv = "libuv",

  -- Overflow strategy constants
  drop_oldest = "drop_oldest",
  drop_newest = "drop_newest",
  block = "block",

  -- Default configuration
  defaults = {
    enabled = false,
    backend = "coroutines",
    batch_size = 50,
    flush_interval = 1.0,
    max_queue_size = 10000,
    overflow_strategy = "drop_oldest"
  },

  -- Statistics function
  get_stats = function()
    return async_writer.get_stats()
  end
}

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

--- Flushes all queued async log events immediately.
-- This function will block until all currently queued log events have been processed.
-- If async logging is not enabled, this function does nothing.
function log.flush()
  async_writer.flush()
end

return log
