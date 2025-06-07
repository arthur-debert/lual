-- Lual Logging Library - Main Entry Point
-- This init.lua file makes the module properly importable with require("lual")

-- Import the logger module which serves as the main API
-- Using require("lual.logger") directly would cause a circular dependency
-- So we use the appropriate require pattern based on how the module is being used
local logger

-- Try using the LuaRocks-installed path first (preferred for tests and real usage)
local success = pcall(function() logger = require("lual.logger") end)

-- If that fails, try the local development path
if not success then
    logger = require("lua.lual.logger")
end

-- Return the logger API
return logger
