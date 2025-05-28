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

    outputs = {
        multiple = true,
        type = "table",
        required = false,
        description = "Array of output configurations.",
        schema = "OutputSchema" -- Reference to another schema
    }
}

-- Output schema definition
M.OutputSchema = {
    type = {
        multiple = false,
        type = "string",
        values = extract_valid_values(constants.VALID_OUTPUT_TYPES),
        required = true,
        description = "The type of output (console or file)."
    },

    formatter = {
        multiple = false,
        type = "string",
        values = extract_valid_values(constants.VALID_FORMATTER_TYPES),
        required = true,
        description = "The formatter type to use for this output."
    },

    path = {
        multiple = false,
        type = "string",
        required = false,
        description = "File path for file outputs.",
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
        description = "Stream for console outputs."
    }
}

return M
