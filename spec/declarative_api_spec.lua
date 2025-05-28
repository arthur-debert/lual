package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua;../lua/?.lua;../lua/?/init.lua"
local lualog = require("lual.logger")
local engine = require("lual.core.logging")
local spy = require("luassert.spy")
local match = require("luassert.match")
local validation = require("lual.config.validation")
local constants = require("lual.config.constants")

-- Helper function to check if something is callable (function or callable table)
local function is_callable(obj)
    if type(obj) == "function" then
        return true
    elseif type(obj) == "table" then
        local mt = getmetatable(obj)
        return mt and type(mt.__call) == "function"
    end
    return false
end

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
            assert.are.same(0, #logger.dispatchers)           -- No dispatchers by default
        end)

        it("should create a logger with full config", function()
            local logger = lualog.logger({
                name = "test.full",
                level = "debug",
                propagate = false,
                dispatchers = {
                    { type = "console", formatter = "text" },
                    { type = "file",    path = "test.log", formatter = "color" }
                }
            })

            assert.is_not_nil(logger)
            assert.are.same("test.full", logger.name)
            assert.are.same(lualog.levels.DEBUG, logger.level)
            assert.is_false(logger.propagate)
            assert.are.same(2, #logger.dispatchers)

            -- Check first dispatcher (console)
            local console_dispatcher = logger.dispatchers[1]
            assert.is_function(console_dispatcher.dispatcher_func)
            assert.is_true(is_callable(console_dispatcher.formatter_func))
            assert.is_table(console_dispatcher.dispatcher_config)

            -- Check second dispatcher (file)
            local file_dispatcher = logger.dispatchers[2]
            assert.is_function(file_dispatcher.dispatcher_func)
            assert.is_true(is_callable(file_dispatcher.formatter_func))
            assert.is_table(file_dispatcher.dispatcher_config)
            assert.are.same("test.log", file_dispatcher.dispatcher_config.path)
        end)

        it("should merge user config with defaults", function()
            local logger = lualog.logger({
                name = "test.merge",
                level = "error"
                -- propagate and dispatchers should use defaults
            })

            assert.are.same("test.merge", logger.name)
            assert.are.same(lualog.levels.ERROR, logger.level)
            assert.is_true(logger.propagate)        -- Default
            assert.are.same(0, #logger.dispatchers) -- Default empty
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

    describe("dispatcher configuration", function()
        it("should configure console dispatcher correctly", function()
            local logger = lualog.logger({
                name = "test.console",
                dispatchers = {
                    { type = "console", formatter = "text" }
                }
            })

            assert.are.same(1, #logger.dispatchers)
            local dispatcher = logger.dispatchers[1]
            assert.is_function(dispatcher.dispatcher_func)
            assert.is_true(is_callable(dispatcher.formatter_func))
            -- Default console config should be empty (uses io.stdout by default)
            assert.is_table(dispatcher.dispatcher_config)
        end)

        it("should configure console dispatcher with custom stream", function()
            local logger = lualog.logger({
                name = "test.console.stderr",
                dispatchers = {
                    { type = "console", formatter = "text", stream = io.stderr }
                }
            })

            assert.are.same(1, #logger.dispatchers)
            local dispatcher = logger.dispatchers[1]
            assert.are.same(io.stderr, dispatcher.dispatcher_config.stream)
        end)

        it("should configure file dispatcher correctly", function()
            local logger = lualog.logger({
                name = "test.file",
                dispatchers = {
                    { type = "file", path = "app.log", formatter = "color" }
                }
            })

            assert.are.same(1, #logger.dispatchers)
            local dispatcher = logger.dispatchers[1]
            assert.is_function(dispatcher.dispatcher_func)
            assert.is_true(is_callable(dispatcher.formatter_func))
            assert.are.same("app.log", dispatcher.dispatcher_config.path)
        end)

        it("should support multiple dispatchers", function()
            local logger = lualog.logger({
                name = "test.multiple",
                dispatchers = {
                    { type = "console", formatter = "color" },
                    { type = "file",    path = "debug.log", formatter = "text" },
                    { type = "console", formatter = "text", stream = io.stderr }
                }
            })

            assert.are.same(3, #logger.dispatchers)

            -- Check that each dispatcher is properly configured
            for i, dispatcher in ipairs(logger.dispatchers) do
                assert.is_function(dispatcher.dispatcher_func, "dispatcher " .. i .. " missing dispatcher_func")
                assert.is_true(is_callable(dispatcher.formatter_func), "dispatcher " .. i .. " missing formatter_func")
                assert.is_table(dispatcher.dispatcher_config, "dispatcher " .. i .. " missing dispatcher_config")
            end

            -- Check file dispatcher has path
            assert.are.same("debug.log", logger.dispatchers[2].dispatcher_config.path)
            -- Check stderr console has stream
            assert.are.same(io.stderr, logger.dispatchers[3].dispatcher_config.stream)
        end)

        it("should configure JSON formatter correctly", function()
            local logger = lualog.logger({
                name = "test.json",
                dispatchers = {
                    { type = "console", formatter = "json" },
                    { type = "file",    path = "app.json", formatter = "json" }
                }
            })

            assert.are.same(2, #logger.dispatchers)

            -- Check that both dispatchers are properly configured with JSON formatter
            for i, dispatcher in ipairs(logger.dispatchers) do
                assert.is_function(dispatcher.dispatcher_func, "dispatcher " .. i .. " missing dispatcher_func")
                assert.is_true(is_callable(dispatcher.formatter_func), "dispatcher " .. i .. " missing formatter_func")
                assert.are.same(lualog.lib.json, dispatcher.formatter_func,
                    "dispatcher " .. i .. " should use JSON formatter")
                assert.is_table(dispatcher.dispatcher_config, "dispatcher " .. i .. " missing dispatcher_config")
            end

            -- Check file dispatcher has path
            assert.are.same("app.json", logger.dispatchers[2].dispatcher_config.path)
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
            local expected_error = "Invalid declarative config: " ..
                constants.generate_expected_error_message("invalid_level", constants.VALID_LEVEL_STRINGS)
            assert.has_error(function()
                    lualog.logger({
                        name = "test",
                        level = "invalid_level"
                    })
                end,
                expected_error)
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

        it("should reject invalid dispatchers type", function()
            assert.has_error(function()
                lualog.logger({
                    name = "test",
                    dispatchers = "not an array"
                })
            end, "Invalid declarative config: Config.dispatchers must be a table")
        end)

        it("should reject dispatchers without type field", function()
            assert.has_error(function()
                lualog.logger({
                    name = "test",
                    dispatchers = {
                        { formatter = "text" }
                    }
                })
            end, "Invalid declarative config: Each dispatcher must have a 'type' string field")
        end)

        it("should reject dispatchers without formatter field", function()
            assert.has_error(function()
                lualog.logger({
                    name = "test",
                    dispatchers = {
                        { type = "console" }
                    }
                })
            end, "Invalid declarative config: Each dispatcher must have a 'formatter' string field")
        end)

        it("should reject unknown dispatcher types", function()
            local expected_error = "Invalid declarative config: " ..
                constants.generate_expected_error_message("unknown", constants.VALID_dispatcher_TYPES)
            assert.has_error(function()
                lualog.logger({
                    name = "test",
                    dispatchers = {
                        { type = "unknown", formatter = "text" }
                    }
                })
            end, expected_error)
        end)

        it("should reject unknown formatter types", function()
            local expected_error = "Invalid declarative config: " ..
                constants.generate_expected_error_message("unknown", constants.VALID_FORMATTER_TYPES)
            assert.has_error(function()
                lualog.logger({
                    name = "test",
                    dispatchers = {
                        { type = "console", formatter = "unknown" }
                    }
                })
            end, expected_error)
        end)

        it("should reject file dispatcher without path", function()
            assert.has_error(function()
                lualog.logger({
                    name = "test",
                    dispatchers = {
                        { type = "file", formatter = "text" }
                    }
                })
            end, "Invalid declarative config: File dispatcher must have a 'path' string field")
        end)

        it("should reject file dispatcher with non-string path", function()
            assert.has_error(function()
                lualog.logger({
                    name = "test",
                    dispatchers = {
                        { type = "file", formatter = "text", path = 123 }
                    }
                })
            end, "Invalid declarative config: File dispatcher must have a 'path' string field")
        end)

        it("should reject console dispatcher with invalid stream type", function()
            assert.has_error(function()
                lualog.logger({
                    name = "test",
                    dispatchers = {
                        { type = "console", formatter = "text", stream = "stdout" }
                    }
                })
            end, "Invalid declarative config: Console dispatcher 'stream' field must be a file handle")
        end)
    end)

    describe("Integration with existing logger functionality", function()
        it("should work with logging methods", function()
            local logger = lualog.logger({
                name = "test.integration",
                level = "debug",
                dispatchers = {
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

            logger:add_dispatcher(lualog.lib.console, lualog.lib.text, {})
            assert.are.same(1, #logger.dispatchers)

            logger:set_propagate(false)
            assert.is_false(logger.propagate)
        end)

        it("should work with propagation", function()
            local parent_logger = lualog.logger({
                name = "test.parent",
                dispatchers = {
                    { type = "console", formatter = "text" }
                }
            })

            local child_logger = lualog.logger({
                name = "test.parent.child",
                propagate = true
            })

            local effective_dispatchers = child_logger:get_effective_dispatchers()
            -- Should include parent's dispatcher plus root's default dispatcher
            assert.is_true(#effective_dispatchers >= 1)

            -- Check that at least one dispatcher comes from parent
            local found_parent_dispatcher = false
            for _, dispatcher in ipairs(effective_dispatchers) do
                if dispatcher.owner_logger_name == "test.parent" then
                    found_parent_dispatcher = true
                    break
                end
            end
            assert.is_true(found_parent_dispatcher)
        end)
    end)


    describe("Edge cases", function()
        it("should handle empty dispatchers array", function()
            local logger = lualog.logger({
                name = "test.empty.dispatchers",
                dispatchers = {}
            })

            assert.are.same(0, #logger.dispatchers)
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
