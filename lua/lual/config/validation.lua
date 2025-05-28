--- Configuration validation functions
-- This module contains all validation logic for different config formats

local constants = require("lual.config.constants")

local M = {}

--- Validates output and formatter types
-- @param output_type string The output type to validate
-- @param formatter_type string The formatter type to validate
-- @return boolean, string True if valid, or false with error message
function M.validate_output_formatter_types(output_type, formatter_type)
    -- Validate known output types
    if not constants.VALID_OUTPUT_TYPES[output_type] then
        return false, "Unknown output type: " .. output_type .. ". Valid types are: console, file"
    end

    -- Validate known formatter types
    if not constants.VALID_FORMATTER_TYPES[formatter_type] then
        return false, "Unknown formatter type: " .. formatter_type .. ". Valid types are: color, json, text"
    end

    return true
end

--- Validates a level value (string or number)
-- @param level The level to validate
-- @return boolean, string True if valid, or false with error message
function M.validate_level(level)
    if level == nil then
        return true -- Level is optional
    end

    if type(level) == "string" then
        if not constants.VALID_LEVEL_STRINGS[string.lower(level)] then
            return false,
                "Invalid level string: " .. level .. ". Valid levels are: critical, debug, error, info, none, warning"
        end
    elseif type(level) == "number" then
        -- Allow numeric levels
    else
        return false, "Level must be a string or number"
    end

    return true
end

--- Validates a timezone value
-- @param timezone The timezone to validate
-- @return boolean, string True if valid, or false with error message
function M.validate_timezone(timezone)
    if timezone == nil then
        return true -- Timezone is optional
    end

    if type(timezone) ~= "string" then
        return false, "Timezone must be a string"
    end

    if not constants.VALID_TIMEZONES[string.lower(timezone)] then
        return false, "Invalid timezone: " .. timezone .. ". Valid timezones are: local, utc"
    end

    return true
end

--- Validates basic config fields (name, propagate, timezone)
-- @param config table The config to validate
-- @return boolean, string True if valid, or false with error message
function M.validate_basic_fields(config)
    if config.name and type(config.name) ~= "string" then
        return false, "Config.name must be a string"
    end

    if config.propagate ~= nil and type(config.propagate) ~= "boolean" then
        return false, "Config.propagate must be a boolean"
    end

    -- Validate timezone
    local valid, err = M.validate_timezone(config.timezone)
    if not valid then
        return false, err
    end

    return true
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
    -- Check for required fields in shortcut format
    if not config.output then
        return false, "Shortcut config must have an 'output' field"
    end

    if not config.formatter then
        return false, "Shortcut config must have a 'formatter' field"
    end

    -- Validate output type
    if type(config.output) ~= "string" then
        return false, "Shortcut config 'output' field must be a string"
    end

    -- Validate formatter type
    if type(config.formatter) ~= "string" then
        return false, "Shortcut config 'formatter' field must be a string"
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
