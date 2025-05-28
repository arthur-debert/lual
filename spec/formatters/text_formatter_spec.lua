package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua;../lua/?.lua;../lua/?/init.lua"
local text_formatter = require("lual.formatters.text")

describe("lual.formatters.text", function()
    describe("Basic functionality", function()
        it("should format a basic log record as text", function()
            local record = {
                timestamp = 1678886400, -- 2023-03-15 10:00:00 UTC
                timezone = "utc",
                level_name = "INFO",
                logger_name = "test.logger",
                message_fmt = "User %s logged in from %s",
                args = { "jane.doe", "10.0.0.1" },
            }

            local formatted = text_formatter(record)

            assert.is_string(formatted)
            -- Use a more flexible pattern to match the timestamp
            assert.matches("%d%d%d%d%-%d%d%-%d%d %d%d:%d%d:%d%d", formatted)
            assert.truthy(formatted:find("INFO"))
            assert.truthy(formatted:find("test.logger"))
            assert.truthy(formatted:find("User jane.doe logged in from 10.0.0.1"))
        end)

        it("should handle records with no arguments", function()
            local record = {
                timestamp = 1678886401,
                timezone = "local",
                level_name = "DEBUG",
                logger_name = "test.debug",
                message_fmt = "Simple debug message",
                args = {},
            }

            local formatted = text_formatter(record)

            assert.is_string(formatted)
            assert.truthy(formatted:find("DEBUG"))
            assert.truthy(formatted:find("test.debug"))
            assert.truthy(formatted:find("Simple debug message"))
        end)

        it("should handle context-only logs", function()
            local record = {
                timestamp = 1678886402,
                timezone = "local",
                level_name = "INFO",
                logger_name = "test.context",
                message_fmt = nil,
                args = {},
                context = { user_id = 123, action = "login" }
            }

            local formatted = text_formatter(record)

            assert.is_string(formatted)
            assert.truthy(formatted:find("INFO"))
            assert.truthy(formatted:find("test.context"))
            assert.truthy(formatted:find("user_id=123"))
            assert.truthy(formatted:find("action=login"))
        end)
    end)

    describe("Timezone handling", function()
        it("should format timestamp in UTC when timezone is 'utc'", function()
            local record = {
                timestamp = 1609459200, -- 2021-01-01 00:00:00 UTC
                timezone = "utc",
                level_name = "INFO",
                logger_name = "test.utc",
                message_fmt = "UTC test message",
                args = {},
            }

            local formatted = text_formatter(record)

            -- Should contain UTC formatted timestamp
            assert.truthy(formatted:find("2021%-01%-01 00:00:00"))
        end)

        it("should format timestamp in local time when timezone is 'local'", function()
            local record = {
                timestamp = 1609459200, -- 2021-01-01 00:00:00 UTC
                timezone = "local",
                level_name = "INFO",
                logger_name = "test.local",
                message_fmt = "Local test message",
                args = {},
            }

            local formatted = text_formatter(record)

            -- Should contain a valid timestamp format (can't predict exact local time)
            assert.matches("%d%d%d%d%-%d%d%-%d%d %d%d:%d%d:%d%d", formatted)
        end)

        it("should default to local timezone when timezone is nil", function()
            local record = {
                timestamp = 1609459200,
                timezone = nil,
                level_name = "INFO",
                logger_name = "test.default",
                message_fmt = "Default timezone test",
                args = {},
            }

            local formatted = text_formatter(record)

            -- Should contain a valid timestamp format
            assert.matches("%d%d%d%d%-%d%d%-%d%d %d%d:%d%d:%d%d", formatted)
        end)

        it("should handle case insensitive timezone values", function()
            local record = {
                timestamp = 1609459200,
                timezone = "UTC", -- Uppercase
                level_name = "INFO",
                logger_name = "test.case",
                message_fmt = "Case test message",
                args = {},
            }

            local formatted = text_formatter(record)

            -- Should contain UTC formatted timestamp
            assert.truthy(formatted:find("2021%-01%-01 00:00:00"))
        end)
    end)

    describe("Fallback handling", function()
        it("should use fallbacks for missing optional fields", function()
            local record = {
                timestamp = 1678886403,
                timezone = "local",
                level_name = nil,
                logger_name = nil,
                message_fmt = "Message with missing fields",
                args = {},
            }

            local formatted = text_formatter(record)

            assert.truthy(formatted:find("UNKNOWN_LEVEL"))
            assert.truthy(formatted:find("UNKNOWN_LOGGER"))
            assert.truthy(formatted:find("Message with missing fields"))
        end)
    end)

    describe("Integration with lual.lib", function()
        it("should be accessible via lual.lib.text", function()
            local lualog = require("lual.logger")

            assert.is_not_nil(lualog.lib.text)
            assert.are.same(text_formatter, lualog.lib.text)
        end)
    end)
end)
