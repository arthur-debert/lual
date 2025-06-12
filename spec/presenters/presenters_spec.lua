#!/usr/bin/env lua
local unpack = unpack or table.unpack

local lual = require("lual")
local text_presenter = lual.text
local color_presenter = lual.color
local json_presenter = lual.json
local time_utils = require("lual.utils.time")

describe("lual Presenters", function()
    -- Sample log record for testing
    local sample_record = {
        timestamp = os.time(),
        level_name = "INFO",
        logger_name = "test.logger",
        message_fmt = "User %s logged in from %s",
        args = { "jane.doe", "10.0.0.1" },
        context = { user_id = 123, action = "login" }
    }

    describe("Text Presenter", function()
        it("should format log records with default settings", function()
            local presenter = text_presenter()
            local output = presenter(sample_record)

            -- Should match format: "TIMESTAMP LEVEL [LOGGER] MESSAGE"
            assert.matches(
                "%d%d%d%d%-%d%d%-%d%d %d%d:%d%d:%d%d INFO %[test%.logger%] User jane%.doe logged in from 10%.0%.0%.1",
                output)
        end)

        it("should handle missing optional fields", function()
            local presenter = text_presenter()
            local minimal_record = {
                timestamp = os.time(),
                message_fmt = "Simple message"
            }
            local output = presenter(minimal_record)

            assert.matches("UNKNOWN_LEVEL %[UNKNOWN_LOGGER%] Simple message", output:match("UNKNOWN_LEVEL.*$"))
        end)

        it("should format context-only logs", function()
            local presenter = text_presenter()
            local context_record = {
                timestamp = os.time(),
                level_name = "INFO",
                logger_name = "test",
                context = { key1 = "value1", key2 = "value2" }
            }
            local output = presenter(context_record)

            -- Check that output contains both key-value pairs in any order
            assert.matches("key1=value1", output)
            assert.matches("key2=value2", output)
            -- Check that it's wrapped in curly braces
            assert.matches("^.*{.*}.*$", output)
        end)
    end)

    describe("JSON Presenter", function()
        it("should format log records as valid JSON", function()
            local presenter = json_presenter()
            local output = presenter(sample_record)

            -- Verify it's valid JSON
            local success, decoded = pcall(require("dkjson").decode, output)
            assert.is_true(success)
            assert.is_table(decoded)

            -- Verify required fields
            assert.are.equal("INFO", decoded.level)
            assert.are.equal("test.logger", decoded.logger)
            assert.are.equal("User jane.doe logged in from 10.0.0.1", decoded.message)
            assert.are.same({ "jane.doe", "10.0.0.1" }, decoded.args)
        end)

        it("should handle pretty printing when configured", function()
            local presenter = json_presenter({ pretty = true })
            local output = presenter(sample_record)

            -- Pretty printed JSON should have newlines
            assert.matches("\n", output)
            assert.matches("  ", output) -- Should have indentation
        end)

        it("should handle non-serializable values gracefully", function()
            local presenter = json_presenter()
            local record_with_function = {
                timestamp = os.time(),
                level_name = "INFO",
                logger_name = "test",
                message_fmt = "Test",
                context = {
                    fn = function() end
                }
            }
            local output = presenter(record_with_function)

            assert.matches('non%-serializable', output)
        end)
    end)

    describe("Color Presenter", function()
        it("should format log records with ANSI colors", function()
            local presenter = color_presenter()
            local output = presenter(sample_record)

            -- Should contain ANSI escape codes
            assert.matches("\27%[", output)
            -- Should have color reset codes
            assert.matches("\27%[0m", output)
        end)

        it("should respect custom level colors", function()
            local presenter = color_presenter({
                level_colors = {
                    INFO = "red" -- Override default green for INFO
                }
            })
            local output = presenter(sample_record)

            -- Should use red color code for INFO
            assert.matches("\27%[31m", output)
        end)

        it("should handle missing color definitions gracefully", function()
            local presenter = color_presenter({
                level_colors = {
                    INFO = "nonexistent_color"
                }
            })
            local output = presenter(sample_record)

            -- Should still produce valid output without color
            assert.matches("INFO", output)
        end)
    end)

    describe("Time Format Options", function()
        it("should respect timezone settings", function()
            local utc_presenter = text_presenter({ timezone = "utc" })
            local local_presenter = text_presenter({ timezone = "local" })

            -- Use a known timestamp: 2021-01-01 00:00:00 UTC
            local test_record = {
                timestamp = 1609459200,
                level_name = "INFO",
                logger_name = "test",
                message_fmt = "Test"
            }

            local utc_output = utc_presenter(test_record)
            local local_output = local_presenter(test_record)

            -- UTC output should contain the known UTC timestamp
            assert.truthy(utc_output:find("2021%-01%-01 00:00:00", 1, false), "Should contain UTC timestamp")

            -- Local output should contain a valid timestamp format (can't predict exact local time)
            assert.matches("^%d%d%d%d%-%d%d%-%d%d %d%d:%d%d:%d%d", local_output)
        end)
    end)
end)
