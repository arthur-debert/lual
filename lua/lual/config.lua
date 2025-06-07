--- Configuration API (Backwards Compatibility Wrapper)
-- This module provides backwards compatibility by delegating to the modular config system

local modular_config = require("lual.config.init")

local M = {}

-- All the complex logic is now in the modular config system
-- This is just a delegation wrapper

--- Delegates to the modular config system
-- @param config_table table Configuration updates to apply
-- @return table The updated _root logger configuration
function M.config(config_table)
    return modular_config.config(config_table)
end

--- Delegates to the modular config system
-- @return table A copy of the current _root logger configuration
function M.get_config()
    return modular_config.get_config()
end

--- Delegates to the modular config system
function M.reset_config()
    return modular_config.reset_config()
end

return M
