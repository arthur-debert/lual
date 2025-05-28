package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua;../lua/?.lua;../lua/?/init.lua"
local lualog = require("lual.logger")
local ingest = require("lual.ingest")
local spy = require("luassert.spy")
local match = require("luassert.match")
-- local utils = require("luassert.utils") -- For stringify

describe("lualog Logger Object", function()
	-- Mocking ingest.dispatch_log_event -- Removed outer before_each/after_each for spy
	--[[ before_each(function()
    spy.on(ingest, "dispatch_log_event")
  end)

  after_each(function()
    if ingest.dispatch_log_event.revert then -- Check if it's a spy
      ingest.dispatch_log_event:revert()
    end
    -- Clear spy calls for the next test if the spy object has 'clear'
    if ingest.dispatch_log_event.clear then
        ingest.dispatch_log_event:clear()
    end
  end) --]]

	describe("lualog.logger(name)", function()
		it("should create a logger with auto-generated name when no name provided", function()
			-- Use a unique name for root to avoid cache from other tests if any test used "root" explicitly
			-- However, logger() or logger("root") should always return the canonical root.
			-- Forcing a reload for pristine cache is complex here. Assuming "root" is testable.
			package.loaded["lual.logger"] = nil -- Attempt to reset cache by reloading module
			local fresh_lualog = require("lual.logger")

			local auto_logger = fresh_lualog.logger()
			-- Should use the test filename (without .lua extension)
			assert.truthy(string.find(auto_logger.name, "logger_spec", 1, true))
			assert.is_false(string.find(auto_logger.name, ".lua", 1, true) ~= nil)
			assert.are.same(fresh_lualog.levels.INFO, auto_logger.level) -- Default level

			local root_logger_named = fresh_lualog.logger("root")
			assert.are.same("root", root_logger_named.name)
			assert.is_nil(root_logger_named.parent)
		end)

		it("should create a named logger and its parents", function()
			package.loaded["lual.logger"] = nil
			local fresh_lualog = require("lual.logger")

			local logger_a_b = fresh_lualog.logger("spec_a.spec_b")
			assert.are.same("spec_a.spec_b", logger_a_b.name)
			assert.is_not_nil(logger_a_b.parent)
			assert.are.same("spec_a", logger_a_b.parent.name)
			assert.is_not_nil(logger_a_b.parent.parent)
			assert.are.same("root", logger_a_b.parent.parent.name)
			assert.is_nil(logger_a_b.parent.parent.parent)
		end)

		it("should cache loggers", function()
			package.loaded["lual.logger"] = nil
			local fresh_lualog = require("lual.logger")

			local logger1 = fresh_lualog.logger("spec_cache_test")
			local logger2 = fresh_lualog.logger("spec_cache_test")
			assert.are.same(logger1, logger2)
		end)

		it("should have propagation enabled by default", function()
			package.loaded["lual.logger"] = nil
			local fresh_lualog = require("lual.logger")
			local logger = fresh_lualog.logger("spec_prop_test")
			assert.is_true(logger.propagate)
		end)
	end)

	describe("Logger Methods", function()
		local test_logger

		-- Create a fresh logger for each test in this block to avoid interference
		before_each(function()
			package.loaded["lual.logger"] = nil
			local fresh_lualog_for_method_tests = require("lual.logger")
			test_logger = fresh_lualog_for_method_tests.logger("suite_logger_methods")
			-- Reset spy on ingest for method tests if already a spy, then apply new one
			if type(ingest.dispatch_log_event) == "table" and ingest.dispatch_log_event.revert then
				ingest.dispatch_log_event:revert()
			end
			spy.on(ingest, "dispatch_log_event")
		end)

		after_each(function()
			local current_dispatch = ingest.dispatch_log_event
			if type(current_dispatch) == "table" and current_dispatch.revert then
				current_dispatch:revert()
			end
			-- Clear any calls on the spy that might remain if a test failed early
			-- or if the spy object persists after revert (though it usually shouldn't for luassert.spy)
			current_dispatch = ingest.dispatch_log_event -- Re-fetch in case revert changed it
			if type(current_dispatch) == "table" and current_dispatch.clear then
				current_dispatch:clear()
			end
		end)

		it("logger:set_level(level) should update the logger's level", function()
			test_logger:set_level(lualog.levels.DEBUG)
			assert.are.same(lualog.levels.DEBUG, test_logger.level)
			test_logger:set_level(lualog.levels.ERROR)
			assert.are.same(lualog.levels.ERROR, test_logger.level)
		end)

		it("logger:is_enabled_for(level_no) should return correct boolean", function()
			test_logger:set_level(lualog.levels.WARNING)
			assert.is_true(test_logger:is_enabled_for(lualog.levels.ERROR))
			assert.is_true(test_logger:is_enabled_for(lualog.levels.CRITICAL))
			assert.is_true(test_logger:is_enabled_for(lualog.levels.WARNING))
			assert.is_false(test_logger:is_enabled_for(lualog.levels.INFO))
			assert.is_false(test_logger:is_enabled_for(lualog.levels.DEBUG))

			test_logger:set_level(lualog.levels.NONE)
			assert.is_false(test_logger:is_enabled_for(lualog.levels.CRITICAL))
			assert.is_true(test_logger:is_enabled_for(lualog.levels.NONE)) -- Only NONE is enabled if level is NONE
		end)

		-- Tests for logging methods (debug, info, warn, error, critical)
		local function test_log_method(method_name, level_enum, level_name_str)
			describe("logger:" .. method_name .. "()", function()
				it("should call ingest.dispatch_log_event when level is enabled", function()
					test_logger:set_level(level_enum) -- Enable the specific level

					local arg1 = "world"
					local arg2 = 123
					test_logger[method_name](test_logger, "Hello %s num %d", arg1, arg2) -- Calling method via string name

					assert
						.spy(ingest.dispatch_log_event).was
						.called_with(match.is_table(), match.is_function(), match.is_table())

					local all_calls = ingest.dispatch_log_event.calls
					assert.are.same(1, #all_calls)

					local record = all_calls[1].vals[1] -- New way based on luassert spy structure for module functions

					assert.are.same(level_enum, record.level_no)
					assert.are.same(level_name_str, record.level_name)
					assert.are.same(test_logger.name, record.logger_name)
					assert.are.same(test_logger.name, record.source_logger_name)
					assert.are.same("Hello %s num %d", record.message_fmt)

					-- Check args (table.pack creates a table with 'n' field)
					assert.is_table(record.args)
					assert.are.same(2, record.args.n)
					assert.are.same(arg1, record.args[1])
					assert.are.same(arg2, record.args[2])
					assert.is_nil(record.context, "Context should be nil for Pattern 1 calls")

					assert.is_number(record.timestamp)
					assert.is_string(record.filename)
					assert.truthy(string.find(record.filename, "spec/logger_spec.lua", 1, true))
					assert.is_number(record.lineno)

					ingest.dispatch_log_event:clear()
				end)

				it("should NOT call ingest.dispatch_log_event when level is disabled", function()
					-- Set level higher than the method's level
					if level_enum < lualog.levels.CRITICAL then
						test_logger:set_level(level_enum + 10)
					else -- if current is CRITICAL, set to NONE or a higher number if more levels are added
						test_logger:set_level(lualog.levels.NONE)
					end

					test_logger[method_name](test_logger, "Disabled message")
					assert.spy(ingest.dispatch_log_event).was.not_called()
					ingest.dispatch_log_event:clear()
				end)
			end)
		end

		test_log_method("debug", lualog.levels.DEBUG, "DEBUG")
		test_log_method("info", lualog.levels.INFO, "INFO")
		test_log_method("warn", lualog.levels.WARNING, "WARNING")
		test_log_method("error", lualog.levels.ERROR, "ERROR")
		test_log_method("critical", lualog.levels.CRITICAL, "CRITICAL")

		describe("logger:log() with string format first (Pattern 1)", function()
			it("should correctly parse message_fmt and args", function()
				test_logger:set_level(lualog.levels.INFO) -- Ensure INFO is enabled

				local msg_format = "User %s performed action: %s with value %d"
				local user_arg = "john.doe"
				local action_arg = "update"
				local value_arg = 42

				test_logger:info(msg_format, user_arg, action_arg, value_arg)

				assert.spy(ingest.dispatch_log_event).was.called_with(match.is_table(), match.is_function(),
					match.is_table())
				local all_calls = ingest.dispatch_log_event.calls
				assert.are.same(1, #all_calls)
				local record = all_calls[1].vals[1]

				assert.are.same(lualog.levels.INFO, record.level_no)
				assert.are.same("INFO", record.level_name)
				assert.are.same(test_logger.name, record.logger_name)

				assert.is_nil(record.context, "Context should be nil for Pattern 1 calls")
				assert.are.same(msg_format, record.message_fmt, "Message format should match")

				assert.is_table(record.args)
				assert.are.same(3, record.args.n, "Should have 3 formatting args")
				assert.are.same(user_arg, record.args[1], "First formatting arg should match")
				assert.are.same(action_arg, record.args[2], "Second formatting arg should match")
				assert.are.same(value_arg, record.args[3], "Third formatting arg should match")

				ingest.dispatch_log_event:clear()
			end)

			it("should handle message_fmt without args", function()
				test_logger:set_level(lualog.levels.INFO)
				local msg_format_no_args = "Simple message without formatting"

				test_logger:info(msg_format_no_args)

				assert.spy(ingest.dispatch_log_event).was.called_with(match.is_table(), match.is_function(),
					match.is_table())
				local all_calls = ingest.dispatch_log_event.calls
				assert.are.same(1, #all_calls)
				local record = all_calls[1].vals[1]

				assert.are.same(lualog.levels.INFO, record.level_no)
				assert.is_nil(record.context, "Context should be nil for Pattern 1 calls")
				assert.are.same(msg_format_no_args, record.message_fmt)
				assert.is_table(record.args)
				assert.are.same(0, record.args.n, "Args should be empty when no formatting args provided")

				ingest.dispatch_log_event:clear()
			end)

			it("should handle non-string first argument by converting to string", function()
				test_logger:set_level(lualog.levels.INFO)
				local number_arg = 12345
				local boolean_arg = true

				-- Test with number
				test_logger:info(number_arg)
				assert.spy(ingest.dispatch_log_event).was.called_with(match.is_table(), match.is_function(),
					match.is_table())
				local all_calls = ingest.dispatch_log_event.calls
				assert.are.same(1, #all_calls)
				local record = all_calls[1].vals[1]

				assert.is_nil(record.context, "Context should be nil for Pattern 1 calls")
				assert.are.same(tostring(number_arg), record.message_fmt, "Number should be converted to string")
				assert.is_table(record.args)
				assert.are.same(0, record.args.n, "Args should be empty for single non-string argument")

				ingest.dispatch_log_event:clear()

				-- Test with boolean
				test_logger:info(boolean_arg)
				all_calls = ingest.dispatch_log_event.calls
				assert.are.same(1, #all_calls)
				record = all_calls[1].vals[1]

				assert.is_nil(record.context, "Context should be nil for Pattern 1 calls")
				assert.are.same(tostring(boolean_arg), record.message_fmt, "Boolean should be converted to string")
				assert.is_table(record.args)
				assert.are.same(0, record.args.n, "Args should be empty for single non-string argument")

				ingest.dispatch_log_event:clear()
			end)

			it("should handle empty arguments (no arguments after level)", function()
				test_logger:set_level(lualog.levels.INFO)

				test_logger:info() -- No arguments

				assert.spy(ingest.dispatch_log_event).was.called_with(match.is_table(), match.is_function(),
					match.is_table())
				local all_calls = ingest.dispatch_log_event.calls
				assert.are.same(1, #all_calls)
				local record = all_calls[1].vals[1]

				assert.are.same(lualog.levels.INFO, record.level_no)
				assert.is_nil(record.context, "Context should be nil for Pattern 1 calls")
				assert.are.same("", record.message_fmt, "Message format should default to empty string")
				assert.is_table(record.args)
				assert.are.same(0, record.args.n, "Args should be empty when no arguments provided")

				ingest.dispatch_log_event:clear()
			end)
		end)

		describe("logger:log() with context table first (Pattern 2)", function()
			it("should correctly parse context, message_fmt, and args", function()
				test_logger:set_level(lualog.levels.INFO) -- Ensure INFO is enabled

				local context_data = { user_id = 123, session = "abc" }
				local msg_format = "User action: %s"
				local action_arg = "login"

				test_logger:info(context_data, msg_format, action_arg)

				assert.spy(ingest.dispatch_log_event).was.called_with(match.is_table(), match.is_function(),
					match.is_table())
				local all_calls = ingest.dispatch_log_event.calls
				assert.are.same(1, #all_calls)
				local record = all_calls[1].vals[1]

				assert.are.same(lualog.levels.INFO, record.level_no)
				assert.are.same("INFO", record.level_name)
				assert.are.same(test_logger.name, record.logger_name)

				assert.are.same(context_data, record.context, "Context table should match")
				assert.are.same(msg_format, record.message_fmt, "Message format should match")

				assert.is_table(record.args)
				assert.are.same(1, record.args.n, "Should have 1 formatting arg")
				assert.are.same(action_arg, record.args[1], "Formatting arg should match")

				ingest.dispatch_log_event:clear()
			end)

			it("should handle context table only (Pattern 2b)", function()
				test_logger:set_level(lualog.levels.INFO)
				local context_only_data = { event = "SystemShutdown", reason = "Maintenance" }

				test_logger:info(context_only_data)

				assert.spy(ingest.dispatch_log_event).was.called_with(match.is_table(), match.is_function(),
					match.is_table())
				local all_calls = ingest.dispatch_log_event.calls
				assert.are.same(1, #all_calls)
				local record = all_calls[1].vals[1]

				assert.are.same(lualog.levels.INFO, record.level_no)
				assert.are.same(context_only_data, record.context, "Context table should match")
				assert.is_nil(record.message_fmt, "Message format should be nil for context-only")
				assert.is_table(record.args)
				assert.are.same(0, record.args.n, "Args should be empty for context-only")

				ingest.dispatch_log_event:clear()
			end)

			it("should handle context table and message_fmt without further args (Pattern 2a)", function()
				test_logger:set_level(lualog.levels.INFO)
				local context_data = { component = "API" }
				local msg_format_no_args = "Request received"

				test_logger:info(context_data, msg_format_no_args)
				assert.spy(ingest.dispatch_log_event).was.called_with(match.is_table(), match.is_function(),
					match.is_table())
				local all_calls = ingest.dispatch_log_event.calls
				assert.are.same(1, #all_calls)
				local record = all_calls[1].vals[1]

				assert.are.same(lualog.levels.INFO, record.level_no)
				assert.are.same(context_data, record.context)
				assert.are.same(msg_format_no_args, record.message_fmt)
				assert.is_table(record.args)
				assert.are.same(0, record.args.n)
				ingest.dispatch_log_event:clear()
			end)
		end)

		it("logger:add_output(output_func, formatter_func, output_config) should add output correctly", function()
			local mock_output_fn = function() end
			local mock_formatter_fn = function() end
			local mock_cfg = { type = "test" }

			test_logger:add_output(mock_output_fn, mock_formatter_fn, mock_cfg)
			assert.are.same(1, #test_logger.outputs)
			local entry = test_logger.outputs[1]
			assert.are.same(mock_output_fn, entry.output_func)
			assert.are.same(mock_formatter_fn, entry.formatter_func)
			assert.are.same(mock_cfg, entry.output_config)

			-- Test with nil config
			test_logger:add_output(mock_output_fn, mock_formatter_fn, nil)
			assert.are.same(2, #test_logger.outputs)
			local entry_nil_config = test_logger.outputs[2]
			assert.is_table(entry_nil_config.output_config) -- Should default to {}
			assert.are.same(0, #entry_nil_config.output_config)
		end)

		describe("logger:get_effective_outputs()", function()
			local fresh_lualog_for_outputs
			local logger_root, logger_p, logger_c

			before_each(function()
				package.loaded["lual.logger"] = nil
				fresh_lualog_for_outputs = require("lual.logger")
				-- Use unique names for this test block to ensure clean hierarchy
				logger_root = fresh_lualog_for_outputs.logger("eff_root")
				logger_p = fresh_lualog_for_outputs.logger("eff_root.p")
				logger_c = fresh_lualog_for_outputs.logger("eff_root.p.c")

				-- Reset levels and outputs for these specific loggers
				logger_root:set_level(fresh_lualog_for_outputs.levels.DEBUG)
				logger_p:set_level(fresh_lualog_for_outputs.levels.DEBUG)
				logger_c:set_level(fresh_lualog_for_outputs.levels.DEBUG)
				-- Clear outputs directly for test setup (this is acceptable for tests)
				logger_root.outputs = {}
				logger_p.outputs = {}
				logger_c.outputs = {}
				logger_root:set_propagate(true)
				logger_p:set_propagate(true)
				logger_c:set_propagate(true)
			end)

			local mock_h_fn = function() end
			local mock_f_fn = function() end

			it("should collect outputs from self and propagating parents", function()
				logger_c:add_output(mock_h_fn, mock_f_fn, { id = "hc" })
				logger_p:add_output(mock_h_fn, mock_f_fn, { id = "hp" })
				logger_root:add_output(mock_h_fn, mock_f_fn, { id = "h_root" })

				local c_outputs = logger_c:get_effective_outputs()
				assert.are.same(4, #c_outputs) -- Expect 3 local + 1 from actual root
				assert.are.same("eff_root.p.c", c_outputs[1].owner_logger_name)
				assert.are.same("eff_root.p", c_outputs[2].owner_logger_name)
				assert.are.same("eff_root", c_outputs[3].owner_logger_name)
				assert.are.same("root", c_outputs[4].owner_logger_name) -- Check the propagated root output
			end)

			it("should stop collecting if propagate is false on child", function()
				-- Reset the logger system to get a clean root logger
				fresh_lualog_for_outputs.reset_config()

				-- Re-get the loggers after reset
				logger_root = fresh_lualog_for_outputs.logger("eff_root")
				logger_p = fresh_lualog_for_outputs.logger("eff_root.p")
				logger_c = fresh_lualog_for_outputs.logger("eff_root.p.c")

				-- Reset levels and outputs for these specific loggers
				logger_root:set_level(fresh_lualog_for_outputs.levels.DEBUG)
				logger_p:set_level(fresh_lualog_for_outputs.levels.DEBUG)
				logger_c:set_level(fresh_lualog_for_outputs.levels.DEBUG)
				logger_root.outputs = {}
				logger_p.outputs = {}
				logger_c.outputs = {}
				logger_root:set_propagate(true)
				logger_p:set_propagate(true)
				logger_c:set_propagate(true)

				logger_c:add_output(mock_h_fn, mock_f_fn, { id = "hc" })
				logger_p:add_output(mock_h_fn, mock_f_fn, { id = "hp" })
				logger_root:add_output(mock_h_fn, mock_f_fn, { id = "h_root" })

				logger_c:set_propagate(false)
				local c_outputs = logger_c:get_effective_outputs()
				assert.are.same(1, #c_outputs)
				assert.are.same("eff_root.p.c", c_outputs[1].owner_logger_name)
			end)

			it("should stop collecting if propagate is false on parent", function()
				-- Reset the logger system to get a clean root logger
				fresh_lualog_for_outputs.reset_config()

				-- Re-get the loggers after reset
				logger_root = fresh_lualog_for_outputs.logger("eff_root")
				logger_p = fresh_lualog_for_outputs.logger("eff_root.p")
				logger_c = fresh_lualog_for_outputs.logger("eff_root.p.c")

				-- Reset levels and outputs for these specific loggers
				logger_root:set_level(fresh_lualog_for_outputs.levels.DEBUG)
				logger_p:set_level(fresh_lualog_for_outputs.levels.DEBUG)
				logger_c:set_level(fresh_lualog_for_outputs.levels.DEBUG)
				logger_root.outputs = {}
				logger_p.outputs = {}
				logger_c.outputs = {}
				logger_root:set_propagate(true)
				logger_p:set_propagate(true)
				logger_c:set_propagate(true)

				logger_c:add_output(mock_h_fn, mock_f_fn, { id = "hc" })
				logger_p:add_output(mock_h_fn, mock_f_fn, { id = "hp" })
				logger_root:add_output(mock_h_fn, mock_f_fn, { id = "h_root" })

				logger_p:set_propagate(false) -- c propagates to p, but p doesn't propagate to root
				local c_outputs = logger_c:get_effective_outputs()
				assert.are.same(2, #c_outputs)
				assert.are.same("eff_root.p.c", c_outputs[1].owner_logger_name)
				assert.are.same("eff_root.p", c_outputs[2].owner_logger_name)
			end)
		end)
	end)
end)

describe("lual.logger (Facade)", function()
	before_each(function()
		-- Ensure a clean state for lualog and its components for each facade test
		package.loaded["lual.logger"] = nil
		package.loaded["lual.core.engine"] = nil
		package.loaded["lual.core.levels"] = nil
		package.loaded["lual.outputs.init"] = nil
		package.loaded["lual.formatters.init"] = nil
		package.loaded["lual.ingest"] = nil

		-- Re-require lualog to get a fresh instance with fresh dependencies
		lualog = require("lual.logger")
	end)

	describe("log.init_default_config()", function()
		it("should add one default output to the root logger", function()
			local root_logger = lualog.logger("root")
			assert.is_not_nil(root_logger)
			assert.are.same(1, #root_logger.outputs, "Root logger should have 1 output after init.")
			if #root_logger.outputs == 1 then
				local output_entry = root_logger.outputs[1]
				assert.is_function(output_entry.output_func)
				assert.is_function(output_entry.formatter_func)
			end
		end)

		it("calling init_default_config multiple times should still result in one default output", function()
			lualog.init_default_config() -- Call again
			lualog.init_default_config() -- Call yet again

			local root_logger = lualog.logger("root")
			assert.are.same(1, #root_logger.outputs, "Root logger should still have 1 output after multiple inits.")
		end)
	end)

	describe("log.reset_config()", function()
		it("should clear logger cache and re-initialize default config", function()
			local logger1 = lualog.logger("testcache.reset")
			logger1:set_level(lualog.levels.DEBUG)

			lualog.reset_config()

			local logger2 = lualog.logger("testcache.reset")
			assert.are_not_same(logger1, logger2, "Logger instance should be new after reset.")
			assert.are.same(lualog.levels.INFO, logger2.level, "Logger level should be default INFO after reset.")

			local root_logger = lualog.logger("root")
			assert.are.same(1, #root_logger.outputs, "Root logger should have 1 default output after reset.")
		end)
	end)

	describe("Proper logger instance usage (non-facade)", function()
		it("logger instance methods should work correctly", function()
			local test_logger = lualog.logger("test_proper_usage")

			-- Test setting level directly on logger instance
			test_logger:set_level(lualog.levels.ERROR)
			assert.are.same(lualog.levels.ERROR, test_logger.level)
			test_logger:set_level(lualog.levels.DEBUG)
			assert.are.same(lualog.levels.DEBUG, test_logger.level)

			-- Test adding output directly on logger instance
			local mock_h = function() end
			local mock_f = function() end
			test_logger:add_output(mock_h, mock_f, { id = "test1" })
			assert.are.same(1, #test_logger.outputs)
			if #test_logger.outputs == 1 then
				assert.are.same(mock_h, test_logger.outputs[1].output_func)
			end
		end)

		it("logger instance logging methods should execute without error", function()
			local test_logger = lualog.logger("test_logging_methods")

			-- Test that logging methods work on logger instances
			assert.is_true(pcall(function()
				test_logger:info("Instance info test: %s", "message")
			end))

			assert.is_true(pcall(function()
				test_logger:debug("Instance debug test")
			end))
		end)
	end)

	describe("Timezone Configuration", function()
		it("should preserve timezone in logger config", function()
			local fresh_lualog = require("lual.logger")
			local utc_logger = fresh_lualog.logger({
				name = "config_test",
				timezone = "UTC", -- Test case insensitive
				output = "console",
				formatter = "text"
			})

			local config = utc_logger:get_config()
			assert.are.equal("UTC", config.timezone)
		end)

		it("should create loggers with timezone configuration", function()
			local fresh_lualog = require("lual.logger")

			-- Test UTC logger creation
			local utc_logger = fresh_lualog.logger({
				name = "utc_test",
				timezone = "utc",
				output = "console",
				formatter = "text"
			})
			assert.are.equal("utc", utc_logger.timezone)

			-- Test local logger creation
			local local_logger = fresh_lualog.logger({
				name = "local_test",
				timezone = "local",
				output = "console",
				formatter = "text"
			})
			assert.are.equal("local", local_logger.timezone)
		end)

		it("should handle timezone in shortcut API", function()
			local fresh_lualog = require("lual.logger")
			local shortcut_logger = fresh_lualog.logger({
				output = "console",
				formatter = "text",
				timezone = "utc"
			})

			assert.are.equal("utc", shortcut_logger.timezone)
		end)
	end)
end)
