#!/usr/bin/env lua
package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua;../lua/?.lua;../lua/?/init.lua"

local lual = require("lual.logger")
local core_levels = require("lua.lual.levels")
local pipeline_module = require("lual.pipelines") -- Directly require the pipeline module for testing internals

describe("Output Log Event Pipeline", function()
    before_each(function()
        -- Reset config and logger cache for each test
        lual.reset_config()
        lual.reset_cache()
    end)

    -- Tests for format_message (completely uncovered)
    describe("format_message function", function()
        local format_message = pipeline_module._format_message

        it("should handle nil message format", function()
            local result = format_message(nil, table.pack())
            assert.are.equal("", result)
        end)

        it("should handle empty format args", function()
            local result = format_message("Simple message", table.pack())
            assert.are.equal("Simple message", result)
        end)

        it("should handle valid format args", function()
            local args = table.pack("world", 42)
            local result = format_message("Hello %s, answer is %d", args)
            assert.are.equal("Hello world, answer is 42", result)
        end)

        it("should handle format errors", function()
            local args = table.pack("world") -- Missing second arg
            local result = format_message("Hello %s, answer is %d", args)
            -- Don't use pattern matching but direct string check
            assert.truthy(result:find("%[FORMAT ERROR:"))
        end)
    end)

    -- Tests for parse_log_args (partially covered)
    describe("parse_log_args function", function()
        local parse_log_args = pipeline_module._parse_log_args

        it("should handle no arguments", function()
            local msg_fmt, args, context = parse_log_args()
            assert.are.equal("", msg_fmt)
            assert.are.equal(0, args.n)
            assert.is_nil(context)
        end)

        it("should handle string message only", function()
            local msg_fmt, args, context = parse_log_args("Simple message")
            assert.are.equal("Simple message", msg_fmt)
            assert.are.equal(0, args.n)
            assert.is_nil(context)
        end)

        it("should handle string with format args", function()
            local msg_fmt, args, context = parse_log_args("Value: %d", 42)
            assert.are.equal("Value: %d", msg_fmt)
            assert.are.equal(1, args.n)
            assert.are.equal(42, args[1])
            assert.is_nil(context)
        end)

        it("should handle context table only", function()
            local ctx = { user_id = 123, msg = "From context" }
            local msg_fmt, args, context = parse_log_args(ctx)
            assert.are.equal("From context", msg_fmt)
            assert.are.equal(0, args.n)
            assert.are.same(ctx, context)
        end)

        it("should handle context with message", function()
            local ctx = { user_id = 123 }
            local msg_fmt, args, context = parse_log_args(ctx, "User action")
            assert.are.equal("User action", msg_fmt)
            assert.are.equal(0, args.n)
            assert.are.same(ctx, context)
        end)

        it("should handle context with message and args", function()
            local ctx = { user_id = 123 }
            local msg_fmt, args, context = parse_log_args(ctx, "User %s: %d", "login", 42)
            assert.are.equal("User %s: %d", msg_fmt)
            assert.are.equal(2, args.n)
            assert.are.equal("login", args[1])
            assert.are.equal(42, args[2])
            assert.are.same(ctx, context)
        end)

        it("should handle non-string single value", function()
            local msg_fmt, args, context = parse_log_args(42)
            assert.are.equal("42", msg_fmt)
            assert.are.equal(0, args.n)
            assert.is_nil(context)
        end)
    end)

    -- Tests for the transformers in process_output (uncovered)
    describe("Transformer pipeline", function()
        it("should process array of transformers", function()
            local transformers_called = {}

            local function test_transformer1(record)
                table.insert(transformers_called, "transformer1")
                record.transformed1 = true
                return record
            end

            local function test_transformer2(record)
                table.insert(transformers_called, "transformer2")
                record.transformed2 = true
                return record
            end

            local captured_record = nil
            local mock_output = function(record)
                captured_record = record
            end

            local logger = lual.logger("transformer.test", {
                level = core_levels.definition.DEBUG,
                pipelines = {
                    {
                        outputs = { mock_output },
                        presenter = lual.text,
                        transformers = {
                            test_transformer1,
                            test_transformer2
                        }
                    }
                }
            })

            logger:info("Test transformers")

            assert.is_not_nil(captured_record, "Output should have been called")
            assert.are.equal(2, #transformers_called, "Both transformers should have been called")
            assert.are.equal("transformer1", transformers_called[1])
            assert.are.equal("transformer2", transformers_called[2])
            assert.is_true(captured_record.transformed1, "First transformer should have modified record")
            assert.is_true(captured_record.transformed2, "Second transformer should have modified record")
        end)

        it("should handle transformer errors", function()
            local transform_called = false
            local captured_record = nil

            local function broken_transformer(record)
                transform_called = true
                error("Transformer error")
                return record
            end

            local mock_output = function(record)
                captured_record = record
                return true -- Return a value to indicate success
            end

            local logger = lual.logger("transformer.error.test", {
                level = core_levels.definition.DEBUG,
                pipelines = {
                    {
                        outputs = { mock_output },
                        presenter = lual.text(),
                        transformers = { broken_transformer }
                    }
                }
            })

            -- We'll just call the logger method normally
            logger:info("Test transformer error")

            -- We should be able to check if the transformer was called
            assert.is_true(transform_called, "Transformer should have been called")
        end)

        it("should process single transformer", function()
            local transformer_called = false

            local function test_transformer(record)
                transformer_called = true
                record.transformed = true
                return record
            end

            local captured_record = nil
            local mock_output = function(record)
                captured_record = record
            end

            local logger = lual.logger("single.transformer.test", {
                level = core_levels.definition.DEBUG,
                pipelines = {
                    {
                        outputs = { mock_output },
                        presenter = lual.text,
                        transformers = { test_transformer }
                    }
                }
            })

            logger:info("Test single transformer")

            assert.is_true(transformer_called, "Transformer should have been called")
            assert.is_not_nil(captured_record, "Output should have been called")
            assert.is_true(captured_record.transformed, "Transformer should have modified record")
        end)

        it("should handle table-based transformers with config", function()
            local transformer_config_used = false

            local table_transformer = {
                func = function(record, config)
                    transformer_config_used = (config.test_value == "test")
                    record.table_transformed = true
                    return record
                end
            }

            local captured_record = nil
            local mock_output = function(record)
                captured_record = record
            end

            local logger = lual.logger("table.transformer.test", {
                level = core_levels.definition.DEBUG,
                pipelines = {
                    {
                        outputs = { mock_output },
                        presenter = lual.text,
                        transformers = {
                            {
                                func = table_transformer.func,
                                config = { test_value = "test" }
                            }
                        }
                    }
                }
            })

            logger:info("Test table transformer")

            assert.is_true(transformer_config_used, "Transformer should have used its config")
            assert.is_not_nil(captured_record, "Output should have been called")
            assert.is_true(captured_record.table_transformed, "Table transformer should have modified record")
        end)
    end)

    -- Tests for presenter in process_output (uncovered)
    describe("Presenter pipeline", function()
        it("should apply presenter to record", function()
            local presenter_called = false

            local function test_presenter(record)
                presenter_called = true
                return "Presented: " .. record.message
            end

            local captured_record = nil
            local mock_output = function(record)
                captured_record = record
            end

            local logger = lual.logger("presenter.test", {
                level = core_levels.definition.DEBUG,
                pipelines = {
                    {
                        outputs = { mock_output },
                        presenter = test_presenter
                    }
                }
            })

            logger:info("Test presenter")

            assert.is_true(presenter_called, "Presenter should have been called")
            assert.is_not_nil(captured_record, "Output should have been called")
            assert.are.equal("Presented: Test presenter", captured_record.presented_message)
            assert.are.equal("Presented: Test presenter", captured_record.message)
        end)

        it("should handle presenter errors", function()
            local presenter_called = false
            local captured_record = nil

            local function broken_presenter(record)
                presenter_called = true
                error("Presenter error")
                return "This won't be returned"
            end

            local mock_output = function(record)
                captured_record = record
                return true -- Return a value to indicate success
            end

            local logger = lual.logger("presenter.error.test", {
                level = core_levels.definition.DEBUG,
                pipelines = {
                    {
                        outputs = { mock_output },
                        presenter = broken_presenter
                    }
                }
            })

            -- Redirect stderr to capture the error
            local old_stderr = io.stderr
            local stderr_output = {}
            io.stderr = { write = function(_, msg) table.insert(stderr_output, msg) end }

            -- Create a test record directly for a controlled test
            local test_record = {
                level_no = core_levels.definition.INFO,
                level_name = "INFO",
                message_fmt = "Test presenter error",
                message = "Test presenter error",
                formatted_message = "Test presenter error",
                args = {},
                timestamp = os.time(),
                logger_name = "presenter.error.test",
                source_logger_name = "presenter.error.test"
            }

            -- Process the pipeline directly
            pipeline_module._process_pipeline(test_record, logger.pipelines[1], logger)

            -- Restore stderr
            io.stderr = old_stderr

            -- Since we're calling the pipeline directly, we should check if stderr was written to
            assert.is_true(#stderr_output > 0, "Error message should have been written to stderr")
            assert.truthy(stderr_output[1]:match("LUAL: Error in presenter function"),
                "Expected presenter error in stderr")
        end)
    end)

    -- Tests for output error handling
    describe("output error handling", function()
        it("should handle output errors", function()
            local function broken_output(record)
                error("output error")
            end

            local logger = lual.logger("output.error.test", {
                level = core_levels.definition.DEBUG,
                pipelines = {
                    {
                        outputs = { broken_output },
                        presenter = lual.text
                    }
                }
            })

            -- Create a direct test without using the logger
            local test_record = pipeline_module._create_log_record(
                logger,
                core_levels.definition.INFO,
                "INFO",
                "Test output error",
                table.pack(),
                nil
            )

            -- Directly test the process_output function
            pipeline_module._process_output(test_record, broken_output, logger)

            -- If no error was thrown, the test passes (the error was handled by the pcall)
            assert.is_true(true)
        end)
    end)

    -- Tests for create_log_record formatting errors (uncovered)
    describe("Log record creation with formatting errors", function()
        it("should handle string formatting errors", function()
            -- Create a test directly using the function
            local logger = { name = "test.logger" }
            local level_no = core_levels.definition.INFO
            local level_name = "INFO"
            local message_fmt = "This %s has %d too many %s placeholders"
            local args = table.pack("value") -- Not enough args to satisfy format

            local record = pipeline_module._create_log_record(
                logger, level_no, level_name, message_fmt, args, nil
            )

            assert.truthy(record.formatted_message:find("%[FORMAT ERROR:"))
        end)
    end)

    -- Tests for raw function outputs (uncovered)
    describe("Raw function outputs", function()
        it("should handle raw function outputs", function()
            local output_called = false
            local output_received_record = nil

            local function raw_output(record)
                output_called = true
                output_received_record = record
                return record
            end

            -- For this test, we need to test with a real logger since the implementation
            -- handles raw function outputs differently than output entry objects
            local logger = lual.logger("raw.output.test", {
                level = core_levels.definition.DEBUG,
                pipelines = {
                    {
                        outputs = { raw_output },
                        presenter = lual.text()
                    }
                }
            })

            logger:info("Test raw output")

            assert.is_true(output_called, "Raw output should have been called")
            assert.is_not_nil(output_received_record, "output should have received record")
            assert.are.equal("Test raw output", output_received_record.message_fmt)
        end)
    end)
end)
