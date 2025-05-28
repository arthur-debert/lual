--- Configuration validation functions
-- This module contains all validation logic for different config formats

local constants = require("lual.config.constants")
local schema = require("lual.schema")

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

    -- 2. Use schema validation
    local result = schema.validate_config(merged)

    -- 3. Check for errors and return in the old format
    if next(result._errors) then
        -- Convert first error to old format (single error string)
        for field, error_msg in pairs(result._errors) do
            if type(error_msg) == "table" then
                -- Handle nested errors (like outputs[1].formatter)
                for sub_field, sub_error in pairs(error_msg) do
                    return nil, sub_error
                end
            else
                return nil, error_msg
            end
        end
    end

    return result.data
end

--- Validates a single output configuration
-- @param output table The output config to validate
-- @return string|nil Error message or nil if valid
function M.validate_single_output(output)
    -- Use schema validation for output
    local result = schema.validate_output(output)

    -- Check for errors and return in the old format
    if next(result._errors) then
        -- Return first error message
        for field, error_msg in pairs(result._errors) do
            return error_msg
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

    -- Validate timezone using schema validation
    if config.timezone then
        local temp_config = { timezone = config.timezone }
        local result = schema.validate_config(temp_config)
        if result._errors.timezone then
            return false, result._errors.timezone
        end
    end

    -- Validate outputs structure (canonical format has functions)
    if config.outputs then
        for i, output in ipairs(config.outputs) do
            if type(output) ~= "table" then
                return false, "Each output must be a table"
            end
            if not output.output_func or type(output.output_func) ~= "function" then
                return false, "Each output must have an output_func function"
            end
            if not output.formatter_func or (type(output.formatter_func) ~= "function" and not (type(output.formatter_func) == "table" and getmetatable(output.formatter_func) and getmetatable(output.formatter_func).__call)) then
                return false, "Each output must have a formatter_func function"
            end
        end
    end

    return true
end

return M
