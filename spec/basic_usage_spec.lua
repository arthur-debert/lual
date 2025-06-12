#!/usr/bin/env lua
package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua;../lua/?.lua;../lua/?/init.lua"

local lual = require("lual.logger")
local core_levels = require("lual.levels")

--[[
REGRESSION TEST: Basic Usage Protection

This test file protects against regressions in the most fundamental usage patterns
that should NEVER break. It was added after a critical bug where the simplest
possible usage of lual caused a "_get_effective_level is nil" error:

    local logger = lual.logger()
    logger.level = lual.debug
    logger:info("message") -- This was failing!

The bug was in the logger factory where method inheritance was incorrectly implemented,
causing method resolution conflicts. The issue was missed by other tests because they
either:
1. Tested _get_effective_level() directly (not through logging method calls)
2. Called lual.config() first, which masked the inheritance bug

This test ensures that the most basic "out of the box" usage works without any
configuration or setup - protecting against similar factory/inheritance bugs.
]]

describe("lual Logger - Basic Usage (Regression Protection)", function()
    before_each(function()
        lual.reset_config()
        lual.reset_cache()
    end)

    describe("Out-of-the-box usage (no config)", function()
        it("should work with the simplest possible logger creation and logging", function()
            -- This is the EXACT user code that was failing
            -- NO lual.config() call first - pure out-of-the-box usage
            local logger = lual.logger()
            logger.level = lual.debug

            -- This should NOT throw an error about _get_effective_level being nil
            assert.has_no_error(function()
                logger:info("Logging setup complete at %Y-%m-%d %H:%M:%S")
            end, "Basic logger:info() call should work without any configuration")
        end)

        it("should work with user's original failing code using dot notation", function()
            -- This is the EXACT user code that was originally failing with dot notation
            assert.has_no_error(function()
                local lual = require("lual")
                local logger = lual.logger()
                logger.set_level(lual.debug) -- This was failing before!
                logger.info("Logging setup complete at %Y-%m-%d %H:%M:%S")
            end, "User's original dot notation code should now work")
        end)

        it("should support all logging levels without configuration", function()
            local logger = lual.logger()
            logger.level = lual.debug

            -- Test that all logging methods work without throwing _get_effective_level errors
            assert.has_no_error(function()
                logger:debug("Debug message")
            end, "logger:debug() should work")

            assert.has_no_error(function()
                logger:info("Info message")
            end, "logger:info() should work")

            assert.has_no_error(function()
                logger:warn("Warning message")
            end, "logger:warn() should work")

            assert.has_no_error(function()
                logger:error("Error message")
            end, "logger:error() should work")

            assert.has_no_error(function()
                logger:critical("Critical message")
            end, "logger:critical() should work")
        end)

        it("should work with logger created with explicit name", function()
            local logger = lual.logger("test.logger")
            logger.level = lual.info

            assert.has_no_error(function()
                logger:info("Named logger test")
            end, "Named logger should work without configuration")
        end)

        it("should work with logger created with config but no global config", function()
            local logger = lual.logger("configured.logger", {
                level = core_levels.definition.DEBUG
            })

            assert.has_no_error(function()
                logger:debug("Configured logger test")
            end, "Logger with local config should work without global configuration")
        end)

        it("should allow _get_effective_level to be called directly", function()
            local logger = lual.logger()

            assert.has_no_error(function()
                local level = logger:_get_effective_level()
                assert.is_number(level, "_get_effective_level should return a number")
            end, "_get_effective_level should be accessible on logger instances")
        end)
    end)

    describe("Config API basic usage", function()
        it("should work with empty config table - lual.config({})", function()
            -- This is another critical basic pattern that users might try
            assert.has_no_error(function()
                lual.config({})
            end, "lual.config({}) should not throw errors")

            -- Should be able to create logger and log after empty config
            local logger = lual.logger()
            assert.has_no_error(function()
                logger:warn("Warning after empty config") -- Should work (WARNING level)
            end, "Logging should work after lual.config({})")

            -- INFO should be filtered (this is correct behavior, not a bug)
            assert.has_no_error(function()
                logger:info("Info after empty config") -- Should be silently filtered
            end, "INFO logging should not crash after lual.config({})")
        end)

        it("should work with config then logger creation", function()
            -- Test the pattern: config first, then create logger
            assert.has_no_error(function()
                lual.config({ level = lual.debug })
                local logger = lual.logger()
                logger:debug("Debug message")
                logger:info("Info message")
                logger:warn("Warning message")
            end, "Config-then-logger pattern should work")
        end)

        it("should work with minimal config variations", function()
            -- Test various minimal configs that users might try
            local minimal_configs = {
                {},
                { level = lual.info },
                { level = lual.debug },
                { propagate = true },
                { propagate = false }
            }

            for i, config in ipairs(minimal_configs) do
                assert.has_no_error(function()
                    lual.reset_config() -- Reset between tests
                    lual.config(config)
                    local logger = lual.logger("test.minimal." .. i)
                    logger:warn("Test message " .. i)
                end, "Minimal config variation " .. i .. " should work")
            end
        end)
    end)

    describe("Method inheritance verification", function()
        it("should have all expected methods on logger instances", function()
            local logger = lual.logger()

            -- Verify core logging methods exist
            assert.is_function(logger.debug, "logger should have debug method")
            assert.is_function(logger.info, "logger should have info method")
            assert.is_function(logger.warn, "logger should have warn method")
            assert.is_function(logger.error, "logger should have error method")
            assert.is_function(logger.critical, "logger should have critical method")
            assert.is_function(logger.log, "logger should have log method")

            -- Verify internal methods exist
            assert.is_function(logger._get_effective_level, "logger should have _get_effective_level method")
            assert.is_function(logger.set_level, "logger should have set_level method")
            assert.is_function(logger.add_pipeline, "logger should have add_pipeline method")
        end)

        it("should allow methods to be called through metatable inheritance", function()
            local logger = lual.logger()

            -- These should all work through metatable method lookup
            assert.has_no_error(function()
                logger:set_level(core_levels.definition.DEBUG)
            end, "set_level should work through inheritance")

            assert.has_no_error(function()
                local config = logger:get_config()
                assert.is_table(config, "get_config should return a table")
            end, "get_config should work through inheritance")
        end)

        it("should support both dot and colon notation for method calls", function()
            -- This verifies universal dot notation support for all methods
            local logger1 = lual.logger("test.colon")
            local logger2 = lual.logger("test.dot")

            -- Colon notation (traditional way)
            assert.has_no_error(function()
                logger1:set_level(lual.debug)
                logger1:info("Colon notation test")
            end, "Colon notation should work")

            -- Dot notation (now supported universally!)
            assert.has_no_error(function()
                logger2.set_level(lual.debug) -- No need for explicit self anymore!
                logger2.info("Dot notation test")
            end, "Dot notation should work for all methods")

            -- Test all major methods with dot notation
            local logger3 = lual.logger("test.comprehensive")
            assert.has_no_error(function()
                logger3.set_level(lual.debug)
                logger3.set_propagate(false)
                logger3.add_pipeline({
                    outputs = { lual.console },
                    presenter = lual.text()
                })

                -- Test all logging methods with dot notation
                logger3.debug("Debug with dot")
                logger3.info("Info with dot")
                logger3.warn("Warning with dot")
                logger3.error("Error with dot")
                logger3.critical("Critical with dot")

                -- Test utility methods
                local config = logger3.get_config()
                assert.is_table(config, "get_config should return table")

                local level = logger3._get_effective_level()
                assert.is_number(level, "_get_effective_level should return number")
            end, "All methods should work with dot notation")
        end)
    end)

    describe("Imperative API basic usage", function()
        it("should work with basic imperative setup", function()
            -- Test the pattern: create logger, then configure imperatively
            local logger = lual.logger()

            assert.has_no_error(function()
                logger:set_level(lual.debug)
            end, "set_level should work")

            assert.has_no_error(function()
                logger:add_pipeline({
                    outputs = { lual.console },
                    presenter = lual.text()
                })
            end, "add_pipeline should work")

            assert.has_no_error(function()
                logger:info("Imperative setup test")
            end, "Logging should work after imperative setup")
        end)

        it("should work with logger created then configured", function()
            -- Another common pattern: create logger without config, then configure
            local logger = lual.logger("test.imperative")

            assert.has_no_error(function()
                logger:set_level(lual.info)
                logger:set_propagate(false)
                logger:info("Test after imperative config")
            end, "Imperative configuration should work")
        end)
    end)
end)
