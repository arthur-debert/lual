--- Configuration API
-- This module provides the new simplified configuration API for the _root logger

local core_levels = require("lua.lual.levels")
local table_utils = require("lual.utils.table")
local component_utils = require("lual.utils.component")
local all_outputs = require("lual.outputs.init")
local all_presenters = require("lual.presenters.init")
local async_writer = require("lual.async_writer")

local M = {}

-- Helper function to create default pipelines
local function create_default_pipelines()
    -- Return a default pipeline with console output and text presenter
    return {
        {
            level = core_levels.definition.WARNING,
            outputs = {
                {
                    func = all_outputs.console_output,
                    config = {}
                }
            },
            presenter = all_presenters.text()
        }
    }
end

-- Default configuration with console output pipeline
local _root_logger_config = {
    level = core_levels.definition.WARNING,
    propagate = true,
    pipelines = {}
}

-- Initialize with a default console output pipeline
local function initialize_default_config()
    -- Initialize with the console output pipeline
    local console_output = require("lual.outputs.console_output")
    local text_presenter = require("lual.presenters.text")
    local component_utils = require("lual.utils.component")

    -- Create a normalized output
    local normalized_output = component_utils.normalize_component(
        console_output,
        component_utils.DISPATCHER_DEFAULTS
    )

    -- Create a default pipeline with the normalized output
    local default_pipeline = {
        level = core_levels.definition.WARNING,
        outputs = { normalized_output },
        presenter = text_presenter()
    }

    -- Add it to the default config
    _root_logger_config.pipelines = { default_pipeline }
end

-- Call initialization
initialize_default_config()

-- Table of valid config keys and their expected types/descriptions
local VALID_CONFIG_KEYS = {
    level = { type = "number", description = "Logging level (use lual.DEBUG, lual.INFO, etc.)" },
    pipelines = { type = "table", description = "Array of pipeline configurations" },
    propagate = { type = "boolean", description = "Whether to propagate messages (always true for root)" },
    custom_levels = { type = "table", description = "Custom log levels as name = value pairs" },
    async_enabled = { type = "boolean", description = "Enable asynchronous logging mode" },
    async_batch_size = { type = "number", description = "Number of messages to batch before writing" },
    async_flush_interval = { type = "number", description = "Time interval (seconds) to force flush batches" },
    max_queue_size = { type = "number", description = "Maximum number of messages in async queue before overflow handling" },
    overflow_strategy = { type = "string", description = "Queue overflow strategy: 'drop_oldest', 'drop_newest', or 'block'" }
}

-- Table of valid pipeline keys and their expected types/descriptions
local VALID_PIPELINE_KEYS = {
    level = { type = "number", description = "Pipeline level threshold (use lual.DEBUG, lual.INFO, etc.)" },
    outputs = { type = "table", description = "Array of output functions or configuration tables", required = true },
    presenter = { description = "Presenter function or configuration", required = true },
    transformers = { type = "table", description = "Array of transformer functions or configuration tables" }
}

--- Validates a pipeline configuration
-- @param pipeline table Pipeline configuration to validate
-- @param index number Index of the pipeline in the pipelines array
-- @return boolean, string True if valid, otherwise false and error message
local function validate_pipeline(pipeline, index)
    if type(pipeline) ~= "table" then
        return false, string.format("pipelines[%d] must be a table, got %s", index, type(pipeline))
    end

    -- Check for required keys
    for key, spec in pairs(VALID_PIPELINE_KEYS) do
        if spec.required and pipeline[key] == nil then
            return false, string.format("pipelines[%d] is missing required key '%s'", index, key)
        end
    end

    -- Check for unknown keys
    local key_diff = table_utils.key_diff(VALID_PIPELINE_KEYS, pipeline)
    if #key_diff.added_keys > 0 then
        local valid_keys = {}
        for valid_key, _ in pairs(VALID_PIPELINE_KEYS) do
            table.insert(valid_keys, valid_key)
        end
        table.sort(valid_keys)
        return false, string.format(
            "Unknown key '%s' in pipelines[%d]. Valid keys are: %s",
            tostring(key_diff.added_keys[1]),
            index,
            table.concat(valid_keys, ", ")
        )
    end

    -- Type validation for each key
    for key, value in pairs(pipeline) do
        local expected_spec = VALID_PIPELINE_KEYS[key]

        -- Skip type validation for presenter which can be function or table
        if key == "presenter" then
            if type(value) ~= "function" and type(value) ~= "table" then
                return false, string.format(
                    "Invalid type for pipelines[%d].%s: expected function or table, got %s. %s",
                    index,
                    key,
                    type(value),
                    expected_spec.description
                )
            end
        elseif expected_spec.type and type(value) ~= expected_spec.type then
            return false, string.format(
                "Invalid type for pipelines[%d].%s: expected %s, got %s. %s",
                index,
                key,
                expected_spec.type,
                type(value),
                expected_spec.description
            )
        end

        -- Additional validation for specific keys
        if key == "level" then
            -- Validate that level is a known level value (including custom levels)
            local all_levels = core_levels.get_all_levels()
            local valid_level = false
            for _, level_value in pairs(all_levels) do
                if value == level_value then
                    valid_level = true
                    break
                end
            end
            if not valid_level then
                local valid_levels = {}
                for level_name, level_value in pairs(all_levels) do
                    table.insert(valid_levels, string.format("%s(%d)", level_name, level_value))
                end
                table.sort(valid_levels)
                return false, string.format(
                    "Invalid level value %d in pipelines[%d]. Valid levels are: %s",
                    value,
                    index,
                    table.concat(valid_levels, ", ")
                )
            end
        elseif key == "outputs" then
            -- Validate each output
            if #value == 0 then
                return false, string.format("pipelines[%d].outputs must not be empty", index)
            end

            for i, output in ipairs(value) do
                -- Simple validation here - detailed validation happens in component.normalize_component
                if type(output) ~= "function" and type(output) ~= "table" then
                    return false,
                        string.format(
                            "pipelines[%d].outputs[%d] must be a function or a table with function as first element, got %s",
                            index,
                            i,
                            type(output)
                        )
                end

                -- Validate table format if it's a table
                if type(output) == "table" and #output == 0 and not component_utils.is_callable(output) then
                    return false, string.format(
                        "pipelines[%d].outputs[%d] must be a function or a table with function as first element",
                        index,
                        i
                    )
                end
            end
        elseif key == "transformers" and #value == 0 then
            return false, string.format("pipelines[%d].transformers must not be empty if specified", index)
        end
    end

    return true
