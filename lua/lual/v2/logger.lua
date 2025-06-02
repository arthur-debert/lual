--- V2 Logger Module
-- This module provides the new logger implementation with effective level calculation

local core_levels = require("lua.lual.v2.levels")
local v2_config = require("lual.v2.config")
local v2_dispatch = require("lual.v2.dispatch")

local M = {}

-- Logger cache for v2 system
local _logger_cache = {}

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

--- Imperative API: Set the level for this logger
-- @param level number The new level
function M.logger_prototype:set_level(level)
    if type(level) ~= "number" then
        error("Level must be a number, got " .. type(level))
    end

    -- Validate that level is a known level value
    local valid_level = false
    for _, level_value in pairs(core_levels.definition) do
        if level == level_value then
            valid_level = true
            break
        end
    end
    if not valid_level then
        error("Invalid level value: " .. level)
    end

    self.level = level
end

--- Imperative API: Add a dispatcher to this logger
-- @param dispatcher_func function The dispatcher function
-- @param config table|nil Optional dispatcher configuration
function M.logger_prototype:add_dispatcher(dispatcher_func, config)
    if type(dispatcher_func) ~= "function" then
        error("Dispatcher must be a function, got " .. type(dispatcher_func))
    end

    table.insert(self.dispatchers, {
        dispatcher_func = dispatcher_func,
        config = config or {}
    })
end

--- Imperative API: Set propagate flag for this logger
-- @param propagate boolean Whether to propagate
function M.logger_prototype:set_propagate(propagate)
    if type(propagate) ~= "boolean" then
        error("Propagate must be a boolean, got " .. type(propagate))
    end

    self.propagate = propagate
end

--- Get configuration of this logger
-- @return table The logger configuration
function M.logger_prototype:get_config()
    return {
        name = self.name,
        level = self.level,
        dispatchers = self.dispatchers,
        propagate = self.propagate,
        parent_name = self.parent and self.parent.name or nil
    }
end

-- Add logging methods from the v2 dispatch system (Step 2.7)
local logging_methods = v2_dispatch.create_logging_methods()
for method_name, method_func in pairs(logging_methods) do
    M.logger_prototype[method_name] = method_func
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

    -- Convert root config dispatchers to proper format
    root_logger.dispatchers = {}
    for _, dispatcher_func in ipairs(root_config.dispatchers) do
        table.insert(root_logger.dispatchers, {
            dispatcher_func = dispatcher_func,
            config = {}
        })
    end

    root_logger.propagate = root_config.propagate
    return root_logger
end

--- Configuration validation for non-root loggers
local VALID_LOGGER_CONFIG_KEYS = {
    level = { type = "number", description = "Logging level (use lual.DEBUG, lual.INFO, etc.)" },
    dispatchers = { type = "table", description = "Array of dispatcher functions" },
    propagate = { type = "boolean", description = "Whether to propagate messages to parent loggers" }
}

