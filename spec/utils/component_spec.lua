#!/usr/bin/env lua
package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua;../lua/?.lua;../lua/?/init.lua"

local component_utils = require("lual.utils.component")

describe("Component Utils", function()
    describe("normalize_component", function()
        it("should convert function to table form with empty defaults", function()
            local function test_func() end
            local result = component_utils.normalize_component(test_func, {})

            assert.is_table(result)
            assert.are.equal(test_func, result.func)
            assert.is_table(result.config)
            assert.are.same({}, result.config)
        end)

        it("should convert function to table form with provided defaults", function()
            local function test_func() end
            local defaults = { timezone = "utc", level = 20 }
            local result = component_utils.normalize_component(test_func, defaults)

            assert.is_table(result)
            assert.are.equal(test_func, result.func)
            assert.is_table(result.config)
            assert.are.same(defaults, result.config)

            -- Verify it's a deep copy, not the same table
            assert.are_not.equal(defaults, result.config)
        end)

        it("should handle table form with function and config", function()
            local function test_func() end
            local input = { test_func, path = "/var/log", level = 30 }
            local defaults = { timezone = "local", level = 20 }

            local result = component_utils.normalize_component(input, defaults)

            assert.is_table(result)
            assert.are.equal(test_func, result.func)
            assert.is_table(result.config)

            -- User config should override defaults
            assert.are.equal("/var/log", result.config.path)
            assert.are.equal(30, result.config.level)         -- user override
            assert.are.equal("local", result.config.timezone) -- from defaults
        end)

        it("should handle callable table as function", function()
            local callable = setmetatable({}, {
                __call = function() return "called" end
            })
            local input = { callable, key = "value" }

            local result = component_utils.normalize_component(input, {})

            assert.are.equal(callable, result.func)
            assert.are.equal("value", result.config.key)
        end)

        it("should handle empty table form (just function)", function()
            local function test_func() end
            local input = { test_func }
            local defaults = { timezone = "utc" }

            local result = component_utils.normalize_component(input, defaults)

            assert.are.equal(test_func, result.func)
            assert.are.same(defaults, result.config)
        end)

        it("should error for invalid input types", function()
            assert.has_error(function()
                component_utils.normalize_component("string", {})
            end, "Component must be a function or a table with function as first element")

            assert.has_error(function()
                component_utils.normalize_component(123, {})
            end, "Component must be a function or a table with function as first element")

            assert.has_error(function()
                component_utils.normalize_component({}, {})
            end, "Component must be a function or a table with function as first element")
        end)

        it("should error for table with non-function first element", function()
            assert.has_error(function()
                component_utils.normalize_component({
                    "not a function",
                    level = 30
                })
            end, "First element of component table must be a function, got string")
        end)
    end)

    describe("normalize_components", function()
        it("should normalize array of functions", function()
            local function func1() end
            local function func2() end
            local input = { func1, func2 }
            local defaults = { timezone = "utc" }

            local result = component_utils.normalize_components(input, defaults)

            assert.are.equal(2, #result)
            assert.are.equal(func1, result[1].func)
            assert.are.equal(func2, result[2].func)
            assert.are.same(defaults, result[1].config)
            assert.are.same(defaults, result[2].config)
        end)

        it("should normalize mixed array of functions and tables", function()
            local function func1() end
            local function func2() end
            local input = {
                func1,
                { func2, path = "/var/log", level = 30 }
            }
            local defaults = { timezone = "local", level = 20 }

            local result = component_utils.normalize_components(input, defaults)

            assert.are.equal(2, #result)

            -- First component (function only)
            assert.are.equal(func1, result[1].func)
            assert.are.same(defaults, result[1].config)

            -- Second component (table with config)
            assert.are.equal(func2, result[2].func)
            assert.are.equal("/var/log", result[2].config.path)
            assert.are.equal(30, result[2].config.level)         -- user override
            assert.are.equal("local", result[2].config.timezone) -- from defaults
        end)

        it("should error for non-table input", function()
            assert.has_error(function()
                component_utils.normalize_components("not_a_table", {})
            end, "Components must be provided as a table/array")

            assert.has_error(function()
                component_utils.normalize_components(123, {})
            end, "Components must be provided as a table/array")
        end)

        it("should handle empty array", function()
            local result = component_utils.normalize_components({}, {})
            assert.are.same({}, result)
        end)
    end)

    describe("default configurations", function()
        it("should have output defaults", function()
            assert.is_table(component_utils.DISPATCHER_DEFAULTS)
            assert.are.equal("local", component_utils.DISPATCHER_DEFAULTS.timezone)
        end)

        it("should have transformer defaults", function()
            assert.is_table(component_utils.TRANSFORMER_DEFAULTS)
        end)

        it("should have presenter defaults", function()
            assert.is_table(component_utils.PRESENTER_DEFAULTS)
            assert.are.equal("local", component_utils.PRESENTER_DEFAULTS.timezone)
        end)
    end)

    describe("integration scenarios", function()
        it("should handle complex output configuration", function()
            local function file_output() end
            local input = { file_output, path = "/var/log/app.log", level = 30, timezone = "utc" }

            local result = component_utils.normalize_component(input, component_utils.DISPATCHER_DEFAULTS)

            assert.are.equal(file_output, result.func)
            assert.are.equal("/var/log/app.log", result.config.path)
            assert.are.equal(30, result.config.level)
            assert.are.equal("utc", result.config.timezone) -- user override
        end)

        it("should handle presenter with timezone override", function()
            local function json_presenter() end
            local input = { json_presenter, pretty = true, timezone = "utc" }

            local result = component_utils.normalize_component(input, component_utils.PRESENTER_DEFAULTS)

            assert.are.equal(json_presenter, result.func)
            assert.is_true(result.config.pretty)
            assert.are.equal("utc", result.config.timezone) -- user override
        end)

        it("should handle transformer with empty defaults", function()
            local function add_hostname() end
            local input = { add_hostname, hostname = "server1" }

            local result = component_utils.normalize_component(input, component_utils.TRANSFORMER_DEFAULTS)

            assert.are.equal(add_hostname, result.func)
            assert.are.equal("server1", result.config.hostname)
        end)
    end)
end)
