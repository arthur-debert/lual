local assert = require("luassert")
-- busted is expected to be a global or run via a CLI that provides describe, it, etc.
-- require("busted")

-- luacheck: globals describe it setup teardown os io

describe("lual.outputs.file_output", function()
	local file_output_factory

	-- Mock storage, localized to this describe block
	local mock_os_rename_calls
	local mock_os_remove_calls
	local mock_io_open_calls
	local mock_io_stderr_write_messages
	local mock_file_object

	local original_os_rename
	local original_os_remove
	local original_io_open
	local original_io_stderr

	setup(function()
		-- Store originals
		original_os_rename = os.rename
		original_os_remove = os.remove
		original_io_open = io.open
		original_io_stderr = io.stderr

		-- Mock implementations
		mock_os_rename_calls = {}
		mock_os_remove_calls = {}
		mock_io_open_calls = {}
		mock_io_stderr_write_messages = {}

		mock_file_object = {
			write_calls = {},
			flush_calls = 0,
			close_calls = 0,
			write = function(self, msg)
				table.insert(self.write_calls, msg)
			end,
			flush = function(self)
				self.flush_calls = self.flush_calls + 1
			end,
			close = function(self)
				self.close_calls = self.close_calls + 1
			end,
		}

		os.rename = function(old, new)
			table.insert(mock_os_rename_calls, { old = old, new = new })
			return true -- Simulate success for actual renames
		end

		os.remove = function(path)
			table.insert(mock_os_remove_calls, path)
			return true -- Simulate success
		end

		io.open = function(path, mode)
			table.insert(mock_io_open_calls, { path = path, mode = mode })
			if mode == "r" then -- For existence checks in rotation
				-- Default: no files exist (return nil)
				-- Tests can override this behavior by setting up specific mocks
				return nil, "No such file or directory"
			end
			return mock_file_object, nil -- Simulate success for append/write
		end

		io.stderr = {
			write = function(self, msg)
				table.insert(mock_io_stderr_write_messages, msg)
			end,
		}

		-- Clear lual's cache if it's already loaded to get fresh mocks
		package.loaded["lual.outputs.file_output"] = nil
		file_output_factory = require("lual.outputs.file_output")
	end)

	before_each(function()
		-- Reset mock call arrays between tests
		mock_os_rename_calls = {}
		mock_os_remove_calls = {}
		mock_io_open_calls = {}
		mock_io_stderr_write_messages = {}

		-- Reset mock file object state but preserve function implementations
		mock_file_object.write_calls = {}
		mock_file_object.flush_calls = 0
		mock_file_object.close_calls = 0

		-- Reset mock file object functions to default implementations
		mock_file_object.write = function(self, msg)
			table.insert(self.write_calls, msg)
		end
		mock_file_object.flush = function(self)
			self.flush_calls = self.flush_calls + 1
		end
		mock_file_object.close = function(self)
			self.close_calls = self.close_calls + 1
		end

		-- Restore default mock functions (in case tests override them)
		os.rename = function(old, new)
			table.insert(mock_os_rename_calls, { old = old, new = new })
			return true -- Simulate success for actual renames
		end

		os.remove = function(path)
			table.insert(mock_os_remove_calls, path)
			return true -- Simulate success
		end

		io.open = function(path, mode)
			table.insert(mock_io_open_calls, { path = path, mode = mode })
			if mode == "r" then -- For existence checks in rotation
				-- Default: no files exist (return nil)
				-- Tests can override this behavior by setting up specific mocks
				return nil, "No such file or directory"
			end
			return mock_file_object, nil -- Simulate success for append/write
		end
	end)

	teardown(function()
		-- Restore originals
		os.rename = original_os_rename
		os.remove = original_os_remove
		io.open = original_io_open
		io.stderr = original_io_stderr

		-- Clear mocks and calls
		mock_os_rename_calls = nil
		mock_os_remove_calls = nil
		mock_io_open_calls = nil
		mock_io_stderr_write_messages = nil
		mock_file_object = nil
	end)

	it("should require config.path", function()
		file_output_factory({})
		local msg1 = mock_io_stderr_write_messages[1]
		assert.truthy(msg1 and string.find(msg1, "requires config.path"))

		-- Reset for next check within same test
		mock_io_stderr_write_messages = {}
		file_output_factory({ path = 123 }) -- Invalid type
		local msg2 = mock_io_stderr_write_messages[1]
		assert.truthy(msg2 and string.find(msg2, "requires config.path"))
	end)

	describe("Log Rotation", function()
		local log_path = "test_app.log"

		it("should attempt to remove oldest backup (e.g., .5)", function()
			-- Simulate oldest_backup_path (.5) exists
			io.open = function(path, mode)
				table.insert(mock_io_open_calls, { path = path, mode = mode })
				if mode == "r" and path == log_path .. ".5" then
					return { close = function() end } -- .5 exists
				elseif mode == "r" then
					return nil, "No such file" -- Other files don't exist
				end
				return mock_file_object -- for append mode
			end

			file_output_factory({ path = log_path })

			-- Check that .5 was checked for existence
			assert.are.same({ path = log_path .. ".5", mode = "r" }, mock_io_open_calls[1])
			-- Check that .5 was removed
			assert.are.same(log_path .. ".5", mock_os_remove_calls[1])
		end)

		it("should shift backups from .4 down to .1", function()
			-- Simulate all backup files .1 to .4 exist
			io.open = function(path, mode)
				table.insert(mock_io_open_calls, { path = path, mode = mode })
				if mode == "r" then
					if string.match(path, "test_app%.log%.[1-4]$") then
						return { close = function() end } -- .1-.4 exist
					else
						return nil, "No such file" -- .5 and main log don't exist
					end
				end
				return mock_file_object -- for append mode
			end

			file_output_factory({ path = log_path })

			-- Expected rename operations for shifting
			-- .4 -> .5, .3 -> .4, .2 -> .3, .1 -> .2
			local expected_renames = {
				{ old = log_path .. ".4", new = log_path .. ".5" },
				{ old = log_path .. ".3", new = log_path .. ".4" },
				{ old = log_path .. ".2", new = log_path .. ".3" },
				{ old = log_path .. ".1", new = log_path .. ".2" },
			}

			-- Check that the renames happened
			assert.are.same(expected_renames[1], mock_os_rename_calls[1]) -- .4 -> .5
			assert.are.same(expected_renames[2], mock_os_rename_calls[2]) -- .3 -> .4
			assert.are.same(expected_renames[3], mock_os_rename_calls[3]) -- .2 -> .3
			assert.are.same(expected_renames[4], mock_os_rename_calls[4]) -- .1 -> .2
		end)

		it("should rotate current log to .1 if it exists", function()
			-- Simulate current log exists
			io.open = function(path, mode)
				table.insert(mock_io_open_calls, { path = path, mode = mode })
				if mode == "r" and path == log_path then
					return { close = function() end } -- main log exists
				elseif mode == "r" then
					return nil, "No such file" -- backups don't exist
				end
				return mock_file_object -- for append mode
			end

			file_output_factory({ path = log_path })

			-- Find the rename of current log to .1
			local found_rename_current_log = false
			for _, call in ipairs(mock_os_rename_calls) do
				if call.old == log_path and call.new == log_path .. ".1" then
					found_rename_current_log = true
					break
				end
			end
			assert.is_true(found_rename_current_log, "Current log was not renamed to .1")
		end)

		it("should handle rotation when no previous log files exist", function()
			-- Default mock behavior: no files exist (already set in setup)
			file_output_factory({ path = log_path })

			-- Check that existence checks were made for all files during rotation
			local expected_checks = {
				{ path = log_path .. ".5", mode = "r" }, -- Check .5
				{ path = log_path .. ".4", mode = "r" }, -- Check .4
				{ path = log_path .. ".3", mode = "r" }, -- Check .3
				{ path = log_path .. ".2", mode = "r" }, -- Check .2
				{ path = log_path .. ".1", mode = "r" }, -- Check .1
				{ path = log_path,         mode = "r" }, -- Check main log
			}

			assert.are.equal(6, #mock_io_open_calls)
			for i, expected in ipairs(expected_checks) do
				assert.are.same(expected, mock_io_open_calls[i])
			end

			-- No renames or removes should have happened
			assert.are.equal(0, #mock_os_rename_calls)
			assert.are.equal(0, #mock_os_remove_calls)
		end)
	end)

	describe("File Writing", function()
		local log_path = "write_test.log"

		it("should open the new log file in append mode for writing", function()
			local handler = file_output_factory({ path = log_path })
			mock_io_open_calls = {} -- Clear calls from rotation phase

			handler({ message = "dummy write to trigger open" })

			assert.are.equal(1, #mock_io_open_calls, "Expected one io.open call by handler")
			assert.are.same({ path = log_path, mode = "a" }, mock_io_open_calls[1])
		end)

		it("should write record message, newline, and flush", function()
			local handler = file_output_factory({ path = log_path })
			local record = { message = "Test log message" }
			handler(record)

			assert.are.same({ "Test log message", "\n" }, mock_file_object.write_calls)
			assert.are.equal(1, mock_file_object.flush_calls)
			assert.are.equal(1, mock_file_object.close_calls) -- Ensure file is closed after write
		end)

		it("should handle io.open failure when writing", function()
			io.open = function(path, mode)
				table.insert(mock_io_open_calls, { path = path, mode = mode })
				if mode == "a" and path == log_path then
					return nil, "Permission denied" -- Simulate open failure
				end
				-- For rotation phase, assume no files exist
				if mode == "r" then
					return nil, "No such file"
				end
				return mock_file_object -- Should not be reached for the 'a' mode in this test
			end

			local handler = file_output_factory({ path = log_path })
			handler({ message = "test" })
			local err_msg_open = mock_io_stderr_write_messages[1]
			assert.truthy(err_msg_open and string.find(err_msg_open, "Error opening log"))
			assert.truthy(err_msg_open and string.find(err_msg_open, "Permission denied"))
		end)

		it("should handle write failure", function()
			mock_file_object.write = function()
				error("Disk full")
			end
			local handler = file_output_factory({ path = log_path })
			handler({ message = "test" })
			local err_msg_write = mock_io_stderr_write_messages[1]
			assert.truthy(err_msg_write and string.find(err_msg_write, "Error writing to log file"))
			assert.truthy(err_msg_write and string.find(err_msg_write, "Disk full"))
		end)
	end)
end)
