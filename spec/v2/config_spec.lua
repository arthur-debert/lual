#!/usr/bin/env lua
package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua;../lua/?.lua;../lua/?/init.lua"

local lual = require("lual.logger")
local core_levels = require("lua.lual.levels")

describe("lual.config() API", function()
    before_each(function()
        -- Reset config for each test
        lual.reset_config()
    end)

    describe("Basic functionality", function()
        it("should update configuration with provided keys", function()
            local updated_config = lual.config({
                level = core_levels.definition.DEBUG
            })

            assert.are.equal(core_levels.definition.DEBUG, updated_config.level)
            assert.are.equal(true, updated_config.propagate)                                     -- Unchanged default
            assert.are.equal(1, #updated_config.dispatchers)                                     -- Default console dispatcher
            assert.are.equal(lual.dispatchers.console_dispatcher, updated_config.dispatchers[1]) -- Console dispatcher
        end)

        it("should preserve existing configuration for unspecified keys", function()
            -- Set initial config
            lual.config({
                level = core_levels.definition.ERROR,
                propagate = false
            })

            -- Update only level
            local updated_config = lual.config({
                level = core_levels.definition.INFO
            })

            assert.are.equal(core_levels.definition.INFO, updated_config.level)
            assert.are.equal(false, updated_config.propagate)                                    -- Preserved from previous call
            assert.are.equal(1, #updated_config.dispatchers)                                     -- Default console dispatcher
            assert.are.equal(lual.dispatchers.console_dispatcher, updated_config.dispatchers[1]) -- Console dispatcher
        end)

        it("should allow updating dispatchers", function()
            local mock_dispatcher = function() end
            local updated_config = lual.config({
                dispatchers = { mock_dispatcher }
            })

            assert.are.equal(1, #updated_config.dispatchers)
            assert.are.equal(mock_dispatcher, updated_config.dispatchers[1])
            assert.are.equal(core_levels.definition.WARNING, updated_config.level) -- Default unchanged
        end)

        it("should allow updating propagate", function()
            local updated_config = lual.config({
                propagate = false
            })

            assert.are.equal(false, updated_config.propagate)
            assert.are.equal(core_levels.definition.WARNING, updated_config.level)               -- Default unchanged
            assert.are.equal(1, #updated_config.dispatchers)                                     -- Default console dispatcher
            assert.are.equal(lual.dispatchers.console_dispatcher, updated_config.dispatchers[1]) -- Console dispatcher
        end)

        it("should allow updating multiple keys at once", function()
            local mock_dispatcher1 = function() end
            local mock_dispatcher2 = function() end

            local updated_config = lual.config({
                level = core_levels.definition.CRITICAL,
                dispatchers = { mock_dispatcher1, mock_dispatcher2 },
                propagate = false
            })

            assert.are.equal(core_levels.definition.CRITICAL, updated_config.level)
            assert.are.equal(false, updated_config.propagate)
            assert.are.equal(2, #updated_config.dispatchers)
            assert.are.equal(mock_dispatcher1, updated_config.dispatchers[1])
            assert.are.equal(mock_dispatcher2, updated_config.dispatchers[2])
        end)
    end)

    describe("Validation - Unknown keys", function()
        it("should reject unknown configuration keys", function()
            assert.has_error(function()
                    lual.config({
                        level = core_levels.definition.DEBUG,
                        unknown_key = "value"
                    })
                end,
                "Invalid configuration: Unknown configuration key 'unknown_key'. Valid keys are: dispatchers, level, propagate")
        end)

        it("should reject multiple unknown keys with helpful message", function()
            assert.has_error(function()
                lual.config({
                    bad_key1 = "value1",
                    bad_key2 = "value2"
                })
            end)
            -- Should contain "Unknown configuration key" somewhere in the error
        end)
    end)

    describe("Validation - Type checking", function()
        it("should reject non-table configuration", function()
            assert.has_error(function()
                lual.config("not a table")
            end, "Invalid configuration: Configuration must be a table, got string")

            assert.has_error(function()
                lual.config(123)
            end, "Invalid configuration: Configuration must be a table, got number")

            assert.has_error(function()
                lual.config(nil)
            end, "Invalid configuration: Configuration must be a table, got nil")
        end)

        it("should reject invalid level type", function()
            assert.has_error(function()
                    lual.config({
                        level = "debug" -- Should be number, not string
                    })
                end,
                "Invalid configuration: Invalid type for 'level': expected number, got string. Logging level (use lual.DEBUG, lual.INFO, etc.)")

            assert.has_error(function()
                    lual.config({
                        level = true
                    })
                end,
                "Invalid configuration: Invalid type for 'level': expected number, got boolean. Logging level (use lual.DEBUG, lual.INFO, etc.)")
        end)

        it("should reject invalid level values", function()
            assert.has_error(function()
                lual.config({
                    level = 999 -- Invalid level number
                })
            end)
            -- Should contain info about valid levels

            assert.has_error(function()
                lual.config({
                    level = -1 -- Invalid level number
                })
            end)
            -- Should contain info about valid levels
        end)

        it("should accept all valid level values", function()
            local valid_levels = {
                core_levels.definition.NOTSET,
                core_levels.definition.DEBUG,
                core_levels.definition.INFO,
                core_levels.definition.WARNING,
                core_levels.definition.ERROR,
                core_levels.definition.CRITICAL,
                core_levels.definition.NONE
            }

            for _, level in ipairs(valid_levels) do
                assert.has_no_error(function()
                    lual.config({ level = level })
                end, "Should accept level " .. level)
            end
        end)

        it("should reject invalid propagate type", function()
            assert.has_error(function()
                    lual.config({
                        propagate = "true" -- Should be boolean, not string
                    })
                end,
                "Invalid configuration: Invalid type for 'propagate': expected boolean, got string. Whether to propagate messages (always true for root)")

            assert.has_error(function()
                    lual.config({
                        propagate = 1 -- Should be boolean, not number
                    })
                end,
                "Invalid configuration: Invalid type for 'propagate': expected boolean, got number. Whether to propagate messages (always true for root)")
        end)

        it("should reject invalid dispatchers type", function()
            assert.has_error(function()
                    lual.config({
                        dispatchers = "not a table"
                    })
                end,
                "Invalid configuration: Invalid type for 'dispatchers': expected table, got string. Array of dispatcher functions or configuration tables")

            assert.has_error(function()
                    lual.config({
                        dispatchers = 123
                    })
                end,
                "Invalid configuration: Invalid type for 'dispatchers': expected table, got number. Array of dispatcher functions or configuration tables")
        end)

        it("should reject dispatchers containing non-functions", function()
            assert.has_error(function()
                    lual.config({
                        dispatchers = { "not a function" }
                    })
                end,
                "Invalid configuration: dispatchers[1] must be a function, a table with dispatcher_func, or a table with type property (string or function), got string")

            assert.has_error(function()
                    lual.config({
                        dispatchers = { function() end, 123, function() end }
                    })
                end,
                "Invalid configuration: dispatchers[2] must be a function, a table with dispatcher_func, or a table with type property (string or function), got number")
        end)

        it("should accept empty dispatchers array", function()
            assert.has_no_error(function()
                lual.config({
                    dispatchers = {}
                })
            end)
        end)

        it("should accept valid dispatchers array", function()
            local mock_dispatcher1 = function() end
            local mock_dispatcher2 = function() end

            assert.has_no_error(function()
                lual.config({
                    dispatchers = { mock_dispatcher1, mock_dispatcher2 }
                })
            end)
        end)
    end)

    describe("get_config() functionality", function()
        it("should return current configuration", function()
            local mock_dispatcher = function() end
            lual.config({
                level = core_levels.definition.ERROR,
                dispatchers = { mock_dispatcher },
                propagate = false
            })

            local current_config = lual.get_config()
            assert.are.equal(core_levels.definition.ERROR, current_config.level)
            assert.are.equal(false, current_config.propagate)
            assert.are.equal(1, #current_config.dispatchers)
            assert.are.equal(mock_dispatcher, current_config.dispatchers[1])
        end)

        it("should return default configuration initially", function()
            local default_config = lual.get_config()
            assert.are.equal(core_levels.definition.WARNING, default_config.level)
            assert.are.equal(true, default_config.propagate)
            assert.are.equal(1, #default_config.dispatchers)                                     -- Default console dispatcher
            assert.are.equal(lual.dispatchers.console_dispatcher, default_config.dispatchers[1]) -- Console dispatcher
        end)

        it("should return a copy (not reference) of configuration", function()
            local config1 = lual.get_config()
            config1.level = core_levels.definition.DEBUG -- Modify the returned config

            local config2 = lual.get_config()
            assert.are.equal(core_levels.definition.WARNING, config2.level) -- Should still be default
        end)

        it("should return a copy of dispatchers array", function()
            local mock_dispatcher = function() end
            lual.config({ dispatchers = { mock_dispatcher } })

            local config = lual.get_config()
            table.insert(config.dispatchers, function() end) -- Modify returned dispatchers

            local config2 = lual.get_config()
            assert.are.equal(1, #config2.dispatchers) -- Should still have original length
        end)
    end)

    describe("reset_config() functionality", function()
        it("should reset configuration to defaults", function()
            -- Set non-default configuration
            local mock_dispatcher = function() end
            lual.config({
                level = core_levels.definition.DEBUG,
                dispatchers = { mock_dispatcher },
                propagate = false
            })

            -- Reset
            lual.reset_config()

            -- Check that defaults are restored
            local config = lual.get_config()
            assert.are.equal(core_levels.definition.WARNING, config.level)
            assert.are.equal(true, config.propagate)
            assert.are.equal(1, #config.dispatchers)                                     -- Default console dispatcher
            assert.are.equal(lual.dispatchers.console_dispatcher, config.dispatchers[1]) -- Console dispatcher
        end)
    end)

    describe("Integration with main lual module", function()
        it("should be accessible via lual.config", function()
            assert.is_function(lual.config)
            assert.is_function(lual.get_config)
            assert.is_function(lual.reset_config)
        end)

        it("should work through lual namespace", function()
            local updated_config = lual.config({
                level = core_levels.definition.INFO
            })

            assert.are.equal(core_levels.definition.INFO, updated_config.level)

            local retrieved_config = lual.get_config()
            assert.are.equal(core_levels.definition.INFO, retrieved_config.level)
        end)

        it("should have logger implemented", function()
            assert.is_function(lual.logger)

            -- Should be able to create loggers now
            assert.has_no_error(function()
                local logger = lual.logger("test.implemented")
                assert.is_not_nil(logger)
                assert.are.equal("test.implemented", logger.name)
            end)
        end)
    end)

    describe("Edge cases", function()
        it("should handle empty configuration table", function()
            local config_before = lual.get_config()
            local updated_config = lual.config({})
            local config_after = lual.get_config()

            -- Should be unchanged
            assert.are.same(config_before, updated_config)
            assert.are.same(config_before, config_after)
        end)

        it("should handle configuration with nil values (should not update)", function()
            lual.config({
                level = core_levels.definition.ERROR
            })

            -- This should not change the level since we're not passing it
            local updated_config = lual.config({
                propagate = false
            })

            assert.are.equal(core_levels.definition.ERROR, updated_config.level) -- Preserved
            assert.are.equal(false, updated_config.propagate)                    -- Updated
        end)
    end)
end)
