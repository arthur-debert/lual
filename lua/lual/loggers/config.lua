--- Logger Configuration Module
-- This module handles configuration validation for loggers

local core_levels = require("lual.levels")
local table_utils = require("lual.utils.table")

-- Configuration validation for non-root loggers
-- DEPRECATED: This is kept for backward compatibility with tests.
-- In the future, all validation should be done by the config registry system.
local VALID_LOGGER_CONFIG_KEYS = {
    level = { type = "number", description = "Logging level (use lual.DEBUG, lual.INFO, etc.)" },
    pipelines = { type = "table", description = "Array of pipeline configurations" },
    propagate = { type = "boolean", description = "Whether to propagate messages to parent loggers" }
}

--- Validates a logger configuration table
-- DEPRECATED: This is kept for backward compatibility with tests.
-- In the future, all validation should be done by the config registry system.
-- @param config_table table The configuration to validate
-- @return boolean, string True if valid, or false with error message
local function validate_logger_config_table(config_table)
    if type(config_table) ~= "table" then
        return false, "Configuration must be a table, got " .. type(config_table)
    end

    -- Reject outputs key entirely - no backward compatibility
    if config_table.outputs then
        return false, "'outputs' is no longer supported. Use 'pipelines' instead."
    end

    local key_diff = table_utils.key_diff(VALID_LOGGER_CONFIG_KEYS, config_table)
    if #key_diff.added_keys > 0 then
        local valid_keys_list = {}
        for valid_key, _ in pairs(VALID_LOGGER_CONFIG_KEYS) do table.insert(valid_keys_list, valid_key) end
        table.sort(valid_keys_list)
        return false,
            string.format("Unknown configuration key '%s'. Valid keys are: %s", tostring(key_diff.added_keys[1]),
                table.concat(valid_keys_list, ", "))
    end

    for key, value in pairs(config_table) do
        local expected_spec = VALID_LOGGER_CONFIG_KEYS[key]
        local expected_type = expected_spec.type
        local actual_type = type(value)
        if actual_type ~= expected_type then
            return false,
                string.format("Invalid type for '%s': expected %s, got %s. %s", key, expected_type, actual_type,
                    expected_spec.description)
        end
        if key == "level" then
            local valid_level = false
            for _, level_value in pairs(core_levels.definition) do
                if value == level_value then
                    valid_level = true
                    break
                end
            end
            if not valid_level then
                local valid_levels_list = {}
                for level_name, level_val in pairs(core_levels.definition) do
                    table.insert(valid_levels_list,
                        string.format("%s(%d)", level_name, level_val))
                end
                table.sort(valid_levels_list)
                return false,
                    string.format("Invalid level value %d. Valid levels are: %s", value,
                        table.concat(valid_levels_list, ", "))
            end
        end
    end
    return true
end

-- Export the module
return {
    validate_logger_config_table = validate_logger_config_table,
    VALID_LOGGER_CONFIG_KEYS = VALID_LOGGER_CONFIG_KEYS
}
