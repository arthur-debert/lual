--- Configuration validation functions
-- This module contains all validation logic for different config formats

local constants = require("lual.config.constants")

local M = {}

--- Helper function to generate expected error message for testing
-- @param value The invalid value
-- @param constant_table The constant table with _meta property
-- @return string The expected error message
function M.generate_expected_error_message(value, constant_table)
    local meta = constant_table._meta
    if not meta then
        error("Constant table missing _meta property")
    end

    local field_name = meta.name

    -- Generate valid values list
    local valid_values = {}
    for key, _ in pairs(constant_table) do
        if key ~= "_meta" then -- Skip the meta property
            table.insert(valid_values, key)
        end
    end
    table.sort(valid_values) -- Sort for consistent output

    return string.format("Invalid %s: %s. Valid values are: %s",
        field_name,
        tostring(value),
        table.concat(valid_values, ", "))
end

--- Generic validator for values against constant tables with metadata
-- @param value The value to validate
-- @param constant_table The constant table with _meta property
-- @param allow_nil boolean Whether nil values are allowed (default: true)
-- @param expected_type string Optional type to validate (e.g., "string", "number")
-- @return boolean, string True if valid, or false with error message
function M.validate_against_constants(value, constant_table, allow_nil, expected_type)
    if allow_nil == nil then allow_nil = true end

    if value == nil then
        return allow_nil, allow_nil and nil or ("Value cannot be nil")
    end

    -- Type validation if specified
    if expected_type and type(value) ~= expected_type then
        local meta = constant_table._meta
        local field_name = meta and meta.name or "value"
        return false, string.format("%s must be a %s", string.gsub(field_name, "^%l", string.upper), expected_type)
    end

    local meta = constant_table._meta
    if not meta then
        error("Constant table missing _meta property")
    end

    local case_sensitive = meta.case_sensitive

    -- Convert value for comparison if case-insensitive
    local lookup_value = value
    if not case_sensitive and type(value) == "string" then
        lookup_value = string.lower(value)
    end

    -- Check if value exists in constant table
    if constant_table[lookup_value] then
        return true
    end

    -- Use the helper function to generate the error message
    local error_msg = M.generate_expected_error_message(value, constant_table)
    return false, error_msg
end

--- Validates multiple fields against their respective constant tables
-- @param field_validations table Array of {value, constant_table, allow_nil, expected_type, custom_validator} tuples
-- @return boolean, string True if all valid, or false with first error message
function M.validate_fields(field_validations)
    for _, validation in ipairs(field_validations) do
        local value = validation[1]
        local constant_table = validation[2]
        local allow_nil = validation[3]
        local expected_type = validation[4]    -- Optional type validation
        local custom_validator = validation[5] -- Optional custom validation function

        -- Apply custom validation first if provided
        if custom_validator then
            local valid, err = custom_validator(value)
            if not valid then
                return false, err
            end
        end

        -- Apply constant table validation
        if constant_table then
            local valid, err = M.validate_against_constants(value, constant_table, allow_nil, expected_type)
            if not valid then
                return false, err
            end
        end
    end

    return true
end

--- Validates output and formatter types
-- @param output_type string The output type to validate
-- @param formatter_type string The formatter type to validate
-- @return boolean, string True if valid, or false with error message
function M.validate_output_formatter_types(output_type, formatter_type)
    return M.validate_fields({
        { output_type,    constants.VALID_OUTPUT_TYPES,    false, "string" },
        { formatter_type, constants.VALID_FORMATTER_TYPES, false, "string" }
    })
end

--- Validates a level value (string or number)
-- @param level The level to validate
-- @return boolean, string True if valid, or false with error message
function M.validate_level(level)
    if level == nil then
        return true -- Level is optional
    end

    if type(level) == "string" then
        -- Validate string levels against constants
        return M.validate_against_constants(level, constants.VALID_LEVEL_STRINGS, false)
    elseif type(level) == "number" then
        -- Allow numeric levels without validation against string constants
        return true
    else
        return false, "Level must be a string or number"
    end
end

--- Validates a timezone value
-- @param timezone The timezone to validate
-- @return boolean, string True if valid, or false with error message
function M.validate_timezone(timezone)
    return M.validate_against_constants(timezone, constants.VALID_TIMEZONES, true, "string")
end

--- Validates basic config fields (name, propagate, timezone)
-- @param config table The config to validate
-- @return boolean, string True if valid, or false with error message
function M.validate_basic_fields(config)
    -- Validate name (optional string)
    if config.name ~= nil then
        if type(config.name) ~= "string" then
            return false, "Config.name must be a string"
        end
    end

    -- Validate propagate (optional boolean)
    if config.propagate ~= nil then
        if type(config.propagate) ~= "boolean" then
            return false, "Config.propagate must be a boolean"
        end
    end

    -- Validate timezone using generic validator
    return M.validate_timezone(config.timezone)
end

--- Validates a canonical config table
-- @param config (table) The config to validate
-- @return boolean, string True if valid, or false with error message
function M.validate_canonical_config(config)
    if type(config) ~= "table" then
        return false, "Config must be a table"
    end

    if config.name and type(config.name) ~= "string" then
        return false, "Config.name must be a string"
    end

    if config.level and type(config.level) ~= "number" then
        return false, "Config.level must be a number"
    end

    if config.outputs and type(config.outputs) ~= "table" then
        return false, "Config.outputs must be a table"
    end

    if config.propagate ~= nil and type(config.propagate) ~= "boolean" then
        return false, "Config.propagate must be a boolean"
    end

    -- Validate timezone
    local valid, err = M.validate_timezone(config.timezone)
    if not valid then
        return false, err
    end

    -- Validate outputs structure
    if config.outputs then
        for i, output in ipairs(config.outputs) do
            if type(output) ~= "table" then
                return false, "Each output must be a table"
            end
            if not output.output_func or type(output.output_func) ~= "function" then
                return false, "Each output must have an output_func function"
            end
            if not output.formatter_func or type(output.formatter_func) ~= "function" then
                return false, "Each output must have a formatter_func function"
            end
        end
    end

    return true
