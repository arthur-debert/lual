package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua;../lua/?.lua;../lua/?/init.lua"
local json_formatter = require("lual.formatters.json")
local dkjson = require("dkjson")

describe("lual.formatters.json", function()
    describe("Basic functionality", function()
        it("should format a basic log record as JSON", function()
            local record = {
                timestamp = 1678886400, -- 2023-03-15 10:00:00 UTC
                level_name = "INFO",
                logger_name = "test.logger",
                message_fmt = "User %s logged in from %s",
                args = { "jane.doe", "10.0.0.1" },
            }

            local formatted = json_formatter(record)
            local parsed = dkjson.decode(formatted)

            assert.is_not_nil(parsed)
            assert.are.same(1678886400, parsed.timestamp)
            local expected_iso = os.date("!%Y-%m-%dT%H:%M:%SZ", record.timestamp)
            assert.are.same(expected_iso, parsed.timestamp_iso)
            assert.are.same("INFO", parsed.level)
            assert.are.same("test.logger", parsed.logger)
            assert.are.same("User %s logged in from %s", parsed.message_fmt)
            assert.are.same({ "jane.doe", "10.0.0.1" }, parsed.args)
            assert.are.same("User jane.doe logged in from 10.0.0.1", parsed.message)
        end)

        it("should handle records with no arguments", function()
            local record = {
                timestamp = 1678886401,
                level_name = "DEBUG",
                logger_name = "test.debug",
                message_fmt = "Simple debug message",
                args = {},
            }

            local formatted = json_formatter(record)
            local parsed = dkjson.decode(formatted)

            assert.is_not_nil(parsed)
            assert.are.same("DEBUG", parsed.level)
            assert.are.same("Simple debug message", parsed.message)
            assert.are.same({}, parsed.args)
        end)

        it("should handle records with nil arguments", function()
            local record = {
                timestamp = 1678886402,
                level_name = "WARNING",
                logger_name = "test.warning",
                message_fmt = "Warning message with no args",
                args = nil,
            }

            local formatted = json_formatter(record)
            local parsed = dkjson.decode(formatted)

            assert.is_not_nil(parsed)
            assert.are.same("WARNING", parsed.level)
            assert.are.same("Warning message with no args", parsed.message)
            assert.are.same({}, parsed.args)
        end)
    end)

    describe("Fallback handling", function()
        it("should use fallbacks for missing optional fields", function()
            local record = {
                timestamp = 1678886403,
                level_name = nil,
                logger_name = nil,
                message_fmt = "Message with missing fields",
                args = {},
            }

            local formatted = json_formatter(record)
            local parsed = dkjson.decode(formatted)

            assert.is_not_nil(parsed)
            assert.are.same("UNKNOWN_LEVEL", parsed.level)
            assert.are.same("UNKNOWN_LOGGER", parsed.logger)
            assert.are.same("Message with missing fields", parsed.message)
        end)

        it("should handle formatting errors gracefully", function()
            local record = {
                timestamp = 1678886404,
                level_name = "ERROR",
                logger_name = "test.error",
                message_fmt = "User %s has %d items and %s status",
                args = { "john", "not_a_number" }, -- Wrong type for %d
            }

            local formatted = json_formatter(record)
            local parsed = dkjson.decode(formatted)

            assert.is_not_nil(parsed)
            assert.are.same("ERROR", parsed.level)
            assert.are.same("User %s has %d items and %s status", parsed.message)
            assert.are.same("Failed to format message with provided arguments", parsed.format_error)
        end)

        it("should handle non-table args gracefully", function()
            local record = {
                timestamp = 1678886405,
                level_name = "INFO",
                logger_name = "test.info",
                message_fmt = "Simple message",
                args = "not_a_table",
            }

            local formatted = json_formatter(record)
            local parsed = dkjson.decode(formatted)

            assert.is_not_nil(parsed)
            assert.are.same("Simple message", parsed.message)
            assert.are.same("not_a_table", parsed.args)
        end)
    end)

    describe("Configuration options", function()
        it("should format as compact JSON by default", function()
            local record = {
                timestamp = 1678886406,
                level_name = "INFO",
                logger_name = "test.compact",
                message_fmt = "Test message",
                args = {},
            }

            local formatted = json_formatter(record)

            -- Compact JSON should not contain newlines or extra spaces
            assert.is_nil(formatted:find("\n"))
            assert.is_nil(formatted:find("  ")) -- Two spaces indicating indentation
        end)

        it("should format as pretty JSON when configured", function()
            local record = {
                timestamp = 1678886407,
                level_name = "INFO",
                logger_name = "test.pretty",
                message_fmt = "Test message",
                args = {},
            }

            local formatted = json_formatter(record, { pretty = true })

            -- Pretty JSON should contain newlines and indentation
            assert.is_not_nil(formatted:find("\n"))
            assert.is_not_nil(formatted:find("  ")) -- Indentation spaces
        end)
    end)

    describe("Additional fields handling", function()
        it("should include caller_info when present", function()
            local record = {
                timestamp = 1678886408,
                level_name = "DEBUG",
                logger_name = "test.caller",
                message_fmt = "Debug with caller info",
                args = {},
                caller_info = {
                    file = "test.lua",
                    line = 42,
                    func = "test_function"
                }
            }

            local formatted = json_formatter(record)
            local parsed = dkjson.decode(formatted)

            assert.is_not_nil(parsed.caller_info)
            assert.are.same("test.lua", parsed.caller_info.file)
            assert.are.same(42, parsed.caller_info.line)
            assert.are.same("test_function", parsed.caller_info.func)
        end)

        it("should include extra fields from record", function()
            local record = {
                timestamp = 1678886409,
                level_name = "INFO",
                logger_name = "test.extra",
                message_fmt = "Message with extra fields",
                args = {},
                user_id = "12345",
                session_id = "abcdef",
                request_id = "req-789"
            }

            local formatted = json_formatter(record)
            local parsed = dkjson.decode(formatted)

            assert.are.same("12345", parsed.user_id)
            assert.are.same("abcdef", parsed.session_id)
            assert.are.same("req-789", parsed.request_id)
        end)

        it("should not override core fields with extra fields", function()
            local record = {
                timestamp = 1678886410,
                level_name = "INFO",
                logger_name = "test.override",
                message_fmt = "Test message",
                args = {},
                level = "SHOULD_NOT_OVERRIDE", -- This should not override the mapped level
                logger = "SHOULD_NOT_OVERRIDE" -- This should not override the mapped logger
            }

            local formatted = json_formatter(record)
            local parsed = dkjson.decode(formatted)

            -- Core fields should not be overridden
            assert.are.same("INFO", parsed.level)
            assert.are.same("test.override", parsed.logger)
        end)
    end)

    describe("Error handling", function()
        it("should handle non-serializable values gracefully", function()
            local record = {
                timestamp = 1678886411,
                level_name = "ERROR",
                logger_name = "test.nonserial",
                message_fmt = "Message with non-serializable data",
                args = {},
                func_value = function() return "test" end,      -- Functions are not JSON serializable
                thread_value = coroutine.create(function() end) -- Threads are not JSON serializable
            }

            local formatted = json_formatter(record)

            -- The JSON should be valid and parseable
            assert.is_string(formatted)
            local parsed = dkjson.decode(formatted)
            assert.is_table(parsed)

            assert.is_not_nil(parsed)
            assert.are.same("ERROR", parsed.level)
            assert.are.same("Message with non-serializable data", parsed.message)

            -- Non-serializable values should be handled gracefully
            -- They should either be converted to strings or omitted entirely
            -- The important thing is that the JSON is valid and doesn't crash
            assert.is_not_nil(formatted:find("ERROR"))
            assert.is_not_nil(formatted:find("test.nonserial"))
        end)

        it("should provide fallback JSON when encoding completely fails", function()
            -- This is a bit tricky to test since dkjson is quite robust
            -- We'll mock a scenario where encoding might fail
            local original_encode = dkjson.encode
            dkjson.encode = function() return nil, "Mock encoding error" end

            local record = {
                timestamp = 1678886412,
                level_name = "CRITICAL",
                logger_name = "test.fail",
                message_fmt = "This should fail to encode",
                args = {},
            }

            local formatted = json_formatter(record)

            -- Restore original function
            dkjson.encode = original_encode

            -- Should get a fallback JSON with error information
            local parsed = dkjson.decode(formatted)
            assert.is_not_nil(parsed.error)
            assert.is_not_nil(parsed.error:find("JSON encoding failed"))
            assert.are.same("This should fail to encode", parsed.original_message)
        end)
    end)

    describe("Complex data types", function()
        it("should handle nested tables in arguments", function()
            local record = {
                timestamp = 1678886413,
                level_name = "INFO",
                logger_name = "test.nested",
                message_fmt = "Processing user data",
                args = {},
                user_data = {
                    name = "John Doe",
                    age = 30,
                    preferences = {
                        theme = "dark",
                        notifications = true
                    },
                    tags = { "admin", "power_user" }
                }
            }

            local formatted = json_formatter(record)
            local parsed = dkjson.decode(formatted)

            assert.is_not_nil(parsed.user_data)
            assert.are.same("John Doe", parsed.user_data.name)
            assert.are.same(30, parsed.user_data.age)
            assert.are.same("dark", parsed.user_data.preferences.theme)
            assert.is_true(parsed.user_data.preferences.notifications)
            assert.are.same({ "admin", "power_user" }, parsed.user_data.tags)
        end)

        it("should handle arrays and mixed data types", function()
            local record = {
                timestamp = 1678886414,
                level_name = "DEBUG",
                logger_name = "test.mixed",
                message_fmt = "Mixed data types test",
                args = {},
                mixed_data = {
                    string_val = "hello",
                    number_val = 42,
                    boolean_val = true,
                    null_val = dkjson.null,
                    array_val = { 1, 2, 3, "four", true }
                }
            }

            local formatted = json_formatter(record)
            local parsed = dkjson.decode(formatted)

            assert.are.same("hello", parsed.mixed_data.string_val)
            assert.are.same(42, parsed.mixed_data.number_val)
            assert.is_true(parsed.mixed_data.boolean_val)
            assert.is_nil(parsed.mixed_data.null_val) -- dkjson.null becomes nil when decoded
            assert.are.same({ 1, 2, 3, "four", true }, parsed.mixed_data.array_val)
        end)
    end)

    describe("Integration with lual.lib", function()
        it("should be accessible via lual.lib.json", function()
            local lualog = require("lual.logger")

            assert.is_not_nil(lualog.lib.json)
            assert.are.same(json_formatter, lualog.lib.json)
        end)
    end)
end)
