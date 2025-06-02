package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua;../lua/?.lua;../lua/?/init.lua"
local lualog = require("lual.logger")
local config = require("lual.config")
local constants = require("lual.config.constants")
local schema = require("lual.config.schema")
local normalization = require("lual.config.normalization")

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

describe("Unified Config API", function()
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

    describe("Convenience syntax detection and transformation", function()
        it("should detect convenience syntax format", function()
            local shortcut_config = { dispatcher = "console", presenter = "text" }
            local full_config = { dispatchers = { { type = "console", presenter = "text" } } }

            assert.is_true(schema.is_convenience_syntax(shortcut_config))
            assert.is_false(schema.is_convenience_syntax(full_config))
        end)

        it("should detect convenience syntax with only dispatcher field", function()
            local config_table = { dispatcher = "console" }
            assert.is_true(schema.is_convenience_syntax(config_table))
        end)

        it("should detect convenience syntax with only presenter field", function()
            local config_table = { presenter = "text" }
            assert.is_true(schema.is_convenience_syntax(config_table))
        end)

        it("should transform console convenience syntax to full format", function()
            local shortcut = {
                name = "test",
                dispatcher = "console",
                presenter = "text",
                level = "debug",
                propagate = false
            }

            local result = normalization.convenience_to_full_config(shortcut)

            assert.are.same("test", result.name)
            assert.are.same("debug", result.level)
            assert.is_false(result.propagate)
            assert.are.same(1, #result.dispatchers)
            assert.are.same("console", result.dispatchers[1].type)
            assert.are.same("text", result.dispatchers[1].presenter)
        end)

        it("should transform file convenience syntax to full format", function()
            local shortcut = {
                name = "test",
                dispatcher = "file",
                path = "app.log",
                presenter = "color"
            }

            local result = normalization.convenience_to_full_config(shortcut)

            assert.are.same("test", result.name)
            assert.are.same(1, #result.dispatchers)
            assert.are.same("file", result.dispatchers[1].type)
            assert.are.same("color", result.dispatchers[1].presenter)
            assert.are.same("app.log", result.dispatchers[1].path)
        end)

        it("should transform console convenience syntax with stream to full format", function()
            local shortcut = {
                dispatcher = "console",
                presenter = "color",
                stream = io.stderr
            }

            local result = normalization.convenience_to_full_config(shortcut)

            assert.are.same(1, #result.dispatchers)
            assert.are.same("console", result.dispatchers[1].type)
            assert.are.same("color", result.dispatchers[1].presenter)
            assert.are.same(io.stderr, result.dispatchers[1].stream)
        end)
    end)

    describe("Basic logger creation - convenience syntax", function()
        it("should create a logger with console dispatcher using convenience syntax", function()
            local logger = lualog.logger("test.shortcut.console", {
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

        it("should create a logger with file dispatcher using convenience syntax", function()
            local logger = lualog.logger("test.shortcut.file", {
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

        it("should create a logger with minimal convenience config", function()
            local logger = lualog.logger({
                dispatcher = "console",
                presenter = "text"
            })

            assert.is_not_nil(logger)
            assert.are.same("_root", logger.name)             -- Default name
            assert.are.same(lualog.levels.INFO, logger.level) -- Default level
            assert.is_true(logger.propagate)                  -- Default propagate
            assert.are.same(1, #logger.dispatchers)
        end)

        it("should support console dispatcher with custom stream", function()
            local logger = lualog.logger("test.shortcut.stderr", {
                dispatcher = "console",
                presenter = "color",
                stream = io.stderr
            })

            assert.are.same(1, #logger.dispatchers)
            local dispatcher = logger.dispatchers[1]
            assert.are.same(io.stderr, dispatcher.dispatcher_config.stream)
        end)
    end)

    describe("Basic logger creation - full syntax", function()
        it("should create a logger with minimal config", function()
            local logger = lualog.logger("test.minimal", {})

            assert.is_not_nil(logger)
            assert.are.same("test.minimal", logger.name)
            assert.are.same(lualog.levels.INFO, logger.level) -- Default level
            assert.is_true(logger.propagate)                  -- Default propagate
            assert.are.same(0, #logger.dispatchers)           -- No dispatchers by default
        end)

        it("should create a logger with full config", function()
            local logger = lualog.logger("test.full", {
                level = "debug",
                propagate = false,
                dispatchers = {
                    { type = "console", presenter = "text" },
                    { type = "file",    path = "test.log", presenter = "color" }
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
            assert.is_true(is_callable(console_dispatcher.presenter_func))
            assert.is_table(console_dispatcher.dispatcher_config)

            -- Check second dispatcher (file)
            local file_dispatcher = logger.dispatchers[2]
            assert.is_function(file_dispatcher.dispatcher_func)
            assert.is_true(is_callable(file_dispatcher.presenter_func))
            assert.is_table(file_dispatcher.dispatcher_config)
            assert.are.same("test.log", file_dispatcher.dispatcher_config.path)
        end)

        it("should merge user config with defaults", function()
            local logger = lualog.logger("test.merge", {
                level = "error"
                -- propagate and dispatchers should use defaults
            })

            assert.are.same("test.merge", logger.name)
            assert.are.same(lualog.levels.ERROR, logger.level)
            assert.is_true(logger.propagate)        -- Default
            assert.are.same(0, #logger.dispatchers) -- Default empty
        end)
    end)

    describe("Dispatcher configuration - full syntax", function()
        it("should configure console dispatcher correctly", function()
            local logger = lualog.logger("test.console", {
                dispatchers = {
                    { type = "console", presenter = "text" }
                }
            })

            assert.are.same(1, #logger.dispatchers)
            local dispatcher = logger.dispatchers[1]
            assert.is_function(dispatcher.dispatcher_func)
            assert.is_true(is_callable(dispatcher.presenter_func))
            -- Default console config should be empty (uses io.stdout by default)
            assert.is_table(dispatcher.dispatcher_config)
        end)

        it("should configure console dispatcher with custom stream", function()
            local logger = lualog.logger("test.console.stderr", {
                dispatchers = {
                    { type = "console", presenter = "text", stream = io.stderr }
                }
            })

            assert.are.same(1, #logger.dispatchers)
            local dispatcher = logger.dispatchers[1]
            assert.are.same(io.stderr, dispatcher.dispatcher_config.stream)
        end)

        it("should configure file dispatcher correctly", function()
            local logger = lualog.logger("test.file", {
                dispatchers = {
                    { type = "file", path = "app.log", presenter = "color" }
                }
            })

            assert.are.same(1, #logger.dispatchers)
            local dispatcher = logger.dispatchers[1]
            assert.is_function(dispatcher.dispatcher_func)
            assert.is_true(is_callable(dispatcher.presenter_func))
            assert.are.same("app.log", dispatcher.dispatcher_config.path)
        end)

        it("should support multiple dispatchers", function()
            local logger = lualog.logger("test.multiple", {
                dispatchers = {
                    { type = "console", presenter = "color" },
                    { type = "file",    path = "debug.log", presenter = "text" },
                    { type = "console", presenter = "text", stream = io.stderr }
                }
            })

            assert.are.same(3, #logger.dispatchers)

            -- Check that each dispatcher is properly configured
            for i, dispatcher in ipairs(logger.dispatchers) do
                assert.is_function(dispatcher.dispatcher_func, "dispatcher " .. i .. " missing dispatcher_func")
                assert.is_true(is_callable(dispatcher.presenter_func), "dispatcher " .. i .. " missing presenter_func")
                assert.is_table(dispatcher.dispatcher_config, "dispatcher " .. i .. " missing dispatcher_config")
            end

            -- Check file dispatcher has path
            assert.are.same("debug.log", logger.dispatchers[2].dispatcher_config.path)
            -- Check stderr console has stream
            assert.are.same(io.stderr, logger.dispatchers[3].dispatcher_config.stream)
        end)

        it("should configure JSON presenter correctly", function()
            local logger = lualog.logger("test.json", {
                dispatchers = {
                    { type = "console", presenter = "json" },
                    { type = "file",    path = "app.json", presenter = "json" }
                }
            })

            assert.are.same(2, #logger.dispatchers)

            -- Check that both dispatchers are properly configured with JSON presenter
            for i, dispatcher in ipairs(logger.dispatchers) do
                assert.is_function(dispatcher.dispatcher_func, "dispatcher " .. i .. " missing dispatcher_func")
                assert.is_true(is_callable(dispatcher.presenter_func), "dispatcher " .. i .. " missing presenter_func")
                -- Check that it's using a JSON presenter (callable table or function)
                assert.is_true(is_callable(dispatcher.presenter_func),
                    "dispatcher " .. i .. " should use JSON presenter")
                assert.is_table(dispatcher.dispatcher_config, "dispatcher " .. i .. " missing dispatcher_config")
            end

            -- Check file dispatcher has path
            assert.are.same("app.json", logger.dispatchers[2].dispatcher_config.path)
        end)
    end)

    describe("Level string conversion", function()
        it("should accept string levels (case insensitive) - convenience syntax", function()
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
                local logger = lualog.logger("test.shortcut.level." .. case.input, {
                    dispatcher = "console",
                    presenter = "text",
                    level = case.input
                })
                assert.are.same(case.expected, logger.level, "Failed for level: " .. case.input)
            end
        end)

        it("should accept string levels (case insensitive) - full syntax", function()
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
                local logger = lualog.logger("test.level." .. case.input, {
                    level = case.input
                })
                assert.are.same(case.expected, logger.level, "Failed for level: " .. case.input)
            end
        end)

        it("should accept numeric levels - convenience syntax", function()
            local logger = lualog.logger("test.shortcut.numeric.level", {
                dispatcher = "console",
                presenter = "text",
                level = lualog.levels.WARNING
            })
            assert.are.same(lualog.levels.WARNING, logger.level)
        end)

        it("should accept numeric levels - full syntax", function()
            local logger = lualog.logger("test.numeric.level", {
                level = lualog.levels.WARNING
            })
            assert.are.same(lualog.levels.WARNING, logger.level)
        end)
    end)

    describe("Validation - convenience syntax", function()
        it("should reject convenience config without dispatcher field", function()
            assert.has_error(function()
                lualog.logger({
                    presenter = "text"
                })
            end, "Invalid convenience config: Convenience config must have an 'dispatcher' field")
        end)

        it("should reject convenience config without presenter field", function()
            assert.has_error(function()
                lualog.logger({
                    dispatcher = "console"
                })
            end, "Invalid convenience config: Convenience config must have a 'presenter' field")
        end)

        it("should reject non-string dispatcher field", function()
            assert.has_error(function()
                lualog.logger({
                    dispatcher = 123,
                    presenter = "text"
                })
            end, "Invalid convenience config: dispatcher type must be a string")
        end)

        it("should reject non-string presenter field", function()
            assert.has_error(function()
                lualog.logger({
                    dispatcher = "console",
                    presenter = 456
                })
            end, "Invalid convenience config: Presenter type must be a string")
        end)

        it("should reject unknown dispatcher types", function()
            local expected_error = "Invalid convenience config: " ..
                constants.generate_expected_error_message("unknown", constants.VALID_dispatcher_TYPES)
            assert.has_error(function()
                lualog.logger({
                    dispatcher = "unknown",
                    presenter = "text"
                })
            end, expected_error)
        end)

        it("should reject unknown presenter types", function()
            local expected_error = "Invalid convenience config: " ..
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
            end, "Invalid convenience config: File dispatcher must have a 'path' string field")
        end)

        it("should reject file dispatcher with non-string path", function()
            assert.has_error(function()
                lualog.logger({
                    dispatcher = "file",
                    presenter = "text",
                    path = 123
                })
            end, "Invalid convenience config: File dispatcher must have a 'path' string field")
        end)

        it("should reject console dispatcher with invalid stream type", function()
            assert.has_error(function()
                lualog.logger({
                    dispatcher = "console",
                    presenter = "text",
                    stream = "stdout"
                })
            end, "Invalid convenience config: Console dispatcher 'stream' field must be a file handle")
        end)

        it("should reject unknown convenience config keys", function()
            assert.has_error(function()
                lualog.logger({
                    dispatcher = "console",
                    presenter = "text",
                    unknown_key = "value"
                })
            end, "Invalid convenience config: Unknown convenience config key: unknown_key")
        end)

        it("should reject invalid level in convenience config", function()
            local expected_error = "Invalid convenience config: " ..
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

        it("should reject invalid propagate type in convenience config", function()
            assert.has_error(function()
                lualog.logger({
                    dispatcher = "console",
                    presenter = "text",
                    propagate = "yes"
                })
            end, "Invalid convenience config: Config.propagate must be a boolean")
        end)
    end)

    describe("Validation - full syntax", function()
        it("should accept string names for simple logger creation", function()
            local logger = lualog.logger("test.string.name")
            assert.is_not_nil(logger)
            assert.are.same("test.string.name", logger.name)
            assert.are.same(lualog.levels.INFO, logger.level) -- Default level
            assert.is_true(logger.propagate)                  -- Default propagate
        end)

        it("should reject logger names starting with underscore", function()
            assert.has_error(function()
                lualog.logger("_invalid")
            end, "Logger names starting with '_' are reserved for internal use. Please use a different name.")
        end)

        it("should reject logger names starting with underscore in two-parameter form", function()
            assert.has_error(function()
                lualog.logger("_invalid", { level = "debug" })
            end, "Logger names starting with '_' are reserved for internal use. Please use a different name.")
        end)

        it("should allow _root as a special exception", function()
            local logger = lualog.logger("_root")
            assert.is_not_nil(logger)
            assert.are.same("_root", logger.name)
        end)

        it("should reject hierarchical logger names starting with underscore", function()
            assert.has_error(function()
                lualog.logger("_internal.sub.logger")
            end, "Logger names starting with '_' are reserved for internal use. Please use a different name.")
        end)

        it("should reject invalid config types (non-string, non-table)", function()
            assert.has_error(function()
                lualog.logger(123)
            end, "logger() expects nil, string, or table argument, got number")
        end)

        it("should reject unknown config keys", function()
            assert.has_error(function()
                lualog.logger({
                    unknown_key = "value"
                })
            end, "Invalid config: Unknown config key: unknown_key")
        end)

        it("should reject invalid level strings", function()
            local expected_error = "Invalid config: " ..
                constants.generate_expected_error_message("invalid_level", constants.VALID_LEVEL_STRINGS)
            assert.has_error(function()
                    lualog.logger({
                        level = "invalid_level"
                    })
                end,
                expected_error)
        end)

        it("should reject invalid level types", function()
            assert.has_error(function()
                lualog.logger({
                    level = true
                })
            end, "Invalid config: Level must be a string or number")
        end)

        it("should reject invalid propagate types", function()
            assert.has_error(function()
                lualog.logger({
                    propagate = "yes"
                })
            end, "Invalid config: Config.propagate must be a boolean")
        end)

        it("should reject invalid dispatchers type", function()
            assert.has_error(function()
                lualog.logger({
                    dispatchers = "not an array"
                })
            end, "Invalid config: Config.dispatchers must be a table")
        end)

        it("should reject dispatchers without type field", function()
            assert.has_error(function()
                lualog.logger({
                    dispatchers = {
                        { presenter = "text" }
                    }
                })
            end, "Invalid config: Each dispatcher must have a 'type' string field")
        end)

        it("should reject dispatchers without presenter field", function()
            assert.has_error(function()
                lualog.logger({
                    dispatchers = {
                        { type = "console" }
                    }
                })
            end, "Invalid config: Each dispatcher must have a 'presenter' string field")
        end)

        it("should reject unknown dispatcher types", function()
            local expected_error = "Invalid config: " ..
                constants.generate_expected_error_message("unknown", constants.VALID_dispatcher_TYPES)
            assert.has_error(function()
                lualog.logger({
                    dispatchers = {
                        { type = "unknown", presenter = "text" }
                    }
                })
            end, expected_error)
        end)

        it("should reject unknown presenter types", function()
            local expected_error = "Invalid config: " ..
                constants.generate_expected_error_message("unknown", constants.VALID_PRESENTER_TYPES)
            assert.has_error(function()
                lualog.logger({
                    dispatchers = {
                        { type = "console", presenter = "unknown" }
                    }
                })
            end, expected_error)
        end)

        it("should reject file dispatcher without path", function()
            assert.has_error(function()
                lualog.logger({
                    dispatchers = {
                        { type = "file", presenter = "text" }
                    }
                })
            end, "Invalid config: File dispatcher must have a 'path' string field")
        end)

        it("should reject file dispatcher with non-string path", function()
            assert.has_error(function()
                lualog.logger({
                    dispatchers = {
                        { type = "file", presenter = "text", path = 123 }
                    }
                })
            end, "Invalid config: File dispatcher must have a 'path' string field")
        end)

        it("should reject console dispatcher with invalid stream type", function()
            assert.has_error(function()
                lualog.logger({
                    dispatchers = {
                        { type = "console", presenter = "text", stream = "stdout" }
                    }
                })
            end, "Invalid config: Console dispatcher 'stream' field must be a file handle")
        end)
    end)

    describe("Common functionality", function()
        it("should create parent loggers automatically", function()
            -- First configure a root logger to enable full hierarchy
            lualog.config({ level = "info" })

            local logger = lualog.logger("app.database.connection", {})

            assert.is_not_nil(logger.parent)
            assert.are.same("app.database", logger.parent.name)
            assert.is_not_nil(logger.parent.parent)
            assert.are.same("app", logger.parent.parent.name)
            assert.is_not_nil(logger.parent.parent.parent)
            assert.are.same("_root", logger.parent.parent.parent.name)
        end)

        it("should cache created loggers", function()
            local logger1 = lualog.logger("test.cache", {})
            local logger2 = lualog.logger("test.cache", {})

            -- Should return the same cached instance
            assert.are.same(logger1, logger2)
        end)

        it("should work with logging methods - convenience syntax", function()
            local logger = lualog.logger("test.shortcut.integration", {
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

        it("should work with logging methods - full syntax", function()
            local logger = lualog.logger("test.integration", {
                level = "debug",
                dispatchers = {
                    { type = "console", presenter = "text" }
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
            local logger = lualog.logger("test.level.check", {
                level = "warning"
            })

            assert.is_false(logger:is_enabled_for(lualog.levels.DEBUG))
            assert.is_false(logger:is_enabled_for(lualog.levels.INFO))
            assert.is_true(logger:is_enabled_for(lualog.levels.WARNING))
            assert.is_true(logger:is_enabled_for(lualog.levels.ERROR))
            assert.is_true(logger:is_enabled_for(lualog.levels.CRITICAL))
        end)

        it("should work with imperative API methods", function()
            local logger = lualog.logger("test.imperative", {
                level = "info"
            })

            -- Should be able to use imperative methods on config-created logger
            logger:set_level(lualog.levels.DEBUG)
            assert.are.same(lualog.levels.DEBUG, logger.level)

            -- Use the dispatchers and presenters directly from the modules
            local all_dispatchers = require("lual.dispatchers.init")
            local all_presenters = require("lual.presenters.init")
            logger:add_dispatcher(all_dispatchers.console_dispatcher, all_presenters.text(), {})
            assert.are.same(1, #logger.dispatchers)

            logger:set_propagate(false)
            assert.is_false(logger.propagate)
        end)

        it("should work with propagation", function()
            local parent_logger = lualog.logger("test.parent", {
                dispatchers = {
                    { type = "console", presenter = "text" }
                }
            })

            local child_logger = lualog.logger("test.parent.child", {
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
            local logger = lualog.logger("test.empty.dispatchers", {
                dispatchers = {}
            })

            assert.are.same(0, #logger.dispatchers)
        end)

        it("should handle root logger creation", function()
            local logger = lualog.logger("_root", {
                level = "debug"
            })

            assert.are.same("_root", logger.name)
            assert.are.same(lualog.levels.DEBUG, logger.level)
            assert.is_nil(logger.parent)
        end)

        it("should handle logger without name (should default to _root)", function()
            local logger = lualog.logger({
                level = "error"
            })

            assert.are.same("_root", logger.name)
            assert.are.same(lualog.levels.ERROR, logger.level)
        end)
    end)

    describe("Examples from API", function()
        it("should support the exact convenience syntax example", function()
            -- Example: {dispatcher = "console", level = "debug", presenter = "color"}
            local logger = lualog.logger({
                dispatcher = "console",
                level = "debug",
                presenter = "color"
            })

            assert.is_not_nil(logger)
            assert.are.same("_root", logger.name) -- Default name
            assert.are.same(lualog.levels.DEBUG, logger.level)
            assert.are.same(1, #logger.dispatchers)

            local dispatcher = logger.dispatchers[1]
            assert.is_function(dispatcher.dispatcher_func)
            assert.is_true(is_callable(dispatcher.presenter_func))
        end)

        it("should work with named logger using convenience syntax", function()
            local logger = lualog.logger("app.database", {
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
