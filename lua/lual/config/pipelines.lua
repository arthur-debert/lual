--- Pipelines Configuration Handler
-- This module handles the 'pipelines' configuration key

local core_levels = require("lua.lual.levels")
local component_utils = require("lual.utils.component")
local table_utils = require("lual.utils.table")

local M = {}

-- Schema for pipeline configuration
M.schema = {
    level = { type = "number", description = "Pipeline level threshold (use lual.DEBUG, lual.INFO, etc.)" },
    outputs = { type = "table", description = "Array of output functions or configuration tables", required = true },
    presenter = { description = "Presenter function or configuration", required = true },
    transformers = { type = "table", description = "Array of transformer functions or configuration tables" }
}

--- Validates a single pipeline configuration
-- @param pipeline table Pipeline configuration to validate
-- @param index number Index of the pipeline in the pipelines array
-- @return boolean, string True if valid, otherwise false and error message
local function validate_pipeline(pipeline, index)
    if type(pipeline) ~= "table" then
        return false, string.format("pipelines[%d] must be a table, got %s", index, type(pipeline))
    end

    -- Check for required keys
    for key, spec in pairs(M.schema) do
        if spec.required and pipeline[key] == nil then
            return false, string.format("pipelines[%d] is missing required key '%s'", index, key)
        end
    end

    -- Check for unknown keys
    local key_diff = table_utils.key_diff(M.schema, pipeline)
    if #key_diff.added_keys > 0 then
        local valid_keys = {}
        for valid_key, _ in pairs(M.schema) do
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
        local expected_spec = M.schema[key]

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

--- Validates pipelines configuration
-- @param pipelines table The pipelines configuration to validate
-- @param full_config table The full configuration context
-- @return boolean, string True if valid, otherwise false and error message
function M.validate(pipelines, full_config)
    if type(pipelines) ~= "table" then
        return false,
            "Invalid type for 'pipelines': expected table, got " ..
            type(pipelines) .. ". Array of pipeline configurations"
    end

    -- Validate each pipeline
    for i, pipeline in ipairs(pipelines) do
        local valid, error_msg = validate_pipeline(pipeline, i)
        if not valid then
            return false, error_msg
        end
    end

    return true
end

--- Normalizes pipelines in the configuration
-- @param pipelines table Array of pipeline configurations
-- @param full_config table The full configuration context
-- @return table Array of normalized pipeline configurations
function M.normalize(pipelines, full_config)
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

--- Applies pipelines configuration
-- @param pipelines table The pipelines configuration to apply
-- @param current_config table The current full configuration
-- @return table The normalized pipelines configuration to store
function M.apply(pipelines, current_config)
    -- Pipelines are normalized and returned as-is
    return pipelines
end

return M
