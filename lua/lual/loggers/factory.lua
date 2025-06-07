--- Logger Factory Module
-- This module handles the creation of logger instances

-- Core modules
local core_levels = require("lua.lual.levels")
local config_module = require("lual.config")
local constants = require("lual.constants")
local table_utils = require("lual.utils.table")
local caller_info = require("lual.utils.caller_info")
local component_utils = require("lual.utils.component")
local tree_module = require("lual.loggers.tree")

-- Forward declarations
local _get_or_create_logger_internal
local create_root_logger_instance
local get_or_create_parent_logger

--- Gets or creates a parent logger by name
-- @param parent_name_str string|nil The parent logger name
-- @return table|nil The parent logger instance or nil
get_or_create_parent_logger = function(parent_name_str, logger_prototype)
    if not parent_name_str then return nil end

    -- Special case: if parent is _root, create it from config
    if parent_name_str == "_root" then
        if tree_module.get_from_cache("_root") then
            return tree_module.get_from_cache("_root")
        else
            -- Create _root logger from config
            local root_logger = create_root_logger_instance(logger_prototype)
            tree_module.add_to_cache("_root", root_logger)
            return root_logger
        end
    end

    -- Parents are created with default configuration via the main factory
    return _get_or_create_logger_internal(parent_name_str, {}, logger_prototype)
end

--- Creates a new logger instance with the given name and configuration
-- @param requested_name_or_nil string|nil The requested logger name
-- @param config_data table The logger configuration
-- @param logger_prototype table The logger prototype object
-- @return table The logger instance
_get_or_create_logger_internal = function(requested_name_or_nil, config_data, logger_prototype)
    local final_name
    if requested_name_or_nil and requested_name_or_nil ~= "" then
        final_name = requested_name_or_nil
    else
        local _, _, auto_module_path = caller_info.get_caller_info(4)
        final_name = (auto_module_path and auto_module_path ~= "") and auto_module_path or "anonymous"
    end

    -- Check if logger already exists in cache
    if tree_module.get_from_cache(final_name) then
        return tree_module.get_from_cache(final_name)
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
        local parent_name_hierarchical = tree_module.get_parent_name_from_hierarchical(final_name)
        new_logger.parent = get_or_create_parent_logger(parent_name_hierarchical, logger_prototype)
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

    -- Add to cache
    tree_module.add_to_cache(final_name, new_logger)
    return new_logger
end

--- Creates the root logger instance with configuration
-- @param logger_prototype table The logger prototype object
-- @return table The root logger instance
create_root_logger_instance = function(logger_prototype)
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
        local default_console = constants.console
        local normalized_output = component_utils.normalize_component(default_console,
            component_utils.DISPATCHER_DEFAULTS)

        -- Create a default pipeline
        local default_pipeline = {
            level = core_levels.definition.WARNING,
            outputs = { normalized_output },
            presenter = constants.text()
        }

        root_config_for_logger.pipelines = { default_pipeline }
    end

    -- Use the internal factory to get or create _root
    return _get_or_create_logger_internal("_root", root_config_for_logger, logger_prototype)
end

-- Export the module
return {
    get_or_create_logger = _get_or_create_logger_internal,
    create_root_logger = create_root_logger_instance
}
