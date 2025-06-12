--- Logger Configuration Module
-- This module handles configuration validation for loggers

local core_levels = require("lual.levels")
local schemer = require("lual.utils.schemer")
local loggers_schema_module = require("lual.loggers.schema")

--- Validates a logger configuration table
-- DEPRECATED: This is kept for backward compatibility with tests.
-- In the future, all validation should be done by the config registry system.
-- @param config_table table The configuration to validate
-- @param return_detailed boolean If true, returns detailed error structure
-- @return boolean, string|table True if valid, or false with error message/structure
local function validate_logger_config_table(config_table, return_detailed)
    if type(config_table) ~= "table" then
        if return_detailed then
            return false, {
                error_code = "INVALID_TYPE",
                message = "Configuration must be a table, got " .. type(config_table),
                field = nil
            }
        else
            return false, "Configuration must be a table, got " .. type(config_table)
        end
    end

    -- Use schemer for validation (includes unknown key detection via on_extra_keys)
    local errors = schemer.validate(config_table, loggers_schema_module.logger_schema)
    if errors then
        if return_detailed then
            -- Convert only UNKNOWN_KEY errors to legacy format for backward compatibility
            if errors.fields then
                for field_name, field_errors in pairs(errors.fields) do
                    for _, error_info in ipairs(field_errors) do
                        local error_code, error_message = error_info[1], error_info[2]
                        if error_code == "UNKNOWN_KEY" then
                            return false, {
                                error_code = error_code,
                                message = error_message,
                                field = field_name
                            }
                        end
                    end
                end
            end
            -- Return schemer format for all other errors
            return false, errors
        else
            return false, errors.error
        end
    end

    return true
end

-- Export the module
return {
    validate_logger_config_table = validate_logger_config_table,
    VALID_LOGGER_CONFIG_KEYS = {
        level = { type = "number", description = "Logging level (use lual.DEBUG, lual.INFO, etc.)" },
        pipelines = { type = "table", description = "Array of pipeline configurations" },
        propagate = { type = "boolean", description = "Whether to propagate messages to parent loggers" }
    }
}
