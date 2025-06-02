--- Schema validation module
-- This module provides validation functions for different config schemas

local validator = require("lual.schema.validator")
local config_schema = require("lual.schema.config_schema")

local M = {}

-- Schema registry for reuse
local schema_registry = {
    ConfigSchema = config_schema.ConfigSchema,
    dispatcherschema = config_schema.dispatcherschema,
    transformerschema = config_schema.transformerschema,
}

--- Validate config data against ConfigSchema
-- @param data table The config data to validate
-- @return table Validation result with data and errors
function M.validate_config(data)
    return validator.validate(data, schema_registry.ConfigSchema, schema_registry)
end

--- Validate dispatcher data against dispatcherschema
-- @param data table The dispatcher data to validate
-- @return table Validation result with data and errors
function M.validate_dispatcher(data)
    return validator.validate(data, schema_registry.dispatcherschema, schema_registry)
end

--- Validate transformer data against transformerschema
-- @param data table The transformer data to validate
-- @return table Validation result with data and errors
function M.validate_transformer(data)
    return validator.validate(data, schema_registry.transformerschema, schema_registry)
end

return M
