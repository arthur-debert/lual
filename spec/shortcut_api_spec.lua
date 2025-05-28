package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua;../lua/?.lua;../lua/?/init.lua"
local lualog = require("lual.logger")
local config = require("lual.config")
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

describe("Shortcut Declarative API", function()
    before_each(function()
        -- Reset the logger system for each test
        package.loaded["lual.logger"] = nil
        package.loaded["lual.core.logging"] = nil
        package.loaded["lual.config"] = nil
        lualog = require("lual.logger")
        config = require("lual.config")

        -- Reset the logger cache
        local engine = require("lual.core.logging")
        engine.reset_cache()
    end)

    describe("Detection and validation", function()
        it("should detect shortcut config format", function()
            local shortcut_config = { dispatcher = "console", presenter = "text" }
            local standard_config = { dispatchers = { { type = "console", presenter = "text" } } }

            assert.is_true(config.is_shortcut_config(shortcut_config))
            assert.is_false(config.is_shortcut_config(standard_config))
        end)

        it("should detect shortcut config with only dispatcher field", function()
            local config_table = { dispatcher = "console" }
            assert.is_true(config.is_shortcut_config(config_table))
        end)

        it("should detect shortcut config with only presenter field", function()
            local config_table = { presenter = "text" }
            assert.is_true(config.is_shortcut_config(config_table))
        end)
    end)

    describe("Basic shortcut functionality", function()
        it("should create a logger with console dispatcher using shortcut syntax", function()
            local logger = lualog.logger({
                name = "test.shortcut.console",
                dispatcher = "console",
                presenter = "text",
                level = "debug"
            })

            assert.is_not_nil(logger)
            assert.are.same("test.shortcut.console", logger.name)
            assert.are.same(lualog.levels.DEBUG, logger.level)
            assert.are.same(1, #logger.dispatchers)

            local dispatcher = logger.dispatchers[1]
            assert.is_function(dispatcher.dispatcher_func)
            assert.is_true(is_callable(dispatcher.presenter_func))
            assert.is_table(dispatcher.dispatcher_config)
        end)

        it("should create a logger with file dispatcher using shortcut syntax", function()
            local logger = lualog.logger({
                name = "test.shortcut.file",
                dispatcher = "file",
                path = "test.log",
                presenter = "color",
                level = "info"
            })

            assert.is_not_nil(logger)
            assert.are.same("test.shortcut.file", logger.name)
            assert.are.same(lualog.levels.INFO, logger.level)
            assert.are.same(1, #logger.dispatchers)

            local dispatcher = logger.dispatchers[1]
            assert.is_function(dispatcher.dispatcher_func)
            assert.is_true(is_callable(dispatcher.presenter_func))
            assert.are.same("test.log", dispatcher.dispatcher_config.path)
        end)

        it("should create a logger with minimal shortcut config", function()
            local logger = lualog.logger({
                dispatcher = "console",
                presenter = "text"
            })

            assert.is_not_nil(logger)
            assert.are.same("root", logger.name)              -- Default name
            assert.are.same(lualog.levels.INFO, logger.level) -- Default level
            assert.is_true(logger.propagate)                  -- Default propagate
            assert.are.same(1, #logger.dispatchers)
        end)

        it("should support console dispatcher with custom stream", function()
            local logger = lualog.logger({
                name = "test.shortcut.stderr",
                dispatcher = "console",
                presenter = "color",
                stream = io.stderr
            })

            assert.are.same(1, #logger.dispatchers)
            local dispatcher = logger.dispatchers[1]
            assert.are.same(io.stderr, dispatcher.dispatcher_config.stream)
        end)
    end)

    describe("Shortcut config validation", function()
        it("should reject shortcut config without dispatcher field", function()
            assert.has_error(function()
                lualog.logger({
                    presenter = "text"
                })
            end, "Invalid shortcut config: Shortcut config must have an 'dispatcher' field")
        end)

        it("should reject shortcut config without presenter field", function()
            assert.has_error(function()
                lualog.logger({
                    dispatcher = "console"
                })
            end, "Invalid shortcut config: Shortcut config must have a 'presenter' field")
        end)

        it("should reject non-string dispatcher field", function()
            assert.has_error(function()
                lualog.logger({
                    dispatcher = 123,
                    presenter = "text"
                })
            end, "Invalid shortcut config: dispatcher type must be a string")
        end)

        it("should reject non-string presenter field", function()
            assert.has_error(function()
                lualog.logger({
                    dispatcher = "console",
                    presenter = 456
                })
            end, "Invalid shortcut config: Formatter type must be a string")
        end)

        it("should reject unknown dispatcher types", function()
            local expected_error = "Invalid shortcut config: " ..
                constants.generate_expected_error_message("unknown", constants.VALID_dispatcher_TYPES)
            assert.has_error(function()
                lualog.logger({
                    dispatcher = "unknown",
                    presenter = "text"
                })
            end, expected_error)
        end)

        it("should reject unknown presenter types", function()
            local expected_error = "Invalid shortcut config: " ..
                constants.generate_expected_error_message("unknown", constants.VALID_PRESENTER_TYPES)
            assert.has_error(function()
                lualog.logger({
                    dispatcher = "console",
                    presenter = "unknown"
                })
            end, expected_error)
        end)

        it("should reject file dispatcher without path", function()
            assert.has_error(function()
                lualog.logger({
                    dispatcher = "file",
                    presenter = "text"
                })
            end, "Invalid shortcut config: File dispatcher must have a 'path' string field")
        end)

        it("should reject file dispatcher with non-string path", function()
            assert.has_error(function()
                lualog.logger({
                    dispatcher = "file",
                    presenter = "text",
                    path = 123
                })
            end, "Invalid shortcut config: File dispatcher must have a 'path' string field")
        end)

        it("should reject console dispatcher with invalid stream type", function()
            assert.has_error(function()
                lualog.logger({
                    dispatcher = "console",
                    presenter = "text",
                    stream = "stdout"
                })
            end, "Invalid shortcut config: Console dispatcher 'stream' field must be a file handle")
        end)

        it("should reject unknown shortcut config keys", function()
            assert.has_error(function()
                lualog.logger({
                    dispatcher = "console",
                    presenter = "text",
                    unknown_key = "value"
                })
            end, "Invalid shortcut config: Unknown shortcut config key: unknown_key")
        end)

        it("should reject invalid level in shortcut config", function()
            local expected_error = "Invalid shortcut config: " ..
                constants.generate_expected_error_message("invalid_level", constants.VALID_LEVEL_STRINGS)
            assert.has_error(function()
                    lualog.logger({
                        dispatcher = "console",
                        presenter = "text",
                        level = "invalid_level"
                    })
                end,
                expected_error)
        end)

        it("should reject invalid name type in shortcut config", function()
            assert.has_error(function()
                lualog.logger({
                    dispatcher = "console",
                    presenter = "text",
                    name = 123
                })
            end, "Invalid shortcut config: Config.name must be a string")
        end)

        it("should reject invalid propagate type in shortcut config", function()
            assert.has_error(function()
                lualog.logger({
                    dispatcher = "console",
                    presenter = "text",
                    propagate = "yes"
                })
            end, "Invalid shortcut config: Config.propagate must be a boolean")
        end)
    end)

    describe("Transformation to standard format", function()
        it("should transform console shortcut to standard declarative format", function()
            local shortcut = {
                name = "test",
                dispatcher = "console",
                presenter = "text",
                level = "debug",
                propagate = false
            }

            local standard = config.shortcut_to_declarative_config(shortcut)

            assert.are.same("test", standard.name)
            assert.are.same("debug", standard.level)
            assert.is_false(standard.propagate)
            assert.are.same(1, #standard.dispatchers)
            assert.are.same("console", standard.dispatchers[1].type)
            assert.are.same("text", standard.dispatchers[1].presenter)
        end)

        it("should transform file shortcut to standard declarative format", function()
            local shortcut = {
                name = "test",
                dispatcher = "file",
                path = "app.log",
                presenter = "color"
            }

            local standard = config.shortcut_to_declarative_config(shortcut)

            assert.are.same("test", standard.name)
            assert.are.same(1, #standard.dispatchers)
            assert.are.same("file", standard.dispatchers[1].type)
            assert.are.same("color", standard.dispatchers[1].presenter)
            assert.are.same("app.log", standard.dispatchers[1].path)
        end)

        it("should transform console shortcut with stream to standard format", function()
            local shortcut = {
                dispatcher = "console",
                presenter = "color",
                stream = io.stderr
            }

            local standard = config.shortcut_to_declarative_config(shortcut)

            assert.are.same(1, #standard.dispatchers)
            assert.are.same("console", standard.dispatchers[1].type)
            assert.are.same("color", standard.dispatchers[1].presenter)
            assert.are.same(io.stderr, standard.dispatchers[1].stream)
        end)
    end)

    describe("Integration with existing functionality", function()
        it("should work with logging methods", function()
            local logger = lualog.logger({
                name = "test.shortcut.integration",
                dispatcher = "console",
                presenter = "text",
                level = "debug"
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
                dispatcher = "console",
                presenter = "text",
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
                dispatcher = "console",
                presenter = "text",
                level = "info"
            })

            -- Should be able to use imperative methods on shortcut-created logger
            logger:set_level(lualog.levels.DEBUG)
            assert.are.same(lualog.levels.DEBUG, logger.level)

            logger:add_dispatcher(lualog.lib.console, lualog.lib.text, {})
            assert.are.same(2, #logger.dispatchers)

            logger:set_propagate(false)
            assert.is_false(logger.propagate)
        end)

        it("should create parent loggers automatically", function()
            local logger = lualog.logger({
                name = "app.database.connection",
                dispatcher = "console",
                presenter = "text"
            })

            assert.is_not_nil(logger.parent)
            assert.are.same("app.database", logger.parent.name)
            assert.is_not_nil(logger.parent.parent)
            assert.are.same("app", logger.parent.parent.name)
            assert.is_not_nil(logger.parent.parent.parent)
            assert.are.same("root", logger.parent.parent.parent.name)
        end)

        it("should cache created loggers", function()
            local logger1 = lualog.logger({
                name = "test.shortcut.cache",
                dispatcher = "console",
                presenter = "text"
            })
            local logger2 = lualog.logger({
                name = "test.shortcut.cache",
                dispatcher = "file",
                path = "different.log",
                presenter = "color"
            })

            -- Should return the same cached instance (first one wins)
            assert.are.same(logger1, logger2)
            -- The second config should be ignored since the logger is already cached
            assert.are.same(1, #logger2.dispatchers) -- Should still have console dispatcher, not file
        end)
    end)

    describe("Level string conversion in shortcut format", function()
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
                    name = "test.shortcut.level." .. case.input,
                    dispatcher = "console",
                    presenter = "text",
                    level = case.input
                })
                assert.are.same(case.expected, logger.level, "Failed for level: " .. case.input)
            end
        end)

        it("should accept numeric levels", function()
            local logger = lualog.logger({
                name = "test.shortcut.numeric.level",
                dispatcher = "console",
                presenter = "text",
                level = lualog.levels.WARNING
            })
            assert.are.same(lualog.levels.WARNING, logger.level)
        end)
    end)

    describe("Examples from API proposal", function()
        it("should support the exact example from the API proposal", function()
            -- Example from api.txt: {dispatcher = "console", level = "debug", presenter = "color"}
            local logger = lualog.logger({
                dispatcher = "console",
                level = "debug",
                presenter = "color"
            })

            assert.is_not_nil(logger)
            assert.are.same("root", logger.name) -- Default name
            assert.are.same(lualog.levels.DEBUG, logger.level)
            assert.are.same(1, #logger.dispatchers)

            local dispatcher = logger.dispatchers[1]
            assert.is_function(dispatcher.dispatcher_func)
            assert.is_true(is_callable(dispatcher.presenter_func))
        end)

        it("should work with named logger using shortcut syntax", function()
            local logger = lualog.logger({
                name = "app.database",
                dispatcher = "console",
                level = "debug",
                presenter = "color"
            })

            assert.are.same("app.database", logger.name)
            assert.are.same(lualog.levels.DEBUG, logger.level)
            assert.are.same(1, #logger.dispatchers)
        end)
    end)
end)