end

--- Validates custom levels configuration
-- @param custom_levels table Custom levels configuration to validate
-- @return boolean, string True if valid, otherwise false and error message
local function validate_custom_levels(custom_levels)
    if type(custom_levels) ~= "table" then
        return false, "custom_levels must be a table"
    end

    -- Validate each custom level
    for name, value in pairs(custom_levels) do
        local name_valid, name_error = core_levels.validate_custom_level_name(name)
        if not name_valid then
            return false, "Invalid custom level name '" .. tostring(name) .. "': " .. name_error
        end

        local value_valid, value_error = core_levels.validate_custom_level_value(value, true) -- exclude current customs
        if not value_valid then
            return false, "Invalid custom level value for '" .. name .. "': " .. value_error
        end
    end

    -- Check for duplicate values
    local seen_values = {}
    for name, value in pairs(custom_levels) do
        if seen_values[value] then
            return false,
                "Duplicate level value " .. value .. " for levels '" .. seen_values[value] .. "' and '" .. name .. "'"
        end
        seen_values[value] = name
    end

    return true
end

--- Validates the configuration structure
-- @param config_table table Configuration to validate
-- @return boolean, string True if valid, otherwise false and error message
local function validate_config(config_table)
    if config_table == nil then
        return false, "Configuration must be a table, got nil"
    end

    if type(config_table) ~= "table" then
        return false, "Configuration must be a table, got " .. type(config_table)
    end

    -- Reject outputs key entirely - no backward compatibility
    if config_table.outputs then
        return false, "'outputs' is no longer supported. Use 'pipelines' instead."
    end

    -- Validate custom_levels if present
    if config_table.custom_levels then
        local valid, error_msg = validate_custom_levels(config_table.custom_levels)
        if not valid then
            return false, error_msg
        end
    end

    -- Validate pipelines if present
    if config_table.pipelines then
        if type(config_table.pipelines) ~= "table" then
            return false,
                "Invalid type for 'pipelines': expected table, got " ..
                type(config_table.pipelines) .. ". Array of pipeline configurations"
        end

        -- Validate each pipeline
        for i, pipeline in ipairs(config_table.pipelines) do
            local valid, error_msg = validate_pipeline(pipeline, i)
            if not valid then
                return false, error_msg
            end
        end
    end

    -- Check for unknown keys using table_utils.key_diff
    local key_diff = table_utils.key_diff(VALID_CONFIG_KEYS, config_table)
    if #key_diff.added_keys > 0 then
        local valid_keys = {}
        for valid_key, _ in pairs(VALID_CONFIG_KEYS) do
            table.insert(valid_keys, valid_key)
        end
        table.sort(valid_keys)
        return false, string.format(
            "Unknown configuration key '%s'",
            tostring(key_diff.added_keys[1])
        )
    end

    -- Type validation
    for key, value in pairs(config_table) do
        local expected_spec = VALID_CONFIG_KEYS[key]

        -- Skip type validation for custom_levels since it's validated separately
        if key == "custom_levels" then
            goto continue
        end

        local expected_type = expected_spec.type
        local actual_type = type(value)

        if actual_type ~= expected_type then
            return false, string.format(
                "Invalid type for '%s': expected %s, got %s. %s",
                key,
                expected_type,
                actual_type,
                expected_spec.description
            )
        end

        -- Additional validation for specific keys
        if key == "level" then
            -- Get all levels (built-in + custom) for validation
            local all_levels = core_levels.get_all_levels()
            local valid_level = false
            for _, level_value in pairs(all_levels) do
                if value == level_value then
                    valid_level = true
                    break
                end
            end
            if not valid_level then
                local valid_levels = {}
                for level_name, level_value in pairs(all_levels) do
                    table.insert(valid_levels, string.format("%s(%d)", level_name, level_value))
                end
                table.sort(valid_levels)
                return false, string.format(
                    "Invalid level value %d. Valid levels are: %s",
                    value,
                    table.concat(valid_levels, ", ")
                )
            end
            -- Root logger cannot be set to NOTSET
            if value == core_levels.definition.NOTSET then
                return false, "Root logger level cannot be set to NOTSET"
            end
        elseif key == "async_batch_size" then
            if value <= 0 then
                return false, "async_batch_size must be greater than 0"
            end
        elseif key == "async_flush_interval" then
            if value <= 0 then
                return false, "async_flush_interval must be greater than 0"
            end
        elseif key == "max_queue_size" then
            if value <= 0 then
                return false, "max_queue_size must be greater than 0"
            end
        elseif key == "overflow_strategy" then
            local valid_strategies = { drop_oldest = true, drop_newest = true, block = true }
            if not valid_strategies[value] then
                return false, "overflow_strategy must be 'drop_oldest', 'drop_newest', or 'block'"
            end
        end

        ::continue::
    end

    return true
