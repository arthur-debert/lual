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
			if old == new then -- Existence check
				-- Default to "not exists". Tests needing a file to "exist"
				-- for an os.rename(path,path) check must provide a specific mock.
				return nil, "No such file (default mock for os.rename existence check)"
			end
			return true -- Simulate success for actual renames (old != new)
		end

		os.remove = function(path)
			table.insert(mock_os_remove_calls, path)
			return true -- Simulate success
		end

		io.open = function(path, mode)
			table.insert(mock_io_open_calls, { path = path, mode = mode })
			if mode == "r" then -- For existence checks in rotation
				-- Simulate file exists if os.rename check passed (which it does by default above)
				-- This logic might need refinement based on specific test scenarios
				if string.match(path, "%.[1-4]$") then -- default non-existence for backups 1-4
					return nil, "No such file or directory"
				end
				return { close = function() end } -- Simulate file exists and can be closed
			end
			return mock_file_object, nil -- Simulate success for append/write
		end

		io.stderr = {
			write = function(msg)
				table.insert(mock_io_stderr_write_messages, msg)
			end,
		}

		-- Clear lual's cache if it's already loaded to get fresh mocks
		package.loaded["lual.outputs.file_output"] = nil
		file_output_factory = require("lual.outputs.file_output")
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

		mock_io_stderr_write_messages = {} -- Reset for next check
		file_output_factory({ path = 123 }) -- Invalid type
		local msg2 = mock_io_stderr_write_messages[1]
		assert.truthy(msg2 and string.find(msg2, "requires config.path"))
	end)

	describe("Log Rotation", function()
		local log_path = "test_app.log"

		it("should attempt to remove oldest backup (e.g., .5)", function()
			-- Simulate oldest_backup_path (.5) exists for os.rename check
			os.rename = function(old, new)
				table.insert(mock_os_rename_calls, { old = old, new = new })
				if old == log_path .. ".5" and new == log_path .. ".5" then
					return true -- Simulate .5 exists for its own check
				end
				-- For other renames in this test, assume success.
				return true
			end

			file_output_factory({ path = log_path })
			assert.are.same({ old = log_path .. ".5", new = log_path .. ".5" }, mock_os_rename_calls[1], ".5 chk fail")
			assert.are.same(log_path .. ".5", mock_os_remove_calls[1])
		end)

		it("should shift backups from .4 down to .1", function()
			-- Simulate all backup files .1 to .4 exist for io.open checks
			io.open = function(path, mode)
				table.insert(mock_io_open_calls, { path = path, mode = mode })
				if mode == "r" then
					if
						path == log_path .. ".4"
						or path == log_path .. ".3"
						or path == log_path .. ".2"
						or path == log_path .. ".1"
						or path == log_path
					then -- current log also exists
						return { close = function() end } -- These exist
					else
						return nil, "No such file (mocked r for this test)" -- Other 'r' mode files don't exist
					end
				elseif mode == "a" and path == log_path then
					return mock_file_object -- Final open for writing
				end
				return nil, "Unhandled io.open in 'shift backups' test"
			end

			-- Simulate .5 does not exist for its initial os.rename check,
			-- but other renames (like .4 -> .5) succeed.
			os.rename = function(old, new)
				table.insert(mock_os_rename_calls, { old = old, new = new })
				if old == log_path .. ".5" and new == log_path .. ".5" then
					return nil, "No such file" -- .5 not exists
				end
				return true -- all other renames succeed
			end

			file_output_factory({ path = log_path })

			-- Expected rename operations for shifting (after the .5 check)
			-- .4 -> .5
			-- .3 -> .4
			-- .2 -> .3
			-- .1 -> .2
			local expected_renames = {
				{ old = log_path .. ".4", new = log_path .. ".5" },
				{ old = log_path .. ".3", new = log_path .. ".4" },
				{ old = log_path .. ".2", new = log_path .. ".3" },
				{ old = log_path .. ".1", new = log_path .. ".2" },
			}
			-- mock_os_rename_calls[1] is the check for .5
			assert.are.same(expected_renames[1], mock_os_rename_calls[2])
			assert.are.same(expected_renames[2], mock_os_rename_calls[3])
			assert.are.same(expected_renames[3], mock_os_rename_calls[4])
			assert.are.same(expected_renames[4], mock_os_rename_calls[5])
		end)

		it("should rotate current log to .1 if it exists", function()
			-- Simulate current log exists for io.open check
			io.open = function(path, mode)
				table.insert(mock_io_open_calls, { path = path, mode = mode })
				if mode == "r" and path == log_path then
					return { close = function() end } -- Simulate current log exists
				end
				return original_io_open(path, mode) -- fallback
			end
			-- Simulate .5 and .1-.4 do not exist for their checks
			os.rename = function(old, new)
				table.insert(mock_os_rename_calls, { old = old, new = new })
				if old == new and (string.match(old, "%.5$") or string.match(old, "%.[1-4]$")) then
					return nil, "No such file" -- .5 and .1-.4 not exist
				end
				return true -- all other renames succeed (specifically log_path to log_path.1)
			end

			file_output_factory({ path = log_path })
			-- After .5 check (call 1) and 4 shifts (calls 2-5, assuming no files existed to shift)
			-- The rename of current log to .1 should be the last rename op if no backups existed.
			-- If backups existed, it would be after them.
			-- Let's find it in the calls list.
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
			-- Simulate no files exist for any os.rename or io.open checks
			os.rename = function(old, new)
				table.insert(mock_os_rename_calls, { old = old, new = new })
				if old == new then
					return nil, "No such file or directory"
				end -- All existence checks fail
				return true -- Renames would succeed if files existed, but they won't be called
			end
			io.open = function(path, mode)
				table.insert(mock_io_open_calls, { path = path, mode = mode })
				if mode == "r" then
					return nil, "No such file or directory"
				end -- All existence checks fail
				return mock_file_object -- for the final open of the new log
			end

			file_output_factory({ path = log_path })

			-- 1. Check .5 (os.rename old==new) -> fails (no remove)
			assert.are.same({ old = log_path .. ".5", new = log_path .. ".5" }, mock_os_rename_calls[1])
			assert.is_nil(mock_os_remove_calls[1]) -- No removal because .5 didn't exist

			-- 2. Shift backups .4 down to .1 (io.open checks) -> all fail (no renames)
			-- Check for .4
			assert.is_true(mock_io_open_calls[1].path == log_path .. ".4" and mock_io_open_calls[1].mode == "r")
			-- Check for .3
			assert.is_true(mock_io_open_calls[2].path == log_path .. ".3" and mock_io_open_calls[2].mode == "r")
			-- Check for .2
			assert.is_true(mock_io_open_calls[3].path == log_path .. ".2" and mock_io_open_calls[3].mode == "r")
			-- Check for .1
			assert.is_true(mock_io_open_calls[4].path == log_path .. ".1" and mock_io_open_calls[4].mode == "r")

			-- Only 1 os.rename call (for .5 check) because no files existed to shift
			assert.are.equal(1, #mock_os_rename_calls, "os.rename called >1 for .5 check")

			-- 3. Rotate current log (io.open check) -> fails (no rename)
			assert.is_true(mock_io_open_calls[5].path == log_path and mock_io_open_calls[5].mode == "r")
			-- No further os.rename calls for current log as it didn't exist

			-- 4. Final open for writing new log
			local last_open_call = mock_io_open_calls[#mock_io_open_calls]
			assert.are.same({ path = log_path, mode = "a" }, last_open_call)
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
				-- For rotation phase, assume success or non-existence as per default mocks
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
