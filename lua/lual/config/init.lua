--- Configuration API (Main Entry Point)
-- This module provides the main configuration API for the lual logging library

local api = require("lual.config.api")

local M = {}

--- Updates the _root logger configuration with the provided settings
-- @param config_table table Configuration updates to apply
-- @return table The updated _root logger configuration
function M.config(config_table)
    return api.config(config_table)
end

--- Gets the current _root logger configuration
-- @return table A copy of the current _root logger configuration
function M.get_config()
    return api.get_config()
end

--- Resets the _root logger configuration to defaults
function M.reset_config()
    return api.reset_config()
end

--- Reset registry (for testing)
function M.reset_registry()
    return api.reset_registry()
end

return M
