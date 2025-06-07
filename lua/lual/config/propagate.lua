--- Propagate Configuration Handler
-- This module handles the 'propagate' configuration key

local M = {}

--- Validates propagate configuration
-- @param propagate boolean The propagate value to validate
-- @param full_config table The full configuration context
-- @return boolean, string True if valid, otherwise false and error message
function M.validate(propagate, full_config)
    if type(propagate) ~= "boolean" then
        return false,
            "Invalid type for 'propagate': expected boolean, got " ..
            type(propagate) .. ". Whether to propagate messages (always true for root)"
    end
    return true
end

--- Applies propagate configuration
-- @param propagate boolean The propagate value to apply
-- @param current_config table The current full configuration
-- @return boolean The propagate value to store in configuration
function M.apply(propagate, current_config)
    return propagate
end

return M
