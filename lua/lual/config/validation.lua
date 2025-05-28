--- Configuration validation functions
-- This module contains all validation logic for different config formats

local constants = require("lual.config.constants")

local M = {}

--- Simple validation: merge with defaults and check for unknown fields
-- @param user_config table The user's config
-- @param default_config table The default config to merge with
-- @return table, string The merged config or nil with error message
function M.validate_and_merge_config(user_config, default_config)
    -- 1. Merge
    local merged = {}
    for k, v in pairs(default_config) do merged[k] = v end
    for k, v in pairs(user_config) do merged[k] = v end

    -- 2. Check unknown keys
    for key in pairs(merged) do
        if not constants.VALID_DECLARATIVE_KEYS[key] then
            return nil, "Unknown config key: " .. key
        end
    end

    -- 3. Validate basic fields
    if merged.name and type(merged.name) ~= "string" then return nil, "Config.name must be a string" end
    if merged.propagate ~= nil and type(merged.propagate) ~= "boolean" then
        return nil,
            "Config.propagate must be a boolean"
    end
    if merged.level and type(merged.level) == "string" then
        local ok, err = constants.validate_against_constants(merged.level, constants.VALID_LEVEL_STRINGS, false)
        if not ok then return nil, err end
    elseif merged.level and type(merged.level) ~= "number" then
        return nil, "Level must be a string or number"
    end
    if merged.timezone then
        local ok, err = constants.validate_against_constants(merged.timezone, constants.VALID_TIMEZONES, true, "string")
        if not ok then return nil, err end
    end

    -- 4. Validate outputs array
    if merged.outputs then
        if type(merged.outputs) ~= "table" then return nil, "Config.outputs must be a table" end
        for i, output in ipairs(merged.outputs) do
            local err = M.validate_single_output(output)
            if err then return nil, err end
        end
    end

    return merged
end

--- Validates a single output configuration
-- @param output table The output config to validate
-- @return string|nil Error message or nil if valid
function M.validate_single_output(output)
    if type(output) ~= "table" then return "Each output must be a table" end

    -- Check unknown keys
    local valid_keys = { type = true, formatter = true, path = true, stream = true }
    for key in pairs(output) do
        if not valid_keys[key] then return "Unknown output key: " .. key end
    end

    -- Required fields
    if not output.type then return "Each output must have a 'type' string field" end
    if not output.formatter then return "Each output must have a 'formatter' string field" end

    -- Validate types
    local ok, err = constants.validate_against_constants(output.type, constants.VALID_OUTPUT_TYPES, false, "string")
    if not ok then return err end
    ok, err = constants.validate_against_constants(output.formatter, constants.VALID_FORMATTER_TYPES, false, "string")
    if not ok then return err end

    -- Type-specific validation
    if output.type == "file" and (not output.path or type(output.path) ~= "string") then
        return "File output must have a 'path' string field"
    end
    if output.type == "console" and output.stream then
        if type(output.stream) == "string" or type(output.stream) == "number" or type(output.stream) == "boolean" then
            return "Console output 'stream' field must be a file handle"
        end
    end

    return nil
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
