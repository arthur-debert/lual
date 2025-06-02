--- V2 API Module
-- This module provides the new v2 API for lual logging

local config_module = require("lual.v2.config")
local logger_module = require("lual.v2.logger")

local M = {}

-- Expose the v2 configuration API
M.config = config_module.config
M.get_config = config_module.get_config
M.reset_config = config_module.reset_config

-- Expose the v2 logger creation functions (for testing step 2.5)
M.create_logger = logger_module.create_logger
M.create_root_logger = logger_module.create_root_logger

-- Placeholder for full logger API (to be implemented in future steps)
function M.logger(...)
    error("lual.v2.logger() not yet implemented - coming in future steps")
end

return M
