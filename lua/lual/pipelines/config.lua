--- Pipelines Configuration Handler
-- This module handles the 'pipelines' configuration key

local core_levels = require("lual.levels")
local component_utils = require("lual.utils.component")
local schemer = require("lual.utils.schemer")

local M = {}

-- Custom validators for complex validation
local function validate_presenter(value)
    return type(value) == "function" or type(value) == "table"
end

local function validate_output_element(value)
    if type(value) == "function" then
        return true
    end
    if type(value) == "table" then
        return #value > 0 or component_utils.is_callable(value)
    end
    return false
end

-- Pipeline schema (level enum created dynamically)
local function get_pipeline_schema()
    return {
        fields = {
            level = {
                type = "number",
                required = false,
                values = schemer.enum(core_levels.get_all_levels())
            },
            outputs = {
                type = "table",
                required = true,
                count = { 1, "*" },
                each = { custom_validator = validate_output_element }
            },
            presenter = {
                required = true,
                custom_validator = validate_presenter
            },
            transformers = {
                type = "table",
                required = false,
                count = { 1, "*" },
                each = { custom_validator = validate_output_element }
            }
        }
    }
end

--- Validates pipelines configuration
function M.validate(pipelines, full_config)
    if type(pipelines) ~= "table" then
        return false, "Invalid type for 'pipelines': expected table, got " .. type(pipelines)
    end

    for i, pipeline in ipairs(pipelines) do
        local errors = schemer.validate(pipeline, get_pipeline_schema())
        if errors then
            return false, string.format("pipelines[%d]: %s", i, errors.error)
        end
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
