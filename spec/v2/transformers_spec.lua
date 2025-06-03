#!/usr/bin/env lua
package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua;../lua/?.lua;../lua/?/init.lua"

local lual = require("lual.logger")
local core_levels = require("lua.lual.levels")

describe("lual Transformers", function()
    before_each(function()
        lual.reset_config()
        lual.reset_cache()
    end)

    describe("No-op Transformer", function()
        it("should pass through log records unchanged", function()
            local output_captured = {}
            local mock_dispatcher = function(record)
                table.insert(output_captured, record)
            end

            local logger = lual.logger("test.noop", {
                dispatchers = {
                    {
                        dispatcher_func = mock_dispatcher,
                        config = {
                            transformer = function(record) return record end
                        }
                    }
                }
            })

            local context = { user_id = 123 }
            logger:info(context, "Test message")

            assert.are.equal(1, #output_captured)
            local record = output_captured[1]
            assert.are.equal("Test message", record.message_fmt)
            assert.are.same(context, record.context)
        end)
    end)

    describe("Multiple Transformers", function()
        it("should apply transformers in order", function()
            local output_captured = {}
            local mock_dispatcher = function(record)
                table.insert(output_captured, record)
            end

            local add_hostname = function(record)
                record.hostname = "test-host"
                return record
            end

            local add_pid = function(record)
                record.pid = 12345
                return record
            end

            local logger = lual.logger("test.multi", {
                dispatchers = {
                    {
                        dispatcher_func = mock_dispatcher,
                        config = {
                            transformers = { add_hostname, add_pid }
                        }
                    }
                }
            })

            logger:info("Test message")

            assert.are.equal(1, #output_captured)
            local record = output_captured[1]
            assert.are.equal("test-host", record.hostname)
            assert.are.equal(12345, record.pid)
        end)
    end)

    describe("Custom Transformers", function()
        it("should support custom transformer functions", function()
            local output_captured = {}
            local mock_dispatcher = function(record)
                table.insert(output_captured, record)
            end

            local custom_transformer = function(record)
                record.custom_field = "custom_value"
                return record
            end

            local logger = lual.logger("test.custom", {
                dispatchers = {
                    {
                        dispatcher_func = mock_dispatcher,
                        config = {
                            transformers = { custom_transformer }
                        }
                    }
                }
            })

            logger:info("Test message")

            assert.are.equal(1, #output_captured)
            local record = output_captured[1]
            assert.are.equal("custom_value", record.custom_field)
        end)
    end)

    describe("Transformer Configuration", function()
        it("should respect transformer configuration", function()
            local output_captured = {}
            local mock_dispatcher = function(record)
                table.insert(output_captured, record)
            end

            local add_field = function(record, config)
                record[config.field_name] = config.field_value
                return record
            end

            local logger = lual.logger("test.config", {
                dispatchers = {
                    {
                        dispatcher_func = mock_dispatcher,
                        config = {
                            transformers = {
                                {
                                    func = add_field,
                                    config = {
                                        field_name = "environment",
                                        field_value = "production"
                                    }
                                }
                            }
                        }
                    }
                }
            })

            logger:info("Test message")

            assert.are.equal(1, #output_captured)
            local record = output_captured[1]
            assert.are.equal("production", record.environment)
        end)
    end)

    describe("Error Handling", function()
        it("should handle transformer errors gracefully", function()
            local output_captured = {}
            local mock_dispatcher = function(record)
                table.insert(output_captured, record)
            end

            local error_transformer = function(record)
                error("Transformer error")
            end

            local logger = lual.logger("test.error", {
                dispatchers = {
                    {
                        dispatcher_func = mock_dispatcher,
                        config = {
                            transformers = { error_transformer }
                        }
                    }
                }
            })

            -- Should not throw error, but should add error info to record
            logger:info("Test message")

            assert.are.equal(1, #output_captured)
            local record = output_captured[1]
            assert.is_not_nil(record.transformer_error)
            assert.matches("Transformer error", record.transformer_error)
        end)
    end)
end)
