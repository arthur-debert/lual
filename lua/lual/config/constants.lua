--- Configuration constants and type definitions
-- This module contains all the constant values used throughout the config system

local M = {}

-- Valid dispatcher types
M.VALID_dispatcher_TYPES = {
    _meta = { name = "dispatcher type", case_sensitive = false },
    console = true,
    file = true
}

-- Valid presenter types
M.VALID_PRESENTER_TYPES = {
    _meta = { name = "Formatter type", case_sensitive = false },
    text = true,
    color = true,
    json = true
}

-- Valid timezone values
M.VALID_TIMEZONES = {
    _meta = { name = "timezone", case_sensitive = false },
    ["local"] = true,
    utc = true
}

-- Valid level strings (case-insensitive)
M.VALID_LEVEL_STRINGS = {
    _meta = { name = "level", case_sensitive = false },
    debug = true,
    info = true,
    warning = true,
    error = true,
    critical = true,
    none = true
}

-- Valid keys for shortcut config format
M.VALID_SHORTCUT_KEYS = {
    name = true,
    level = true,
    dispatcher = true,
    presenter = true,
    propagate = true,
    timezone = true,
    -- File-specific fields
    path = true,
    -- Console-specific fields
    stream = true
}

-- Valid keys for declarative config format
M.VALID_DECLARATIVE_KEYS = {
    name = true,
    level = true,
    dispatchers = true,
    propagate = true,
    timezone = true
}

--- Helper function to generate expected error message for testing
-- @param value The invalid value
-- @param constant_table The constant table with _meta property
-- @return string The expected error message
function M.generate_expected_error_message(value, constant_table)
    local meta = constant_table._meta
    if not meta then
        error("Constant table missing _meta property")
    end

    local field_name = meta.name

    -- Generate valid values list
    local valid_values = {}
    for key, _ in pairs(constant_table) do
        if key ~= "_meta" then -- Skip the meta property
            table.insert(valid_values, key)
        end
    end
    table.sort(valid_values) -- Sort for consistent dispatcher

    return string.format("Invalid %s: %s. Valid values are: %s",
        field_name,
        tostring(value),
        table.concat(valid_values, ", "))
end

--- Generic validator for values against constant tables with metadata
-- @param value The value to validate
-- @param constant_table The constant table with _meta property
-- @param allow_nil boolean Whether nil values are allowed (default: true)
-- @param expected_type string Optional type to validate (e.g., "string", "number")
-- @return boolean, string True if valid, or false with error message
function M.validate_against_constants(value, constant_table, allow_nil, expected_type)
    if allow_nil == nil then allow_nil = true end

    if value == nil then
        return allow_nil, allow_nil and nil or ("Value cannot be nil")
    end

    -- Type validation if specified
    if expected_type and type(value) ~= expected_type then
        local meta = constant_table._meta
        local field_name = meta and meta.name or "value"
        return false, string.format("%s must be a %s", field_name, expected_type)
    end

    local meta = constant_table._meta
    if not meta then
        error("Constant table missing _meta property")
    end

    local case_sensitive = meta.case_sensitive

    -- Convert value for comparison if case-insensitive
    local lookup_value = value
    if not case_sensitive and type(value) == "string" then
        lookup_value = string.lower(value)
    end

    -- Check if value exists in constant table
    if constant_table[lookup_value] then
        return true
    end

    -- Use the helper function to generate the error message
    local error_msg = M.generate_expected_error_message(value, constant_table)
    return false, error_msg
end

return M