end

--- Validates a single output configuration
-- @param output table The output config to validate
-- @param index number The index of the output (for error messages)
-- @return boolean, string True if valid, or false with error message
function M.validate_single_output(output, index)
    if type(output) ~= "table" then
        return false, "Each output must be a table"
    end

    if not output.type or type(output.type) ~= "string" then
        return false, "Each output must have a 'type' string field"
    end

    if not output.formatter or type(output.formatter) ~= "string" then
        return false, "Each output must have a 'formatter' string field"
    end

    -- Validate output and formatter types
    local valid, err = M.validate_output_formatter_types(output.type, output.formatter)
    if not valid then
        return false, err
    end

    -- Validate type-specific fields
    if output.type == "file" then
        if not output.path or type(output.path) ~= "string" then
            return false, "File output must have a 'path' string field"
        end
    end

    if output.type == "console" and output.stream then
        -- stream should be a file handle, but we can't easily validate that
        -- so we'll just check it's not a string/number/boolean
        if type(output.stream) == "string" or type(output.stream) == "number" or type(output.stream) == "boolean" then
            return false, "Console output 'stream' field must be a file handle"
        end
    end

    return true
end

--- Validates outputs array for declarative format
-- @param outputs table The outputs array to validate
-- @return boolean, string True if valid, or false with error message
function M.validate_outputs(outputs)
    if outputs == nil then
        return true -- Outputs is optional
    end

    if type(outputs) ~= "table" then
        return false, "Config.outputs must be a table"
    end

    for i, output in ipairs(outputs) do
        local valid, err = M.validate_single_output(output, i)
        if not valid then
            return false, err
        end
    end

    return true
end

--- Validates that declarative config doesn't contain unknown keys
-- @param config table The config to validate
-- @return boolean, string True if valid, or false with error message
function M.validate_declarative_known_keys(config)
    for key, _ in pairs(config) do
        if not constants.VALID_DECLARATIVE_KEYS[key] then
            return false, "Unknown config key: " .. tostring(key)
        end
    end

    return true
end

--- Validates a declarative config table (with string-based types)
-- @param config (table) The declarative config to validate
-- @return boolean, string True if valid, or false with error message
function M.validate_declarative_config(config)
    if type(config) ~= "table" then
        return false, "Config must be a table"
    end

    -- Validate unknown keys
    local valid, err = M.validate_declarative_known_keys(config)
    if not valid then
        return false, err
    end

    -- Validate basic fields
    valid, err = M.validate_basic_fields(config)
    if not valid then
        return false, err
    end

    -- Validate level
    valid, err = M.validate_level(config.level)
    if not valid then
        return false, err
    end

    -- Validate outputs
    valid, err = M.validate_outputs(config.outputs)
    if not valid then
        return false, err
    end

    return true
end

--- Validates that shortcut config doesn't contain unknown keys
-- @param config table The config to validate
-- @return boolean, string True if valid, or false with error message
function M.validate_shortcut_known_keys(config)
    for key, _ in pairs(config) do
        if not constants.VALID_SHORTCUT_KEYS[key] then
            return false, "Unknown shortcut config key: " .. tostring(key)
        end
    end

    return true
end

--- Validates shortcut config fields
-- @param config table The shortcut config to validate
-- @return boolean, string True if valid, or false with error message
function M.validate_shortcut_fields(config)
    -- Check for required fields
    if not config.output then
        return false, "Shortcut config must have an 'output' field"
    end
    if not config.formatter then
        return false, "Shortcut config must have a 'formatter' field"
    end

    -- Validate output and formatter types
    local valid, err = M.validate_output_formatter_types(config.output, config.formatter)
    if not valid then
        return false, err
    end

    -- Validate file-specific requirements
    if config.output == "file" then
        if not config.path or type(config.path) ~= "string" then
            return false, "File output in shortcut config must have a 'path' string field"
        end
    end

    -- Validate console-specific fields
    if config.output == "console" and config.stream then
        if type(config.stream) == "string" or type(config.stream) == "number" or type(config.stream) == "boolean" then
            return false, "Console output 'stream' field must be a file handle"
        end
    end

    return true
end

--- Validates a shortcut declarative config table
-- @param config table The shortcut config to validate
-- @return boolean, string True if valid, or false with error message
function M.validate_shortcut_config(config)
    if type(config) ~= "table" then
        return false, "Config must be a table"
    end

    -- Validate unknown keys
    local valid, err = M.validate_shortcut_known_keys(config)
    if not valid then
        return false, err
    end

    -- Validate basic fields (name, propagate)
    valid, err = M.validate_basic_fields(config)
    if not valid then
        return false, err
    end

    -- Validate level
    valid, err = M.validate_level(config.level)
    if not valid then
        return false, err
    end

    -- Validate shortcut-specific fields
    valid, err = M.validate_shortcut_fields(config)
    if not valid then
        return false, err
    end

    return true
end

return M
