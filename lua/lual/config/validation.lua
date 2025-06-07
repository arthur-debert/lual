--- Configuration Validation
-- This module handles validation of configuration structures

local M = {}

--- Validates the configuration structure
-- @param config_table table Configuration to validate
-- @param registry table Registry instance for checking valid keys
-- @return boolean, string True if valid, otherwise false and error message
function M.validate_config_structure(config_table, registry)
    if config_table == nil then
        return false, "Configuration must be a table, got nil"
    end

    if type(config_table) ~= "table" then
        return false, "Configuration must be a table, got " .. type(config_table)
    end

    -- Reject outputs key entirely - no backward compatibility
    if config_table.outputs then
        return false, "'outputs' is no longer supported. Use 'pipelines' instead."
    end

    -- Check for unknown keys
    local registered_keys = registry.get_registered_keys()
    local valid_keys = {}
    for _, key in ipairs(registered_keys) do
        valid_keys[key] = true
    end

    for key, _ in pairs(config_table) do
        if not valid_keys[key] then
            local valid_key_list = {}
            for valid_key, _ in pairs(valid_keys) do
                table.insert(valid_key_list, valid_key)
            end
            table.sort(valid_key_list)
            return false, string.format(
                "Unknown configuration key '%s'",
                tostring(key)
            )
        end
    end

    -- Validate using registry
    local valid, error_msg = registry.validate(config_table)
    if not valid then
        return false, error_msg
    end

    return true
end

return M
