--- Logger factory and creation logic
-- This module handles the creation and instantiation of logger objects

local core_levels = require("lual.core.levels")
local caller_info = require("lual.core.caller_info")
local config_module = require("lual.config")
local prototype = require("lual.core.logging.prototype")

local M = {}

--- Creates a logger from a canonical config table and name
-- @param name string The logger name
-- @param config (table) The canonical config
-- @return table The logger instance
function M.create_logger_from_config(name, config)
    -- Validate that user loggers cannot start with underscore (reserved for internal use)
    if name and name ~= "_root" and string.sub(name, 1, 1) == "_" then
        error("Logger names starting with '_' are reserved for internal use. Please use a different name.")
    end

    local valid, err = config_module.validate_canonical_config(config)
    if not valid then
        error("Invalid logger config: " .. err)
    end

    local canonical_config = config_module.create_canonical_config(config)

    -- Create new logger object based on prototype
    local new_logger = {}
    for k, v in pairs(prototype.logger_prototype) do
        new_logger[k] = v
    end

    new_logger.name = name
    new_logger.level = canonical_config.level
    new_logger.dispatchers = canonical_config.dispatchers
    new_logger.propagate = canonical_config.propagate
    new_logger.parent = canonical_config.parent

    return new_logger
end

--- Creates a simple logger with minimal configuration
-- @param name string The logger name
-- @param parent_logger table|nil The parent logger (if any)
-- @return table The logger instance
function M.create_simple_logger(name, parent_logger)
    local logger_name = name
    if name == nil or name == "" then
        -- Auto-generate logger name from caller's filename
        local filename, _, _ = caller_info.get_caller_info(nil, true) -- Use dot notation conversion
        if filename then
            logger_name = filename
        else
            logger_name = "_root"
        end
    end

    -- Validate that user loggers cannot start with underscore (reserved for internal use)
    if logger_name and logger_name ~= "_root" and string.sub(logger_name, 1, 1) == "_" then
        error("Logger names starting with '_' are reserved for internal use. Please use a different name.")
    end

    -- Create logger using config-based approach
    local config = {
        level = logger_name == "_root" and core_levels.definition.INFO or core_levels.definition.NOTSET,
        dispatchers = {},
        propagate = true,
        parent = parent_logger
    }

    return M.create_logger_from_config(logger_name, config)
end

--- Creates a logger from configuration (kept for backward compatibility)
-- @param name string The logger name
-- @param input_config table The config
-- @param default_config table Default configuration to merge with
-- @param get_logger_func function Function to get parent loggers (deprecated, parent should be in config)
-- @return table The logger instance
function M.create_logger(name, input_config, default_config, get_logger_func)
    -- Use the config module to process the input config
    local canonical_config = config_module.process_config(input_config, default_config)

    return M.create_logger_from_config(name, canonical_config)
end

return M
