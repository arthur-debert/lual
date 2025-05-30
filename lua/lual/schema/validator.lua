--- Generic schema validation functions
-- This module provides the core validation logic for all schemas

local constants = require("lual.config.constants")

local M = {}

--- Generate field-specific error messages
-- @param field_name string The field name
-- @param value any The field value
-- @param valid_values table Valid values for the field
-- @param schema_context string Context for schema (for error messages)
-- @return string The error message
local function generate_field_error(field_name, value, valid_values, schema_context)
    if valid_values then
        local values_list = {}
        for key, _ in pairs(valid_values) do
            table.insert(values_list, key)
        end
        table.sort(values_list)

        if field_name == "type" then
            if schema_context == "transformer" then
                return string.format("Invalid transformer type: %s. Valid values are: %s",
                    tostring(value), table.concat(values_list, ", "))
            else
                return string.format("Invalid dispatcher type: %s. Valid values are: %s",
                    tostring(value), table.concat(values_list, ", "))
            end
        elseif field_name == "presenter" then
            return string.format("Invalid presenter type: %s. Valid values are: %s",
                tostring(value), table.concat(values_list, ", "))
        else
            return string.format("Invalid %s: %s. Valid values are: %s",
                field_name, tostring(value), table.concat(values_list, ", "))
        end
    elseif field_name == "type" then
        if schema_context == "transformer" then
            return "Each transformer must have a 'type' string field"
        else
            return "Each dispatcher must have a 'type' string field"
        end
    elseif field_name == "presenter" then
        return "Each dispatcher must have a 'presenter' string field"
    else
        return string.format("Invalid %s: %s", field_name, tostring(value))
    end
end

--- Generate type error messages
-- @param field_name string The field name
-- @param field_schema table The field schema
-- @return string The error message
local function generate_type_error(field_name, field_schema)
    if field_schema.type then
        local type_str = type(field_schema.type) == "table"
            and table.concat(field_schema.type, " or ")
            or field_schema.type

        -- Generate more specific error messages for certain fields
        if field_name == "name" then
            return "Config.name must be a string"
        elseif field_name == "propagate" then
            return "Config.propagate must be a boolean"
        elseif field_name == "dispatchers" then
            return "Config.dispatchers must be a table"
        elseif field_name == "transformers" then
            return "Config.transformers must be a table"
        elseif field_name == "stream" then
            return "Console dispatcher 'stream' field must be a file handle"
        elseif field_name == "path" then
            return "File dispatcher must have a 'path' string field"
        else
            return string.format("%s must be a %s",
                string.gsub(field_name, "^%l", string.upper), type_str)
        end
    else
        return string.format("Invalid %s", field_name)
    end
end

--- Validate a single field against its schema
-- @param field_name string The field name
-- @param value any The field value
-- @param field_schema table The field schema
-- @param data table The full data being validated
-- @param schema_context string Context for schema (for error messages)
-- @return boolean, string True if valid, or false with error message
local function validate_field(field_name, value, field_schema, data, schema_context)
    -- Check if field is required
    if field_schema.required and value == nil then
        if field_name == "type" then
            if schema_context == "transformer" then
                return false, "Each transformer must have a 'type' string field"
            else
                return false, "Each dispatcher must have a 'type' string field"
            end
        elseif field_name == "presenter" then
            return false, "Each dispatcher must have a 'presenter' string field"
        else
            return false, string.format("%s is required", string.gsub(field_name, "^%l", string.upper))
        end
    end

    -- Skip validation if field is nil and not required, unless there's conditional validation that applies
    if value == nil then
        if not field_schema.conditional then
            return true
        else
            -- For conditional fields, only validate if the condition is met
            local condition = field_schema.conditional
            local condition_field_value = data[condition.field]
            if condition_field_value ~= condition.value then
                -- Condition not met, skip validation of this conditional field
                return true
            end
            -- Condition is met, continue with validation
        end
    end

    -- Validate field type
    if field_schema.type then
        local expected_types = type(field_schema.type) == "table" and field_schema.type or { field_schema.type }
        local value_type = type(value)
        local type_valid = false

        for _, expected_type in ipairs(expected_types) do
            if value_type == expected_type then
                type_valid = true
                break
            end
        end

        if not type_valid then
            return false, generate_type_error(field_name, field_schema)
        end
    end

    -- Validate against allowed values
    if field_schema.values then
        local value_key = value
        -- Handle case-insensitive validation for string values
        if type(value) == "string" and field_schema.values._meta and not field_schema.values._meta.case_sensitive then
            value_key = string.lower(value)
        end

        if not field_schema.values[value_key] then
            return false, generate_field_error(field_name, value, field_schema.values, schema_context)
        end
    end

    -- Validate conditional requirements (check this even if value is not nil)
    if field_schema.conditional then
        local condition = field_schema.conditional
        local condition_field_value = data[condition.field]
        if condition_field_value == condition.value and condition.required and (value == nil or (type(value) == "string" and value == "")) then
            return false, generate_type_error(field_name, field_schema)
        end
    end

    return true
end

--- Main validation function
-- @param data table The data to validate
-- @param schema table The schema to validate against
-- @param schema_registry table Registry of all schemas
-- @return table Result with data and _errors fields
function M.validate(data, schema, schema_registry)
    local result = {
        data = {},
        _errors = {}
    }

    if type(data) ~= "table" then
        result._errors._root = "Data must be a table"
        return result
    end

    -- Copy data to result
    for k, v in pairs(data) do
        result.data[k] = v
    end

    -- Determine schema context for error messages
    local schema_context = nil
    if schema == schema_registry.transformerschema then
        schema_context = "transformer"
    end

    -- Validate each field in the schema
    for field_name, field_schema in pairs(schema) do
        local value = data[field_name]

        if field_schema.multiple then
            -- Handle array fields
            if value ~= nil then
                if type(value) ~= "table" then
                    result._errors[field_name] = generate_type_error(field_name, field_schema)
                else
                    -- Validate each item in the array
                    for i, item in ipairs(value) do
                        if field_schema.schema then
                            -- Nested schema validation
                            local nested_schema = schema_registry[field_schema.schema]
                            if nested_schema then
                                local nested_result = M.validate(item, nested_schema, schema_registry)
                                if next(nested_result._errors) then
                                    -- Create nested error structure that tests expect
                                    result._errors[string.format("%s[%d]", field_name, i)] = nested_result._errors
                                end
                            end
                        else
                            -- Direct field validation for array items
                            local valid, error_msg = validate_field(field_name, item, field_schema, data, schema_context)
                            if not valid then
                                result._errors[string.format("%s[%d]", field_name, i)] = error_msg
                            end
                        end
                    end
                end
            end
        else
            -- Handle single fields - always validate even if value is nil to catch conditional requirements
            local valid, error_msg = validate_field(field_name, value, field_schema, data, schema_context)
            if not valid then
                result._errors[field_name] = error_msg
            end
        end
    end

    -- Check for unknown fields
    for field_name, _ in pairs(data) do
        if not schema[field_name] then
            result._errors[field_name] = "Unknown config key: " .. field_name
        end
    end

    return result
end

return M