--- Validates a logger configuration table
-- @param config_table table The configuration to validate
-- @return boolean, string True if valid, or false with error message
local function validate_logger_config(config_table)
    if type(config_table) ~= "table" then
        return false, "Configuration must be a table, got " .. type(config_table)
    end

    -- Check for unknown keys
    for key, value in pairs(config_table) do
        if not VALID_LOGGER_CONFIG_KEYS[key] then
            local valid_keys = {}
            for valid_key, _ in pairs(VALID_LOGGER_CONFIG_KEYS) do
                table.insert(valid_keys, valid_key)
            end
            table.sort(valid_keys)
            return false, string.format(
                "Unknown configuration key '%s'. Valid keys are: %s",
                tostring(key),
                table.concat(valid_keys, ", ")
            )
        end

        -- Type validation
        local expected_spec = VALID_LOGGER_CONFIG_KEYS[key]
        local expected_type = expected_spec.type
        local actual_type = type(value)

        if actual_type ~= expected_type then
            return false, string.format(
                "Invalid type for '%s': expected %s, got %s. %s",
                key,
                expected_type,
                actual_type,
                expected_spec.description
            )
        end

        -- Additional validation for specific keys
        if key == "level" then
            -- Validate that level is a known level value
            local valid_level = false
            for _, level_value in pairs(core_levels.definition) do
                if value == level_value then
                    valid_level = true
                    break
                end
            end
            if not valid_level then
                local valid_levels = {}
                for level_name, level_value in pairs(core_levels.definition) do
                    table.insert(valid_levels, string.format("%s(%d)", level_name, level_value))
                end
                table.sort(valid_levels)
                return false, string.format(
                    "Invalid level value %d. Valid levels are: %s",
                    value,
                    table.concat(valid_levels, ", ")
                )
            end
        elseif key == "dispatchers" then
            -- Validate that dispatchers is an array of functions
            if not (#value >= 0) then -- Basic array check
                return false, "dispatchers must be an array (table with numeric indices)"
            end
            for i, dispatcher in ipairs(value) do
                if type(dispatcher) ~= "function" then
                    return false, string.format(
                        "dispatchers[%d] must be a function, got %s",
                        i,
                        type(dispatcher)
                    )
                end
            end
        end
    end

    return true
end

--- Determines the parent logger name based on hierarchical naming
-- @param logger_name string The logger name
-- @return string|nil The parent logger name or nil if this is a top-level logger
local function get_parent_name(logger_name)
    if logger_name == "_root" then
        return nil -- Root logger has no parent
    end

    -- Find the last dot to determine parent
    local parent_name = logger_name:match("(.+)%.[^%.]+$")

    -- If no dot found, parent is _root
    if not parent_name then
        return "_root"
    end

    return parent_name
end

--- Gets or creates a parent logger
-- @param parent_name string The parent logger name
-- @return table|nil The parent logger or nil
local function get_or_create_parent(parent_name)
    if not parent_name then
        return nil
    end

    -- Special case: if parent is _root, create it from v2 config
    if parent_name == "_root" then
        if _logger_cache["_root"] then
            return _logger_cache["_root"]
        else
            -- Create _root logger from v2 config
            local root_logger = M.create_root_logger()
            _logger_cache["_root"] = root_logger
            return root_logger
        end
    end

    -- If parent is already in cache, return it
    if _logger_cache[parent_name] then
        return _logger_cache[parent_name]
    end

    -- Create parent with default configuration
    return M.logger(parent_name)
end

--- Main logger creation API (Step 2.6)
-- Creates a logger from a config table. Can be called with:
-- 1. String name only: lual.v2.logger("name") - creates logger with defaults
-- 2. String name + config: lual.v2.logger("name", {level=lual.debug, ...})
-- @param name string The logger name
-- @param config_table table|nil Optional configuration table
-- @return table The logger instance
function M.logger(name, config_table)
    -- Validate name
    if type(name) ~= "string" or name == "" then
        error("Logger name must be a non-empty string, got " .. type(name))
    end

    -- Validate that user loggers cannot start with underscore (reserved for internal use)
    if name ~= "_root" and string.sub(name, 1, 1) == "_" then
        error("Logger names starting with '_' are reserved for internal use. Please use a different name.")
    end

    -- Use default config if none provided
    config_table = config_table or {}



    -- Validate configuration
    local valid, error_msg = validate_logger_config(config_table)
    if not valid then
        error("Invalid logger configuration: " .. error_msg)
    end

    -- Check if logger already exists in cache
    if _logger_cache[name] then
        return _logger_cache[name]
    end

    -- Default initial state for non-root loggers (Step 2.6 requirement)
    local defaults = {
        level = name == "_root" and core_levels.definition.WARNING or core_levels.definition.NOTSET,
        dispatchers = {},
        propagate = true
    }

    -- Apply only explicitly provided settings (Step 2.6 requirement)
    local logger_config = {}
    for key, default_value in pairs(defaults) do
        if config_table[key] ~= nil then
            -- Use explicitly provided value
            logger_config[key] = config_table[key]
        else
            -- Use default value
            logger_config[key] = default_value
        end
    end

    -- Determine parent based on hierarchical naming
    local parent_name = get_parent_name(name)
    local parent_logger = nil

    if parent_name then
        parent_logger = get_or_create_parent(parent_name)
    end

    -- Create logger
    local new_logger = M.create_logger(name, logger_config.level, parent_logger)

    -- Set dispatcher functions (convert simple functions to dispatcher objects)
    new_logger.dispatchers = {}
    for _, dispatcher_func in ipairs(logger_config.dispatchers) do
        table.insert(new_logger.dispatchers, {
            dispatcher_func = dispatcher_func,
            config = {}
        })
    end

    new_logger.propagate = logger_config.propagate

    -- Cache the logger
    _logger_cache[name] = new_logger

    return new_logger
end

--- Resets the logger cache (for testing)
function M.reset_cache()
    _logger_cache = {}
end

return M
