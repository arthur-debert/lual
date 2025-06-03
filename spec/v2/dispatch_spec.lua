#!/usr/bin/env lua
package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua;../lua/?.lua;../lua/?/init.lua"

local lual = require("lual.logger")
local core_levels = require("lua.lual.levels")
local console_dispatcher = require("lual.dispatchers.console_dispatcher")
local file_dispatcher = require("lual.dispatchers.file_dispatcher")
local syslog_dispatcher = require("lual.dispatchers.syslog_dispatcher")
local all_presenters = require("lual.presenters.init") -- For presenter tests

-- Helper function to check if a file exists
local function file_exists(path)
    local file = io.open(path, "r")
    if file then
        file:close()
        return true
    end
    return false
end

describe("Dispatch Loop Logic (Step 2.7)", function()
    before_each(function()
        -- Reset config and logger cache for each test
        lual.reset_config()
        lual.reset_cache()
    end)

    describe("Basic logging methods", function()
        it("should have all logging methods available", function()
            local logger = lual.logger("test.methods")

            assert.is_function(logger.debug)
            assert.is_function(logger.info)
            assert.is_function(logger.warn)
            assert.is_function(logger.error)
            assert.is_function(logger.critical)
            assert.is_function(logger.log)
        end)

        it("should not output when level is not enabled", function()
            local output_captured = {}
            local mock_dispatcher = function(record)
                table.insert(output_captured, record)
            end

            local logger = lual.logger("test.level.check", {
                level = core_levels.definition.WARNING,
                dispatchers = { mock_dispatcher }
            })

            -- DEBUG and INFO should not be dispatched (below WARNING)
            logger:debug("Debug message")
            logger:info("Info message")

            assert.are.equal(0, #output_captured, "No messages should be dispatched below WARNING level")

            -- WARNING should be dispatched
            logger:warn("Warning message")
            assert.are.equal(1, #output_captured, "WARNING message should be dispatched")
        end)

        it("should use effective level for checking", function()
            local output_captured = {}
            local mock_dispatcher = function(record)
                table.insert(output_captured, record)
            end

            -- Set root config to ERROR
            lual.config({ level = core_levels.definition.ERROR })

            -- Create child logger with NOTSET (inherits ERROR from root)
            local child_logger = lual.logger("inherits.error", {
                dispatchers = { mock_dispatcher }
            })

            -- Should inherit ERROR level from root
            assert.are.equal(core_levels.definition.NOTSET, child_logger.level)
            assert.are.equal(core_levels.definition.ERROR, child_logger:_get_effective_level())

            -- DEBUG, INFO, WARNING should not be dispatched
            child_logger:debug("Debug message")
            child_logger:info("Info message")
            child_logger:warn("Warning message")
            assert.are.equal(0, #output_captured, "Messages below ERROR should not be dispatched")

            -- ERROR should be dispatched
            child_logger:error("Error message")
            assert.are.equal(1, #output_captured, "ERROR message should be dispatched")
        end)
    end)

    describe("Dispatch loop hierarchy processing", function()
        it("should dispatch through logger's own dispatchers when level matches", function()
            local child_output = {}
            local parent_output = {}

            local child_dispatcher = function(record)
                table.insert(child_output, record)
            end

            local parent_dispatcher = function(record)
                table.insert(parent_output, record)
            end

            -- Create hierarchy with dispatchers
            local parent_logger = lual.logger("parent", {
                level = core_levels.definition.DEBUG,
                dispatchers = { parent_dispatcher }
            })

            local child_logger = lual.logger("parent.child", {
                level = core_levels.definition.DEBUG,
                dispatchers = { child_dispatcher }
            })

            -- Log through child
            child_logger:info("Test message")

            -- Both child and parent should receive the message (propagation)
            assert.are.equal(1, #child_output, "Child dispatcher should receive message")
            assert.are.equal(1, #parent_output, "Parent dispatcher should receive message via propagation")

            -- Check that records have correct owner information
            assert.are.equal("parent.child", child_output[1].owner_logger_name)
            assert.are.equal("parent", parent_output[1].owner_logger_name)
        end)

        it("should not dispatch when logger level doesn't match", function()
            local high_level_output = {}
            local low_level_output = {}

            local high_level_dispatcher = function(record)
                table.insert(high_level_output, record)
            end

            local low_level_dispatcher = function(record)
                table.insert(low_level_output, record)
            end

            -- Create hierarchy with different levels
            local parent_logger = lual.logger("parent", {
                level = core_levels.definition.ERROR, -- Only ERROR and above
                dispatchers = { high_level_dispatcher }
            })

            local child_logger = lual.logger("parent.child", {
                level = core_levels.definition.DEBUG, -- All messages
                dispatchers = { low_level_dispatcher }
            })

            -- Log INFO message through child
            child_logger:info("Info message")

            -- Child should receive it (DEBUG <= INFO), parent should not (ERROR > INFO)
            assert.are.equal(1, #low_level_output, "Child dispatcher should receive INFO message")
            assert.are.equal(0, #high_level_output, "Parent dispatcher should not receive INFO message")

            -- Log ERROR message through child
            child_logger:error("Error message")

            -- Both should receive ERROR message
            assert.are.equal(2, #low_level_output, "Child dispatcher should receive ERROR message")
            assert.are.equal(1, #high_level_output, "Parent dispatcher should receive ERROR message")
        end)

        it("should stop propagation when propagate is false", function()
            local child_output = {}
            local parent_output = {}

            local child_dispatcher = function(record)
                table.insert(child_output, record)
            end

            local parent_dispatcher = function(record)
                table.insert(parent_output, record)
            end

            -- Create hierarchy with propagate = false on child
            local parent_logger = lual.logger("parent", {
                level = core_levels.definition.DEBUG,
                dispatchers = { parent_dispatcher }
            })

            local child_logger = lual.logger("parent.child", {
                level = core_levels.definition.DEBUG,
                dispatchers = { child_dispatcher },
                propagate = false -- Stop propagation
            })

            -- Log through child
            child_logger:info("Test message")

            -- Only child should receive the message
            assert.are.equal(1, #child_output, "Child dispatcher should receive message")
            assert.are.equal(0, #parent_output, "Parent dispatcher should not receive message (propagate=false)")
        end)

        it("should stop propagation at _root", function()
            local root_output = {}
            local child_output = {}

            local root_dispatcher = function(record)
                table.insert(root_output, record)
            end

            local child_dispatcher = function(record)
                table.insert(child_output, record)
            end

            -- Configure root logger manually
            lual.config({
                level = core_levels.definition.DEBUG,
                dispatchers = { root_dispatcher }
            })

            -- Create child logger
            local child_logger = lual.logger("child", {
                level = core_levels.definition.DEBUG,
                dispatchers = { child_dispatcher }
            })

            -- Log through child
            child_logger:info("Test message")

            -- Both child and root should receive message, but propagation stops at root
            assert.are.equal(1, #child_output, "Child dispatcher should receive message")
            assert.are.equal(1, #root_output, "Root dispatcher should receive message")

            -- Verify record ownership
            assert.are.equal("child", child_output[1].owner_logger_name)
            assert.are.equal("_root", root_output[1].owner_logger_name)
        end)

        it("should handle loggers with no dispatchers", function()
            local parent_output = {}

            local parent_dispatcher = function(record)
                table.insert(parent_output, record)
            end

            -- Create hierarchy where child has no dispatchers
            local parent_logger = lual.logger("parent", {
                level = core_levels.definition.DEBUG,
                dispatchers = { parent_dispatcher }
            })

            local child_logger = lual.logger("parent.child", {
                level = core_levels.definition.DEBUG
                -- No dispatchers specified
            })

            -- Log through child
            child_logger:info("Test message")

            -- Child produces no output itself, but parent should receive via propagation
            assert.are.equal(1, #parent_output, "Parent dispatcher should receive message via propagation")
            assert.are.equal("parent", parent_output[1].owner_logger_name)
        end)
    end)

    describe("Log record creation and content", function()
        it("should create properly formatted log records", function()
            local captured_record = nil
            local mock_dispatcher = function(record)
                captured_record = record
            end

            local logger = lual.logger("record.test", {
                level = core_levels.definition.DEBUG,
                dispatchers = { mock_dispatcher }
            })

            logger:info("Test message %s %d", "arg1", 42)

            assert.is_not_nil(captured_record)
            assert.are.equal(core_levels.definition.INFO, captured_record.level_no)
            assert.are.equal("INFO", captured_record.level_name)
            assert.are.equal("Test message %s %d", captured_record.message_fmt)
            assert.are.equal("record.test", captured_record.logger_name)
            assert.are.equal("record.test", captured_record.source_logger_name)
            assert.is_number(captured_record.timestamp)
            assert.is_string(captured_record.filename)
            assert.is_number(captured_record.lineno)

            -- Check args
            assert.is_table(captured_record.args)
            assert.are.equal(2, captured_record.args.n)
            assert.are.equal("arg1", captured_record.args[1])
            assert.are.equal(42, captured_record.args[2])

            -- Check owner logger context
            assert.are.equal("record.test", captured_record.owner_logger_name)
            assert.are.equal(core_levels.definition.DEBUG, captured_record.owner_logger_level)
            assert.are.equal(true, captured_record.owner_logger_propagate)
        end)

        it("should handle context-based logging", function()
            local captured_record = nil
            local mock_dispatcher = function(record)
                captured_record = record
            end

            local logger = lual.logger("context.test", {
                level = core_levels.definition.DEBUG,
                dispatchers = { mock_dispatcher }
            })

            local context = { user_id = 123, action = "login" }
            logger:info(context, "User performed action: %s", "login")

            assert.is_not_nil(captured_record)
            assert.are.same(context, captured_record.context)
            assert.are.equal("User performed action: %s", captured_record.message_fmt)
            assert.are.equal(1, captured_record.args.n)
            assert.are.equal("login", captured_record.args[1])
        end)

        it("should handle context-only logging", function()
            local captured_record = nil
            local mock_dispatcher = function(record)
                captured_record = record
            end

            local logger = lual.logger("context.only.test", {
                level = core_levels.definition.DEBUG,
                dispatchers = { mock_dispatcher }
            })

            local context = { event = "SystemRestart", reason = "Update" }
            logger:info(context)

            assert.is_not_nil(captured_record)
            assert.are.same(context, captured_record.context)
            assert.are.equal("", captured_record.message_fmt)
            assert.are.equal(0, captured_record.args.n)
        end)
    end)

    describe("Deep hierarchy testing", function()
        it("should properly propagate through deep hierarchy", function()
            local outputs = {
                level1 = {},
                level2 = {},
                level3 = {},
                level4 = {}
            }

            -- Create dispatchers for each level
            local dispatchers = {}
            for level, output in pairs(outputs) do
                dispatchers[level] = function(record)
                    table.insert(output, record)
                end
            end

            -- Create deep hierarchy: level1 -> level2 -> level3 -> level4
            local level1 = lual.logger("level1", {
                level = core_levels.definition.DEBUG,
                dispatchers = { dispatchers.level1 }
            })

            local level2 = lual.logger("level1.level2", {
                level = core_levels.definition.DEBUG,
                dispatchers = { dispatchers.level2 }
            })

            local level3 = lual.logger("level1.level2.level3", {
                level = core_levels.definition.DEBUG,
                dispatchers = { dispatchers.level3 }
            })

            local level4 = lual.logger("level1.level2.level3.level4", {
                level = core_levels.definition.DEBUG,
                dispatchers = { dispatchers.level4 }
            })

            -- Log from deepest level
            level4:info("Deep message")

            -- All levels should receive the message
            assert.are.equal(1, #outputs.level4, "Level4 should receive message")
            assert.are.equal(1, #outputs.level3, "Level3 should receive message")
            assert.are.equal(1, #outputs.level2, "Level2 should receive message")
            assert.are.equal(1, #outputs.level1, "Level1 should receive message")

            -- Check owner logger names
            assert.are.equal("level1.level2.level3.level4", outputs.level4[1].owner_logger_name)
            assert.are.equal("level1.level2.level3", outputs.level3[1].owner_logger_name)
            assert.are.equal("level1.level2", outputs.level2[1].owner_logger_name)
            assert.are.equal("level1", outputs.level1[1].owner_logger_name)
        end)

        it("should handle mixed propagation settings in hierarchy", function()
            local outputs = {
                level1 = {},
                level2 = {},
                level3 = {},
                level4 = {}
            }

            local dispatchers = {}
            for level, output in pairs(outputs) do
                dispatchers[level] = function(record)
                    table.insert(output, record)
                end
            end

            -- Create hierarchy with mixed propagation settings
            local level1 = lual.logger("mixed1", {
                level = core_levels.definition.DEBUG,
                dispatchers = { dispatchers.level1 },
                propagate = true
            })

            local level2 = lual.logger("mixed1.mixed2", {
                level = core_levels.definition.DEBUG,
                dispatchers = { dispatchers.level2 },
                propagate = false -- Stop propagation here
            })

            local level3 = lual.logger("mixed1.mixed2.mixed3", {
                level = core_levels.definition.DEBUG,
                dispatchers = { dispatchers.level3 },
                propagate = true
            })

            local level4 = lual.logger("mixed1.mixed2.mixed3.mixed4", {
                level = core_levels.definition.DEBUG,
                dispatchers = { dispatchers.level4 },
                propagate = true
            })

            -- Log from deepest level
            level4:info("Mixed propagation message")

            -- Level4, Level3, and Level2 should receive message
            -- Level1 should not (stopped at Level2)
            assert.are.equal(1, #outputs.level4, "Level4 should receive message")
            assert.are.equal(1, #outputs.level3, "Level3 should receive message")
            assert.are.equal(1, #outputs.level2, "Level2 should receive message")
            assert.are.equal(0, #outputs.level1, "Level1 should not receive message (propagation stopped)")
        end)
    end)

    describe("Generic log method", function()
        it("should work with numeric log levels", function()
            local captured_record = nil
            local mock_dispatcher = function(record)
                captured_record = record
            end

            local logger = lual.logger("generic.test", {
                level = core_levels.definition.DEBUG,
                dispatchers = { mock_dispatcher }
            })

            logger:log(core_levels.definition.WARNING, "Warning via log method")

            assert.is_not_nil(captured_record)
            assert.are.equal(core_levels.definition.WARNING, captured_record.level_no)
            assert.are.equal("WARNING", captured_record.level_name)
            assert.are.equal("Warning via log method", captured_record.message_fmt)
        end)

        it("should reject invalid log level types", function()
            local logger = lual.logger("invalid.level.test")

            assert.has_error(function()
                logger:log("warning", "Invalid level type")
            end, "Log level must be a number, got string")
        end)

        it("should respect level checking for generic log method", function()
            local output_captured = {}
            local mock_dispatcher = function(record)
                table.insert(output_captured, record)
            end

            local logger = lual.logger("generic.level.test", {
                level = core_levels.definition.WARNING,
                dispatchers = { mock_dispatcher }
            })

            -- Below WARNING level should not be dispatched
            logger:log(core_levels.definition.DEBUG, "Debug via log method")
            logger:log(core_levels.definition.INFO, "Info via log method")

            assert.are.equal(0, #output_captured, "Messages below WARNING should not be dispatched")

            -- WARNING and above should be dispatched
            logger:log(core_levels.definition.WARNING, "Warning via log method")
            logger:log(core_levels.definition.ERROR, "Error via log method")

            assert.are.equal(2, #output_captured, "WARNING and ERROR messages should be dispatched")
        end)
    end)
end)

describe("Presenter Configuration in Dispatchers", function()
    local captured_record_for_presenter_test

    local mock_dispatcher_func = function(record)
        captured_record_for_presenter_test = record
    end

    before_each(function()
        lual.reset_config()
        lual.reset_cache()
        captured_record_for_presenter_test = nil
    end)

    it("should use 'text' presenter when configured as string 'text'", function()
        local logger = lual.logger("presenter.text.string", {
            level = lual.levels.DEBUG,
            dispatchers = {
                { dispatcher_func = mock_dispatcher_func, config = { presenter = "text" } }
            }
        })
        logger:info("Hello text presenter")

        assert.is_not_nil(captured_record_for_presenter_test, "Dispatcher was not called")
        assert.is_string(captured_record_for_presenter_test.presented_message)
        -- Basic check, text presenter usually includes level, logger name, and message
        assert.matches("INFO", captured_record_for_presenter_test.presented_message)
        assert.matches("presenter.text.string", captured_record_for_presenter_test.presented_message)
        assert.matches("Hello text presenter", captured_record_for_presenter_test.presented_message)
    end)

    it("should use 'json' presenter when configured as string 'json'", function()
        local logger = lual.logger("presenter.json.string", {
            level = lual.levels.DEBUG,
            dispatchers = {
                { dispatcher_func = mock_dispatcher_func, config = { presenter = "json" } }
            }
        })
        logger:info("Hello json presenter")

        assert.is_not_nil(captured_record_for_presenter_test, "Dispatcher was not called")
        assert.is_string(captured_record_for_presenter_test.presented_message)
        -- Check for JSON structure (basic check: starts with { and ends with })
        assert.matches("^{.*}$", captured_record_for_presenter_test.presented_message)
        assert.matches("\"message\":\"Hello json presenter\"", captured_record_for_presenter_test.presented_message)
        -- Default JSON is compact (no newlines)
        assert.is_nil(captured_record_for_presenter_test.presented_message:match("\n"))
    end)

    it("should use 'json' presenter with pretty print when configured via table with type and config", function()
        local logger = lual.logger("presenter.json.table.pretty", {
            level = lual.levels.DEBUG,
            dispatchers = {
                { dispatcher_func = mock_dispatcher_func, config = { presenter = { type = "json", config = { pretty = true } } } }
            }
        })
        logger:info("Hello pretty json")

        assert.is_not_nil(captured_record_for_presenter_test, "Dispatcher was not called")
        assert.is_string(captured_record_for_presenter_test.presented_message)
        assert.matches("^{.*}$", captured_record_for_presenter_test.presented_message)
        assert.matches("\"message\": \"Hello pretty json\"", captured_record_for_presenter_test.presented_message)
        -- Pretty JSON should have newlines
        assert.is_not_nil(captured_record_for_presenter_test.presented_message:match("\n"))
    end)

    it("should use 'json' presenter (compact) when configured via table with type and empty/no config", function()
        local logger = lual.logger("presenter.json.table.noconf", {
            level = lual.levels.DEBUG,
            dispatchers = {
                { dispatcher_func = mock_dispatcher_func, config = { presenter = { type = "json", config = {} } } }
            }
        })
        logger:info("Hello json no config")

        assert.is_not_nil(captured_record_for_presenter_test, "Dispatcher was not called")
        assert.is_string(captured_record_for_presenter_test.presented_message)
        assert.matches("^{.*}$", captured_record_for_presenter_test.presented_message)
        assert.matches("\"message\":\"Hello json no config\"", captured_record_for_presenter_test.presented_message)
        assert.is_nil(captured_record_for_presenter_test.presented_message:match("\n"))

        -- Test with presenter = { type = "json" } (config field completely missing)
        captured_record_for_presenter_test = nil
        local logger2 = lual.logger("presenter.json.table.missingconf", {
            level = lual.levels.DEBUG,
            dispatchers = {
                { dispatcher_func = mock_dispatcher_func, config = { presenter = { type = "json" } } }
            }
        })
        logger2:info("Hello json missing config field")
        assert.is_not_nil(captured_record_for_presenter_test, "Dispatcher was not called (logger2)")
        assert.is_string(captured_record_for_presenter_test.presented_message)
        assert.matches("^{.*}$", captured_record_for_presenter_test.presented_message)
        assert.matches("\"message\":\"Hello json missing config field\"", captured_record_for_presenter_test.presented_message)
        assert.is_nil(captured_record_for_presenter_test.presented_message:match("\n"))
    end)

    it("should use a direct function as presenter", function()
        local custom_presenter = function(record)
            return string.format("CUSTOM PRESENTATION: %s - %s", record.level_name, record.message)
        end
        local logger = lual.logger("presenter.function", {
            level = lual.levels.DEBUG,
            dispatchers = {
                { dispatcher_func = mock_dispatcher_func, config = { presenter = custom_presenter } }
            }
        })
        logger:info("Hello custom function presenter")

        assert.is_not_nil(captured_record_for_presenter_test, "Dispatcher was not called")
        assert.are.equal("CUSTOM PRESENTATION: INFO - Hello custom function presenter", captured_record_for_presenter_test.presented_message)
    end)

    it("should handle unknown presenter type string gracefully", function()
        local stderr_spy = spy.new(function() end)
        local old_stderr_write = io.stderr.write
        io.stderr.write = stderr_spy

        local logger = lual.logger("presenter.unknown.string", {
            level = lual.levels.DEBUG,
            dispatchers = {
                { dispatcher_func = mock_dispatcher_func, config = { presenter = "nonexistent_presenter" } }
            }
        })
        logger:info("Hello unknown presenter")

        assert.is_not_nil(captured_record_for_presenter_test, "Dispatcher was not called")
        -- Message should remain unformatted if presenter fails to load
        assert.are.equal("Hello unknown presenter", captured_record_for_presenter_test.message)
        assert.is_nil(captured_record_for_presenter_test.presented_message)
        assert.is_string(captured_record_for_presenter_test.presenter_error)
        assert.matches("Presenter type not found: nonexistent_presenter", captured_record_for_presenter_test.presenter_error)
        assert.spy(stderr_spy).was.called_with(match.is_string(match.contains("LUAL: Presenter type 'nonexistent_presenter' not found.")))

        io.stderr.write = old_stderr_write -- Restore
    end)

    it("should handle unknown presenter type in table config gracefully", function()
        local stderr_spy = spy.new(function() end)
        local old_stderr_write = io.stderr.write
        io.stderr.write = stderr_spy

        local logger = lual.logger("presenter.unknown.table", {
            level = lual.levels.DEBUG,
            dispatchers = {
                { dispatcher_func = mock_dispatcher_func, config = { presenter = { type = "super_unknown_presenter" } } }
            }
        })
        logger:info("Hello unknown table presenter")

        assert.is_not_nil(captured_record_for_presenter_test, "Dispatcher was not called")
        assert.are.equal("Hello unknown table presenter", captured_record_for_presenter_test.message)
        assert.is_nil(captured_record_for_presenter_test.presented_message)
        assert.is_string(captured_record_for_presenter_test.presenter_error)
        assert.matches("Presenter type not found: super_unknown_presenter", captured_record_for_presenter_test.presenter_error)
        assert.spy(stderr_spy).was.called_with(match.is_string(match.contains("LUAL: Presenter type 'super_unknown_presenter' not found.")))

        io.stderr.write = old_stderr_write -- Restore
    end)

     it("should use raw message if presenter function errors", function()
        local stderr_spy = spy.new(function() end)
        local old_stderr_write = io.stderr.write
        io.stderr.write = stderr_spy

        local erroring_presenter = function()
            error("Simulated presenter error")
        end
        local logger = lual.logger("presenter.erroring.func", {
            level = lual.levels.DEBUG,
            dispatchers = {
                { dispatcher_func = mock_dispatcher_func, config = { presenter = erroring_presenter } }
            }
        })
        logger:info("Message for erroring presenter")

        assert.is_not_nil(captured_record_for_presenter_test, "Dispatcher was not called")
        assert.are.equal("Message for erroring presenter", captured_record_for_presenter_test.message)
        assert.is_nil(captured_record_for_presenter_test.presented_message)
        assert.is_string(captured_record_for_presenter_test.presenter_error)
        assert.matches("Simulated presenter error", captured_record_for_presenter_test.presenter_error)
        assert.spy(stderr_spy).was.called_with(match.is_string(match.contains("LUAL: Error in presenter function")))

        io.stderr.write = old_stderr_write -- Restore
    end)
end)

describe("lual Dispatchers", function()
    -- Sample log record for testing
    local sample_record = {
        timestamp = os.time(),
        level_name = "INFO",
        logger_name = "test.logger",
        message_fmt = "User %s logged in from %s",
        args = { "jane.doe", "10.0.0.1" },
        context = { user_id = 123, action = "login" },
        presented_message = "2024-03-15 10:00:00 INFO [test.logger] User jane.doe logged in from 10.0.0.1"
    }

    describe("Console Dispatcher", function()
        it("should write to stdout by default", function()
            -- Capture stdout
            local old_stdout = io.stdout
            local output = {}
            io.stdout = {
                write = function(_, str) table.insert(output, str) end,
                flush = function() end
            }

            console_dispatcher(sample_record)

            -- Restore stdout
            io.stdout = old_stdout

            -- Verify output
            assert.is_true(#output >= 2) -- Message + newline
            assert.matches("User jane.doe logged in from 10.0.0.1", output[1])
        end)

        it("should write to specified stream", function()
            local output = {}
            local mock_stream = {
                write = function(_, str) table.insert(output, str) end,
                flush = function() end
            }

            console_dispatcher(sample_record, { stream = mock_stream })

            assert.is_true(#output >= 2) -- Message + newline
            assert.matches("User jane.doe logged in from 10.0.0.1", output[1])
        end)

        it("should handle string messages", function()
            local output = {}
            local mock_stream = {
                write = function(_, str) table.insert(output, str) end,
                flush = function() end
            }

            console_dispatcher("Direct string message", { stream = mock_stream })

            assert.are.equal("Direct string message", output[1])
            assert.are.equal("\n", output[2])
        end)

        it("should handle errors gracefully", function()
            local stderr_output = {}
            local old_stderr = io.stderr
            io.stderr = {
                write = function(_, str) table.insert(stderr_output, str) end
            }

            local failing_stream = {
                write = function() error("Write failed") end,
                flush = function() end
            }

            console_dispatcher(sample_record, { stream = failing_stream })

            io.stderr = old_stderr

            assert.matches("Error writing to stream", stderr_output[1])
        end)
    end)

    describe("File Dispatcher", function()
        local test_log = "test.log"

        after_each(function()
            os.remove(test_log)
            for i = 1, 5 do
                os.remove(test_log .. "." .. i)
            end
        end)

        it("should create and write to log file", function()
            local dispatcher = file_dispatcher({ path = test_log })
            dispatcher(sample_record)

            -- Read the file content
            local file = io.open(test_log, "r")
            local content = file:read("*all")
            file:close()

            assert.matches("User jane.doe logged in from 10.0.0.1", content)
        end)

        it("should handle rotation", function()
            -- Create initial log file
            local file = io.open(test_log, "w")
            file:write("initial log content")
            file:close()

            -- Create some backup files
            for i = 1, 3 do
                local file = io.open(test_log .. "." .. i, "w")
                file:write("old log " .. i)
                file:close()
            end

            -- Create the dispatcher (this triggers rotation)
            local dispatcher = file_dispatcher({ path = test_log })

            -- Write to the main log
            dispatcher(sample_record)

            -- Give the file system a moment to complete operations
            os.execute("sleep 0.1")

            -- Verify rotation
            assert.is_true(file_exists(test_log), "Main log file should exist")
            assert.is_true(file_exists(test_log .. ".1"), "First backup should exist")
            assert.is_true(file_exists(test_log .. ".2"), "Second backup should exist")
            assert.is_true(file_exists(test_log .. ".3"), "Third backup should exist")
            assert.is_true(file_exists(test_log .. ".4"), "Fourth backup should exist")

            -- Verify content
            local file = io.open(test_log, "r")
            local content = file:read("*all")
            file:close()
            assert.matches("User jane.doe logged in from 10.0.0.1", content)

            -- Verify backup content
            local backup = io.open(test_log .. ".1", "r")
            local backup_content = backup:read("*all")
            backup:close()
            assert.matches("initial log content", backup_content)
        end)

        it("should validate rotation commands", function()
            local commands = file_dispatcher._generate_rotation_commands(test_log)
            local valid, err = file_dispatcher._validate_rotation_commands(commands, test_log)

            assert.is_true(valid)
        end)

        it("should handle invalid paths", function()
            local dispatcher = file_dispatcher({ path = "/invalid/path/test.log" })

            -- Should not error, but write to stderr
            local stderr_output = {}
            local old_stderr = io.stderr
            io.stderr = {
                write = function(_, str) table.insert(stderr_output, str) end
            }

            dispatcher(sample_record)

            io.stderr = old_stderr

            assert.matches("Error opening log", stderr_output[1])
        end)
    end)

    describe("Syslog Dispatcher", function()
        it("should validate configuration", function()
            -- Valid configurations
            assert.is_true(syslog_dispatcher._validate_config({
                facility = "LOCAL0",
                host = "localhost",
                port = 514
            }))

            assert.is_true(syslog_dispatcher._validate_config({
                facility = "USER",
                tag = "myapp"
            }))

            -- Invalid configurations
            local valid, err = syslog_dispatcher._validate_config({
                facility = "INVALID"
            })
            assert.is_false(valid)
            assert.matches("Unknown syslog facility", err)

            valid, err = syslog_dispatcher._validate_config({
                port = "not_a_number"
            })
            assert.is_false(valid)
            assert.matches("port must be a number", err)
        end)

        it("should map log levels to syslog severities", function()
            local map = syslog_dispatcher._map_level_to_severity
            local sev = syslog_dispatcher._SEVERITIES

            assert.are.equal(sev.DEBUG, map(10))    -- DEBUG
            assert.are.equal(sev.INFO, map(20))     -- INFO
            assert.are.equal(sev.WARNING, map(30))  -- WARNING
            assert.are.equal(sev.ERROR, map(40))    -- ERROR
            assert.are.equal(sev.CRITICAL, map(50)) -- CRITICAL
        end)

        it("should format syslog messages correctly", function()
            local format = syslog_dispatcher._format_syslog_message
            local facility = syslog_dispatcher._FACILITIES.USER

            local message = format(sample_record, facility, "testhost", "myapp")

            -- Check RFC 3164 format: <priority>timestamp hostname tag: message
            assert.matches("^<%d+>%w+ %d+ %d+:%d+:%d+ testhost myapp: .*$", message)
        end)

        it("should handle network errors gracefully", function()
            local dispatcher = syslog_dispatcher({
                facility = "USER",
                host = "nonexistent.host",
                port = 55555 -- Unlikely to be open
            })

            -- Should not error, but write to stderr
            local stderr_output = {}
            local old_stderr = io.stderr
            io.stderr = {
                write = function(_, str) table.insert(stderr_output, str) end
            }

            dispatcher(sample_record)

            io.stderr = old_stderr

            assert.is_true(#stderr_output > 0)
        end)
    end)
end)
