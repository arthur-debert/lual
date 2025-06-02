#!/usr/bin/env lua
package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua;../lua/?.lua;../lua/?/init.lua"

local lual = require("lual.logger")
local core_levels = require("lua.lual.levels")

describe("lual.v2 Dispatch Loop Logic (Step 2.7)", function()
    before_each(function()
        -- Reset v2 config and logger cache for each test
        lual.v2.reset_config()
        lual.v2.reset_cache()
    end)

    describe("Basic logging methods", function()
        it("should have all logging methods available", function()
            local logger = lual.v2.logger("test.methods")

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

            local logger = lual.v2.logger("test.level.check", {
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
            lual.v2.config({ level = core_levels.definition.ERROR })

            -- Create child logger with NOTSET (inherits ERROR from root)
            local child_logger = lual.v2.logger("inherits.error", {
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
            local parent_logger = lual.v2.logger("parent", {
                level = core_levels.definition.DEBUG,
                dispatchers = { parent_dispatcher }
            })

            local child_logger = lual.v2.logger("parent.child", {
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
            local parent_logger = lual.v2.logger("parent", {
                level = core_levels.definition.ERROR, -- Only ERROR and above
                dispatchers = { high_level_dispatcher }
            })

            local child_logger = lual.v2.logger("parent.child", {
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
            local parent_logger = lual.v2.logger("parent", {
                level = core_levels.definition.DEBUG,
                dispatchers = { parent_dispatcher }
            })

            local child_logger = lual.v2.logger("parent.child", {
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
            lual.v2.config({
                level = core_levels.definition.DEBUG,
                dispatchers = { root_dispatcher }
            })

            -- Create child logger
            local child_logger = lual.v2.logger("child", {
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
            local parent_logger = lual.v2.logger("parent", {
                level = core_levels.definition.DEBUG,
                dispatchers = { parent_dispatcher }
            })

            local child_logger = lual.v2.logger("parent.child", {
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

            local logger = lual.v2.logger("record.test", {
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

            local logger = lual.v2.logger("context.test", {
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

            local logger = lual.v2.logger("context.only.test", {
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
            local level1 = lual.v2.logger("level1", {
                level = core_levels.definition.DEBUG,
                dispatchers = { dispatchers.level1 }
            })

            local level2 = lual.v2.logger("level1.level2", {
                level = core_levels.definition.DEBUG,
                dispatchers = { dispatchers.level2 }
            })

            local level3 = lual.v2.logger("level1.level2.level3", {
                level = core_levels.definition.DEBUG,
                dispatchers = { dispatchers.level3 }
            })

            local level4 = lual.v2.logger("level1.level2.level3.level4", {
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
            local level1 = lual.v2.logger("mixed1", {
                level = core_levels.definition.DEBUG,
                dispatchers = { dispatchers.level1 },
                propagate = true
            })

            local level2 = lual.v2.logger("mixed1.mixed2", {
                level = core_levels.definition.DEBUG,
                dispatchers = { dispatchers.level2 },
                propagate = false -- Stop propagation here
            })

            local level3 = lual.v2.logger("mixed1.mixed2.mixed3", {
                level = core_levels.definition.DEBUG,
                dispatchers = { dispatchers.level3 },
                propagate = true
            })

            local level4 = lual.v2.logger("mixed1.mixed2.mixed3.mixed4", {
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

            local logger = lual.v2.logger("generic.test", {
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
            local logger = lual.v2.logger("invalid.level.test")

            assert.has_error(function()
                logger:log("warning", "Invalid level type")
            end, "Log level must be a number, got string")
        end)

        it("should respect level checking for generic log method", function()
            local output_captured = {}
            local mock_dispatcher = function(record)
                table.insert(output_captured, record)
            end

            local logger = lual.v2.logger("generic.level.test", {
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
