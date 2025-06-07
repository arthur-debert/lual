local unpack = unpack or table.unpack

-- Core modules
-- Note: For direct execution with 'lua', use require("lua.lual.*")
-- For LuaRocks installed modules or busted tests, use require("lual.*")
local core_levels = require("lua.lual.levels")
local config_module = require("lual.config")
local pipeline_module = require("lual.pipelines")
local table_utils = require("lual.utils.table")
local caller_info = require("lual.utils.caller_info")
local component_utils = require("lual.utils.component")

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
        presenter = require("lual.pipelines.presenters.init").text()
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
            local log_record = pipeline_module._create_log_record(self_inner, level_no, key:upper(), msg_fmt, args,
                context)
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
create_root_logger_instance = function()         -- Renamed from create_root_logger if that was the old name
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
        local default_console = require("lual.pipelines.outputs.init").console
        local normalized_output = component_utils.normalize_component(default_console,
            component_utils.DISPATCHER_DEFAULTS)

        -- Create a default pipeline
        local default_pipeline = {
            level = core_levels.definition.WARNING,
            outputs = { normalized_output },
            presenter = require("lual.pipelines.presenters.init").text()
        }

        root_config_for_logger.pipelines = { default_pipeline }
    end

    -- Use the new internal factory to get or create _root
    return _get_or_create_logger_internal("_root", root_config_for_logger)
end

-- Configuration validation for non-root loggers
-- DEPRECATED: This is kept for backward compatibility with tests.
-- In the future, all validation should be done by the config registry system.
local VALID_LOGGER_CONFIG_KEYS = {
    level = { type = "number", description = "Logging level (use lual.DEBUG, lual.INFO, etc.)" },
    pipelines = { type = "table", description = "Array of pipeline configurations" },
    propagate = { type = "boolean", description = "Whether to propagate messages to parent loggers" }
}

--- Validates a logger configuration table (renamed from validate_logger_config)
-- DEPRECATED: This is kept for backward compatibility with tests.
-- In the future, all validation should be done by the config registry system.
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
                    string.format("Invalid level value %d. Valid levels are: %s", value,
                        table.concat(valid_levels_list, ", "))
            end
        end
    end
    return true
end

-- Export the module
local M = {
    -- Logger creation
    _get_or_create_logger_internal = _get_or_create_logger_internal,
    create_root_logger = create_root_logger_instance,
    validate_logger_config_table = validate_logger_config_table,

    -- Cache management
    reset_cache = function()
        _logger_cache = {}
    end
}

return M
