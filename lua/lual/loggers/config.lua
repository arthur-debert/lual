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

    -- Reject outputs key entirely - no backward compatibility
    if config_table.outputs then
        if return_detailed then
            return false, {
                error_code = "DEPRECATED_KEY",
                message = "'outputs' is no longer supported. Use 'pipelines' instead.",
                field = "outputs"
            }
        else
            return false, "'outputs' is no longer supported. Use 'pipelines' instead."
        end
    end

    -- Check for unknown keys first
    local valid_keys = { "level", "pipelines", "propagate" }
    for key, _ in pairs(config_table) do
        local found = false
        for _, valid_key in ipairs(valid_keys) do
            if key == valid_key then
                found = true
                break
            end
        end
        if not found then
            if return_detailed then
                return false, {
                    error_code = "UNKNOWN_KEY",
                    message = "Unknown configuration key '" .. key .. "'",
                    field = key
                }
            else
                return false, "Unknown configuration key '" .. key .. "'"
            end
        end
    end

    -- Use schemer for validation
    local errors = schemer.validate(config_table, loggers_schema_module.logger_schema)
    if errors then
        if return_detailed then
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
