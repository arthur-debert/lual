package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua;../lua/?.lua;../lua/?/init.lua"
local unpack = unpack or table.unpack
local color_factory = require("lual.formatters.color")

describe("lual.formatters.color", function()
	local colors = {
		reset = "\27[0m",
		dim = "\27[2m",
		cyan = "\27[36m",
		blue = "\27[34m",
		green = "\27[32m",
		yellow = "\27[33m",
		red = "\27[31m",
		bright_red = "\27[91m",
		white = "\27[37m",
	}

	it("should format a basic log record with colors", function()
		local color = color_factory()
		local record = {
			timestamp = 1678886400, -- 2023-03-15 10:00:00 UTC
			timezone = "utc", -- Explicitly set timezone for predictable test
			level_name = "INFO",
			logger_name = "test.logger",
			message_fmt = "User %s logged in from %s",
			args = { "jane.doe", "10.0.0.1" },
		}
		local timestamp_str = os.date("!%Y-%m-%d %H:%M:%S", record.timestamp)
		local expected_message = string.format(record.message_fmt, unpack(record.args))
		local formatted = color(record)

		-- Print debug info
		print("Expected message:", expected_message)
		print("Formatted dispatcher:", formatted)

		assert.truthy(
			formatted:find(colors.dim .. timestamp_str .. colors.reset, 1, true),
			"Timestamp should be dimmed"
		)
		assert.truthy(
			formatted:find(colors.green .. record.level_name .. colors.reset, 1, true),
			"INFO level should be green"
		)
		assert.truthy(
			formatted:find(colors.cyan .. record.logger_name .. colors.reset, 1, true),
			"Logger name should be cyan"
		)
		-- Use string.find with better error reporting
		assert.truthy(formatted:find(expected_message, 1, true), "Message should contain the formatted message")
	end)

	it("should handle nil arguments gracefully", function()
		local color = color_factory()
		local record = {
			timestamp = 1678886401, -- 2023-03-15 10:00:01 UTC
			level_name = "DEBUG",
			logger_name = "nil.args.test",
			message_fmt = "Test message with no args",
			args = nil,
		}

		local formatted = color(record)

		assert.truthy(
			formatted:find(colors.blue .. record.level_name .. colors.reset, 1, true),
			"DEBUG level should be blue"
		)
		assert.truthy(formatted:find(record.message_fmt, 1, true), "Message should contain the message format string")
	end)

	it("should use fallbacks for missing optional record fields", function()
		local color = color_factory()
		local ts = 1678886402 -- 2023-03-15 10:00:02 UTC

		local record1 = {
			timestamp = ts,
			level_name = nil, -- Missing level_name
			logger_name = "test.missing.level",
			message_fmt = "Message with nil level",
			args = {},
		}
		local formatted1 = color(record1)

		assert.truthy(formatted1:find("UNKNOWN_LEVEL", 1, true), "Should use UNKNOWN_LEVEL fallback")
		assert.truthy(
			formatted1:find(colors.white .. "UNKNOWN_LEVEL" .. colors.reset, 1, true),
			"Unknown level should use white color"
		)

		local record2 = {
			timestamp = ts,
			level_name = "WARNING",
			logger_name = nil, -- Missing logger_name
			message_fmt = "Message with nil logger name",
			args = {},
		}
		local formatted2 = color(record2)

		assert.truthy(
			formatted2:find(colors.yellow .. "WARNING" .. colors.reset, 1, true),
			"WARNING level should be yellow"
		)
		assert.truthy(formatted2:find("UNKNOWN_LOGGER", 1, true), "Should use UNKNOWN_LOGGER fallback")
	end)

	it("should use custom colors when provided in config", function()
		local record = {
			timestamp = 1678886403, -- 2023-03-15 10:00:03 UTC
			level_name = "INFO",
			logger_name = "custom.colors.test",
			message_fmt = "Testing custom colors",
			args = {},
		}
		local custom_level_colors = {
			INFO = "bright_red", -- Override default green with bright_red
			DEBUG = "cyan",
			default = "yellow",
		}
		local color = color_factory({ level_colors = custom_level_colors })
		local formatted = color(record)
		assert.truthy(
			formatted:find(colors.bright_red .. "INFO" .. colors.reset, 1, true),
			"INFO level should use custom bright_red color"
		)
	end)

	describe("Timezone handling", function()
		it("should format timestamp in UTC when timezone is 'utc'", function()
			local color = color_factory()
			local record = {
				timestamp = 1609459200, -- 2021-01-01 00:00:00 UTC
				timezone = "utc",
				level_name = "INFO",
				logger_name = "test.utc",
				message_fmt = "UTC test message",
				args = {},
			}

			local formatted = color(record)

			-- Should contain UTC formatted timestamp
			assert.truthy(formatted:find("2021%-01%-01 00:00:00", 1, false), "Should contain UTC timestamp")
		end)

		it("should format timestamp in local time when timezone is 'local'", function()
			local color = color_factory()
			local record = {
				timestamp = 1609459200, -- 2021-01-01 00:00:00 UTC
				timezone = "local",
				level_name = "INFO",
				logger_name = "test.local",
				message_fmt = "Local test message",
				args = {},
			}

			local formatted = color(record)

			-- Should contain a valid timestamp format (can't predict exact local time)
			assert.matches("%d%d%d%d%-%d%d%-%d%d %d%d:%d%d:%d%d", formatted)
		end)

		it("should default to local timezone when timezone is nil", function()
			local color = color_factory()
			local record = {
				timestamp = 1609459200,
				timezone = nil,
				level_name = "INFO",
				logger_name = "test.default",
				message_fmt = "Default timezone test",
				args = {},
			}

			local formatted = color(record)

			-- Should contain a valid timestamp format
			assert.matches("%d%d%d%d%-%d%d%-%d%d %d%d:%d%d:%d%d", formatted)
		end)

		it("should handle case insensitive timezone values", function()
			local color = color_factory()
			local record = {
				timestamp = 1609459200,
				timezone = "UTC", -- Uppercase
				level_name = "INFO",
				logger_name = "test.case",
				message_fmt = "Case test message",
				args = {},
			}

			local formatted = color(record)

			-- Should contain UTC formatted timestamp
			assert.truthy(formatted:find("2021%-01%-01 00:00:00", 1, false), "Should contain UTC timestamp")
		end)
	end)
end)
