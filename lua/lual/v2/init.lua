--- V2 API Module
-- This module provides the new v2 API for lual logging

local config_module = require("lual.v2.config")
local logger_module = require("lual.v2.logger")
local dispatch_module = require("lual.v2.dispatch")

local M = {}

-- Expose the v2 configuration API
M.config = config_module.config
M.get_config = config_module.get_config
M.reset_config = config_module.reset_config

-- Expose the v2 logger creation functions (for testing)
M.create_logger = logger_module.create_logger
M.create_root_logger = logger_module.create_root_logger

-- Expose the main logger API (Step 2.6)
M.logger = logger_module.logger
M.reset_cache = logger_module.reset_cache

-- Expose the dispatch API (Step 2.7)
M.dispatch_log_event = dispatch_module.dispatch_log_event

return M
