--- Schema validation module
-- This module provides the main interface for schema-based validation

local validator = require("lual.schema.validator")
local config_schema = require("lual.schema.config_schema")

local M = {}

-- Schema registry
local schema_registry = {
    ConfigSchema = config_schema.ConfigSchema,
    dispatcherschema = config_schema.dispatcherschema,
    ShortcutSchema = config_schema.ShortcutSchema
}

--- Validate configuration data
-- @param data table The configuration data to validate
-- @return table Result with data and _errors keys
function M.validate_config(data)
    return validator.validate(data, schema_registry.ConfigSchema, schema_registry)
end

--- Validate dispatcher data
-- @param data table The dispatcher data to validate
-- @return table Result with data and _errors keys
function M.validate_dispatcher(data)
    return validator.validate(data, schema_registry.dispatcherschema, schema_registry)
end

--- Validate shortcut config data
-- @param data table The shortcut config data to validate
-- @return table Result with data and _errors keys
function M.validate_shortcut(data)
    return validator.validate(data, schema_registry.ShortcutSchema, schema_registry)
end

--- Generic validation function
-- @param data table The data to validate
-- @param schema_name string The name of the schema to use
-- @return table Result with data and _errors keys
function M.validate(data, schema_name)
    local schema = schema_registry[schema_name]
    if not schema then
        return {
            data = data,
            _errors = { _root = "Unknown schema: " .. tostring(schema_name) }
        }
    end
    return validator.validate(data, schema, schema_registry)
end

-- Export schemas for direct access if needed
M.schemas = schema_registry
M.validator = validator

return M