end

--- Normalizes pipelines in the configuration
-- @param pipelines table Array of pipeline configurations
-- @return table Array of normalized pipeline configurations
local function normalize_pipelines(pipelines)
    local normalized_pipelines = {}

    for i, pipeline in ipairs(pipelines) do
        local normalized_pipeline = {
            level = pipeline.level,
            transformers = pipeline.transformers
        }

        -- Normalize outputs
        normalized_pipeline.outputs = component_utils.normalize_components(pipeline.outputs,
            component_utils.DISPATCHER_DEFAULTS)

        -- Handle presenter (could be function or table)
        if type(pipeline.presenter) == "function" then
            normalized_pipeline.presenter = pipeline.presenter
        else
            normalized_pipeline.presenter = pipeline.presenter
        end

        -- Add to the result
        table.insert(normalized_pipelines, normalized_pipeline)
    end

    return normalized_pipelines
end

--- Updates the _root logger configuration with the provided settings
-- @param config_table table Configuration updates to apply
-- @return table The updated _root logger configuration
function M.config(config_table)
    -- Handle custom levels first if present
    if config_table.custom_levels then
        core_levels.set_custom_levels(config_table.custom_levels)
    end

    -- Validate the configuration (after custom levels are set)
    local valid, error_msg = validate_config(config_table)
    if not valid then
        error("Invalid configuration: " .. error_msg)
    end

    -- Update _root logger configuration with provided values
    for key, value in pairs(config_table) do
        if key == "pipelines" then
            -- Normalize the pipelines
            _root_logger_config[key] = normalize_pipelines(value)
        elseif key == "custom_levels" then
            -- Skip custom_levels as it's already processed
            -- (We don't store it in _root_logger_config)
        else
            _root_logger_config[key] = value
        end
    end

    -- Handle async configuration - start/stop async writer as needed
    if config_table.async_enabled ~= nil then
        if config_table.async_enabled then
            -- Start async writer with current config
            local async_config = {
                async_enabled = _root_logger_config.async_enabled,
                async_batch_size = _root_logger_config.async_batch_size or 50,
                async_flush_interval = _root_logger_config.async_flush_interval or 1.0,
                max_queue_size = _root_logger_config.max_queue_size or 10000,
                overflow_strategy = _root_logger_config.overflow_strategy or "drop_oldest"
            }
            async_writer.start(async_config, nil)
            -- Setup the dispatch function in pipeline module
            local pipeline_module = require("lual.pipeline")
            pipeline_module.setup_async_writer()
        else
            -- Stop async writer
            async_writer.stop()
        end
    end

    return table_utils.deepcopy(_root_logger_config)
end

--- Gets the current _root logger configuration
-- @return table A copy of the current _root logger configuration
function M.get_config()
    -- Return a deep copy of the internal configuration
    return table_utils.deepcopy(_root_logger_config)
end

--- Resets the _root logger configuration to defaults
function M.reset_config()
    -- Stop async writer if running
    async_writer.stop()

    -- Reset to defaults
    _root_logger_config = {
        level = core_levels.definition.WARNING,
        propagate = true,
        pipelines = {}
    }

    -- Re-initialize with default output
    initialize_default_config()

    return table_utils.deepcopy(_root_logger_config)
end

return M
