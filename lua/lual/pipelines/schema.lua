--- Pipelines Configuration Schema
-- Schema definition for pipeline configuration validation

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
function M.get_pipeline_schema()
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
        },
        on_extra_keys = "error"
    }
end

-- Pipelines array schema for declarative validation
function M.get_pipelines_array_schema()
    return {
        type = "table",
        count = { 1, "*" }, -- At least one pipeline required
        each = M.get_pipeline_schema()
    }
end

return M
