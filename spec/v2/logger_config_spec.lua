#!/usr/bin/env lua
package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua;../lua/?.lua;../lua/?/init.lua"

local lual = require("lual.logger")
local core_levels = require("lua.lual.levels")
local table_utils = require("lual.utils.table")

--- Helper function to verify that a dispatcher matches the expected function
-- @param actual table The normalized dispatcher
-- @param expected_func function The expected function
-- @return boolean Whether the dispatcher matches
local function verify_dispatcher(actual, expected_func)
    assert.is_table(actual, "Dispatcher should be a normalized table")
    assert.is_table(actual.config, "Dispatcher should have a config table")
    assert.is_function(actual.func, "Dispatcher should have a func property")
    assert.are.equal(expected_func, actual.func, "Dispatcher function should match expected")
    return true
end

describe("lual Logger Configuration API (Step 2.6)", function()
    before_each(function()
        -- Reset config and logger cache for each test
        lual.reset_config()
        lual.reset_cache()
    end)

    describe("lual.logger(name) - basic logger creation", function()
        it("should create logger with default configuration", function()
            local logger = lual.logger("test.logger")

            assert.is_not_nil(logger)
            assert.are.equal("test.logger", logger.name)

            -- Default initial state for non-root loggers (Step 2.6 requirement)
            assert.are.equal(core_levels.definition.NOTSET, logger.level)
            assert.is_table(logger.dispatchers)
            assert.are.equal(0, #logger.dispatchers)
            assert.are.equal(true, logger.propagate)
        end)

        it("should create hierarchical loggers automatically", function()
            local child_logger = lual.logger("app.service.database")

            assert.are.equal("app.service.database", child_logger.name)
            assert.is_not_nil(child_logger.parent)
            assert.are.equal("app.service", child_logger.parent.name)
            assert.is_not_nil(child_logger.parent.parent)
            assert.are.equal("app", child_logger.parent.parent.name)
            assert.is_not_nil(child_logger.parent.parent.parent)
            assert.are.equal("_root", child_logger.parent.parent.parent.name)
        end)

        it("should cache created loggers", function()
            local logger1 = lual.logger("cached.logger")
            local logger2 = lual.logger("cached.logger")

            assert.are.same(logger1, logger2)
        end)

        it("should reject invalid logger names", function()
            assert.has_error(function()
                lual.logger("")
            end, "Logger name cannot be an empty string.")

            assert.has_error(function()
                lual.logger(123)
            end, "Invalid 1st arg: expected name (string), config (table), or nil, got number")
        end)

        it("should reject names starting with underscore", function()
            assert.has_error(function()
                lual.logger("_internal.logger")
            end, "Logger names starting with '_' are reserved (except '_root'). Name: _internal.logger")
        end)

        it("should allow _root as special exception", function()
            local root_logger = lual.logger("_root")
            assert.is_not_nil(root_logger)
            assert.are.equal("_root", root_logger.name)
        end)
    end)

    describe("lual.logger(name, config) - configuration API", function()
        it("should apply only explicitly provided settings", function()
            local mock_dispatcher = function() end

            local logger = lual.logger("configured.logger", {
                level = core_levels.definition.DEBUG,
                dispatchers = { mock_dispatcher }
                -- propagate not specified, should use default
            })

            assert.are.equal(core_levels.definition.DEBUG, logger.level)
            assert.are.equal(1, #logger.dispatchers)
            assert.are.equal(true, logger.propagate) -- Default value
        end)

        it("should use defaults for unspecified settings", function()
            local logger = lual.logger("partial.config", {
                propagate = false
            })

            assert.are.equal(core_levels.definition.NOTSET, logger.level) -- Default
            assert.is_table(logger.dispatchers)                           -- Default is empty table
            assert.are.equal(0, #logger.dispatchers)
            assert.are.equal(false, logger.propagate)                     -- Explicitly set
        end)

        it("should handle empty configuration table", function()
            local logger = lual.logger("empty.config", {})

            assert.are.equal(core_levels.definition.NOTSET, logger.level)
            assert.is_table(logger.dispatchers)
            assert.are.equal(0, #logger.dispatchers)
            assert.are.equal(true, logger.propagate)
        end)

        it("should handle multiple dispatchers", function()
            local mock_dispatcher1 = function() end
            local mock_dispatcher2 = function() end

            local logger = lual.logger("test.dispatchers", {
                dispatchers = { mock_dispatcher1, mock_dispatcher2 }
            })

            assert.are.equal("test.dispatchers", logger.name)
            assert.are.equal(2, #logger.dispatchers)

            -- Verify both dispatchers
            verify_dispatcher(logger.dispatchers[1], mock_dispatcher1)
            verify_dispatcher(logger.dispatchers[2], mock_dispatcher2)
        end)
    end)

    describe("Configuration validation", function()
        it("should reject non-table configuration if name is provided", function()
            assert.has_error(function()
                lual.logger("test", "not a table")
            end, "Invalid 2nd arg: expected table (config) or nil, got string")

            assert.has_error(function()
                lual.logger("test", 123)
            end, "Invalid 2nd arg: expected table (config) or nil, got number")
        end)

        it("should reject unknown configuration keys", function()
            assert.has_error(function()
                    lual.logger("test_unknown", {
                        level = core_levels.definition.DEBUG,
                        unknown_key = "value"
                    })
                end,
                "Invalid logger configuration: Unknown configuration key 'unknown_key'. Valid keys are: dispatchers, level, propagate")
        end)

        it("should reject invalid level type", function()
            assert.has_error(function()
                    lual.logger("test_leveltype", {
                        level = "debug"
                    })
                end,
                "Invalid logger configuration: Invalid type for 'level': expected number, got string. Logging level (use lual.DEBUG, lual.INFO, etc.)")
        end)

        it("should reject invalid level values", function()
            assert.has_error(function()
                    lual.logger("test_levelval", {
                        level = 999
                    })
                end,
                "Invalid logger configuration: Invalid level value 999. Valid levels are: CRITICAL(50), DEBUG(10), ERROR(40), INFO(20), NONE(100), NOTSET(0), WARNING(30)")
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
            for _, level_val in ipairs(valid_levels) do
                assert.has_no_error(function()
                    lual.logger("test.level." .. tostring(level_val) .. math.random(), { level = level_val })
                end, "Should accept level " .. tostring(level_val))
            end
        end)

        it("should reject invalid propagate type", function()
            assert.has_error(function()
                    lual.logger("test_propag", {
                        propagate = "true"
                    })
                end,
                "Invalid logger configuration: Invalid type for 'propagate': expected boolean, got string. Whether to propagate messages to parent loggers")
        end)

        it("should reject invalid dispatchers type", function()
            assert.has_error(function()
                    lual.logger("test_disptype", {
                        dispatchers = "not a table"
                    })
                end,
                "Invalid logger configuration: Invalid type for 'dispatchers': expected table, got string. Array of dispatcher functions or dispatcher config tables")
        end)

        it("should reject non-function/non-table dispatchers in array", function()
            assert.has_error(function()
                    lual.logger("test_dispitem1", {
                        dispatchers = { "not a function" }
                    })
                end,
                "Invalid logger configuration: dispatchers[1] must be a function, a table with dispatcher_func, or a table with type (string or function), got string")

            assert.has_error(function()
                    lual.logger("test_dispitem2", {
                        dispatchers = { function() end, 123, function() end }
                    })
                end,
                "Invalid logger configuration: dispatchers[2] must be a function, a table with dispatcher_func, or a table with type (string or function), got number")
        end)

        it("should accept empty dispatchers array", function()
            assert.has_no_error(function()
                lual.logger("test_empty_disp_ok", {
                    dispatchers = {}
                })
            end)
        end)
    end)

    describe("Imperative methods", function()
        local test_logger

        before_each(function()
            test_logger = lual.logger("imperative.test")
        end)

        describe("set_level()", function()
            it("should update logger level", function()
                test_logger:set_level(core_levels.definition.ERROR)
                assert.are.equal(core_levels.definition.ERROR, test_logger.level)

                test_logger:set_level(core_levels.definition.DEBUG)
                assert.are.equal(core_levels.definition.DEBUG, test_logger.level)
            end)

            it("should reject non-number levels", function()
                assert.has_error(function()
                    test_logger:set_level("debug")
                end, "Level must be a number, got string")
            end)

            it("should reject invalid level values", function()
                assert.has_error(function()
                    test_logger:set_level(999)
                end, "Invalid level value: 999")
            end)

            it("should accept all valid levels", function()
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
                        test_logger:set_level(level)
                    end)
                    assert.are.equal(level, test_logger.level)
                end
            end)
        end)

        describe("add_dispatcher()", function()
            it("should add dispatcher to logger", function()
                local mock_dispatcher = function() end
                local logger = lual.logger("test.add_dispatcher")

                logger:add_dispatcher(mock_dispatcher)

                assert.are.equal(1, #logger.dispatchers)
                verify_dispatcher(logger.dispatchers[1], mock_dispatcher)
            end)

            it("should add dispatcher with config", function()
                local mock_dispatcher = function() end
                local logger = lual.logger("test.add_dispatcher_config")

                logger:add_dispatcher(mock_dispatcher, { level = 30, stream = "test" })

                assert.are.equal(1, #logger.dispatchers)
                verify_dispatcher(logger.dispatchers[1], mock_dispatcher)
                assert.are.equal(30, logger.dispatchers[1].config.level)
                assert.are.equal("test", logger.dispatchers[1].config.stream)
            end)

            it("should add multiple dispatchers", function()
                local mock_dispatcher1 = function() end
                local mock_dispatcher2 = function() end
                local logger = lual.logger("test.add_multiple_dispatchers")

                logger:add_dispatcher(mock_dispatcher1)
                logger:add_dispatcher(mock_dispatcher2)

                assert.are.equal(2, #logger.dispatchers)
                verify_dispatcher(logger.dispatchers[1], mock_dispatcher1)
                verify_dispatcher(logger.dispatchers[2], mock_dispatcher2)
            end)

            it("should reject non-function dispatchers", function()
                assert.has_error(function()
                    test_logger:add_dispatcher("not a function")
                end, "Dispatcher must be a function, got string")
            end)
        end)

        describe("set_propagate()", function()
            it("should update propagate flag", function()
                test_logger:set_propagate(false)
                assert.are.equal(false, test_logger.propagate)

                test_logger:set_propagate(true)
                assert.are.equal(true, test_logger.propagate)
            end)

            it("should reject non-boolean values", function()
                assert.has_error(function()
                    test_logger:set_propagate("true")
                end, "Propagate must be a boolean, got string")

                assert.has_error(function()
                    test_logger:set_propagate(1)
                end, "Propagate must be a boolean, got number")
            end)
        end)

        describe("get_config()", function()
            it("should return logger configuration", function()
                local mock_dispatcher = function() end
                local logger = lual.logger("test", {
                    level = core_levels.definition.INFO,
                    dispatchers = { mock_dispatcher },
                    propagate = false
                })

                local config = logger:get_config()

                assert.are.equal("test", config.name)
                assert.are.equal(core_levels.definition.INFO, config.level)
                assert.are.equal(false, config.propagate)
                assert.are.equal("_root", config.parent_name)

                -- Verify dispatchers array contains normalized dispatchers
                assert.are.equal(1, #config.dispatchers)
                verify_dispatcher(config.dispatchers[1], mock_dispatcher)
            end)

            it("should return nil parent_name for orphaned logger", function()
                local orphan_logger = lual.logger("orphan_no_parent_explicit")
                lual.reset_cache()
                local root_logger = lual.logger("_root")
                local config = root_logger:get_config()
                assert.is_nil(config.parent_name, "_root logger should have nil parent_name")
            end)
        end)
    end)

    describe("Integration with effective level calculation", function()
        it("should work with existing _get_effective_level method", function()
            local logger = lual.logger("integration.test", {
                level = core_levels.definition.DEBUG
            })

            assert.are.equal(core_levels.definition.DEBUG, logger:_get_effective_level())

            -- Change level imperatively
            logger:set_level(core_levels.definition.ERROR)
            assert.are.equal(core_levels.definition.ERROR, logger:_get_effective_level())
        end)

        it("should inherit from parent when using NOTSET", function()
            lual.reset_cache()
            local parent = lual.logger("parent_for_inherit", {
                level = core_levels.definition.WARNING
            })

            local child = lual.logger("parent_for_inherit.child")

            assert.are.equal(core_levels.definition.NOTSET, child.level)
            assert.are.equal(core_levels.definition.WARNING, child:_get_effective_level())
        end)
    end)

    describe("Default behavior alignment", function()
        it("should have correct defaults for non-root loggers", function()
            local logger = lual.logger("non.root.defaults")

            assert.are.equal(core_levels.definition.NOTSET, logger.level)
            assert.is_table(logger.dispatchers)
            assert.are.equal(0, #logger.dispatchers)
            assert.are.equal(true, logger.propagate)
        end)

        it("should have correct defaults for _root logger", function()
            lual.reset_cache()
            local root_logger = lual.logger("_root")

            assert.are.equal(core_levels.definition.WARNING, root_logger.level)
            assert.is_table(root_logger.dispatchers)
            -- assert.are.equal(0, #root_logger.dispatchers) -- This will be changed by the new default
            assert.are.equal(true, root_logger.propagate)
        end)

        it("should have a default console dispatcher for _root logger if none configured", function()
            -- Create a new root logger with default dispatchers
            local root_logger = lual.create_root_logger()

            -- Debug output: print("Root logger:", require("inspect")(root_logger))

            -- Check that we have a default console dispatcher
            assert.are.equal(1, #root_logger.dispatchers, "Root logger should have one default dispatcher")
            assert.are.equal(lual.dispatchers.console_dispatcher, root_logger.dispatchers[1].func,
                "Default dispatcher should be console")
        end)
    end)
end)
