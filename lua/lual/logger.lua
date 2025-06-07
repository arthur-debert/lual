local unpack = unpack or table.unpack

--[[
High-Level API Draft for a Lua Logging Library

This outlines the main functions and their intended signatures.
]]

-- Import the refactored modules
-- Note: For direct execution with 'lua', use require("lual.api")
-- For LuaRocks installed modules or busted tests, use require("lual.api")
local api = require("lual.api")

-- Return the main API directly
return api
