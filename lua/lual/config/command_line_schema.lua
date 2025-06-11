--- Command Line Verbosity Configuration Schema
-- Schema definition for command-line driven logging level configuration

local core_levels = require("lual.levels")
local schemer = require("lual.utils.schemer")

local M = {}

-- Default mapping of command line flags to log levels
M.DEFAULT_MAPPING = {
    v = "warning",
    vv = "info",
    vvv = "debug",
    verbose = "info",
    quiet = "error",
    silent = "critical"
}

-- Custom validator for mapping that accepts both string level names and numeric level values
local function validate_mapping(mapping)
    if type(mapping) ~= "table" then
        return false, "mapping must be a table"
    end

    -- Create enum with reverse lookup for level validation
    local level_enum = schemer.enum(core_levels.get_all_levels(), {
        reverse = true,
        case_insensitive = true
    })

    for flag, level_value in pairs(mapping) do
        if type(flag) ~= "string" then
            return false, "mapping keys must be strings"
        end

        -- Validate the level value using schemer's enum validation
        local field_schema = {
            values = level_enum
        }

        local errors, normalized_value = schemer.validate({ level = level_value }, {
            fields = { level = field_schema }
        })

        if errors then
            return false, "invalid level value '" .. tostring(level_value) .. "' for flag '" .. flag .. "'"
        end

        -- Update the mapping with the normalized value (string -> number conversion)
        mapping[flag] = normalized_value.level
    end

    return true
end

-- Command line verbosity configuration schema
M.command_line_schema = {
    fields = {
        mapping = {
            type = "table",
            required = false,
            default = M.DEFAULT_MAPPING,
            custom_validator = validate_mapping
        },
        auto_detect = {
            type = "boolean",
            required = false,
            default = true
        }
    },
    on_extra_keys = "error"
}

return M
