-- Live Log Level Changes
-- This module allows changing log levels through environment variables at runtime

-- Note: For direct execution with 'lua', use require("lual.*")
-- For LuaRocks installed modules or busted tests, use require("lual.*")
local core_levels = require("lual.levels")
local schemer = require("lual.utils.schemer")
local live_level_schema_module = require("lual.config.live_level_schema")

local M = {}

-- Configuration
local _check_interval = 100 -- Check every 100 log entries by default
local _entry_counter = 0
local _env_var_name = nil
local _last_value = nil
local _enabled = false
local _get_env_func = os.getenv -- Can be overridden for testing

--- Validates the live_level configuration
-- @param config table Configuration for live_level
-- @param full_config table The full configuration table
-- @return boolean, string True if valid, or false with error message
local function validate(config, full_config)
    if type(config) ~= "table" then
        return false, "live_level must be a table"
    end

    local errors = schemer.validate(config, live_level_schema_module.live_level_schema)
    if errors then
        return false, errors.error
    end

    return true
end

--- Normalizes the live_level configuration
-- @param config table The configuration to normalize
-- @return table The normalized configuration
local function normalize(config)
    local normalized = {}

    -- Only set env_var if explicitly provided
    normalized.env_var = config.env_var
    normalized.check_interval = config.check_interval or 100

    -- Default enabled to true only if env_var is explicitly provided
    if config.enabled == nil then
        normalized.enabled = (config.env_var ~= nil)
    else
        normalized.enabled = config.enabled
    end

    return normalized
end

--- Applies the live_level configuration
-- @param config table The configuration to apply
-- @param current_config table The current configuration state
-- @return table The updated configuration state
local function apply(config, current_config)
    -- Store configuration in current_config.live_level
    current_config.live_level = {
        env_var = config.env_var,
        check_interval = config.check_interval,
        enabled = config.enabled
    }

    -- Update global state
    _env_var_name = config.env_var
    _check_interval = config.check_interval or 100

    -- Feature is only enabled if explicitly enabled and env_var is provided
    if config.enabled == nil then
        _enabled = (config.env_var ~= nil)
    else
        _enabled = config.enabled and (config.env_var ~= nil)
    end

    -- Also store the enabled state in the config
    current_config.live_level.enabled = _enabled

    _entry_counter = 0

    -- Initialize last value
    if _enabled and _env_var_name then
        _last_value = _get_env_func(_env_var_name)

        -- Apply initial value if present
        if _last_value and _last_value ~= "" then
            local level_value = M.parse_level_value(_last_value)
            if level_value then
                current_config.level = level_value
            end
        end
    end

    return current_config
end

--- Parse a level value from string representation
-- @param value string The level value as string (number, uppercase or lowercase level name)
-- @return number|nil The numeric level value, or nil if invalid
function M.parse_level_value(value)
    if not value then return nil end

    -- Try as a number first
    local num_value = tonumber(value)
    if num_value then
        return num_value
    end

    -- Try as a level name (case insensitive)
    local level_name, level_value = core_levels.get_level_by_name(value:upper())
    if level_name and level_value then
        return level_value
    end

    return nil
end

--- Checks if the environment variable has changed and updates the log level
-- @param config table The current configuration
-- @return boolean, number|nil True and new level if level changed, false otherwise
function M.check_level_change(config)
    if not _enabled or not _env_var_name then
        return false, nil
    end

    -- Only check periodically
    _entry_counter = _entry_counter + 1
    if _entry_counter % _check_interval ~= 0 then
        return false, nil
    end

    -- Check current value
    local current_value = _get_env_func(_env_var_name)

    -- No change or empty value
    if current_value == _last_value or not current_value or current_value == "" then
        return false, nil
    end

    -- Try to parse the level value
    local level_value = M.parse_level_value(current_value)
    if level_value then
        _last_value = current_value
        return true, level_value
    end

    return false, nil
end

--- Set the environment lookup function (for testing)
-- @param func function The function to use for environment variable lookup
function M.set_env_func(func)
    if type(func) == "function" then
        _get_env_func = func
    end
end

--- Reset the internal state (for testing)
function M.reset()
    _check_interval = 100
    _entry_counter = 0
    _env_var_name = nil
    _last_value = nil
    _enabled = false
    _get_env_func = os.getenv
end

-- Export configuration functions
M.validate = validate
M.normalize = normalize
M.apply = apply

return M
