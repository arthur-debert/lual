--- Logger factory and creation logic
-- This module handles the creation and instantiation of logger objects

local core_levels = require("lual.core.levels")
local caller_info = require("lual.core.caller_info")
local config_module = require("lual.config")
local prototype = require("lual.core.logging.prototype")

local M = {}

--- Creates a logger from a canonical config table
-- @param config (table) The canonical config
-- @return table The logger instance
function M.create_logger_from_config(config)
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

    new_logger.name = canonical_config.name
    new_logger.level = canonical_config.level
    new_logger.dispatchers = canonical_config.dispatchers
    new_logger.propagate = canonical_config.propagate
    new_logger.parent = canonical_config.parent
    new_logger.timezone = canonical_config.timezone

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
        local filename, _ = caller_info.get_caller_info(nil, true) -- Use dot notation conversion
        if filename then
            logger_name = filename
        else
            logger_name = "root"
        end
    end

    -- Create logger using config-based approach
    local config = {
        name = logger_name,
        level = core_levels.definition.INFO,
        dispatchers = {},
        propagate = true,
        parent = parent_logger,
        timezone = "local", -- Default to local time
    }

    return M.create_logger_from_config(config)
end

--- Creates a logger from configuration (kept for backward compatibility)
-- @param input_config table The config
-- @param default_config table Default configuration to merge with
-- @param get_logger_func function Function to get parent loggers (deprecated, parent should be in config)
-- @return table The logger instance
function M.create_logger(input_config, default_config, get_logger_func)
    -- Use the config module to process the input config
    local canonical_config = config_module.process_config(input_config, default_config)

    return M.create_logger_from_config(canonical_config)
end

return M
