--- Configuration schema definitions and field specifications
-- This module centralizes all the schema-related logic for configs

local constants = require("lual.config.constants")
local core_levels = require("lual.core.levels")

local M = {}

-- =============================================================================
-- SCHEMA DEFINITIONS
-- =============================================================================

--- Valid keys for the full config format
M.VALID_CONFIG_KEYS = {
    name = true,
    level = true,
    dispatchers = true,
    propagate = true
}

--- Valid keys for convenience config format
M.VALID_CONVENIENCE_KEYS = {
    name = true,
    level = true,
    dispatcher = true,
    presenter = true,
    propagate = true,
    timezone = true,
    path = true,
    stream = true
}

--- Level string to number mapping
M.LEVEL_MAP = {
    debug = core_levels.definition.DEBUG,
    info = core_levels.definition.INFO,
    warning = core_levels.definition.WARNING,
    error = core_levels.definition.ERROR,
    critical = core_levels.definition.CRITICAL,
    none = core_levels.definition.NONE
}

--- Default config values
M.DEFAULTS = {
    name = "root",
    level = core_levels.definition.INFO,
    dispatchers = {},
    propagate = true
}

-- =============================================================================
-- FIELD VALIDATORS
-- =============================================================================

--- Field validation specifications
M.FIELD_VALIDATORS = {
    name = {
        optional = true,
        type = "string",
        validate = function(value)
            return type(value) == "string"
        end,
        error_msg = "Config.name must be a string"
    },

    propagate = {
        optional = true,
        type = "boolean",
        validate = function(value)
            return type(value) == "boolean"
        end,
        error_msg = "Config.propagate must be a boolean"
    },

    level = {
        optional = true,
        validate = function(value)
            if type(value) == "string" then
                return constants.validate_against_constants(value, constants.VALID_LEVEL_STRINGS, true, "string")
            elseif type(value) == "number" then
                return true
            else
                return false, "Level must be a string or number"
            end
        end
    },

    timezone = {
        optional = true,
        validate = function(value)
            return constants.validate_against_constants(value, constants.VALID_TIMEZONES, true, "string")
        end
    },

    dispatcher = {
        optional = false, -- Required in convenience syntax
        validate = function(value)
            return constants.validate_against_constants(value, constants.VALID_dispatcher_TYPES, false, "string")
        end
    },

    presenter = {
        optional = false, -- Required in convenience syntax
        validate = function(value)
            return constants.validate_against_constants(value, constants.VALID_PRESENTER_TYPES, false, "string")
        end
    }
}

-- =============================================================================
-- HELPER FUNCTIONS
-- =============================================================================

--- Detects if a config uses convenience syntax
-- @param config table The config to check
-- @return boolean True if convenience syntax is detected
function M.is_convenience_syntax(config)
    return config.dispatcher ~= nil or config.presenter ~= nil
end

--- Gets the appropriate valid keys set for a config format
-- @param is_convenience boolean Whether this is convenience syntax
-- @return table Set of valid keys
function M.get_valid_keys(is_convenience)
    return is_convenience and M.VALID_CONVENIENCE_KEYS or M.VALID_CONFIG_KEYS
end

--- Converts string level to numeric level
-- @param level string|number The level to convert
-- @return number The numeric level
function M.convert_level(level)
    if type(level) == "string" then
        return M.LEVEL_MAP[string.lower(level)]
    end
    return level
end

return M
