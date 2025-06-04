#!/usr/bin/env lua
package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua;../lua/?.lua;../lua/?/init.lua"

-- Test suite for dispatcher-specific levels
local lual = require("lual.logger")
local core_levels = require("lua.lual.levels")

describe("Dispatcher-specific levels", function()
    -- Create a spy dispatcher to track log events
    local function create_spy_dispatcher()
        local spy = {
            calls = {},
            config = {}
        }

        -- The dispatcher function that records calls
        spy.dispatcher_func = function(log_record)
            table.insert(spy.calls, {
                level_no = log_record.level_no,
                level_name = log_record.level_name,
                message = log_record.message
            })
        end

        -- Helper to get call count
        function spy:count()
            return #self.calls
        end

        -- Helper to clear calls
        function spy:clear()
            self.calls = {}
        end

        return spy
    end

    before_each(function()
        -- Reset logging system before each test
        lual.reset_config()
        lual.reset_cache()
    end)

    it("respects dispatcher level filtering using direct configuration API", function()
        -- Create spies for different levels
        local debug_spy = create_spy_dispatcher()
        local warning_spy = create_spy_dispatcher()

        -- Configure root logger with both dispatchers using the flat format API
        lual.reset_config()

        -- Use only dispatcher_func instead of mixing with type
        lual.config({
            level = lual.debug, -- Process all logs
            dispatchers = {
                {
                    dispatcher_func = debug_spy.dispatcher_func,
                    level = lual.debug
                },
                {
                    dispatcher_func = warning_spy.dispatcher_func,
                    level = lual.warning
                }
            }
        })

        local logger = lual.logger()

        -- Send messages at different levels
        logger:debug("Debug message")
        logger:info("Info message")
        logger:warn("Warning message")
        logger:error("Error message")

        -- Check actual spy contents for debugging
        print("\nDebug spy received " .. debug_spy:count() .. " messages:")
        for i, call in ipairs(debug_spy.calls) do
            print(i, call.level_name, call.message)
        end

        print("\nWarning spy received " .. warning_spy:count() .. " messages:")
        for i, call in ipairs(warning_spy.calls) do
            print(i, call.level_name, call.message)
        end

        -- Debug spy should receive all 4 messages
        assert.equals(4, debug_spy:count())
        assert.equals("Debug message", debug_spy.calls[1].message)
        assert.equals("Info message", debug_spy.calls[2].message)
        assert.equals("Warning message", debug_spy.calls[3].message)
        assert.equals("Error message", debug_spy.calls[4].message)

        -- Warning spy should only receive WARNING and ERROR (2 messages)
        assert.equals(2, warning_spy:count())
        assert.equals("Warning message", warning_spy.calls[1].message)
        assert.equals("Error message", warning_spy.calls[2].message)
    end)

    it("supports the flat format for dispatcher configuration", function()
        -- Use the flat format for configuration where level, path, and presenter are at the same level
        local spy = create_spy_dispatcher()

        -- Configure the root logger with the proper API format - use only dispatcher_func
        lual.config({
            level = lual.debug,
            dispatchers = {
                {
                    dispatcher_func = spy.dispatcher_func,
                    level = lual.warning,
                    presenter = { type = "text" }
                }
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
        local root_spy = create_spy_dispatcher()
        local app_spy = create_spy_dispatcher()

        -- Configure root logger using the flat format
        lual.config({
            level = lual.debug,
            dispatchers = {
                {
                    dispatcher_func = root_spy.dispatcher_func
                }
            }
        })

        -- Create a specific logger with its own dispatcher
        local app_logger = lual.logger("app", {
            level = lual.debug, -- Process all logs
            dispatchers = {
                {
                    dispatcher_func = app_spy.dispatcher_func,
                    level = lual.info
                }
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
        local spy = create_spy_dispatcher()

        -- Configure root logger using the flat format
        lual.config({
            level = lual.info, -- Only process INFO and above
            dispatchers = {
                {
                    dispatcher_func = spy.dispatcher_func,
                    level = lual.notset
                }
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
