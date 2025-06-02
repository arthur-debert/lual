package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua;../lua/?.lua;../lua/?/init.lua"
local text_presenter_factory = require("lual.presenters.text")

describe("lual.presenters.text", function()
    local text_presenter

    before_each(function()
        text_presenter = text_presenter_factory()
    end)

    describe("Basic functionality", function()
        it("should format a basic log record as text", function()
            local record = {
                timestamp = 1678886400, -- 2023-03-15 10:00:00 UTC
                level_name = "INFO",
                logger_name = "test.logger",
                message_fmt = "User %s logged in from %s",
                args = { "jane.doe", "10.0.0.1" },
            }

            local formatted = text_presenter(record)

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
                level_name = "DEBUG",
                logger_name = "test.debug",
                message_fmt = "Simple debug message",
                args = {},
            }

            local formatted = text_presenter(record)

            assert.is_string(formatted)
            assert.truthy(formatted:find("DEBUG"))
            assert.truthy(formatted:find("test.debug"))
            assert.truthy(formatted:find("Simple debug message"))
        end)

        it("should handle context-only logs", function()
            local record = {
                timestamp = 1678886402,
                level_name = "INFO",
                logger_name = "test.context",
                message_fmt = nil,
                args = {},
                context = { user_id = 123, action = "login" }
            }

            local formatted = text_presenter(record)

            assert.is_string(formatted)
            assert.truthy(formatted:find("INFO"))
            assert.truthy(formatted:find("test.context"))
            assert.truthy(formatted:find("user_id=123"))
            assert.truthy(formatted:find("action=login"))
        end)
    end)

    describe("Timezone handling", function()
        it("should format timestamp in UTC when timezone is 'utc'", function()
            local utc_presenter = text_presenter_factory({ timezone = "utc" })
            local record = {
                timestamp = 1609459200, -- 2021-01-01 00:00:00 UTC
                level_name = "INFO",
                logger_name = "test.utc",
                message_fmt = "UTC test message",
                args = {},
            }

            local formatted = utc_presenter(record)

            -- Should contain UTC formatted timestamp
            assert.truthy(formatted:find("2021%-01%-01 00:00:00"))
        end)

        it("should format timestamp in local time when timezone is 'local'", function()
            local local_presenter = text_presenter_factory({ timezone = "local" })
            local record = {
                timestamp = 1609459200, -- 2021-01-01 00:00:00 UTC
                level_name = "INFO",
                logger_name = "test.local",
                message_fmt = "Local test message",
                args = {},
            }

            local formatted = local_presenter(record)

            -- Should contain a valid timestamp format (can't predict exact local time)
            assert.matches("%d%d%d%d%-%d%d%-%d%d %d%d:%d%d:%d%d", formatted)
        end)

        it("should default to local timezone when no timezone is configured", function()
            local default_presenter = text_presenter_factory() -- No timezone config, defaults to local
            local record = {
                timestamp = 1609459200,
                level_name = "INFO",
                logger_name = "test.default",
                message_fmt = "Default timezone test",
                args = {},
            }

            local formatted = default_presenter(record)

            -- Should contain a valid timestamp format
            assert.matches("%d%d%d%d%-%d%d%-%d%d %d%d:%d%d:%d%d", formatted)
        end)

        it("should handle case insensitive timezone values", function()
            local case_presenter = text_presenter_factory({ timezone = "UTC" }) -- Uppercase
            local record = {
                timestamp = 1609459200,
                level_name = "INFO",
                logger_name = "test.case",
                message_fmt = "Case test message",
                args = {},
            }

            local formatted = case_presenter(record)

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

            local formatted = text_presenter(record)

            assert.truthy(formatted:find("UNKNOWN_LEVEL"))
            assert.truthy(formatted:find("UNKNOWN_LOGGER"))
            assert.truthy(formatted:find("Message with missing fields"))
        end)
    end)

    describe("Integration with lual constants", function()
        it("should be accessible via flat namespace", function()
            local lualog = require("lual.logger")

            -- Check flat namespace constant
            assert.are.equal("text", lualog.text)

            -- Get the actual presenter function
            local all_presenters = require("lual.presenters.init")
            local text_presenter = all_presenters.text()

            assert.is_table(text_presenter)
            assert.is_not_nil(getmetatable(text_presenter))
            assert.is_function(getmetatable(text_presenter).__call)

            -- Test that it actually works as a presenter
            local test_record = {
                timestamp = 1640995200,
                timezone = "utc",
                level_name = "INFO",
                logger_name = "test",
                message_fmt = "test message",
                args = {}
            }
            local result = text_presenter(test_record)
            assert.is_string(result)
            assert.truthy(result:find("INFO"))
            assert.truthy(result:find("test message"))
        end)

        it("should have flat namespace constant lual.text", function()
            local lualog = require("lual.logger")

            assert.is_not_nil(lualog.text)
            assert.are.equal("text", lualog.text)

            -- Test that the flat constant works in logger config
            local logger = lualog.logger({
                dispatcher = lualog.console,
                presenter = lualog.text,
                level = lualog.debug
            })

            assert.is_not_nil(logger)
            assert.are.equal(lualog.debug, logger.level)
        end)
    end)
end)
