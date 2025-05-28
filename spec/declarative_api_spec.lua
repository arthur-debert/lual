package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua;../lua/?.lua;../lua/?/init.lua"
local lualog = require("lual.logger")
local engine = require("lual.core.logging")
local spy = require("luassert.spy")
local match = require("luassert.match")

describe("Declarative API", function()
    before_each(function()
        -- Reset the logger system for each test
        package.loaded["lual.logger"] = nil
        package.loaded["lual.core.logging"] = nil
        lualog = require("lual.logger")
        engine = require("lual.core.logging")

        -- Reset the logger cache
        engine.reset_cache()
    end)

    describe("lualog.logger() - Basic functionality", function()
        it("should create a logger with minimal config", function()
            local logger = lualog.logger({
                name = "test.minimal"
            })

            assert.is_not_nil(logger)
            assert.are.same("test.minimal", logger.name)
            assert.are.same(lualog.levels.INFO, logger.level) -- Default level
            assert.is_true(logger.propagate)                  -- Default propagate
            assert.are.same(0, #logger.outputs)               -- No outputs by default
        end)

        it("should create a logger with full config", function()
            local logger = lualog.logger({
                name = "test.full",
                level = "debug",
                propagate = false,
                outputs = {
                    { type = "console", formatter = "text" },
                    { type = "file",    path = "test.log", formatter = "color" }
                }
            })

            assert.is_not_nil(logger)
            assert.are.same("test.full", logger.name)
            assert.are.same(lualog.levels.DEBUG, logger.level)
            assert.is_false(logger.propagate)
            assert.are.same(2, #logger.outputs)

            -- Check first output (console)
            local console_output = logger.outputs[1]
            assert.is_function(console_output.output_func)
            assert.is_function(console_output.formatter_func)
            assert.is_table(console_output.output_config)

            -- Check second output (file)
            local file_output = logger.outputs[2]
            assert.is_function(file_output.output_func)
            assert.is_function(file_output.formatter_func)
            assert.is_table(file_output.output_config)
            assert.are.same("test.log", file_output.output_config.path)
        end)

        it("should merge user config with defaults", function()
            local logger = lualog.logger({
                name = "test.merge",
                level = "error"
                -- propagate and outputs should use defaults
            })

            assert.are.same("test.merge", logger.name)
            assert.are.same(lualog.levels.ERROR, logger.level)
            assert.is_true(logger.propagate)    -- Default
            assert.are.same(0, #logger.outputs) -- Default empty
        end)

        it("should create parent loggers automatically", function()
            local logger = lualog.logger({
                name = "app.database.connection"
            })

            assert.is_not_nil(logger.parent)
            assert.are.same("app.database", logger.parent.name)
            assert.is_not_nil(logger.parent.parent)
            assert.are.same("app", logger.parent.parent.name)
            assert.is_not_nil(logger.parent.parent.parent)
            assert.are.same("root", logger.parent.parent.parent.name)
        end)

        it("should cache created loggers", function()
            local logger1 = lualog.logger({ name = "test.cache" })
            local logger2 = lualog.logger({ name = "test.cache" })

            -- Should return the same cached instance
            assert.are.same(logger1, logger2)
        end)
    end)

    describe("Level string conversion", function()
        it("should accept string levels (case insensitive)", function()
            local test_cases = {
                { input = "debug",    expected = lualog.levels.DEBUG },
                { input = "DEBUG",    expected = lualog.levels.DEBUG },
                { input = "info",     expected = lualog.levels.INFO },
                { input = "INFO",     expected = lualog.levels.INFO },
                { input = "warning",  expected = lualog.levels.WARNING },
                { input = "WARNING",  expected = lualog.levels.WARNING },
                { input = "error",    expected = lualog.levels.ERROR },
                { input = "ERROR",    expected = lualog.levels.ERROR },
                { input = "critical", expected = lualog.levels.CRITICAL },
                { input = "CRITICAL", expected = lualog.levels.CRITICAL },
                { input = "none",     expected = lualog.levels.NONE },
                { input = "NONE",     expected = lualog.levels.NONE }
            }

            for _, case in ipairs(test_cases) do
                local logger = lualog.logger({
                    name = "test.level." .. case.input,
                    level = case.input
                })
                assert.are.same(case.expected, logger.level, "Failed for level: " .. case.input)
            end
        end)

        it("should accept numeric levels", function()
            local logger = lualog.logger({
                name = "test.numeric.level",
                level = lualog.levels.WARNING
            })
            assert.are.same(lualog.levels.WARNING, logger.level)
        end)
    end)

    describe("Output configuration", function()
        it("should configure console output correctly", function()
            local logger = lualog.logger({
                name = "test.console",
                outputs = {
                    { type = "console", formatter = "text" }
                }
            })

            assert.are.same(1, #logger.outputs)
            local output = logger.outputs[1]
            assert.is_function(output.output_func)
            assert.is_function(output.formatter_func)
            -- Default console config should be empty (uses io.stdout by default)
            assert.is_table(output.output_config)
        end)

        it("should configure console output with custom stream", function()
            local logger = lualog.logger({
                name = "test.console.stderr",
                outputs = {
                    { type = "console", formatter = "text", stream = io.stderr }
                }
            })

            assert.are.same(1, #logger.outputs)
            local output = logger.outputs[1]
            assert.are.same(io.stderr, output.output_config.stream)
        end)

        it("should configure file output correctly", function()
            local logger = lualog.logger({
                name = "test.file",
                outputs = {
                    { type = "file", path = "app.log", formatter = "color" }
                }
            })

            assert.are.same(1, #logger.outputs)
            local output = logger.outputs[1]
            assert.is_function(output.output_func)
            assert.is_function(output.formatter_func)
            assert.are.same("app.log", output.output_config.path)
        end)

        it("should support multiple outputs", function()
            local logger = lualog.logger({
                name = "test.multiple",
                outputs = {
                    { type = "console", formatter = "color" },
                    { type = "file",    path = "debug.log", formatter = "text" },
                    { type = "console", formatter = "text", stream = io.stderr }
                }
            })

            assert.are.same(3, #logger.outputs)

            -- Check that each output is properly configured
            for i, output in ipairs(logger.outputs) do
                assert.is_function(output.output_func, "Output " .. i .. " missing output_func")
                assert.is_function(output.formatter_func, "Output " .. i .. " missing formatter_func")
                assert.is_table(output.output_config, "Output " .. i .. " missing output_config")
            end

            -- Check file output has path
            assert.are.same("debug.log", logger.outputs[2].output_config.path)
            -- Check stderr console has stream
            assert.are.same(io.stderr, logger.outputs[3].output_config.stream)
        end)

        it("should configure JSON formatter correctly", function()
            local logger = lualog.logger({
                name = "test.json",
                outputs = {
                    { type = "console", formatter = "json" },
                    { type = "file",    path = "app.json", formatter = "json" }
                }
            })

            assert.are.same(2, #logger.outputs)

            -- Check that both outputs are properly configured with JSON formatter
            for i, output in ipairs(logger.outputs) do
                assert.is_function(output.output_func, "Output " .. i .. " missing output_func")
                assert.is_function(output.formatter_func, "Output " .. i .. " missing formatter_func")
                assert.are.same(lualog.lib.json, output.formatter_func, "Output " .. i .. " should use JSON formatter")
                assert.is_table(output.output_config, "Output " .. i .. " missing output_config")
            end

            -- Check file output has path
            assert.are.same("app.json", logger.outputs[2].output_config.path)
        end)
    end)

    describe("Validation", function()
        it("should accept string names for simple logger creation", function()
            local logger = lualog.logger("test.string.name")
            assert.is_not_nil(logger)
            assert.are.same("test.string.name", logger.name)
            assert.are.same(lualog.levels.INFO, logger.level) -- Default level
            assert.is_true(logger.propagate)                  -- Default propagate
        end)

        it("should reject invalid config types (non-string, non-table)", function()
            assert.has_error(function()
                lualog.logger(123)
            end, "logger() expects nil, string, or table argument, got number")
        end)

        it("should reject unknown config keys", function()
            assert.has_error(function()
                lualog.logger({
                    name = "test",
                    unknown_key = "value"
                })
            end, "Invalid declarative config: Unknown config key: unknown_key")
        end)

        it("should reject invalid level strings", function()
            assert.has_error(function()
                    lualog.logger({
                        name = "test",
                        level = "invalid_level"
                    })
                end,
                "Invalid declarative config: Invalid level string: invalid_level. Valid levels are: critical, debug, error, info, none, warning")
        end)

        it("should reject invalid level types", function()
            assert.has_error(function()
                lualog.logger({
                    name = "test",
                    level = true
                })
            end, "Invalid declarative config: Level must be a string or number")
        end)

        it("should reject invalid name types", function()
            assert.has_error(function()
                lualog.logger({
                    name = 123
                })
            end, "Invalid declarative config: Config.name must be a string")
        end)

        it("should reject invalid propagate types", function()
            assert.has_error(function()
                lualog.logger({
                    name = "test",
                    propagate = "yes"
                })
            end, "Invalid declarative config: Config.propagate must be a boolean")
        end)

        it("should reject invalid outputs type", function()
            assert.has_error(function()
                lualog.logger({
                    name = "test",
                    outputs = "not an array"
                })
            end, "Invalid declarative config: Config.outputs must be a table")
        end)

        it("should reject outputs without type field", function()
            assert.has_error(function()
                lualog.logger({
                    name = "test",
                    outputs = {
                        { formatter = "text" }
                    }
                })
            end, "Invalid declarative config: Each output must have a 'type' string field")
        end)

        it("should reject outputs without formatter field", function()
            assert.has_error(function()
                lualog.logger({
                    name = "test",
                    outputs = {
                        { type = "console" }
                    }
                })
            end, "Invalid declarative config: Each output must have a 'formatter' string field")
        end)

        it("should reject unknown output types", function()
            assert.has_error(function()
                lualog.logger({
                    name = "test",
                    outputs = {
                        { type = "unknown", formatter = "text" }
                    }
                })
            end, "Invalid declarative config: Unknown output type: unknown. Valid types are: console, file")
        end)

        it("should reject unknown formatter types", function()
            assert.has_error(function()
                lualog.logger({
                    name = "test",
                    outputs = {
                        { type = "console", formatter = "unknown" }
                    }
                })
            end, "Invalid declarative config: Unknown formatter type: unknown. Valid types are: color, json, text")
        end)

        it("should reject file output without path", function()
            assert.has_error(function()
                lualog.logger({
                    name = "test",
                    outputs = {
                        { type = "file", formatter = "text" }
                    }
                })
            end, "Invalid declarative config: File output must have a 'path' string field")
        end)

        it("should reject file output with non-string path", function()
            assert.has_error(function()
                lualog.logger({
                    name = "test",
                    outputs = {
                        { type = "file", formatter = "text", path = 123 }
                    }
                })
            end, "Invalid declarative config: File output must have a 'path' string field")
        end)

        it("should reject console output with invalid stream type", function()
            assert.has_error(function()
                lualog.logger({
                    name = "test",
                    outputs = {
                        { type = "console", formatter = "text", stream = "stdout" }
                    }
                })
            end, "Invalid declarative config: Console output 'stream' field must be a file handle")
        end)
    end)

    describe("Integration with existing logger functionality", function()
        it("should work with logging methods", function()
            local logger = lualog.logger({
                name = "test.integration",
                level = "debug",
                outputs = {
                    { type = "console", formatter = "text" }
                }
            })

            -- These should not throw errors
            assert.is_true(pcall(function()
                logger:debug("Debug message")
                logger:info("Info message")
                logger:warn("Warning message")
                logger:error("Error message")
                logger:critical("Critical message")
            end))
        end)

        it("should work with level checking", function()
            local logger = lualog.logger({
                name = "test.level.check",
                level = "warning"
            })

            assert.is_false(logger:is_enabled_for(lualog.levels.DEBUG))
            assert.is_false(logger:is_enabled_for(lualog.levels.INFO))
            assert.is_true(logger:is_enabled_for(lualog.levels.WARNING))
            assert.is_true(logger:is_enabled_for(lualog.levels.ERROR))
            assert.is_true(logger:is_enabled_for(lualog.levels.CRITICAL))
        end)

        it("should work with imperative API methods", function()
            local logger = lualog.logger({
                name = "test.imperative",
                level = "info"
            })

            -- Should be able to use imperative methods on declaratively created logger
            logger:set_level(lualog.levels.DEBUG)
            assert.are.same(lualog.levels.DEBUG, logger.level)

            logger:add_output(lualog.lib.console, lualog.lib.text, {})
            assert.are.same(1, #logger.outputs)

            logger:set_propagate(false)
            assert.is_false(logger.propagate)
        end)

        it("should work with propagation", function()
            local parent_logger = lualog.logger({
                name = "test.parent",
                outputs = {
                    { type = "console", formatter = "text" }
                }
            })

            local child_logger = lualog.logger({
                name = "test.parent.child",
                propagate = true
            })

            local effective_outputs = child_logger:get_effective_outputs()
            -- Should include parent's output plus root's default output
            assert.is_true(#effective_outputs >= 1)

            -- Check that at least one output comes from parent
            local found_parent_output = false
            for _, output in ipairs(effective_outputs) do
                if output.owner_logger_name == "test.parent" then
                    found_parent_output = true
                    break
                end
            end
            assert.is_true(found_parent_output)
        end)
    end)


    describe("Edge cases", function()
        it("should handle empty outputs array", function()
            local logger = lualog.logger({
                name = "test.empty.outputs",
                outputs = {}
            })

            assert.are.same(0, #logger.outputs)
        end)

        it("should handle root logger creation", function()
            local logger = lualog.logger({
                name = "root",
                level = "debug"
            })

            assert.are.same("root", logger.name)
            assert.are.same(lualog.levels.DEBUG, logger.level)
            assert.is_nil(logger.parent)
        end)

        it("should handle logger without name (should default to root)", function()
            local logger = lualog.logger({
                level = "error"
            })

            assert.are.same("root", logger.name)
            assert.are.same(lualog.levels.ERROR, logger.level)
        end)
    end)
end)
