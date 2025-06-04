#!/usr/bin/env lua
package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua;../lua/?.lua;../lua/?/init.lua"

local component_utils = require("lual.utils.component")

-- Test a simple function
local function test_func(record)
    print("Test function called with:", record)
end

print("\nTesting function normalization:")
local result1 = component_utils.normalize_component(test_func)
print("Result:", require("inspect")(result1))

-- Test a table with function as first element
local test_table = { test_func, level = 20, name = "test" }
print("\nTesting table normalization:")
local result2 = component_utils.normalize_component(test_table)
print("Result:", require("inspect")(result2))

-- Test a callable table
local callable_table = setmetatable({}, {
    __call = function(self, record)
        print("Callable table called with:", record)
    end
})
print("\nTesting callable table normalization:")
local result3 = component_utils.normalize_component(callable_table)
print("Result:", require("inspect")(result3))
