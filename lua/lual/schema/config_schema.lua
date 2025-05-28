--- Configuration schema definition
-- This module defines the schema for validating configuration objects

local constants = require("lual.config.constants")

local M = {}

-- Extract valid values from constants (removing _meta)
local function extract_valid_values(constant_table)
    local values = {}
    for key, value in pairs(constant_table) do
        if key ~= "_meta" then
            values[key] = value
        end
    end
    return values
end

-- Helper function to generate expected error messages for testing
function M.generate_expected_error(schema_name, field_name, error_type, value)
    local schema = M[schema_name]
    if not schema or not schema[field_name] then
        return "Unknown field or schema"
    end

    local field_schema = schema[field_name]

    if error_type == "required" then
        if field_name == "type" then
            if schema_name == "transformerschema" then
                return "Each transformer must have a 'type' string field"
            else
                return "Each dispatcher must have a 'type' string field"
            end
        elseif field_name == "presenter" then
            return "Each dispatcher must have a 'presenter' string field"
        else
            return string.format("%s is required", string.gsub(field_name, "^%l", string.upper))
        end
    elseif error_type == "type" then
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
        else
            local type_str = type(field_schema.type) == "table"
                and table.concat(field_schema.type, " or ")
                or field_schema.type
            return string.format("%s must be a %s",
                string.gsub(field_name, "^%l", string.upper), type_str)
        end
    elseif error_type == "invalid_value" then
        if field_schema.values then
            local valid_values = {}
            for key, _ in pairs(field_schema.values) do
                table.insert(valid_values, key)
            end
            table.sort(valid_values)

            if field_name == "type" then
                if schema_name == "transformerschema" then
                    return string.format("Invalid transformer type: %s. Valid values are: %s",
                        tostring(value), table.concat(valid_values, ", "))
                else
                    return string.format("Invalid dispatcher type: %s. Valid values are: %s",
                        tostring(value), table.concat(valid_values, ", "))
                end
            elseif field_name == "presenter" then
                return string.format("Invalid presenter type: %s. Valid values are: %s",
                    tostring(value), table.concat(valid_values, ", "))
            else
                return string.format("Invalid %s: %s. Valid values are: %s",
                    field_name, tostring(value), table.concat(valid_values, ", "))
            end
        end
    elseif error_type == "conditional" then
        if field_name == "path" then
            return "File dispatcher must have a 'path' string field"
        end
    elseif error_type == "unknown" then
        return "Unknown config key: " .. field_name
    end

    return "Unknown error type"
end

-- Configuration schema definition
M.ConfigSchema = {
    name = {
        multiple = false,
        type = "string",
        required = false,
        description = "The name of the logger instance."
    },

    level = {
        multiple = false,
        type = { "string", "number" },
        values = extract_valid_values(constants.VALID_LEVEL_STRINGS),
        required = false,
        description = "The logging level threshold."
    },

    propagate = {
        multiple = false,
        type = "boolean",
        required = false,
        description = "Whether to propagate log messages to parent loggers."
    },

    timezone = {
        multiple = false,
        type = "string",
        values = extract_valid_values(constants.VALID_TIMEZONES),
        required = false,
        description = "The timezone to use for timestamps."
    },

    dispatchers = {
        multiple = true,
        type = "table",
        required = false,
        description = "Array of dispatcher configurations.",
        schema = "dispatcherschema" -- Reference to another schema
    }
}

-- dispatcher schema definition
M.dispatcherschema = {
    type = {
        multiple = false,
        type = "string",
        values = extract_valid_values(constants.VALID_dispatcher_TYPES),
        required = true,
        description = "The type of dispatcher (console or file)."
    },

    presenter = {
        multiple = false,
        type = "string",
        values = extract_valid_values(constants.VALID_PRESENTER_TYPES),
        required = true,
        description = "The presenter type to use for this dispatcher."
    },

    transformers = {
        multiple = true,
        type = "table",
        required = false,
        description = "Array of transformer configurations.",
        schema = "transformerschema" -- Reference to transformer schema
    },

    path = {
        multiple = false,
        type = "string",
        required = false,
        description = "File path for file dispatchers.",
        conditional = {
            field = "type",
            value = "file",
            required = true
        }
    },

    stream = {
        multiple = false,
        type = "userdata", -- file handle
        required = false,
        description = "Stream for console dispatchers."
    }
}

-- transformer schema definition
M.transformerschema = {
    type = {
        multiple = false,
        type = "string",
        values = extract_valid_values(constants.VALID_TRANSFORMER_TYPES),
        required = true,
        description = "The type of transformer (noop, etc.)."
    }
}

-- Shortcut schema definition (for shortcut API validation)
M.ShortcutSchema = {
    name = {
        multiple = false,
        type = "string",
        required = false,
        description = "The name of the logger instance."
    },

    level = {
        multiple = false,
        type = { "string", "number" },
        values = extract_valid_values(constants.VALID_LEVEL_STRINGS),
        required = false,
        description = "The logging level threshold."
    },

    propagate = {
        multiple = false,
        type = "boolean",
        required = false,
        description = "Whether to propagate log messages to parent loggers."
    },

    timezone = {
        multiple = false,
        type = "string",
        values = extract_valid_values(constants.VALID_TIMEZONES),
        required = false,
        description = "The timezone to use for timestamps."
    },

    dispatcher = {
        multiple = false,
        type = "string",
        values = extract_valid_values(constants.VALID_dispatcher_TYPES),
        required = true,
        description = "The type of dispatcher (console or file)."
    },

    presenter = {
        multiple = false,
        type = "string",
        values = extract_valid_values(constants.VALID_PRESENTER_TYPES),
        required = true,
        description = "The presenter type to use for this dispatcher."
    },

    path = {
        multiple = false,
        type = "string",
        required = false,
        description = "File path for file dispatchers.",
        conditional = {
            field = "dispatcher",
            value = "file",
            required = true
        }
    },

    stream = {
        multiple = false,
        type = "userdata", -- file handle
        required = false,
        description = "Stream for console dispatchers."
    }
}

return M
