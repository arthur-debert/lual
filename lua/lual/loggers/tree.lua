--- Logger Hierarchy Management
-- This module handles the hierarchical structure of loggers

-- Module dependencies
local core_levels = require("lua.lual.levels")
local caller_info = require("lual.utils.caller_info")

-- Logger cache - shared with other modules via the exported API
local _logger_cache = {}

--- Extracts the parent logger name from a hierarchical logger name
-- @param logger_name string The logger name to process
-- @return string|nil The parent logger name, or nil if this is the root
local function get_parent_name_from_hierarchical(logger_name)
    if logger_name == "_root" then return nil end
    local match = logger_name:match("(.+)%.[^%.]+$")
    return match or "_root" -- Always return "_root" for top-level loggers
end

-- Export the module
local M = {
    -- Functions
    get_parent_name_from_hierarchical = get_parent_name_from_hierarchical,

    -- Cache access
    get_from_cache = function(name)
        return _logger_cache[name]
    end,

    add_to_cache = function(name, logger)
        _logger_cache[name] = logger
        return logger
    end,

    -- Cache management
    reset_cache = function()
        _logger_cache = {}
    end
}

return M
