-- Internal Debug System for lual
-- This module provides internal debugging functionality for the lual library itself
-- It's designed to be completely independent to avoid circular dependencies

local M = {}

-- Internal debug state
local _INTERNAL_DEBUG_ENABLED = false

-- Check environment variable on module load
local function _init_internal_debug()
    local env_value = os.getenv("LUAL_INTERNAL_DEBUG")
    if env_value then
        local lower_val = string.lower(env_value)
        _INTERNAL_DEBUG_ENABLED = (lower_val == "true" or lower_val == "1" or lower_val == "yes")
    end
end

-- Initialize debug state immediately
_init_internal_debug()

-- Internal debug flag (read-only access)
M._INTERNAL_DEBUG = _INTERNAL_DEBUG_ENABLED

-- Internal debug print function
-- This function bypasses the main logging system entirely to avoid circular dependencies
-- @param message string The message to print (supports string.format style formatting)
-- @param ... any Additional arguments for string formatting
function M._debug_print(message, ...)
    if not _INTERNAL_DEBUG_ENABLED then
        return
    end

    -- Handle string formatting if additional arguments provided
    local formatted_message
    if select('#', ...) > 0 then
        formatted_message = string.format(message, ...)
    else
        formatted_message = tostring(message)
    end

    -- Print directly to stderr with prefix to distinguish from regular output
    io.stderr:write("[LUAL_DEBUG] " .. formatted_message .. "\n")
    -- Flush if available (not all Lua environments support it)
    if io.stderr.flush then
        io.stderr:flush()
    end
end

-- Function to enable/disable internal debug at runtime (for testing)
-- @param enabled boolean Whether to enable internal debug
function M._set_internal_debug(enabled)
    _INTERNAL_DEBUG_ENABLED = enabled
    M._INTERNAL_DEBUG = _INTERNAL_DEBUG_ENABLED
end

return M
