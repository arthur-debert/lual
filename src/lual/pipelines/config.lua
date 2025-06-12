--- Pipelines Configuration Handler
-- This module handles the 'pipelines' configuration key

local component_utils = require("lual.utils.component")
local schemer = require("lual.utils.schemer")
local pipelines_schema_module = require("lual.pipelines.schema")

local M = {}

--- Validates pipelines configuration
function M.validate(pipelines, full_config)
    -- Use schemer's array validation with detailed error reporting
    local errors = schemer.validate(pipelines, pipelines_schema_module.get_pipelines_array_schema())
    if errors then
        return false, errors.error
    end

    return true
end

--- Normalizes pipelines in the configuration
function M.normalize(pipelines, full_config)
    local normalized_pipelines = {}

    for i, pipeline in ipairs(pipelines) do
        local normalized_pipeline = {
            level = pipeline.level,
            transformers = pipeline.transformers,
            outputs = component_utils.normalize_components(pipeline.outputs, component_utils.DISPATCHER_DEFAULTS),
            presenter = pipeline.presenter
        }
        table.insert(normalized_pipelines, normalized_pipeline)
    end

    return normalized_pipelines
end

--- Applies pipelines configuration
function M.apply(pipelines, current_config)
    return pipelines
end

return M
