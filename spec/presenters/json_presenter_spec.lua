package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua;../lua/?.lua;../lua/?/init.lua"
local json_presenter_factory = require("lual.presenters.json")
local dkjson = require("dkjson")

describe("lual.presenters.json", function()
    describe("Basic functionality", function()
        it("should format a basic log record as JSON", function()
            local json_presenter = json_presenter_factory({ timezone = "utc" }) -- Set timezone in config for predictable test
            local record = {
                timestamp = 1678886400,                                         -- 2023-03-15 10:00:00 UTC
                level_name = "INFO",
                logger_name = "test.logger",
                message_fmt = "User %s logged in from %s",
                args = { "jane.doe", "10.0.0.1" },
            }

            local formatted = json_presenter(record)
            local parsed = dkjson.decode(formatted)

            assert.is_not_nil(parsed)
            assert.are.same(1678886400, parsed.timestamp)
            -- Check that it's a valid UTC ISO format with Z suffix
            assert.matches("%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%dZ", parsed.timestamp_iso)
            assert.are.same("utc", parsed.timezone)
            assert.are.same("INFO", parsed.level)
            assert.are.same("test.logger", parsed.logger)
            assert.are.same("User %s logged in from %s", parsed.message_fmt)
            assert.are.same({ "jane.doe", "10.0.0.1" }, parsed.args)
            assert.are.same("User jane.doe logged in from 10.0.0.1", parsed.message)
        end)

        it("should handle records with no arguments", function()
            local json_presenter = json_presenter_factory()
            local record = {
                timestamp = 1678886401,
                level_name = "DEBUG",
                logger_name = "test.debug",
                message_fmt = "Simple debug message",
                args = {},
            }

            local formatted = json_presenter(record)
            local parsed = dkjson.decode(formatted)

            assert.is_not_nil(parsed)
            assert.are.same("DEBUG", parsed.level)
            assert.are.same("Simple debug message", parsed.message)
            assert.are.same({}, parsed.args)
        end)

        it("should handle records with nil arguments", function()
            local json_presenter = json_presenter_factory()
            local record = {
                timestamp = 1678886402,
                level_name = "WARNING",
                logger_name = "test.warning",
                message_fmt = "Warning message with no args",
                args = nil,
            }

            local formatted = json_presenter(record)
            local parsed = dkjson.decode(formatted)

            assert.is_not_nil(parsed)
            assert.are.same("WARNING", parsed.level)
            assert.are.same("Warning message with no args", parsed.message)
            assert.are.same({}, parsed.args)
        end)
    end)

    describe("Fallback handling", function()
        it("should use fallbacks for missing optional fields", function()
            local json_presenter = json_presenter_factory()
            local record = {
                timestamp = 1678886403,
                level_name = nil,
                logger_name = nil,
                message_fmt = "Message with missing fields",
                args = {},
            }

            local formatted = json_presenter(record)
            local parsed = dkjson.decode(formatted)

            assert.is_not_nil(parsed)
            assert.are.same("UNKNOWN_LEVEL", parsed.level)
            assert.are.same("UNKNOWN_LOGGER", parsed.logger)
            assert.are.same("Message with missing fields", parsed.message)
        end)

        it("should handle formatting errors gracefully", function()
            local json_presenter = json_presenter_factory()
            local record = {
                timestamp = 1678886404,
                level_name = "ERROR",
                logger_name = "test.error",
                message_fmt = "User %s has %d items and %s status",
                args = { "john", "not_a_number" }, -- Wrong type for %d
            }

            local formatted = json_presenter(record)
            local parsed = dkjson.decode(formatted)

            assert.is_not_nil(parsed)
            assert.are.same("ERROR", parsed.level)
            assert.are.same("User %s has %d items and %s status", parsed.message)
            assert.are.same("Failed to format message with provided arguments", parsed.format_error)
        end)

        it("should handle non-table args gracefully", function()
            local json_presenter = json_presenter_factory()
            local record = {
                timestamp = 1678886405,
                level_name = "INFO",
                logger_name = "test.info",
                message_fmt = "Simple message",
                args = "not_a_table",
            }

            local formatted = json_presenter(record)
            local parsed = dkjson.decode(formatted)

            assert.is_not_nil(parsed)
            assert.are.same("Simple message", parsed.message)
            assert.are.same("not_a_table", parsed.args)
        end)
    end)

    describe("Configuration options", function()
        it("should format as compact JSON by default", function()
            local json_presenter = json_presenter_factory()
            local record = {
                timestamp = 1678886406,
                level_name = "INFO",
                logger_name = "test.compact",
                message_fmt = "Test message",
                args = {},
            }

            local formatted = json_presenter(record)

            -- Compact JSON should not contain newlines or extra spaces
            assert.is_nil(formatted:find("\n"))
            assert.is_nil(formatted:find("  ")) -- Two spaces indicating indentation
        end)

        it("should format as pretty JSON when configured", function()
            local json_presenter = json_presenter_factory({ pretty = true })
            local record = {
                timestamp = 1678886407,
                level_name = "INFO",
                logger_name = "test.pretty",
                message_fmt = "Test message",
                args = {},
            }

            local formatted = json_presenter(record)

            -- Pretty JSON should contain newlines and indentation
            assert.is_not_nil(formatted:find("\n"))
            assert.is_not_nil(formatted:find("  ")) -- Indentation spaces
        end)
    end)

    describe("Additional fields handling", function()
        it("should include caller_info when present", function()
            local json_presenter = json_presenter_factory()
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

            local formatted = json_presenter(record)
            local parsed = dkjson.decode(formatted)

            assert.is_not_nil(parsed.caller_info)
            assert.are.same("test.lua", parsed.caller_info.file)
            assert.are.same(42, parsed.caller_info.line)
            assert.are.same("test_function", parsed.caller_info.func)
        end)

        it("should include extra fields from record", function()
            local json_presenter = json_presenter_factory()
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

            local formatted = json_presenter(record)
            local parsed = dkjson.decode(formatted)

            assert.are.same("12345", parsed.user_id)
            assert.are.same("abcdef", parsed.session_id)
            assert.are.same("req-789", parsed.request_id)
        end)

        it("should not override core fields with extra fields", function()
            local json_presenter = json_presenter_factory()
            local record = {
                timestamp = 1678886410,
                level_name = "INFO",
                logger_name = "test.override",
                message_fmt = "Test message",
                args = {},
                level = "SHOULD_NOT_OVERRIDE", -- This should not override the mapped level
                logger = "SHOULD_NOT_OVERRIDE" -- This should not override the mapped logger
            }

            local formatted = json_presenter(record)
            local parsed = dkjson.decode(formatted)

            -- Core fields should not be overridden
            assert.are.same("INFO", parsed.level)
            assert.are.same("test.override", parsed.logger)
        end)
    end)

    describe("Error handling", function()
        it("should handle non-serializable values gracefully", function()
            local json_presenter = json_presenter_factory()
            local record = {
                timestamp = 1678886411,
                level_name = "ERROR",
                logger_name = "test.nonserial",
                message_fmt = "Message with non-serializable data",
                args = {},
                func_value = function() return "test" end,      -- Functions are not JSON serializable
                thread_value = coroutine.create(function() end) -- Threads are not JSON serializable
            }

            local formatted = json_presenter(record)

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
            local json_presenter = json_presenter_factory()
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

            local formatted = json_presenter(record)

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
            local json_presenter = json_presenter_factory()
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

            local formatted = json_presenter(record)
            local parsed = dkjson.decode(formatted)

            assert.is_not_nil(parsed.user_data)
            assert.are.same("John Doe", parsed.user_data.name)
            assert.are.same(30, parsed.user_data.age)
            assert.are.same("dark", parsed.user_data.preferences.theme)
            assert.is_true(parsed.user_data.preferences.notifications)
            assert.are.same({ "admin", "power_user" }, parsed.user_data.tags)
        end)

        it("should handle arrays and mixed data types", function()
            local json_presenter = json_presenter_factory()
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

            local formatted = json_presenter(record)
            local parsed = dkjson.decode(formatted)

            assert.are.same("hello", parsed.mixed_data.string_val)
            assert.are.same(42, parsed.mixed_data.number_val)
            assert.is_true(parsed.mixed_data.boolean_val)
            assert.is_nil(parsed.mixed_data.null_val) -- dkjson.null becomes nil when decoded
            assert.are.same({ 1, 2, 3, "four", true }, parsed.mixed_data.array_val)
        end)
    end)

    describe("Timezone handling", function()
        it("should format timestamp in UTC when timezone is 'utc'", function()
            local json_presenter = json_presenter_factory({ timezone = "utc" })
            local record = {
                timestamp = 1609459200, -- 2021-01-01 00:00:00 UTC
                level_name = "INFO",
                logger_name = "test.utc",
                message_fmt = "UTC test message",
                args = {},
            }

            local formatted = json_presenter(record)
            local parsed = dkjson.decode(formatted)

            assert.is_not_nil(parsed)
            assert.are.same("utc", parsed.timezone)
            assert.are.same("2021-01-01T00:00:00Z", parsed.timestamp_iso)
        end)

        it("should format timestamp in local time when timezone is 'local'", function()
            local json_presenter = json_presenter_factory({ timezone = "local" })
            local record = {
                timestamp = 1609459200, -- 2021-01-01 00:00:00 UTC
                level_name = "INFO",
                logger_name = "test.local",
                message_fmt = "Local test message",
                args = {},
            }

            local formatted = json_presenter(record)
            local parsed = dkjson.decode(formatted)

            assert.is_not_nil(parsed)
            assert.are.same("local", parsed.timezone)
            -- For local time, should not end with Z
            assert.is_not.matches("Z$", parsed.timestamp_iso)
            -- Should match ISO format
            assert.matches("%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%d", parsed.timestamp_iso)
        end)

        it("should default to local timezone when no timezone is configured", function()
            local json_presenter = json_presenter_factory() -- No timezone config, defaults to local
            local record = {
                timestamp = 1609459200,
                level_name = "INFO",
                logger_name = "test.default",
                message_fmt = "Default timezone test",
                args = {},
            }

            local formatted = json_presenter(record)
            local parsed = dkjson.decode(formatted)

            assert.is_not_nil(parsed)
            assert.are.same("local", parsed.timezone)
        end)

        it("should handle case insensitive timezone values", function()
            local json_presenter = json_presenter_factory({ timezone = "UTC" }) -- Uppercase
            local record = {
                timestamp = 1609459200,
                level_name = "INFO",
                logger_name = "test.case",
                message_fmt = "Case test message",
                args = {},
            }

            local formatted = json_presenter(record)
            local parsed = dkjson.decode(formatted)

            assert.is_not_nil(parsed)
            assert.are.same("UTC", parsed.timezone)
            assert.are.same("2021-01-01T00:00:00Z", parsed.timestamp_iso)
        end)
    end)

    describe("Integration with lual constants", function()
        it("should be accessible via flat namespace", function()
            local lualog = require("lual.logger")

            -- Check flat namespace constant
            assert.are.equal("json", lualog.json)

            -- Get the actual presenter function
            local all_presenters = require("lual.presenters.init")
            local json_presenter = all_presenters.json()

            assert.is_table(json_presenter)
            assert.is_not_nil(getmetatable(json_presenter))
            assert.is_function(getmetatable(json_presenter).__call)

            -- Test that it actually works as a presenter
            local test_record = {
                timestamp = 1640995200,
                level_name = "INFO",
                logger_name = "test",
                message_fmt = "test message",
                args = {}
            }
            local result = json_presenter(test_record)
            assert.is_string(result)
            local parsed = require("dkjson").decode(result)
            assert.is_table(parsed)
            assert.are.same("INFO", parsed.level)
            assert.are.same("test message", parsed.message)
        end)

        it("should have flat namespace constant lual.json", function()
            local lualog = require("lual.logger")

            assert.is_not_nil(lualog.json)
            assert.are.equal("json", lualog.json)

            -- Test that the flat constant works in logger config
            local logger = lualog.logger({
                dispatcher = lualog.console,
                presenter = lualog.json,
                level = lualog.info
            })

            assert.is_not_nil(logger)
            assert.are.equal(lualog.info, logger.level)
        end)
    end)
end)
