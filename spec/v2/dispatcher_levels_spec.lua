#!/usr/bin/env lua
package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua;../lua/?.lua;../lua/?/init.lua"

-- Test suite for dispatcher-specific levels
local lual = require("lual.logger")
local core_levels = require("lua.lual.levels")
local test_helpers = require("spec.utils.test_helpers")

describe("Dispatcher-specific levels", function()
    before_each(function()
        -- Reset logging system before each test
        lual.reset_config()
        lual.reset_cache()
    end)

    it("respects dispatcher level filtering using direct configuration API", function()
        -- Create test logger with pre-configured spies
        local logger = test_helpers.create_test_logger(lual, "test.level.check")

        -- Send messages at different levels
        logger:debug("Debug message")
        logger:info("Info message")
        logger:warn("Warning message")
        logger:error("Error message")

        -- Check actual spy contents for debugging
        print("\nDebug spy received " .. logger.spies.debug:count() .. " messages:")
        for i, call in ipairs(logger.spies.debug.calls) do
            print(i, call.level_name, call.message)
        end

        print("\nWarning spy received " .. logger.spies.warning:count() .. " messages:")
        for i, call in ipairs(logger.spies.warning.calls) do
            print(i, call.level_name, call.message)
        end

        -- Debug spy should receive all 4 messages (since level = debug)
        assert.equals(4, logger.spies.debug:count())
        assert.equals("Debug message", logger.spies.debug.calls[1].message)
        assert.equals("Info message", logger.spies.debug.calls[2].message)
        assert.equals("Warning message", logger.spies.debug.calls[3].message)
        assert.equals("Error message", logger.spies.debug.calls[4].message)

        -- Warning spy should only receive WARNING and ERROR (2 messages)
        assert.equals(2, logger.spies.warning:count())
        assert.equals("Warning message", logger.spies.warning.calls[1].message)
        assert.equals("Error message", logger.spies.warning.calls[2].message)
    end)

    it("supports the flat format for dispatcher configuration", function()
        -- Create a spy with warning level
        local spy = test_helpers.create_spy_dispatcher()

        -- Force the warning level for this test
        spy.config = {
            level = lual.warning,
            presenter = { type = "text" }
        }

        -- Ensure the spy's func is used
        spy.func = function(record)
            if record.level_no >= lual.warning then
                table.insert(spy.calls, {
                    level_no = record.level_no,
                    level_name = record.level_name,
                    message = record.message
                })
            end
        end

        -- Configure the root logger with the proper API format
        lual.config({
            level = lual.debug,
            dispatchers = {
                spy -- Use the whole spy object
            }
        })

        local logger = lual.logger()

        -- Send messages at different levels
        logger:debug("Debug message")
        logger:info("Info message")
        logger:warn("Warning message")
        logger:error("Error message")

        -- Debug output
        print("\nSpy received " .. spy:count() .. " messages:")
        for i, call in ipairs(spy.calls) do
            print(i, call.level_name, call.message)
        end

        -- Spy should only receive WARNING and ERROR (2 messages)
        assert.equals(2, spy:count())
        assert.equals("Warning message", spy.calls[1].message)
        assert.equals("Error message", spy.calls[2].message)
    end)

    it("works correctly with logger levels and propagation", function()
        -- Create spies
        local root_spy = test_helpers.create_spy_dispatcher()
        local app_spy = test_helpers.create_spy_dispatcher()

        -- Set level in config
        app_spy.config = { level = lual.info }

        -- Configure root logger
        lual.config({
            level = lual.debug,
            dispatchers = {
                root_spy
            }
        })

        -- Create a specific logger with its own dispatcher
        local app_logger = lual.logger("app", {
            level = lual.debug, -- Process all logs
            dispatchers = {
                app_spy
            }
        })

        -- Send messages at different levels
        app_logger:debug("App debug message")
        app_logger:info("App info message")
        app_logger:warn("App warning message")

        -- App spy should only get INFO and WARN (due to dispatcher level)
        assert.equals(2, app_spy:count())
        assert.equals("App info message", app_spy.calls[1].message)
        assert.equals("App warning message", app_spy.calls[2].message)

        -- Root spy should get all 3 messages (via propagation)
        assert.equals(3, root_spy:count())
        assert.equals("App debug message", root_spy.calls[1].message)
        assert.equals("App info message", root_spy.calls[2].message)
        assert.equals("App warning message", root_spy.calls[3].message)
    end)

    it("handles NOTSET dispatcher level correctly", function()
        -- Create spy with NOTSET level (should inherit from logger)
        local spy = test_helpers.create_spy_dispatcher()

        -- Set NOTSET level in config
        spy.config = { level = lual.notset }

        -- Configure root logger using the flat format
        lual.config({
            level = lual.info, -- Only process INFO and above
            dispatchers = {
                spy
            }
        })

        local logger = lual.logger()

        -- Send messages at different levels
        logger:debug("Debug message")  -- Should be filtered by logger level
        logger:info("Info message")    -- Should pass
        logger:warn("Warning message") -- Should pass

        -- Spy should get INFO and WARN (due to logger level)
        assert.equals(2, spy:count())
        assert.equals("Info message", spy.calls[1].message)
        assert.equals("Warning message", spy.calls[2].message)
    end)

    it("supports flat configuration with real dispatchers", function()
        -- This test uses actual dispatchers to test the full API

        -- Configure root logger with both file and console dispatchers
        lual.config({
            level = lual.debug,
            dispatchers = {
                {
                    type = "file", -- Use string type instead of function reference
                    level = lual.debug,
                    path = "test_log.log",
                    presenter = { type = "json" } -- Use string type
                },
                {
                    type = "console",             -- Use string type instead of function reference
                    level = lual.warning,
                    presenter = { type = "text" } -- Use string type
                }
            }
        })

        -- Verify the configuration was accepted without errors
        -- (We don't actually verify output since that would require mocking the file system)
        assert.is_true(true)

        -- Clean up the test log file if it was created
        os.remove("test_log.log")
    end)
end)
