--- Configuration validation functions
-- This module contains all validation logic for different config formats

local constants = require("lual.config.constants")

local M = {}

--- Simple validation: merge with defaults and check for unknown fields
-- @param user_config table The user's config
-- @param default_config table The default config to merge with
-- @return table, string The merged config or nil with error message
function M.validate_and_merge_config(user_config, default_config)
    -- Start with default config
    local merged_config = {}
    for k, v in pairs(default_config) do
        merged_config[k] = v
    end

    -- Override with user config
    for k, v in pairs(user_config) do
        merged_config[k] = v
    end

    -- Check for unknown fields in merged config
    for key, _ in pairs(merged_config) do
        if not constants.VALID_DECLARATIVE_KEYS[key] then
            return nil, "Unknown config key: " .. tostring(key)
        end
    end

    -- Validate outputs array if present
    if merged_config.outputs then
        if type(merged_config.outputs) ~= "table" then
            return nil, "Config.outputs must be a table"
        end

        for i, output in ipairs(merged_config.outputs) do
            if type(output) ~= "table" then
                return nil, "Each output must be a table"
            end

            -- Check for unknown fields in output
            local valid_output_keys = {
                type = true,
                formatter = true,
                path = true,   -- for file outputs
                stream = true, -- for console outputs
            }

            for key, _ in pairs(output) do
                if not valid_output_keys[key] then
                    return nil, "Unknown output key: " .. tostring(key)
                end
            end

            -- Validate required fields
            if not output.type then
                return nil, "Each output must have a 'type' string field"
            end
            if not output.formatter then
                return nil, "Each output must have a 'formatter' string field"
            end

            -- Validate output type
            local valid, err = constants.validate_against_constants(output.type, constants.VALID_OUTPUT_TYPES, false,
                "string")
            if not valid then
                return nil, err
            end

            -- Validate formatter type
            valid, err = constants.validate_against_constants(output.formatter, constants.VALID_FORMATTER_TYPES, false,
                "string")
            if not valid then
                return nil, err
            end

            -- Validate type-specific requirements
            if output.type == "file" then
                if not output.path or type(output.path) ~= "string" then
                    return nil, "File output must have a 'path' string field"
                end
            elseif output.type == "console" and output.stream then
                -- Validate stream is a file handle (not string/number/boolean)
                if type(output.stream) == "string" or type(output.stream) == "number" or type(output.stream) == "boolean" then
                    return nil, "Console output 'stream' field must be a file handle"
                end
            end
        end
    end

    -- Basic field validation
    if merged_config.name and type(merged_config.name) ~= "string" then
        return nil, "Config.name must be a string"
    end

    if merged_config.propagate ~= nil and type(merged_config.propagate) ~= "boolean" then
        return nil, "Config.propagate must be a boolean"
    end

    if merged_config.level then
        if type(merged_config.level) == "string" then
            local valid, err = constants.validate_against_constants(merged_config.level, constants.VALID_LEVEL_STRINGS,
                false)
            if not valid then
                return nil, err
            end
        elseif type(merged_config.level) ~= "number" then
            return nil, "Level must be a string or number"
        end
    end

    if merged_config.timezone then
        local valid, err = constants.validate_against_constants(merged_config.timezone, constants.VALID_TIMEZONES, true,
            "string")
        if not valid then
            return nil, err
        end
    end

    return merged_config, nil
end

--- Validates shortcut config and checks for unknown fields
-- @param config table The shortcut config to validate
-- @return boolean, string True if valid, or false with error message
function M.validate_shortcut_config(config)
    if type(config) ~= "table" then
        return false, "Config must be a table"
    end

    -- Check for unknown fields
    for key, _ in pairs(config) do
        if not constants.VALID_SHORTCUT_KEYS[key] then
            return false, "Unknown shortcut config key: " .. tostring(key)
        end
    end

    -- Check required fields
    if not config.output then
        return false, "Shortcut config must have an 'output' field"
    end
    if not config.formatter then
        return false, "Shortcut config must have a 'formatter' field"
    end

    -- Validate output and formatter types
    local valid, err = constants.validate_against_constants(config.output, constants.VALID_OUTPUT_TYPES, false, "string")
    if not valid then
        return false, err
    end

    valid, err = constants.validate_against_constants(config.formatter, constants.VALID_FORMATTER_TYPES, false, "string")
    if not valid then
        return false, err
    end

    -- Validate type-specific requirements
    if config.output == "file" then
        if not config.path or type(config.path) ~= "string" then
            return false, "File output in shortcut config must have a 'path' string field"
        end
    elseif config.output == "console" and config.stream then
        -- Validate stream is a file handle (not string/number/boolean)
        if type(config.stream) == "string" or type(config.stream) == "number" or type(config.stream) == "boolean" then
            return false, "Console output 'stream' field must be a file handle"
        end
    end

    -- Validate other fields
    if config.name and type(config.name) ~= "string" then
        return false, "Config.name must be a string"
    end

    if config.propagate ~= nil and type(config.propagate) ~= "boolean" then
        return false, "Config.propagate must be a boolean"
    end

    if config.level then
        if type(config.level) == "string" then
            local valid, err = constants.validate_against_constants(config.level, constants.VALID_LEVEL_STRINGS, false)
            if not valid then
                return false, err
            end
        elseif type(config.level) ~= "number" then
            return false, "Level must be a string or number"
        end
    end

    if config.timezone then
        local valid, err = constants.validate_against_constants(config.timezone, constants.VALID_TIMEZONES, true,
            "string")
        if not valid then
            return false, err
        end
    end

    return true
end

--- Validates a canonical config table (still needed by the system)
-- @param config table The config to validate
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
    if config.timezone then
        local valid, err = constants.validate_against_constants(config.timezone, constants.VALID_TIMEZONES, true,
            "string")
        if not valid then
            return false, err
        end
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

return M
