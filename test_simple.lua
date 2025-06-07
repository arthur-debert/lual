#!/usr/bin/env lua
package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua"
local pipelines_config = require("lual.pipelines.config")

-- Test invalid configuration
local valid, err = pipelines_config.validate({ {
    outputs = { "not a function" },
    presenter = function() end
} }, {})
print("Valid:", valid)
print("Error:", err)

-- Test valid configuration
local valid2, err2 = pipelines_config.validate({ {
    level = 30,
    outputs = { function() end },
    presenter = function() end
} }, {})
print("\nValid:", valid2)
print("Error:", err2 or "nil")
