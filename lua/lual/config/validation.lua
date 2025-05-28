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
                -- Handle nested errors (like dispatchers[1].formatter)
                for sub_field, sub_error in pairs(error_msg) do
                    return nil, sub_error
                end
            else
                return nil, error_msg
            end
        end
    end

    -- 4. Convert string-based config to function-based config if needed
    local validated_config = result.data
    if validated_config.dispatchers then
        local all_dispatchers = require("lual.dispatchers.init")
        local all_formatters = require("lual.formatters.init")

        for i, dispatcher in ipairs(validated_config.dispatchers) do
            -- Convert string formatter to function if it's still a string
            if type(dispatcher.formatter) == "string" then
                if dispatcher.formatter == "text" then
                    dispatcher.formatter_func = all_formatters.text
                elseif dispatcher.formatter == "color" then
                    dispatcher.formatter_func = all_formatters.color
                elseif dispatcher.formatter == "json" then
                    dispatcher.formatter_func = all_formatters.json
                end
                -- Keep the original string for reference but add the function
            end

            -- Convert string dispatcher type to function if needed
            if type(dispatcher.type) == "string" then
                if dispatcher.type == "console" then
                    dispatcher.dispatcher_func = all_dispatchers.console_dispatcher
                elseif dispatcher.type == "file" then
                    -- File dispatcher is a factory, so we need to call it with config
                    local config = { path = dispatcher.path }
                    -- Copy other file-specific config
                    for k, v in pairs(dispatcher) do
                        if k ~= "type" and k ~= "formatter" and k ~= "path" and k ~= "formatter_func" and k ~= "dispatcher_func" then
                            config[k] = v
                        end
                    end
                    dispatcher.dispatcher_func = all_dispatchers.file_dispatcher(config)
                    dispatcher.dispatcher_config = config
                end
            end
        end
    end

    return validated_config
end

--- Validates a single dispatcher configuration
-- @param dispatcher table The dispatcher config to validate
-- @return string|nil Error message or nil if valid
function M.validate_single_dispatcher(dispatcher)
    -- Use schema validation for dispatcher
    local result = schema.validate_dispatcher(dispatcher)

    -- Check for errors and return in the old format
    if next(result._errors) then
        -- Return first error message
        for field, error_msg in pairs(result._errors) do
            return error_msg
        end
    end

    -- Convert string-based config to function-based config if needed
    local validated_dispatcher = result.data
    if validated_dispatcher then
        local all_dispatchers = require("lual.dispatchers.init")
        local all_formatters = require("lual.formatters.init")

        -- Convert string formatter to function if it's still a string
        if type(validated_dispatcher.formatter) == "string" then
            if validated_dispatcher.formatter == "text" then
                validated_dispatcher.formatter_func = all_formatters.text
            elseif validated_dispatcher.formatter == "color" then
                validated_dispatcher.formatter_func = all_formatters.color
            elseif validated_dispatcher.formatter == "json" then
                validated_dispatcher.formatter_func = all_formatters.json
            end
        end

        -- Convert string dispatcher type to function if needed
        if type(validated_dispatcher.type) == "string" then
            if validated_dispatcher.type == "console" then
                validated_dispatcher.dispatcher_func = all_dispatchers.console_dispatcher
            elseif validated_dispatcher.type == "file" then
                -- File dispatcher is a factory, so we need to call it with config
                local config = { path = validated_dispatcher.path }
                -- Copy other file-specific config
                for k, v in pairs(validated_dispatcher) do
                    if k ~= "type" and k ~= "formatter" and k ~= "path" and k ~= "formatter_func" and k ~= "dispatcher_func" then
                        config[k] = v
                    end
                end
                validated_dispatcher.dispatcher_func = all_dispatchers.file_dispatcher(config)
                validated_dispatcher.dispatcher_config = config
            end
        end

        -- Copy the converted dispatcher back to the original
        for k, v in pairs(validated_dispatcher) do
            dispatcher[k] = v
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

    if config.dispatchers and type(config.dispatchers) ~= "table" then
        return false, "Config.dispatchers must be a table"
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

    -- Validate dispatchers structure (canonical format has functions)
    if config.dispatchers then
        for i, dispatcher in ipairs(config.dispatchers) do
            if type(dispatcher) ~= "table" then
                return false, "Each dispatcher must be a table"
            end
            if not dispatcher.dispatcher_func or type(dispatcher.dispatcher_func) ~= "function" then
                return false, "Each dispatcher must have an dispatcher_func function"
            end
            if not dispatcher.formatter_func or (type(dispatcher.formatter_func) ~= "function" and not (type(dispatcher.formatter_func) == "table" and getmetatable(dispatcher.formatter_func) and getmetatable(dispatcher.formatter_func).__call)) then
                return false, "Each dispatcher must have a formatter_func function"
            end
        end
    end

    return true
end

return M
