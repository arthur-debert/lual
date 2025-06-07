local unpack = unpack or table.unpack

-- Core modules
-- Note: For direct execution with 'lua', use require("lua.lual.*")
-- For LuaRocks installed modules or busted tests, use require("lual.*")
local core_levels = require("lua.lual.levels")
local config_module = require("lual.config")
local log_module = require("lual.log")
local constants = require("lual.constants")
local table_utils = require("lual.utils.table")
local caller_info = require("lual.utils.caller_info")
local component_utils = require("lual.utils.component")
local logger_config = require("lual.loggers.config")
local tree_module = require("lual.loggers.tree")
local factory_module = require("lual.loggers.factory")
local async_writer = require("lual.async")

------------------------------------------
-- LOGGER PROTOTYPE AND CORE FUNCTIONALITY
------------------------------------------

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
        presenter = constants.text()
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

-----------------------
-- LOG EVENT PROCESSING
-----------------------

-- Implements the pipeline dispatch logic
-- @param source_logger table The logger that originated the log event
-- @param log_record table The log record to process
local function dispatch_log_event(source_logger, log_record)
    -- Check if async mode is enabled
    if async_writer.is_enabled() then
        -- Queue the event for async processing
        async_writer.queue_log_event(source_logger, log_record)
        return
    end

    -- Synchronous processing using the log module
    log_module.process_log_record(source_logger, log_record)
end

-- Define logging methods directly
local function create_logging_methods()
    local methods = {}

    -- Get the live level module for environment variable checking
    local live_level = require("lual.config.live_level")

    -- Helper function to check for live level changes
    local function check_for_level_changes()
        if not config_module then return end

        -- Get current config
        local current_config = config_module.get_config()

        -- Check for level changes via environment variable
        local changed, new_level = live_level.check_level_change(current_config)
        if changed and new_level then
            -- Update the config with the new level
            config_module.config({ level = new_level })
        end
    end

    -- Helper function to create a log method for a specific level
    local function create_log_method(level_no, level_name)
        return function(self, ...)
            -- Check for environment variable level changes
            check_for_level_changes()

            -- Check if logging is enabled for this level
            local effective_level = self:_get_effective_level()
            if level_no < effective_level then
                return -- Early exit if level not enabled
            end

            -- Parse arguments
            local msg_fmt, args, context = log_module.parse_log_args(...)

            -- Create log record
            local log_record = log_module.create_log_record(self, level_no, level_name, msg_fmt, args, context)

            -- Dispatch the log event
            dispatch_log_event(self, log_record)
        end
    end

    -- Create methods for each log level
    methods.debug = create_log_method(core_levels.definition.DEBUG, "DEBUG")
    methods.info = create_log_method(core_levels.definition.INFO, "INFO")
    methods.warn = create_log_method(core_levels.definition.WARNING, "WARNING")
    methods.error = create_log_method(core_levels.definition.ERROR, "ERROR")
    methods.critical = create_log_method(core_levels.definition.CRITICAL, "CRITICAL")

    -- Generic log method
    methods.log = function(self, level_arg, ...)
        -- Check for environment variable level changes
        check_for_level_changes()

        local level_no
        local level_name

        -- Handle both numeric levels and level names (built-in or custom)
        if type(level_arg) == "number" then
            level_no = level_arg
            level_name = core_levels.get_level_name(level_no)
        elseif type(level_arg) == "string" then
            -- Check if it's a valid level name (built-in or custom)
            level_name, level_no = core_levels.get_level_by_name(level_arg)
            if not level_name or not level_no then
                error("Unknown level name: " .. level_arg)
            end
        else
            error("Log level must be a number or string, got " .. type(level_arg))
        end

        -- Check if logging is enabled for this level
        local effective_level = self:_get_effective_level()
        if level_no < effective_level then
            return -- Early exit if level not enabled
        end

        -- Parse arguments
        local msg_fmt, args, context = log_module.parse_log_args(...)

        -- Create log record
        local log_record = log_module.create_log_record(self, level_no, level_name, msg_fmt, args, context)

        -- Dispatch the log event
        dispatch_log_event(self, log_record)
    end

    return methods
end

-- Set up the async writer with the dispatch function
async_writer.set_dispatch_function(log_module.process_log_record)

-- Add logging methods to the logger prototype
local logging_methods = create_logging_methods()
for method_name, method_func in pairs(logging_methods) do
    logger_prototype[method_name] = method_func
end

-- Set up metamethod for custom level method dispatch
logger_prototype.__index = function(self, key)
    -- First check if it's a regular method
    if logger_prototype[key] then
        return logger_prototype[key]
    end

    -- Then check if it's a level name (built-in or custom)
    local level_name, level_no = core_levels.get_level_by_name(key)
    if level_name and level_no then
        return function(self_inner, ...)
            -- Check for environment variable level changes
            local live_level = require("lual.config.live_level")
            local current_config = config_module.get_config()
            local changed, new_level = live_level.check_level_change(current_config)
            if changed and new_level then
                config_module.config({ level = new_level })
            end

            -- Check if logging is enabled for this level
            local effective_level = self_inner:_get_effective_level()
            if level_no < effective_level then
                return -- Early exit if level not enabled
            end

            -- Parse arguments
            local msg_fmt, args, context = log_module.parse_log_args(...)

            -- Create log record
            local log_record = log_module.create_log_record(self_inner, level_no, level_name, msg_fmt, args, context)

            -- Dispatch the log event
            dispatch_log_event(self_inner, log_record)
        end
    end

    -- Return nil if not found
    return nil
end

-- Wrapper function for get_or_create_logger to pass logger_prototype
local function _get_or_create_logger_internal(requested_name_or_nil, config_data)
    return factory_module.get_or_create_logger(requested_name_or_nil, config_data, logger_prototype)
end

-- Wrapper function for create_root_logger to pass logger_prototype
local function create_root_logger_instance()
    return factory_module.create_root_logger(logger_prototype)
end

-- Export the module
local M = {
    -- Logger creation
    _get_or_create_logger_internal = _get_or_create_logger_internal,
    create_root_logger = create_root_logger_instance,
    validate_logger_config_table = logger_config.validate_logger_config_table,

    -- Cache management
    reset_cache = tree_module.reset_cache
}

return M
