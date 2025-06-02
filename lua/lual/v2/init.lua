--- V2 API Module
-- This module provides the new v2 API for lual logging

local config_module = require("lual.v2.config")

local M = {}

-- Expose the v2 configuration API
M.config = config_module.config
M.get_config = config_module.get_config
M.reset_config = config_module.reset_config

-- Placeholder for logger API (to be implemented in future steps)
function M.logger(...)
    error("lual.v2.logger() not yet implemented - coming in future steps")
end

return M
