package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua;../lua/?.lua;../lua/?/init.lua"

-- Compatibility for Lua 5.1 if running in a context where table.unpack is not defined
local unpack = unpack or table.unpack
local lualog = require("lual.logger")

describe("text presenter", function()
	it("should format a basic log record", function()
		local all_presenters = require("lual.presenters.init")
		local text_presenter = all_presenters.text()

		local record = {
			timestamp = 1678886400, -- 2023-03-15 10:00:00 UTC
			timezone = "utc", -- Explicitly set timezone for predictable test
			level_name = "INFO",
			logger_name = "test.logger",
			message_fmt = "User %s logged in from %s",
			args = { "jane.doe", "10.0.0.1" },
		}
		local expected_timestamp = os.date("!%Y-%m-%d %H:%M:%S", record.timestamp)
		local expected_dispatcher = expected_timestamp .. " INFO [test.logger] User jane.doe logged in from 10.0.0.1"
		assert.are.same(expected_dispatcher, text_presenter(record))
	end)

	it("should handle nil arguments gracefully", function()
		local all_presenters = require("lual.presenters.init")
		local text_presenter = all_presenters.text()

		local record = {
			timestamp = 1678886401, -- 2023-03-15 10:00:01 UTC
			timezone = "utc", -- Explicitly set timezone for predictable test
			level_name = "DEBUG",
			logger_name = "nil.args.test",
			message_fmt = "Test message with no args",
			args = nil,
		}
		local expected_timestamp = os.date("!%Y-%m-%d %H:%M:%S", record.timestamp)
		local expected_dispatcher = expected_timestamp .. " DEBUG [nil.args.test] Test message with no args"
		assert.are.same(expected_dispatcher, text_presenter(record))
	end)

	it("should handle empty arguments table", function()
		local all_presenters = require("lual.presenters.init")
		local text_presenter = all_presenters.text()

		local record = {
			timestamp = 1678886402, -- 2023-03-15 10:00:02 UTC
			timezone = "utc", -- Explicitly set timezone for predictable test
			level_name = "WARNING",
			logger_name = "empty.args.test",
			message_fmt = "Test message with empty args",
			args = {},
		}
		local expected_timestamp = os.date("!%Y-%m-%d %H:%M:%S", record.timestamp)
		local expected_dispatcher = expected_timestamp .. " WARNING [empty.args.test] Test message with empty args"
		assert.are.same(expected_dispatcher, text_presenter(record))
	end)

	it("should use fallbacks for missing optional record fields", function()
		local all_presenters = require("lual.presenters.init")
		local text_presenter = all_presenters.text()

		local ts = 1678886403 -- 2023-03-15 10:00:03 UTC
		local expected_timestamp = os.date("!%Y-%m-%d %H:%M:%S", ts)

		local record1 = {
			timestamp = ts,
			timezone = "utc", -- Explicitly set timezone for predictable test
			level_name = nil, -- Missing level_name
			logger_name = "test.missing.level",
			message_fmt = "Message with nil level",
			args = {},
		}
		local expected_dispatcher1 = expected_timestamp .. " UNKNOWN_LEVEL [test.missing.level] Message with nil level"
		assert.are.same(expected_dispatcher1, text_presenter(record1))

		local record2 = {
			timestamp = ts,
			timezone = "utc", -- Explicitly set timezone for predictable test
			level_name = "ERROR",
			logger_name = nil, -- Missing logger_name
			message_fmt = "Message with nil logger name",
			args = {},
		}
		local expected_dispatcher2 = expected_timestamp .. " ERROR [UNKNOWN_LOGGER] Message with nil logger name"
		assert.are.same(expected_dispatcher2, text_presenter(record2))

		local record3 = {
			timestamp = ts,
			timezone = "utc", -- Explicitly set timezone for predictable test
			level_name = "CRITICAL",
			logger_name = "test.missing.args",
			message_fmt = "Message with missing args",
			args = nil, -- Missing args
		}
		local expected_dispatcher3 = expected_timestamp .. " CRITICAL [test.missing.args] Message with missing args"
		assert.are.same(expected_dispatcher3, text_presenter(record3))
	end)
end)

describe("console dispatcher", function()
	local mock_stream
	local original_stdout
	local mock_stderr_stream
	local original_stderr

	before_each(function()
		-- Mock for general stream testing
		mock_stream = {
			written_data = "",
			flushed = false,
			write = function(self, ...)
				for i = 1, select("#", ...) do
					self.written_data = self.written_data .. tostring(select(i, ...))
				end
			end,
			flush = function(self)
				self.flushed = true
			end,
		}
		-- Store original io.stdout and replace it
		original_stdout = io.stdout
		io.stdout = mock_stream -- Default for some tests

		-- Mock for stderr testing
		mock_stderr_stream = {
			written_data = "",
			write = function(self, ...)
				for i = 1, select("#", ...) do
					self.written_data = self.written_data .. tostring(select(i, ...))
				end
			end,
			flush = function(self) end, -- Not strictly needed for stderr mock unless testing flush
		}
		original_stderr = io.stderr
		io.stderr = mock_stderr_stream
	end)

	after_each(function()
		-- Restore original streams
		io.stdout = original_stdout
		io.stderr = original_stderr
	end)

	it("should write to default stream (io.stdout) if no stream specified in config", function()
		local all_dispatchers = require("lual.dispatchers.init")

		local record = { message = "Hello default stdout" }
		all_dispatchers.console_dispatcher(record, {}) -- Empty config
		assert.are.same("Hello default stdout\n", mock_stream.written_data)
		assert.is_true(mock_stream.flushed)
	end)

	it("should write to a custom stream if specified in config", function()
		local all_dispatchers = require("lual.dispatchers.init")

		local custom_mock_stream = {
			written_data = "",
			flushed = false,
			write = function(self, ...)
				for i = 1, select("#", ...) do
					self.written_data = self.written_data .. tostring(select(i, ...))
				end
			end,
			flush = function(self)
				self.flushed = true
			end,
		}
		local record = { message = "Hello custom stream" }
		all_dispatchers.console_dispatcher(record, { stream = custom_mock_stream })

		assert.are.same("Hello custom stream\n", custom_mock_stream.written_data)
		assert.is_true(custom_mock_stream.flushed)
		assert.are.same("", mock_stream.written_data) -- Ensure default io.stdout (mocked by mock_stream) was not written to
	end)

	it("should handle stream write error and report to io.stderr", function()
		local all_dispatchers = require("lual.dispatchers.init")

		local erroring_mock_stream = {
			write = function(self, ...)
				error("Simulated stream write error")
			end,
			flush = function(self)
				-- This might or might not be called depending on pcall sequence
			end,
		}
		local record = { message = "Message that will fail to write" }

		-- Call the dispatcher with the erroring stream
		all_dispatchers.console_dispatcher(record, { stream = erroring_mock_stream })

		-- Check that an error message was written to our mock_stderr_stream
		assert.is_not_nil(string.find(mock_stderr_stream.written_data, "Error writing to stream:", 1, true))
		assert.is_not_nil(string.find(mock_stderr_stream.written_data, "Simulated stream write error", 1, true))

		-- Ensure default io.stdout (mocked by mock_stream) was not written to with the original message
		assert.are.same("", mock_stream.written_data)
	end)
end)
