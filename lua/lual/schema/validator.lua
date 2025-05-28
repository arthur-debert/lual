--- Schema-based validator
-- This module provides validation functions that work with schema definitions

local constants = require("lual.config.constants")

local M = {}

--- Generate error message for invalid values
-- @param field_name string The name of the field
-- @param value any The invalid value
-- @param field_schema table The schema definition for the field
-- @return string The error message
local function generate_error_message(field_name, value, field_schema)
    if field_schema.values then
        local valid_values = {}
        for key, _ in pairs(field_schema.values) do
            table.insert(valid_values, key)
        end
        table.sort(valid_values)

        -- For non-string values that should be strings, show type error instead of enum error
        if type(value) ~= "string" then
            if field_name == "level" then
                return "Level must be a string or number"
            elseif field_name == "output" then -- For shortcut API
                return "Output type must be a string"
            elseif field_name == "formatter" then
                return "Formatter type must be a string"
            end
        end

        -- Generate more specific error messages for certain fields
        if field_name == "type" then
            return string.format("Invalid output type: %s. Valid values are: %s",
                tostring(value), table.concat(valid_values, ", "))
        elseif field_name == "output" then -- For shortcut API
            return string.format("Invalid output type: %s. Valid values are: %s",
                tostring(value), table.concat(valid_values, ", "))
        elseif field_name == "formatter" then
            return string.format("Invalid formatter type: %s. Valid values are: %s",
                tostring(value), table.concat(valid_values, ", "))
        else
            return string.format("Invalid %s: %s. Valid values are: %s",
                field_name, tostring(value), table.concat(valid_values, ", "))
        end
    elseif field_schema.type then
        local type_str = type(field_schema.type) == "table"
            and table.concat(field_schema.type, " or ")
            or field_schema.type

        -- Generate more specific error messages for certain fields
        if field_name == "name" then
            return "Config.name must be a string"
        elseif field_name == "propagate" then
            return "Config.propagate must be a boolean"
        elseif field_name == "outputs" then
            return "Config.outputs must be a table"
        elseif field_name == "stream" then
            return "Console output 'stream' field must be a file handle"
        elseif field_name == "path" then
            return "File output must have a 'path' string field"
        else
            return string.format("%s must be a %s",
                string.gsub(field_name, "^%l", string.upper), type_str)
        end
    else
        return string.format("Invalid %s: %s", field_name, tostring(value))
    end
end

--- Validate a single field against its schema
-- @param field_name string The name of the field
-- @param value any The value to validate
-- @param field_schema table The schema definition for the field
-- @param data table The full data object (for conditional validation)
-- @param is_shortcut boolean Whether this is shortcut config validation
-- @return boolean, string True if valid, or false with error message
local function validate_field(field_name, value, field_schema, data, is_shortcut)
    -- Check if field is required
    if value == nil then
        if field_schema.required then
            -- Generate specific required field messages
            if field_name == "type" then
                return false, "Each output must have a 'type' string field"
            elseif field_name == "output" then -- For shortcut API
                return false, "Shortcut config must have an 'output' field"
            elseif field_name == "formatter" then
                if is_shortcut then
                    return false, "Shortcut config must have a 'formatter' field"
                else
                    return false, "Each output must have a 'formatter' string field"
                end
            else
                return false, string.format("%s is required", string.gsub(field_name, "^%l", string.upper))
            end
        end
        -- Check conditional requirements
        if field_schema.conditional then
            local cond = field_schema.conditional
            if data[cond.field] == cond.value and cond.required then
                if field_name == "path" then
                    return false, "File output must have a 'path' string field"
                else
                    return false, string.format("%s is required when %s is %s",
                        string.gsub(field_name, "^%l", string.upper), cond.field, cond.value)
                end
            end
        end
        return true -- nil is valid for non-required fields
    end

    -- Type validation
    if field_schema.type then
        local valid_type = false
        local expected_types = type(field_schema.type) == "table" and field_schema.type or { field_schema.type }

        for _, expected_type in ipairs(expected_types) do
            if type(value) == expected_type then
                valid_type = true
                break
            end
        end

        if not valid_type then
            return false, generate_error_message(field_name, value, field_schema)
        end
    end

    -- Value validation (for enums)
    if field_schema.values and type(value) == "string" then
        -- Case-insensitive lookup
        local lookup_value = string.lower(value)
        if not field_schema.values[lookup_value] then
            return false, generate_error_message(field_name, value, field_schema)
        end
    end

    return true
end

--- Validate data against a schema
-- @param data table The data to validate
-- @param schema table The schema definition
-- @param schema_registry table Optional registry of schemas for nested validation
-- @return table Result with data and _errors keys
function M.validate(data, schema, schema_registry)
    local result = {
        data = {},
        _errors = {}
    }

    if type(data) ~= "table" then
        result._errors._root = "Data must be a table"
        return result
    end

    schema_registry = schema_registry or {}

    -- Detect if this is shortcut schema validation
    local is_shortcut = schema == schema_registry.ShortcutSchema

    -- Validate known fields
    for field_name, field_schema in pairs(schema) do
        local value = data[field_name]
        local valid, error_msg = validate_field(field_name, value, field_schema, data, is_shortcut)

        if not valid then
            result._errors[field_name] = error_msg
            result.data[field_name] = value -- Include original value even if invalid
        else
            -- Handle nested schema validation
            if field_schema.schema and value ~= nil then
                local nested_schema = schema_registry[field_schema.schema]
                if nested_schema then
                    if field_schema.multiple and type(value) == "table" then
                        -- Validate array of objects
                        local validated_array = {}
                        local has_errors = false

                        for i, item in ipairs(value) do
                            local item_result = M.validate(item, nested_schema, schema_registry)
                            validated_array[i] = item_result.data

                            if next(item_result._errors) then
                                has_errors = true
                                result._errors[field_name .. "[" .. i .. "]"] = item_result._errors
                            end
                        end

                        result.data[field_name] = validated_array
                        if has_errors then
                            -- Keep the original value in case of errors
                            result.data[field_name] = value
                        end
                    else
                        -- Validate single nested object
                        local nested_result = M.validate(value, nested_schema, schema_registry)
                        result.data[field_name] = nested_result.data

                        if next(nested_result._errors) then
                            result._errors[field_name] = nested_result._errors
                        end
                    end
                else
                    result.data[field_name] = value
                end
            else
                result.data[field_name] = value
            end
        end
    end

    -- Check for unknown fields
    for field_name, value in pairs(data) do
        if not schema[field_name] then
            if is_shortcut then
                result._errors[field_name] = "Unknown shortcut config key: " .. field_name
            else
                result._errors[field_name] = "Unknown config key: " .. field_name
            end
            result.data[field_name] = value
        end
    end

    return result
end

return M
