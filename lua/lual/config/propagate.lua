--- Propagate Configuration Handler
-- This module handles the 'propagate' configuration key

local schemer = require("lual.utils.schemer")
local propagate_schema_module = require("lual.config.propagate_schema")

local M = {}

--- Validates propagate configuration
-- @param propagate boolean The propagate value to validate
-- @param full_config table The full configuration context
-- @return boolean, string True if valid, otherwise false and error message
function M.validate(propagate, full_config)
    -- Use schemer for validation
    local errors = schemer.validate({ propagate = propagate }, propagate_schema_module.propagate_schema)
    if errors then
        if errors.fields and errors.fields.propagate then
            local error_code = errors.fields.propagate[1][1]
            if error_code == "INVALID_TYPE" then
                return false,
                    "Invalid type for 'propagate': expected boolean, got " ..
                    type(propagate) .. ". Whether to propagate messages (always true for root)"
            end
        end
        return false, errors.error
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
