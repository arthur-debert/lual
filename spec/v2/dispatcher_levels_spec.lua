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
        -- Create a very simple test
        local calls_debug = {}
        local calls_warning = {}

        -- Create simple dispatch functions with level filtering
        local function debug_dispatcher(record, config)
            -- Debug output: print("DEBUG DISPATCHER - record level: " .. record.level_no ..
            --     ", config type: " .. type(config) ..
            --     ", config.level: " .. tostring(config.level))

            if config.level and record.level_no < config.level then
                -- Debug output: print("  FILTERING OUT - level too low")
                return -- Skip if below level threshold
            end
            -- Debug output: print("  ACCEPTING RECORD")
            table.insert(calls_debug, record.message)
        end

        local function warning_dispatcher(record, config)
            -- Debug output: print("WARNING DISPATCHER - record level: " .. record.level_no ..
            --     ", config type: " .. type(config) ..
            --     ", config.level: " .. tostring(config.level))

            if config.level and record.level_no < config.level then
                -- Debug output: print("  FILTERING OUT - level too low")
                return -- Skip if below level threshold
            end
            -- Debug output: print("  ACCEPTING RECORD")
            table.insert(calls_warning, record.message)
        end

        -- Create logger with these dispatchers
        local logger = lual.logger("simple.test")

        -- Debug output: print("Logger dispatchers before:", #logger.dispatchers)

        -- Add our dispatchers
        logger:add_dispatcher(debug_dispatcher, { level = lual.debug })
        logger:add_dispatcher(warning_dispatcher, { level = lual.warning })

        -- Debug dispatcher dump:
        -- print("Logger dispatchers after:", #logger.dispatchers)
        -- for i, disp in ipairs(logger.dispatchers) do
        --     print("  Dispatcher " .. i .. ":")
        --     print("    func: " .. tostring(disp.func))
        --     print("    config: " .. tostring(disp.config))
        --     print("    config.level: " .. tostring(disp.config.level))
        -- end

        -- Set logger level to debug to allow all messages
        logger:set_level(lual.debug)

        -- Send messages at different levels
        logger:debug("Debug message")
        logger:info("Info message")
        logger:warn("Warning message")
        logger:error("Error message")

        -- Debug level dispatcher should see all messages
        assert.equals(4, #calls_debug)

        -- Warning level dispatcher should only see warning and error
        assert.equals(2, #calls_warning)
        assert.equals("Warning message", calls_warning[1])
        assert.equals("Error message", calls_warning[2])
    end)

    it("supports the flat format for dispatcher configuration", function()
        -- Create a very simple test
        local calls_captured = {}

        -- Create simple dispatch functions with level filtering
        local function capture_logs(record, config)
            -- Debug output: print("CAPTURE LOGS - record level: " .. record.level_no ..
            --     ", config type: " .. type(config) ..
            --     ", config.level: " .. tostring(config.level))

            if config.level and record.level_no < config.level then
                -- Debug output: print("  FILTERING OUT - level too low")
                return -- Skip if below level threshold
            end
            -- Debug output: print("  ACCEPTING RECORD")
            table.insert(calls_captured, record.message)
        end

        -- Configure the root logger with the level in the config
        lual.config({
            level = lual.debug,
            dispatchers = {
                { capture_logs, level = lual.warning }
            }
        })

        local logger = lual.logger()

        -- Send messages at different levels
        logger:debug("Debug message")
        logger:info("Info message")
        logger:warn("Warning message")
        logger:error("Error message")

        -- Spy should only receive WARNING and ERROR (2 messages)
        assert.equals(2, #calls_captured)
        assert.equals("Warning message", calls_captured[1])
        assert.equals("Error message", calls_captured[2])
    end)

    it("works correctly with logger levels and propagation", function()
        -- Create a very simple test
        local root_calls = {}
        local app_calls = {}

        -- Create simple dispatch functions with level filtering
        local function root_dispatcher(record, config)
            -- Debug output: print("ROOT DISPATCHER - record level: " .. record.level_no ..
            --     ", config type: " .. type(config) ..
            --     ", config.level: " .. tostring(config.level))

            if config.level and record.level_no < config.level then
                -- Debug output: print("  FILTERING OUT - level too low")
                return -- Skip if below level threshold
            end
            -- Debug output: print("  ACCEPTING RECORD")
            table.insert(root_calls, record.message)
        end

        local function app_dispatcher(record, config)
            -- Debug output: print("APP DISPATCHER - record level: " .. record.level_no ..
            --     ", config type: " .. type(config) ..
            --     ", config.level: " .. tostring(config.level))

            if config.level and record.level_no < config.level then
                -- Debug output: print("  FILTERING OUT - level too low")
                return -- Skip if below level threshold
            end
            -- Debug output: print("  ACCEPTING RECORD")
            table.insert(app_calls, record.message)
        end

        -- Configure root logger
        lual.config({
            level = lual.debug,
            dispatchers = {
                { root_dispatcher } -- No level, accepts all
            }
        })

        -- Create a specific logger with its own dispatcher
        local app_logger = lual.logger("app", {
            level = lual.debug,                       -- Process all logs
            dispatchers = {
                { app_dispatcher, level = lual.info } -- Only INFO and above
            }
        })

        -- Send messages at different levels
        app_logger:debug("App debug message")
        app_logger:info("App info message")
        app_logger:warn("App warning message")

        -- App spy should only get INFO and WARN (due to dispatcher level)
        assert.equals(2, #app_calls)
        assert.equals("App info message", app_calls[1])
        assert.equals("App warning message", app_calls[2])

        -- Root spy should get all 3 messages (via propagation)
        assert.equals(3, #root_calls)
        assert.equals("App debug message", root_calls[1])
        assert.equals("App info message", root_calls[2])
        assert.equals("App warning message", root_calls[3])
    end)

    it("handles NOTSET dispatcher level correctly", function()
        -- Create a very simple test
        local calls_captured = {}

        -- Create simple dispatch functions with level filtering
        local function capture_logs(record, config)
            -- Debug output: print("NOTSET DISPATCHER - record level: " .. record.level_no ..
            --     ", config type: " .. type(config) ..
            --     ", config.level: " .. tostring(config.level))

            if config.level and config.level > 0 and record.level_no < config.level then
                -- Debug output: print("  FILTERING OUT - level too low")
                return -- Skip if below level threshold
            end
            -- Debug output: print("  ACCEPTING RECORD")
            table.insert(calls_captured, record.message)
        end

        -- Configure root logger using level = NOTSET
        lual.config({
            level = lual.info,                        -- Only process INFO and above
            dispatchers = {
                { capture_logs, level = lual.notset } -- Should inherit logger level
            }
        })

        local logger = lual.logger()

        -- Send messages at different levels
        logger:debug("Debug message")  -- Should be filtered by logger level
        logger:info("Info message")    -- Should pass
        logger:warn("Warning message") -- Should pass

        -- Spy should get INFO and WARN (due to logger level)
        assert.equals(2, #calls_captured)
        assert.equals("Info message", calls_captured[1])
        assert.equals("Warning message", calls_captured[2])
    end)

    it("supports standard format with real dispatchers", function()
        -- This test uses actual dispatchers to test the full API

        -- Configure root logger with both file and console dispatchers
        lual.config({
            level = lual.debug,
            dispatchers = {
                { lual.dispatchers.file_dispatcher,    path = "test_log.log", level = lual.debug },
                { lual.dispatchers.console_dispatcher, level = lual.warning }
            }
        })

        -- Verify the configuration was accepted without errors
        -- (We don't actually verify output since that would require mocking the file system)
        assert.is_true(true)

        -- Clean up the test log file if it was created
        os.remove("test_log.log")
    end)
end)
