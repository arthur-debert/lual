#!/usr/bin/env lua
package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua;../lua/?.lua;../lua/?/init.lua"

local lual = require("lual.logger")
local core_levels = require("lua.lual.levels")
local table_utils = require("lual.utils.table")

--- Helper function to verify that a output matches the expected function
-- @param actual table The normalized output
-- @param expected_func function The expected function
-- @return boolean Whether the output matches
local function verify_output(actual, expected_func)
    assert.is_table(actual, "output should be a normalized table")
    assert.is_table(actual.config, "output should have a config table")
    assert.is_function(actual.func, "output should have a func property")
    assert.are.equal(expected_func, actual.func, "output function should match expected")
    return true
end

-- Helper function to verify if a logger has an output in its pipelines
-- @param logger table The logger to check
-- @param expected_func function The expected output function
-- @return boolean Whether the logger has the output
local function has_output_in_pipelines(logger, expected_func)
    if not logger.pipelines then
        return false
    end

    for _, pipeline in ipairs(logger.pipelines) do
        for _, output in ipairs(pipeline.outputs) do
            if output.func == expected_func then
                return true
            end
        end
    end

    return false
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
            assert.is_table(logger.pipelines)
            assert.are.equal(0, #logger.pipelines)
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
            local mock_output = function() end

            local logger = lual.logger("configured.logger", {
                level = core_levels.definition.DEBUG,
                pipelines = {
                    {
                        outputs = { mock_output },
                        presenter = lual.text
                    }
                }
                -- propagate not specified, should use default
            })

            assert.are.equal(core_levels.definition.DEBUG, logger.level)
            assert.are.equal(1, #logger.pipelines)
            assert.are.equal(1, #logger.pipelines[1].outputs)
            assert.are.equal(mock_output, logger.pipelines[1].outputs[1].func)
            assert.are.equal(true, logger.propagate) -- Default value
        end)

        it("should use defaults for unspecified settings", function()
            local logger = lual.logger("partial.config", {
                propagate = false
            })

            assert.are.equal(core_levels.definition.NOTSET, logger.level) -- Default
            assert.is_table(logger.pipelines)                             -- Default is empty table
            assert.are.equal(0, #logger.pipelines)
            assert.are.equal(false, logger.propagate)                     -- Explicitly set
        end)

        it("should handle empty configuration table", function()
            local logger = lual.logger("empty.config", {})

            assert.are.equal(core_levels.definition.NOTSET, logger.level)
            assert.is_table(logger.pipelines)
            assert.are.equal(0, #logger.pipelines)
            assert.are.equal(true, logger.propagate)
        end)

        it("should handle multiple outputs", function()
            local mock_output1 = function() end
            local mock_output2 = function() end

            local logger = lual.logger("test.outputs", {
                pipelines = {
                    {
                        outputs = { mock_output1, mock_output2 },
                        presenter = lual.text
                    }
                }
            })

            assert.are.equal("test.outputs", logger.name)
            assert.are.equal(1, #logger.pipelines)
            assert.are.equal(2, #logger.pipelines[1].outputs)

            -- Verify both outputs
            verify_output(logger.pipelines[1].outputs[1], mock_output1)
            verify_output(logger.pipelines[1].outputs[2], mock_output2)
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
                "Invalid logger configuration: Unknown configuration key 'unknown_key'. Valid keys are: level, pipelines, propagate")
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

        it("should reject outputs configuration", function()
            assert.has_error(function()
                    lual.logger("test_disptype", {
                        outputs = "not a table"
                    })
                end,
                "Invalid logger configuration: 'outputs' is no longer supported. Use 'pipelines' instead.")
        end)

        it("should reject outputs array entirely", function()
            assert.has_error(function()
                    lual.logger("test_dispitem1", {
                        outputs = { "not a function" }
                    })
                end,
                "Invalid logger configuration: 'outputs' is no longer supported. Use 'pipelines' instead.")

            assert.has_error(function()
                    lual.logger("test_dispitem2", {
                        outputs = { function() end, 123, function() end }
                    })
                end,
                "Invalid logger configuration: 'outputs' is no longer supported. Use 'pipelines' instead.")
        end)

        it("should accept empty pipelines array", function()
            assert.has_no_error(function()
                lual.logger("test_empty_pipelines_ok", {
                    pipelines = {}
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

        describe("add_output()", function()
            it("should add output to logger", function()
                local mock_output = function() end
                local logger = lual.logger("test.add_output")

                logger:add_output(mock_output)

                assert.are.equal(1, #logger.pipelines)
                assert.are.equal(1, #logger.pipelines[1].outputs)

                -- Function is now stored directly, not normalized
                assert.is_function(logger.pipelines[1].outputs[1])
                assert.are.equal(mock_output, logger.pipelines[1].outputs[1])
            end)

            it("should add output with config", function()
                local mock_output = function() end
                local logger = lual.logger("test.add_output_config")

                logger:add_output(mock_output, { level = 30, stream = "test" })

                assert.are.equal(1, #logger.pipelines)
                assert.are.equal(1, #logger.pipelines[1].outputs)

                -- Function is now stored directly, not normalized
                assert.is_function(logger.pipelines[1].outputs[1])
                assert.are.equal(mock_output, logger.pipelines[1].outputs[1])
            end)

            it("should add multiple outputs", function()
                local mock_output1 = function() end
                local mock_output2 = function() end
                local logger = lual.logger("test.add_multiple_outputs")

                logger:add_output(mock_output1)
                logger:add_output(mock_output2)

                assert.are.equal(2, #logger.pipelines)
                assert.are.equal(1, #logger.pipelines[1].outputs)
                assert.are.equal(1, #logger.pipelines[2].outputs)

                -- Functions are now stored directly, not normalized
                assert.is_function(logger.pipelines[1].outputs[1])
                assert.is_function(logger.pipelines[2].outputs[1])
                assert.are.equal(mock_output1, logger.pipelines[1].outputs[1])
                assert.are.equal(mock_output2, logger.pipelines[2].outputs[1])
            end)

            it("should reject non-function outputs", function()
                assert.has_error(function()
                    test_logger:add_output("not a function")
                end, "Output must be a function, got string")
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
                local mock_output = function() end
                local logger = lual.logger("test", {
                    level = core_levels.definition.INFO,
                    pipelines = {
                        {
                            outputs = { mock_output },
                            presenter = lual.text()
                        }
                    },
                    propagate = false
                })

                local config = logger:get_config()

                assert.are.equal("test", config.name)
                assert.are.equal(core_levels.definition.INFO, config.level)
                assert.are.equal(false, config.propagate)
                assert.are.equal("_root", config.parent_name)

                -- Verify pipelines array
                assert.are.equal(1, #config.pipelines)
                assert.are.equal(1, #config.pipelines[1].outputs)
                assert.is_function(config.pipelines[1].outputs[1].func)
                assert.are.equal(mock_output, config.pipelines[1].outputs[1].func)

                -- No backward compatibility - outputs field doesn't exist
                assert.is_nil(config.outputs)
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
            assert.is_table(logger.pipelines)
            assert.are.equal(0, #logger.pipelines)
            assert.are.equal(true, logger.propagate)
        end)

        it("should have correct defaults for _root logger", function()
            lual.reset_cache()
            local root_logger = lual.logger("_root")

            assert.are.equal(core_levels.definition.WARNING, root_logger.level)
            assert.is_table(root_logger.pipelines)
            -- assert.are.equal(0, #root_logger.outputs) -- This will be changed by the new default
            assert.are.equal(true, root_logger.propagate)
        end)

        it("should have a default console output for _root logger if none configured", function()
            -- Create a new root logger with default outputs
            local root_logger = lual.create_root_logger()

            -- Debug output: print("Root logger:", require("inspect")(root_logger))

            -- Check that we have a default pipeline with console output
            assert.is_table(root_logger.pipelines, "Root logger should have pipelines")
            assert.are.equal(1, #root_logger.pipelines, "Root logger should have one default pipeline")
            assert.is_table(root_logger.pipelines[1].outputs, "Pipeline should have outputs")
            assert.are.equal(1, #root_logger.pipelines[1].outputs, "Default pipeline should have one output")
            assert.are.equal(lual.pipeline.outputs.console_output, root_logger.pipelines[1].outputs[1].func,
                "Default output should be console")
        end)
    end)
end)
