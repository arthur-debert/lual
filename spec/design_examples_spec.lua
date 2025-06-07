#!/usr/bin/env lua
package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua;../lua/?.lua;../lua/?/init.lua"

local lual = require("lual.logger")
local core_levels = require("lual.levels")

--- Creates a mock output function that captures output
-- @return function A output function that records calls
local function create_mock_output()
    local calls = {}

    -- The output function
    local function mock_output(record)
        table.insert(calls, record)
    end

    -- Add helper methods to the function object for easier test assertions
    local api = {
        -- Return the function
        func = mock_output,

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

            -- Create a simple function output
            local function capture_logs(record)
                table.insert(output_captured, record)
            end

            -- Configure root logger with this output function
            lual.config({
                pipelines = {
                    {
                        outputs = { capture_logs },
                        presenter = lual.text
                    }
                }
            })

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

            -- Create a simple function output
            local function capture_logs(record)
                table.insert(output_captured, record)
            end

            -- Configure root logger with DEBUG level and simple function output
            lual.config({
                level = core_levels.definition.DEBUG,
                pipelines = {
                    {
                        outputs = { capture_logs },
                        presenter = lual.json
                    }
                }
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
            local root_records = {}
            local feature_records = {}

            -- Create simple function outputs
            local function root_output(record)
                table.insert(root_records, record)
            end

            local function feature_output(record)
                table.insert(feature_records, record)
            end

            -- Configure root logger with INFO level and function output
            lual.config({
                level = core_levels.definition.INFO,
                pipelines = {
                    {
                        outputs = { root_output },
                        presenter = lual.text
                    }
                }
            })

            -- Create feature logger with DEBUG level and its own function output
            local feature_logger = lual.logger("app.featureX", {
                level = core_levels.definition.DEBUG,
                pipelines = {
                    {
                        outputs = { feature_output },
                        presenter = lual.text
                    }
                },
                propagate = true
            })

            -- Debug message should only go to feature logger
            feature_logger:debug("A detailed debug message from Feature X.")
            assert.are.equal(1, #feature_records, "Debug message should be logged by feature logger")
            assert.are.equal(0, #root_records, "Debug message should not be logged by root logger")

            -- Warning message should go to both loggers
            feature_logger:warn("A warning from Feature X.")
            assert.are.equal(2, #feature_records, "Warning message should be logged by feature logger")
            assert.are.equal(1, #root_records, "Warning message should be logged by root logger")
        end)
    end)
end)
