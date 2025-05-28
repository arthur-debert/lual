--- Configuration constants and type definitions
-- This module contains all the constant values used throughout the config system

local M = {}

-- Valid output types
M.VALID_OUTPUT_TYPES = {
    _meta = { name = "output type", case_sensitive = false },
    console = true,
    file = true
}

-- Valid formatter types
M.VALID_FORMATTER_TYPES = {
    _meta = { name = "formatter type", case_sensitive = false },
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
    output = true,
    formatter = true,
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
    outputs = true,
    propagate = true,
    timezone = true
}

return M
