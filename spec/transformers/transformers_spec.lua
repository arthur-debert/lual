#!/usr/bin/env lua
package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua;../lua/?.lua;../lua/?/init.lua"

local lual = require("lual.constants")
local transformers = lual.transformers

describe("lual Transformers", function()
    -- Sample log record for testing
    local sample_record = {
        timestamp = os.time(),
        level_name = "INFO",
        logger_name = "test.logger",
        message_fmt = "User %s logged in from %s",
        args = { "jane.doe", "10.0.0.1" },
        context = { user_id = 123, action = "login" }
    }

    describe("No-op Transformer", function()
        it("should pass through log records unchanged", function()
            local noop = transformers.noop()
            local original_record = {
                timestamp = os.time(),
                level_name = "INFO",
                message_fmt = "Test message",
                context = { key = "value" }
            }

            -- Create a deep copy for comparison
            local original_copy = {}
            for k, v in pairs(original_record) do
                if type(v) == "table" then
                    original_copy[k] = {}
                    for k2, v2 in pairs(v) do
                        original_copy[k][k2] = v2
                    end
                else
                    original_copy[k] = v
                end
            end

            local transformed = noop(original_record)

            -- Verify record is unchanged
            assert.are.same(original_copy, transformed)
            -- Verify it's the same table instance (no copying)
            assert.are.equal(original_record, transformed)
        end)

        it("should handle empty records", function()
            local noop = transformers.noop()
            local empty_record = {}
            local transformed = noop(empty_record)

            assert.are.same({}, transformed)
            assert.are.equal(empty_record, transformed)
        end)

        it("should handle nil values in record", function()
            local noop = transformers.noop()
            local record_with_nil = {
                timestamp = os.time(),
                level_name = nil,
                message_fmt = "Test"
            }
            local transformed = noop(record_with_nil)

            assert.are.same(record_with_nil, transformed)
        end)
    end)

    describe("Transformer Factory Pattern", function()
        it("should return a callable object with schema", function()
            local transformer = transformers.noop()

            -- Check it's a table
            assert.is_table(transformer)
            -- Check it has a schema
            assert.is_table(transformer.schema)
            -- Check it's callable
            assert.is_function(getmetatable(transformer).__call)
        end)

        it("should accept optional configuration", function()
            local transformer = transformers.noop({
                some_config = "value"
            })

            -- Should still work as a transformer
            local result = transformer(sample_record)
            assert.are.same(sample_record, result)
        end)
    end)

    describe("Transformer Chain", function()
        it("should allow chaining multiple transformers", function()
            -- Create some test transformers
            local add_hostname = function(record)
                record.hostname = "test-host"
                return record
            end

            local add_pid = function(record)
                record.pid = 12345
                return record
            end

            -- Chain them manually
            local record = { message = "test" }
            record = add_hostname(record)
            record = add_pid(record)

            -- Verify transformations were applied in order
            assert.are.equal("test-host", record.hostname)
            assert.are.equal(12345, record.pid)
        end)

        it("should handle errors in transformer chain", function()
            -- Create test transformers
            local add_field = function(record)
                record.field1 = "value1"
                return record
            end

            local error_transformer = function(record)
                error("Transformer error")
            end

            local add_another = function(record)
                record.field2 = "value2"
                return record
            end

            -- Try to chain them with error handling
            local record = { message = "test" }
            record = add_field(record)

            local success, result = pcall(function()
                return error_transformer(record)
            end)
            assert.is_false(success)
            assert.are.equal("value1", record.field1)

            -- Chain should continue after error
            record = add_another(record)
            assert.are.equal("value2", record.field2)
        end)
    end)

    describe("Custom Transformers", function()
        it("should support adding custom fields", function()
            local custom = function(record)
                record.custom_field = "custom_value"
                record.timestamp_ms = record.timestamp * 1000
                return record
            end

            local result = custom(sample_record)
            assert.are.equal("custom_value", result.custom_field)
            assert.are.equal(sample_record.timestamp * 1000, result.timestamp_ms)
        end)

        it("should support modifying existing fields", function()
            local modifier = function(record)
                record.level_name = record.level_name .. "_MODIFIED"
                record.logger_name = "modified." .. record.logger_name
                return record
            end

            local result = modifier(sample_record)
            assert.are.equal("INFO_MODIFIED", result.level_name)
            assert.are.equal("modified.test.logger", result.logger_name)
        end)

        it("should support conditional transformations", function()
            local conditional = function(record)
                if record.level_name == "ERROR" then
                    record.alert = true
                end
                return record
            end

            local error_record = {
                level_name = "ERROR",
                message_fmt = "Error occurred"
            }
            local info_record = {
                level_name = "INFO",
                message_fmt = "Info message"
            }

            local error_result = conditional(error_record)
            local info_result = conditional(info_record)

            assert.is_true(error_result.alert)
            assert.is_nil(info_result.alert)
        end)
    end)
end)
