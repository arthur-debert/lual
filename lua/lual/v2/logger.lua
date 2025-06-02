--- V2 Logger Module
-- This module provides the new logger implementation with effective level calculation

local core_levels = require("lual.core.levels")
local v2_config = require("lual.v2.config")

local M = {}

-- Logger prototype for v2
M.logger_prototype = {}

--- Gets the effective level for this logger, resolving NOTSET by inheritance
-- This implements the logic from step 2.5:
-- - If self.level is not lual.NOTSET, return self.level
-- - Else, if self is _root, return _root.level (it must have an explicit level)
-- - Else, recursively call self.parent:_get_effective_level()
function M.logger_prototype:_get_effective_level()
    -- Special case: if this is the _root logger, always use the current v2 config level
    -- This ensures _root always reflects the current configuration
    if self.name == "_root" then
        local root_config = v2_config.get_config()
        return root_config.level
    end

    -- If this logger has an explicit level (not NOTSET), use it
    if self.level ~= core_levels.definition.NOTSET then
        return self.level
    end

    -- Recursively call parent's _get_effective_level()
    if self.parent then
        return self.parent:_get_effective_level()
    end

    -- Fallback - this shouldn't normally happen in a well-formed hierarchy
    -- But return INFO as a safe default
    return core_levels.definition.INFO
end

--- Creates a new v2 logger instance
-- @param name string The logger name
-- @param level number The logger level (defaults to NOTSET for non-root)
-- @param parent table|nil The parent logger (if any)
-- @return table The logger instance
function M.create_logger(name, level, parent)
    local logger = {}

    -- Copy prototype methods
    for k, v in pairs(M.logger_prototype) do
        logger[k] = v
    end

    -- Set logger properties
    logger.name = name or "unnamed"
    logger.level = level or (name == "_root" and core_levels.definition.WARNING or core_levels.definition.NOTSET)
    logger.parent = parent
    logger.dispatchers = {}
    logger.propagate = true

    return logger
end

--- Creates the _root logger using v2 config
-- @return table The _root logger instance
function M.create_root_logger()
    local root_config = v2_config.get_config()
    local root_logger = M.create_logger("_root", root_config.level, nil)
    root_logger.dispatchers = root_config.dispatchers
    root_logger.propagate = root_config.propagate
    return root_logger
end

return M
