#!/usr/bin/env lua
package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua;../lua/?.lua;../lua/?/init.lua"

local lual = require("lual.logger")
local core_levels = require("lua.lual.levels")

--- Creates a mock dispatcher function that captures output
-- @return function A dispatcher function that records calls
local function create_mock_dispatcher()
    local calls = {}

    -- The dispatcher function
    local function mock_dispatcher(record)
        table.insert(calls, record)
    end

    -- Add helper methods to the function object for easier test assertions
    local api = {
        -- Return the function
        func = mock_dispatcher,

        -- Return the calls for assertions
        get_calls = function()
            return calls
        end,

        -- Get call count
        count = function()
            return #calls
        end,

        -- Clear calls
        clear = function()
            calls = {}
        end
    }

    return api
end

describe("lual Logger - Design Examples", function()
    before_each(function()
        lual.reset_config()
        lual.reset_cache()
    end)

    describe("Example 1: Simplest Case (Out-of-the-box, no user config)", function()
        it("should work with default configuration", function()
            -- Use a simple array to collect log records
            local output_captured = {}

            -- Create a simple function dispatcher
            local function capture_logs(record)
                table.insert(output_captured, record)
            end

            -- Configure root logger with this dispatcher function
            lual.config({ dispatchers = { capture_logs } })

            -- Create logger with auto-name
            local logger = lual.logger()

            -- Debug should not be logged (root is at WARNING)
            logger:debug("This is a debug message.")
            assert.are.equal(0, #output_captured, "Debug message should not be logged")

            -- Warning should be logged
            logger:warn("This is a warning.")
            assert.are.equal(1, #output_captured, "Warning message should be logged")
            assert.are.equal("This is a warning.", output_captured[1].message_fmt)

            -- Error should be logged
            logger:error("This is an error!")
            assert.are.equal(2, #output_captured, "Error message should be logged")
            assert.are.equal("This is an error!", output_captured[2].message_fmt)
        end)
    end)

    describe("Example 2: User Configures Root Logger", function()
        it("should handle root logger configuration with JSON presenter", function()
            -- Use a simple array to collect log records
            local output_captured = {}

            -- Create a simple function dispatcher
            local function capture_logs(record)
                table.insert(output_captured, record)
            end

            -- Configure root logger with DEBUG level and simple function dispatcher
            lual.config({
                level = core_levels.definition.DEBUG,
                dispatchers = { capture_logs }
            })

            -- Create logger with hierarchical name
            local mod_logger = lual.logger("myApp.moduleA")

            -- Debug should be logged (root is at DEBUG)
            mod_logger:debug("Module A is starting up.")
            assert.are.equal(1, #output_captured, "Debug message should be logged")
            assert.are.equal("Module A is starting up.", output_captured[1].message_fmt)

            -- Info should be logged
            mod_logger:info("Module A info.")
            assert.are.equal(2, #output_captured, "Info message should be logged")
            assert.are.equal("Module A info.", output_captured[2].message_fmt)
        end)
    end)

    describe("Example 3: Logger-Specific Configuration with Root Config", function()
        it("should handle mixed logger configurations", function()
            -- Use simple arrays to collect log records
            local root_output = {}
            local feature_output = {}

            -- Create simple function dispatchers
            local function root_dispatcher(record)
                table.insert(root_output, record)
            end

            local function feature_dispatcher(record)
                table.insert(feature_output, record)
            end

            -- Configure root logger with INFO level and function dispatcher
            lual.config({
                level = core_levels.definition.INFO,
                dispatchers = { root_dispatcher }
            })

            -- Create feature logger with DEBUG level and its own function dispatcher
            local feature_logger = lual.logger("app.featureX", {
                level = core_levels.definition.DEBUG,
                dispatchers = { feature_dispatcher },
                propagate = true
            })

            -- Debug message should only go to feature logger
            feature_logger:debug("A detailed debug message from Feature X.")
            assert.are.equal(1, #feature_output, "Debug message should be logged by feature logger")
            assert.are.equal(0, #root_output, "Debug message should not be logged by root logger")

            -- Warning message should go to both loggers
            feature_logger:warn("A warning from Feature X.")
            assert.are.equal(2, #feature_output, "Warning message should be logged by feature logger")
            assert.are.equal(1, #root_output, "Warning message should be logged by root logger")
        end)
    end)
end)
