#!/usr/bin/env lua
package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua;../lua/?.lua;../lua/?/init.lua"

local component_utils = require("lual.utils.component")
local all_outputs = require("lual.pipeline.outputs.init")
local all_presenters = require("lual.pipeline.presenters.init")
local all_transformers = require("lual.pipeline.transformers.init")
local core_levels = require("lua.lual.levels")

describe("Component Utils End-to-End", function()
    it("should correctly process a log record through normalized components", function()
        -- Create a log record
        local log_record = {
            level_no = core_levels.definition.INFO,
            level_name = "INFO",
            message_fmt = "User %s logged in from %s",
            args = { "john.doe", "192.168.1.1" },
            formatted_message = "User john.doe logged in from 192.168.1.1",
            message = "User john.doe logged in from 192.168.1.1",
            context = { user_id = 123 },
            timestamp = os.time(),
            logger_name = "test.logger",
            source_logger_name = "test.logger",
            filename = "test.lua",
            lineno = 42
        }

        -- Create a test output buffer
        local output_buffer = {}
        local test_stream = {
            write = function(_, str)
                table.insert(output_buffer, str)
                return true
            end,
            flush = function() return true end
        }

        -- Create components using our new system
        local console_output = {
            all_outputs.console_output,
            stream = test_stream
        }

        -- Normalize the output
        local normalized_output = component_utils.normalize_component(
            console_output,
            component_utils.DISPATCHER_DEFAULTS
        )

        -- Create a text presenter
        local text_presenter = all_presenters.text()

        -- Normalize the presenter
        local normalized_presenter = component_utils.normalize_component(
            text_presenter,
            component_utils.PRESENTER_DEFAULTS
        )

        -- Add presenter to output config
        normalized_output.config.presenter = normalized_presenter.func

        -- Process the log record
        normalized_output.func(log_record, normalized_output.config)

        -- Verify the output
        assert.is_true(#output_buffer > 0, "No output was produced")
        local output = table.concat(output_buffer)

        -- Verify that the output contains the expected log message
        assert.matches("INFO", output)
        assert.matches("test.logger", output)
        assert.matches("User john.doe logged in from 192.168.1.1", output)
    end)

    it("should respect level filtering with normalized output", function()
        -- Create log records with different levels
        local debug_record = {
            level_no = core_levels.definition.DEBUG,
            level_name = "DEBUG",
            message = "Debug message",
            timestamp = os.time(),
            logger_name = "test.logger"
        }

        local info_record = {
            level_no = core_levels.definition.INFO,
            level_name = "INFO",
            message = "Info message",
            timestamp = os.time(),
            logger_name = "test.logger"
        }

        -- Create a test output buffer
        local output_buffer = {}
        local test_stream = {
            write = function(_, str)
                table.insert(output_buffer, str)
                return true
            end,
            flush = function() return true end
        }

        -- Create output with WARNING level
        local console_output = {
            all_outputs.console_output,
            level = core_levels.definition.WARNING,
            stream = test_stream
        }

        -- Normalize the output
        local normalized_output = component_utils.normalize_component(
            console_output,
            component_utils.DISPATCHER_DEFAULTS
        )

        -- Process both records
        -- This simulates the level check that would happen in the output.lua module
        if debug_record.level_no >= normalized_output.config.level then
            normalized_output.func(debug_record, normalized_output.config)
        end

        if info_record.level_no >= normalized_output.config.level then
            normalized_output.func(info_record, normalized_output.config)
        end

        -- Verify neither record was processed due to level filtering
        assert.are.equal(0, #output_buffer, "Output buffer should be empty due to level filtering")

        -- Create a warning record that should pass the filter
        local warning_record = {
            level_no = core_levels.definition.WARNING,
            level_name = "WARNING",
            message = "Warning message",
            timestamp = os.time(),
            logger_name = "test.logger"
        }

        -- Process the warning record
        if warning_record.level_no >= normalized_output.config.level then
            normalized_output.func(warning_record, normalized_output.config)
        end

        -- Verify the warning record was processed
        -- Note: The console output writes two entries to the output buffer
        -- (the message and a newline), so we need to check that it's greater than 0
        assert.is_true(#output_buffer > 0, "Warning message should have been processed")
        local output = table.concat(output_buffer)
        assert.matches("WARNING", output)
        assert.matches("Warning message", output)
    end)
end)
