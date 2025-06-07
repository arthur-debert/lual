--- Configuration Registry
-- This module manages registration and delegation of config keys to subsystems

local M = {}

-- Registry storage
local _handlers = {}
local _schemas = {}

--- Register a config subsystem
-- @param key string The config key this subsystem handles
-- @param handler table Handler with validate, normalize, and apply functions
function M.register(key, handler)
    if type(key) ~= "string" then
        error("Registry key must be a string, got " .. type(key))
    end

    if type(handler) ~= "table" then
        error("Registry handler must be a table, got " .. type(handler))
    end

    -- Validate handler has required functions
    if not handler.validate or type(handler.validate) ~= "function" then
        error("Handler for '" .. key .. "' must have a validate function")
    end

    if not handler.apply or type(handler.apply) ~= "function" then
        error("Handler for '" .. key .. "' must have an apply function")
    end

    -- normalize is optional
    if handler.normalize and type(handler.normalize) ~= "function" then
        error("Handler for '" .. key .. "' normalize must be a function if provided")
    end

    _handlers[key] = handler

    -- Store schema if provided
    if handler.schema then
        _schemas[key] = handler.schema
    end
end

--- Get all registered keys
-- @return table Array of registered config keys
function M.get_registered_keys()
    local keys = {}
    for key, _ in pairs(_handlers) do
        table.insert(keys, key)
    end
    table.sort(keys)
    return keys
end

--- Check if a key is registered
-- @param key string The config key to check
-- @return boolean True if key is registered
function M.is_registered(key)
    return _handlers[key] ~= nil
end

--- Get handler for a key
-- @param key string The config key
-- @return table|nil The handler or nil if not registered
function M.get_handler(key)
    return _handlers[key]
end

--- Validate config using registered handlers
-- @param config table The configuration to validate
-- @return boolean, string True if valid, otherwise false and error message
function M.validate(config)
    for key, value in pairs(config) do
        local handler = _handlers[key]
        if handler then
            local valid, error_msg = handler.validate(value, config)
            if not valid then
                return false, error_msg
            end
        end
    end
    return true
end

--- Normalize config using registered handlers
-- @param config table The configuration to normalize
-- @return table The normalized configuration
function M.normalize(config)
    local normalized = {}

    for key, value in pairs(config) do
        local handler = _handlers[key]
        if handler and handler.normalize then
            normalized[key] = handler.normalize(value, config)
        else
            normalized[key] = value
        end
    end

    return normalized
end

--- Apply config using registered handlers
-- @param config table The configuration to apply
-- @param current_config table The current configuration state
-- @return table The updated configuration state
function M.apply(config, current_config)
    local updated_config = {}

    -- Start with current config
    for key, value in pairs(current_config) do
        updated_config[key] = value
    end

    -- Apply changes from registered handlers
    for key, value in pairs(config) do
        local handler = _handlers[key]
        if handler then
            local applied_value = handler.apply(value, updated_config)
            if applied_value ~= nil then
                updated_config[key] = applied_value
            end
        else
            -- For unregistered keys, just copy the value
            updated_config[key] = value
        end
    end

    return updated_config
end

--- Reset registry (for testing)
function M.reset()
    _handlers = {}
    _schemas = {}
end

return M
