--- Logger management and lifecycle operations
-- This module handles logger configuration changes and updates

local config_module = require("lual.config")

local M = {}

--- Updates a logger's level
-- @param logger table The logger instance to update
-- @param level string|number The new level
-- @param create_logger_func function Function to create new logger instances
-- @param update_cache_func function Function to update the logger cache
function M.set_level(logger, level, create_logger_func, update_cache_func)
    -- Get current config, modify it, and recreate logger
    local current_config = M.get_config(logger)
    current_config.level = level
    local new_logger = create_logger_func(current_config)

    -- Update the cache with the new logger
    update_cache_func(logger.name, new_logger)

    -- Copy new logger properties to self (for existing references)
    for k, v in pairs(new_logger) do
        if k ~= "name" then -- Don't change the name
            logger[k] = v
        end
    end
end

--- Adds an dispatcher to a logger
-- @param logger table The logger instance to update
-- @param dispatcher_func function The dispatcher function
-- @param formatter_func function The formatter function
-- @param dispatcher_config table The dispatcher configuration
-- @param create_logger_func function Function to create new logger instances
-- @param update_cache_func function Function to update the logger cache
function M.add_dispatcher(logger, dispatcher_func, formatter_func, dispatcher_config, create_logger_func,
                          update_cache_func)
    -- Get current config, modify it, and recreate logger
    local current_config = M.get_config(logger)
    table.insert(current_config.dispatchers, {
        dispatcher_func = dispatcher_func,
        formatter_func = formatter_func,
        dispatcher_config = dispatcher_config or {},
    })
    local new_logger = create_logger_func(current_config)

    -- Update the cache with the new logger
    update_cache_func(logger.name, new_logger)

    -- Copy new logger properties to self (for existing references)
    for k, v in pairs(new_logger) do
        if k ~= "name" then -- Don't change the name
            logger[k] = v
        end
    end
end

--- Sets the propagation setting for a logger
-- @param logger table The logger instance to update
-- @param propagate boolean The new propagation setting
-- @param create_logger_func function Function to create new logger instances
-- @param update_cache_func function Function to update the logger cache
function M.set_propagate(logger, propagate, create_logger_func, update_cache_func)
    -- Get current config, modify it, and recreate logger
    local current_config = M.get_config(logger)
    current_config.propagate = propagate
    local new_logger = create_logger_func(current_config)

    -- Update the cache with the new logger
    update_cache_func(logger.name, new_logger)

    -- Copy new logger properties to self (for existing references)
    for k, v in pairs(new_logger) do
        if k ~= "name" then -- Don't change the name
            logger[k] = v
        end
    end
end

--- Gets the current configuration of a logger
-- @param logger table The logger instance
-- @return table The current configuration as a canonical config table
function M.get_config(logger)
    return config_module.create_canonical_config({
        name = logger.name,
        level = logger.level,
        dispatchers = logger.dispatchers or {},
        propagate = logger.propagate,
        parent = logger.parent,
        timezone = logger.timezone,
    })
end

--- Adds management methods to a logger prototype
-- @param logger_prototype table The logger prototype to extend
-- @param create_logger_func function Function to create new logger instances
-- @param update_cache_func function Function to update the logger cache
function M.add_management_methods(logger_prototype, create_logger_func, update_cache_func)
    function logger_prototype:set_level(level)
        M.set_level(self, level, create_logger_func, update_cache_func)
    end

    function logger_prototype:add_dispatcher(dispatcher_func, formatter_func, dispatcher_config)
        M.add_dispatcher(self, dispatcher_func, formatter_func, dispatcher_config, create_logger_func, update_cache_func)
    end

    function logger_prototype:set_propagate(propagate)
        M.set_propagate(self, propagate, create_logger_func, update_cache_func)
    end

    function logger_prototype:get_config()
        return M.get_config(self)
    end
end

return M
