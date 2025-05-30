package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua"
describe("ingest.dispatch_log_event", function()
	-- Compatibility for Lua 5.2+ which moved unpack to table.unpack
	local unpack = unpack or table.unpack

	local mock_log_levels = {
		DEBUG = 10,
		INFO = 20,
		WARNING = 30,
		ERROR = 40,
		CRITICAL = 50,
	}

	local registered_mock_loggers = {}
	local presenter_calls = {}
	local dispatcher_calls = {}
	local dispatcher_calls_ok = {} -- For tests with mixed erroring/non-erroring dispatchers
	local stderr_messages = {}

	local function create_mock_logger(name, level, dispatchers, propagate, parent)
		local logger = {
			name = name,
			level = level,
			dispatchers = dispatchers or {},
			propagate = propagate,
			parent = parent,
			is_enabled_for = function(self, message_level)
				return message_level >= (self.level or mock_log_levels.INFO)
			end,
			-- This mock get_effective_dispatchers needs to match the structure expected by the new ingest.dispatch_log_event
			get_effective_dispatchers = function(self)
				local collected_dispatchers = {}
				local current = self
				while current do
					if current.dispatchers then
						for _, h_entry in ipairs(current.dispatchers) do
							-- Ensure h_entry has dispatcher_func, presenter_func, etc.
							table.insert(collected_dispatchers, {
								dispatcher_func = h_entry.dispatcher_func,
								presenter_func = h_entry.presenter_func,
								dispatcher_config = h_entry.dispatcher_config,
								owner_logger_name = current.name, -- Add owner context
								owner_logger_level = current.level, -- Add owner context
							})
						end
					end
					if not current.propagate or not current.parent then
						break
					end
					current = current.parent
				end
				return collected_dispatchers
			end,
		}
		return logger
	end

	local function set_mock_loggers(loggers_map)
		registered_mock_loggers = loggers_map
	end

	local function mock_logger_internal(logger_name)
		return registered_mock_loggers[logger_name]
	end

	local function mock_presenter_func(base_record)
		table.insert(presenter_calls, { params = base_record })
		-- Format the message using message_fmt and args
		local original_msg = string.format(base_record.message_fmt, unpack(base_record.args or {}))
		return string.format("Formatted: %s", original_msg)
	end

	local function mock_erroring_presenter_func(base_record)
		error("Presenter error")
	end

	local function get_presenter_calls()
		return presenter_calls
	end

	local function clear_presenter_calls()
		presenter_calls = {}
	end

	local function mock_dispatcher_func(record, config)
		table.insert(dispatcher_calls, { params = record, config = config })
	end

	local function mock_erroring_dispatcher_func(record, config)
		error("dispatcher error")
	end

	local function get_dispatcher_calls()
		return dispatcher_calls
	end

	local function clear_dispatcher_calls()
		dispatcher_calls = {}
	end

	local function mock_dispatcher_func_ok(record, config)
		table.insert(dispatcher_calls_ok, { params = record, config = config }) -- Adjusted for consistency, though not strictly required by subtask
	end

	local function get_dispatcher_calls_ok()
		return dispatcher_calls_ok
	end

	local function clear_dispatcher_calls_ok()
		dispatcher_calls_ok = {}
	end

	local function mock_stderr_write(_, message)
		-- First argument is 'self' (the io.stderr table)
		table.insert(stderr_messages, message)
	end

	local function get_stderr_messages()
		return stderr_messages
	end

	local function clear_stderr_messages()
		stderr_messages = {}
	end

	local function clear_all_mocks()
		clear_presenter_calls()
		clear_dispatcher_calls()
		clear_dispatcher_calls_ok()
		clear_stderr_messages()
		registered_mock_loggers = {}
	end

	-- Setup global log object
	_G.log = {}
	_G.log.levels = mock_log_levels
	_G.log.logger_internal =
		mock_logger_internal -- Retain for other potential internal uses or direct logger method tests.

	-- Require the ingest module
	local ingest_module_status, ingest = pcall(require, "lual.ingest")
	if not ingest_module_status then
		error("Failed to require lual.ingest: " .. tostring(ingest))
	end
	-- local dispatch_log_event = ingest.dispatch_log_event -- This will be used in tests

	local original_stderr

	before_each(function()
		clear_all_mocks()
		original_stderr = io.stderr
		io.stderr = { write = mock_stderr_write }
	end)

	after_each(function()
		if original_stderr then
			io.stderr = original_stderr
		end
	end)

	it("should load ingest module and mock logger_internal", function()
		assert.is_function(ingest.dispatch_log_event)
		assert.is_function(mock_logger_internal)
	end)

	it("should call dispatcher and presenter for a single logger", function()
		set_mock_loggers({
			main_logger = create_mock_logger("main_logger", _G.log.levels.INFO, {
				{
					presenter_func = mock_presenter_func,
					dispatcher_func = mock_dispatcher_func,
					dispatcher_config = { dest = "mock_dispatcher" },
				},
			}),
		})

		local event_details = {
			level_no = _G.log.levels.INFO,
			level_name = "INFO",
			message_fmt = "Event: %s occurred",
			args = { "login" },
			timestamp = 1678886400,
			filename = "app.lua",
			lineno = 42,
			source_logger_name = "main_logger",
			context = nil, -- Added context field
		}

		print("Event Level No: " .. tostring(event_details.level_no))
		print("Event Source Logger: " .. tostring(event_details.source_logger_name))
		local logger = _G.log.logger_internal("main_logger")
		print("Logger Name: " .. tostring(logger.name))
		print("Logger Level: " .. tostring(logger.level))
		print("Logger dispatchers Count: " .. tostring(#logger.dispatchers))
		if #logger.dispatchers > 0 then
			print(
				"Presenter func is mock_presenter_func: "
				.. tostring(logger.dispatchers[1].presenter_func == mock_presenter_func)
			)
		end
		if #logger.dispatchers > 0 then
			print("dispatcher func is mock_dispatcher_func: " ..
				tostring(logger.dispatchers[1].dispatcher_func == mock_dispatcher_func))
		end

		ingest.dispatch_log_event(event_details, mock_logger_internal, mock_log_levels)

		print("#presenter_calls after dispatch: " .. tostring(#get_presenter_calls()))
		print("#dispatcher_calls after dispatch: " .. tostring(#get_dispatcher_calls()))

		local presenter_calls_list = get_presenter_calls()
		assert.are.same(1, #presenter_calls_list)
		if #presenter_calls_list > 0 then
			local fc = presenter_calls_list[1]
			assert.are.same("INFO", fc.params.level_name)
			assert.are.same("main_logger", fc.params.logger_name)
			assert.are.same("Event: %s occurred", fc.params.message_fmt)
			assert.are.same("login", fc.params.args[1])
			assert.are.same(1678886400, fc.params.timestamp)
			assert.are.same("app.lua", fc.params.filename)
			assert.are.same(42, fc.params.lineno)
			assert.is_nil(fc.params.context) -- Check for context
		end

		local dispatcher_calls_list = get_dispatcher_calls()
		assert.are.same(1, #dispatcher_calls_list)
		if #dispatcher_calls_list > 0 then
			local hc_params = dispatcher_calls_list[1].params
			local hc_config = dispatcher_calls_list[1].config
			assert.are.same("INFO", hc_params.level_name)
			assert.are.same("main_logger", hc_params.logger_name)
			-- Expected message is based on mock_presenter_func's behavior
			-- The mock_presenter_func creates a message like "Formatted: %s" where %s is base_record.message
			-- The base_record.message is string.format(event_details.message_fmt, unpack(event_details.args))
			local expected_formatted_message =
				string.format("Formatted: %s", string.format(event_details.message_fmt, unpack(event_details.args)))
			assert.are.same(expected_formatted_message, hc_params.message)
			assert.are.same(1678886400, hc_params.timestamp)
			assert.are.same("app.lua", hc_params.filename)
			assert.are.same(42, hc_params.lineno)
			assert.are.same("Event: %s occurred", hc_params.raw_message_fmt)
			assert.are.same("login", hc_params.raw_args[1])
			assert.is_nil(hc_params.context) -- Check for context in dispatcher record
			assert.are.same("main_logger", hc_params.source_logger_name)
			assert.are.same("mock_dispatcher", hc_config.dest)
		end

		assert.are.same(0, #get_stderr_messages())
	end)

	it("should ignore message if its level is below logger's level", function()
		set_mock_loggers({
			filter_logger = create_mock_logger("filter_logger", _G.log.levels.WARNING, {
				{ presenter_func = mock_presenter_func, dispatcher_func = mock_dispatcher_func, dispatcher_config = {} },
			}),
		})

		local event_details = {
			level_no = _G.log.levels.INFO,
			level_name = "INFO",
			message_fmt = "Debug info",
			args = {},
			timestamp = 1678886401,
			filename = "filter_app.lua",
			lineno = 10,
			source_logger_name = "filter_logger",
			context = nil,
		}

		ingest.dispatch_log_event(event_details, mock_logger_internal, mock_log_levels)

		assert.are.same(0, #get_presenter_calls())
		assert.are.same(0, #get_dispatcher_calls())
		assert.are.same(0, #get_stderr_messages())
	end)

	it("should process message if its level is equal to logger's level", function()
		set_mock_loggers({
			filter_logger = create_mock_logger("filter_logger", _G.log.levels.INFO, {
				{ presenter_func = mock_presenter_func, dispatcher_func = mock_dispatcher_func, dispatcher_config = {} },
			}),
		})

		local event_details = {
			level_no = _G.log.levels.INFO,
			level_name = "INFO",
			message_fmt = "Regular info",
			args = {},
			timestamp = 1678886402,
			filename = "filter_app.lua",
			lineno = 20,
			source_logger_name = "filter_logger",
			context = nil,
		}

		ingest.dispatch_log_event(event_details, mock_logger_internal, mock_log_levels)

		local fc_list_eq = get_presenter_calls()
		assert.are.same(1, #fc_list_eq)
		if #fc_list_eq > 0 then assert.is_nil(fc_list_eq[1].params.context) end
		local hc_list_eq = get_dispatcher_calls()
		assert.are.same(1, #hc_list_eq)
		if #hc_list_eq > 0 then assert.is_nil(hc_list_eq[1].params.context) end
		assert.are.same(0, #get_stderr_messages())
	end)

	it("should process message if its level is above logger's level", function()
		set_mock_loggers({
			filter_logger = create_mock_logger("filter_logger", _G.log.levels.INFO, {
				{ presenter_func = mock_presenter_func, dispatcher_func = mock_dispatcher_func, dispatcher_config = {} },
			}),
		})

		local event_details = {
			level_no = _G.log.levels.ERROR,
			level_name = "ERROR",
			message_fmt = "Critical failure",
			args = {},
			timestamp = 1678886403,
			filename = "filter_app.lua",
			lineno = 30,
			source_logger_name = "filter_logger",
			context = nil,
		}

		ingest.dispatch_log_event(event_details, mock_logger_internal, mock_log_levels)

		local presenter_calls_list = get_presenter_calls()
		assert.are.same(1, #presenter_calls_list)
		if #presenter_calls_list > 0 then
			assert.are.same("ERROR", presenter_calls_list[1].params.level_name)
			assert.is_nil(presenter_calls_list[1].params.context)
		end

		local dispatcher_calls_list = get_dispatcher_calls()
		assert.are.same(1, #dispatcher_calls_list)
		if #dispatcher_calls_list > 0 then
			assert.are.same("ERROR", dispatcher_calls_list[1].params.level_name)
			assert.is_nil(dispatcher_calls_list[1].params.context)
		end
		assert.are.same(0, #get_stderr_messages())
	end)

	it("should propagate from child to parent, both processing", function()
		local parent_logger = create_mock_logger("parent_logger", _G.log.levels.DEBUG, {
			{
				presenter_func = mock_presenter_func,
				dispatcher_func = mock_dispatcher_func,
				dispatcher_config = { id = "parent_h" },
			},
		})
		local child_logger = create_mock_logger("child_logger", _G.log.levels.DEBUG, {
			{
				presenter_func = mock_presenter_func,
				dispatcher_func = mock_dispatcher_func,
				dispatcher_config = { id = "child_h" },
			},
		}, true, parent_logger)
		set_mock_loggers({ parent_logger = parent_logger, child_logger = child_logger })

		local event_details = {
			level_no = _G.log.levels.DEBUG,
			level_name = "DEBUG",
			message_fmt = "Test message",
			args = {},
			timestamp = 1678886404,
			filename = "prop_app.lua",
			lineno = 1,
			source_logger_name = "child_logger",
			context = nil,
		}
		ingest.dispatch_log_event(event_details, mock_logger_internal, mock_log_levels)

		local fc_list = get_presenter_calls()
		local hc_list = get_dispatcher_calls()
		assert.are.same(2, #fc_list)
		assert.are.same(2, #hc_list)

		if #fc_list == 2 then
			assert.are.same("child_logger", fc_list[1].params.logger_name)
			assert.is_nil(fc_list[1].params.context)
			assert.are.same("parent_logger", fc_list[2].params.logger_name)
			assert.is_nil(fc_list[2].params.context)
		end
		if #hc_list == 2 then
			assert.are.same("child_logger", hc_list[1].params.logger_name)
			assert.is_nil(hc_list[1].params.context)
			assert.are.same("child_h", hc_list[1].config.id)
			assert.are.same("parent_logger", hc_list[2].params.logger_name)
			assert.is_nil(hc_list[2].params.context)
			assert.are.same("parent_h", hc_list[2].config.id)
			-- Check that the message for the parent's dispatcher was formatted by the parent's presenter.
			-- Our mock_presenter_func prepends "Formatted: " to the original message.
			-- The original message for the parent logger's presenter is the *already formatted* message from the child.
			-- However, the dispatch_log_event re-formats for each logger based on the *original* event_details.
			local expected_parent_formatted_message =
				string.format("Formatted: %s", string.format(event_details.message_fmt, unpack(event_details.args)))
			assert.are.same(expected_parent_formatted_message, hc_list[2].params.message)
		end
		assert.are.same(0, #get_stderr_messages())
	end)

	it("should not propagate if child's propagate is false", function()
		local parent_logger_no_prop = create_mock_logger("parent_logger_no_prop", _G.log.levels.DEBUG, {
			{ presenter_func = mock_presenter_func, dispatcher_func = mock_dispatcher_func },
		})
		local child_logger_no_prop = create_mock_logger("child_logger_no_prop", _G.log.levels.DEBUG, {
			{ presenter_func = mock_presenter_func, dispatcher_func = mock_dispatcher_func },
		}, false, parent_logger_no_prop) -- propagate = false
		set_mock_loggers({ parent_logger_no_prop = parent_logger_no_prop, child_logger_no_prop = child_logger_no_prop })

		local event_details = {
			level_no = _G.log.levels.DEBUG,
			level_name = "DEBUG",
			message_fmt = "No propagate message",
			args = {},
			timestamp = 1678886405,
			filename = "prop_app.lua",
			lineno = 2,
			source_logger_name = "child_logger_no_prop",
			context = nil,
		}
		ingest.dispatch_log_event(event_details, mock_logger_internal, mock_log_levels)

		assert.are.same(1, #get_presenter_calls())
		assert.are.same(1, #get_dispatcher_calls())
		if #get_presenter_calls() == 1 then
			assert.are.same("child_logger_no_prop", get_presenter_calls()[1].params.logger_name)
			assert.is_nil(get_presenter_calls()[1].params.context)
		end
		if #get_dispatcher_calls() == 1 then
			assert.is_nil(get_dispatcher_calls()[1].params.context)
		end
		assert.are.same(0, #get_stderr_messages())
	end)

	it("should propagate up a three-level hierarchy", function()
		local root_logger = create_mock_logger("root_logger", _G.log.levels.DEBUG, {
			{ presenter_func = mock_presenter_func, dispatcher_func = mock_dispatcher_func, dispatcher_config = { id = "root_h" } },
		})
		local mid_logger = create_mock_logger("mid_logger", _G.log.levels.DEBUG, {
			{ presenter_func = mock_presenter_func, dispatcher_func = mock_dispatcher_func, dispatcher_config = { id = "mid_h" } },
		}, true, root_logger)
		local leaf_logger = create_mock_logger("leaf_logger", _G.log.levels.DEBUG, {
			{ presenter_func = mock_presenter_func, dispatcher_func = mock_dispatcher_func, dispatcher_config = { id = "leaf_h" } },
		}, true, mid_logger)
		set_mock_loggers({ root_logger = root_logger, mid_logger = mid_logger, leaf_logger = leaf_logger })

		local event_details = {
			level_no = _G.log.levels.DEBUG,
			level_name = "DEBUG",
			message_fmt = "Leaf message",
			args = {},
			timestamp = 1678886406,
			filename = "prop_app.lua",
			lineno = 3,
			source_logger_name = "leaf_logger",
			context = nil,
		}
		ingest.dispatch_log_event(event_details, mock_logger_internal, mock_log_levels)

		local fc_list = get_presenter_calls()
		local hc_list = get_dispatcher_calls()
		assert.are.same(3, #fc_list)
		assert.are.same(3, #hc_list)

		if #fc_list == 3 then
			assert.are.same("leaf_logger", fc_list[1].params.logger_name)
			assert.is_nil(fc_list[1].params.context)
			assert.are.same("mid_logger", fc_list[2].params.logger_name)
			assert.is_nil(fc_list[2].params.context)
			assert.are.same("root_logger", fc_list[3].params.logger_name)
			assert.is_nil(fc_list[3].params.context)
		end
		if #hc_list == 3 then
			assert.are.same("leaf_logger", hc_list[1].params.logger_name)
			assert.is_nil(hc_list[1].params.context)
			assert.are.same("leaf_h", hc_list[1].config.id)
			assert.are.same("mid_logger", hc_list[2].params.logger_name)
			assert.is_nil(hc_list[2].params.context)
			assert.are.same("mid_h", hc_list[2].config.id)
			assert.are.same("root_logger", hc_list[3].params.logger_name)
			assert.is_nil(hc_list[3].params.context)
			assert.are.same("root_h", hc_list[3].config.id)
		end
		assert.are.same(0, #get_stderr_messages())
	end)

	it("parent should filter propagated message based on its own level", function()
		local parent_filter_logger = create_mock_logger("parent_filter_logger", _G.log.levels.WARNING, {
			{ presenter_func = mock_presenter_func, dispatcher_func = mock_dispatcher_func },
		})
		local child_source_logger = create_mock_logger("child_source_logger", _G.log.levels.INFO, {
			{ presenter_func = mock_presenter_func, dispatcher_func = mock_dispatcher_func },
		}, true, parent_filter_logger)
		set_mock_loggers({ parent_filter_logger = parent_filter_logger, child_source_logger = child_source_logger })

		local event_details = {
			level_no = _G.log.levels.INFO, -- Child processes, parent filters
			level_name = "INFO",
			message_fmt = "Info for child, too low for parent",
			args = {},
			timestamp = 1678886407,
			filename = "prop_app.lua",
			lineno = 4,
			source_logger_name = "child_source_logger",
			context = nil,
		}
		ingest.dispatch_log_event(event_details, mock_logger_internal, mock_log_levels)

		local fc_list = get_presenter_calls()
		local hc_list = get_dispatcher_calls()
		assert.are.same(1, #fc_list)
		assert.are.same(1, #hc_list)

		if #fc_list == 1 then
			assert.are.same("child_source_logger", fc_list[1].params.logger_name)
			assert.is_nil(fc_list[1].params.context)
		end
		if #hc_list == 1 then
			assert.are.same("child_source_logger", hc_list[1].params.logger_name)
			assert.is_nil(hc_list[1].params.context)
		end
		assert.are.same(0, #get_stderr_messages())
	end)

	it("should handle presenter error gracefully and use fallback message", function()
		set_mock_loggers({
			error_logger = create_mock_logger("error_logger", _G.log.levels.INFO, {
				{
					presenter_func = mock_erroring_presenter_func,
					dispatcher_func = mock_dispatcher_func,
					dispatcher_config = { id = "h_after_fmt_err" },
				},
			}),
		})

		local event_details = {
			level_no = _G.log.levels.INFO,
			level_name = "INFO",
			message_fmt = "original message %s",
			args = { "arg1" },
			timestamp = 1678886408,
			filename = "error_app.lua",
			lineno = 50,
			source_logger_name = "error_logger",
		}
		ingest.dispatch_log_event(event_details, mock_logger_internal, mock_log_levels)

		assert.are.same(0, #get_presenter_calls()) -- Presenter errored, so no call recorded by mock_presenter_func

		local hc_list = get_dispatcher_calls()
		assert.are.same(1, #hc_list)

		if #hc_list > 0 then
			local hc_params_data = hc_list[1].params
			local raw_message_to_check = string.format(event_details.message_fmt, unpack(event_details.args or {}))

			local texts_to_find = {
				"PRESENTER ERROR",
				event_details.level_name,
				event_details.filename,
				tostring(event_details.lineno),
				raw_message_to_check,
				event_details.source_logger_name,
			}

			for i, text_to_find in ipairs(texts_to_find) do
				local find_attempt_val = string.find(hc_params_data.message, text_to_find, 1, true)
				local expression_result = (find_attempt_val ~= nil)
				assert.are.same(true, expression_result)
			end

			assert.are.same("h_after_fmt_err", hc_list[1].config.id)
		end

		local stderr_list = get_stderr_messages()
		assert.are.same(1, #stderr_list)
		if #stderr_list > 0 then
			assert.is_true(string.find(stderr_list[1], "Logging system error: PRESENTER", 1, true) ~= nil)
			assert.is_true(string.find(stderr_list[1], "error_logger", 1, true) ~= nil)
			assert.is_true(string.find(stderr_list[1], "Presenter error", 1, true) ~= nil) -- The error from mock_erroring_presenter_func
		end
	end)

	it("should handle dispatcher error gracefully", function()
		set_mock_loggers({
			error_logger = create_mock_logger("error_logger", _G.log.levels.INFO, {
				{ presenter_func = mock_presenter_func, dispatcher_func = mock_erroring_dispatcher_func },
			}),
		})

		local event_details = {
			level_no = _G.log.levels.INFO,
			level_name = "INFO",
			message_fmt = "Message for erroring dispatcher",
			args = {},
			timestamp = 1678886409,
			filename = "error_app.lua",
			lineno = 60,
			source_logger_name = "error_logger",
		}
		ingest.dispatch_log_event(event_details, mock_logger_internal, mock_log_levels)

		assert.are.same(1, #get_presenter_calls()) -- Presenter should have been called
		assert.are.same(0, #get_dispatcher_calls()) -- Erroring dispatcher does not record its call

		local stderr_list = get_stderr_messages()
		assert.are.same(1, #stderr_list)
		if #stderr_list > 0 then
			assert.is_true(string.find(stderr_list[1], "Logging system error: dispatcher", 1, true) ~= nil)
			assert.is_true(string.find(stderr_list[1], "error_logger", 1, true) ~= nil)
			assert.is_true(string.find(stderr_list[1], "dispatcher error", 1, true) ~= nil) -- The error from mock_erroring_dispatcher_func
		end
	end)

	it("error in one dispatcher should not affect subsequent dispatchers for the same logger", function()
		set_mock_loggers({
			multi_dispatcher_logger = create_mock_logger("multi_dispatcher_logger", _G.log.levels.INFO, {
				{
					presenter_func = mock_presenter_func,
					dispatcher_func = mock_erroring_dispatcher_func,
					dispatcher_config = { id = "error_dispatcher" },
				},
				{
					presenter_func = mock_presenter_func,
					dispatcher_func = mock_dispatcher_func_ok,
					dispatcher_config = { id = "ok_dispatcher" },
				},
			}),
		})

		local event_details = {
			level_no = _G.log.levels.INFO,
			level_name = "INFO",
			message_fmt = "Test for multi-dispatcher with error",
			args = {},
			timestamp = 1678886410,
			filename = "error_app.lua",
			lineno = 70,
			source_logger_name = "multi_dispatcher_logger",
		}
		ingest.dispatch_log_event(event_details, mock_logger_internal, mock_log_levels)

		assert.are.same(2, #get_presenter_calls()) -- Both presenters should be called
		assert.are.same(0, #get_dispatcher_calls()) -- Erroring dispatcher does not record

		local hc_ok_list = get_dispatcher_calls_ok()
		assert.are.same(1, #hc_ok_list)
		if #hc_ok_list > 0 then
			assert.are.same("ok_dispatcher", hc_ok_list[1].config.id)
			local expected_message =
				string.format("Formatted: %s", string.format(event_details.message_fmt, unpack(event_details.args)))
			assert.are.same(expected_message, hc_ok_list[1].params.message)
		end

		local stderr_list = get_stderr_messages()
		assert.are.same(1, #stderr_list) -- Only one error message from the first dispatcher
		if #stderr_list > 0 then
			-- First error message should mention both "dispatcher" and failed
			assert.is_true(string.find(stderr_list[1], "dispatcher", 1, true) ~= nil)
			assert.is_true(string.find(stderr_list[1], "multi_dispatcher_logger", 1, true) ~= nil)
			assert.is_true(string.find(stderr_list[1], "failed", 1, true) ~= nil)
			assert.is_true(string.find(stderr_list[1], "dispatcher error", 1, true) ~= nil)
		end
	end)

	it("error in child's dispatcher should not affect propagation to parent", function()
		local parent_logger_prop = create_mock_logger("parent_logger_prop", _G.log.levels.INFO, {
			{
				presenter_func = mock_presenter_func,
				dispatcher_func = mock_dispatcher_func_ok,
				dispatcher_config = { id = "parent_ok_h" },
			},
		})
		local child_logger_prop_error = create_mock_logger("child_logger_prop_error", _G.log.levels.INFO, {
			{
				presenter_func = mock_presenter_func,
				dispatcher_func = mock_erroring_dispatcher_func,
				dispatcher_config = { id = "child_err_h" },
			},
		}, true, parent_logger_prop)
		set_mock_loggers({ parent_logger_prop = parent_logger_prop, child_logger_prop_error = child_logger_prop_error })

		local event_details = {
			level_no = _G.log.levels.INFO,
			level_name = "INFO",
			message_fmt = "Test for error propagation",
			args = {},
			timestamp = 1678886411,
			filename = "error_app.lua",
			lineno = 80,
			source_logger_name = "child_logger_prop_error",
		}
		ingest.dispatch_log_event(event_details, mock_logger_internal, mock_log_levels)

		local fc_list = get_presenter_calls()
		assert.are.same(2, #fc_list) -- Child's presenter, then Parent's presenter
		if #fc_list == 2 then
			assert.are.same("child_logger_prop_error", fc_list[1].params.logger_name)
			assert.are.same(event_details.context, fc_list[1].params.context)
			assert.are.same("parent_logger_prop", fc_list[2].params.logger_name)
			assert.are.same(event_details.context, fc_list[2].params.context)
		end

		assert.are.same(0, #get_dispatcher_calls()) -- Child's erroring dispatcher does not record
		local hc_ok_list = get_dispatcher_calls_ok()
		assert.are.same(1, #hc_ok_list)       -- Parent's OK dispatcher should be called
		if #hc_ok_list == 1 then
			assert.are.same("parent_logger_prop", hc_ok_list[1].params.logger_name)
			assert.are.same(event_details.context, hc_ok_list[1].params.context)
			assert.are.same("parent_ok_h", hc_ok_list[1].config.id)
			local expected_message = string.format(
				"Formatted: %s",
				string.format(event_details.message_fmt, unpack(event_details.args))
			)
			assert.are.same(expected_message, hc_ok_list[1].params.message)
		end

		local stderr_list = get_stderr_messages()
		assert.are.same(1, #stderr_list) -- Error from child's dispatcher
		if #stderr_list > 0 then
			-- First error message should mention both "dispatcher" and failed
			assert.is_true(string.find(stderr_list[1], "dispatcher", 1, true) ~= nil)
			assert.is_true(string.find(stderr_list[1], "child_logger_prop_error", 1, true) ~= nil)
			assert.is_true(string.find(stderr_list[1], "failed", 1, true) ~= nil)
			assert.is_true(string.find(stderr_list[1], "dispatcher error", 1, true) ~= nil)
		end
	end)

	it("should pass all event_details fields correctly to presenter and dispatcher", function()
		-- We need both the emitter and the passthrough logger
		local passthrough_logger = create_mock_logger("passthrough_logger", _G.log.levels.INFO, {
			{
				presenter_func = mock_presenter_func,
				dispatcher_func = mock_dispatcher_func,
				dispatcher_config = { id = "passthrough_h" },
			},
		})

		set_mock_loggers({
			passthrough_logger = passthrough_logger,
			emitter_logger = create_mock_logger("emitter_logger", _G.log.levels.INFO, {}, true, passthrough_logger),
		})

		local event_details = {
			level_no = _G.log.levels.INFO,
			level_name = "NOTIFY", -- Custom name for testing
			message_fmt = "Event ID: %d, Data: %s",
			args = { 1001, "SampleData" },
			timestamp = 1678880000, -- Unique timestamp
			filename = "modules/core.lua",
			lineno = 256,
			source_logger_name = "emitter_logger", -- Different from passthrough_logger
		}

		ingest.dispatch_log_event(event_details, mock_logger_internal, mock_log_levels)

		local presenter_calls_list = get_presenter_calls()
		assert.are.same(1, #presenter_calls_list)
		if #presenter_calls_list > 0 then
			local presenter_params = presenter_calls_list[1].params
			assert.are.equal(event_details.level_name, presenter_params.level_name)
			assert.are.equal(event_details.level_no, presenter_params.level_no)
			assert.are.equal("passthrough_logger", presenter_params.logger_name) -- Logger processing it
			assert.are.equal(event_details.message_fmt, presenter_params.message_fmt)
			assert.are.same(event_details.args, presenter_params.args)
			assert.are.equal(event_details.timestamp, presenter_params.timestamp)
			assert.are.equal(event_details.filename, presenter_params.filename)
			assert.are.equal(event_details.lineno, presenter_params.lineno)
			-- source_logger_name is part of the base_record which is now presenter_calls_list[1].params
			assert.are.equal(event_details.source_logger_name, presenter_params.source_logger_name) -- This line was already correct in the read_files dispatcher for turn 13.
		end

		local dispatcher_calls_list = get_dispatcher_calls()
		assert.are.same(1, #dispatcher_calls_list)
		if #dispatcher_calls_list > 0 then
			local dispatcher_input_params = dispatcher_calls_list[1].params
			assert.are.equal(event_details.level_name, dispatcher_input_params.level_name)
			assert.are.equal(event_details.level_no, dispatcher_input_params.level_no)
			assert.are.equal("passthrough_logger", dispatcher_input_params.logger_name)
			assert.is_string(dispatcher_input_params.message) -- Actual content checked by mock_presenter_func behavior
			local expected_formatted_message =
				string.format("Formatted: %s", string.format(event_details.message_fmt, unpack(event_details.args)))
			assert.are.equal(expected_formatted_message, dispatcher_input_params.message)
			assert.are.equal(event_details.timestamp, dispatcher_input_params.timestamp)
			assert.are.equal(event_details.filename, dispatcher_input_params.filename)
			assert.are.equal(event_details.lineno, dispatcher_input_params.lineno)
			assert.are.equal(event_details.message_fmt, dispatcher_input_params.raw_message_fmt)
			assert.are.same(event_details.args, dispatcher_input_params.raw_args)
			assert.are.same(event_details.context, dispatcher_input_params.context) -- Check context
			assert.are.equal(event_details.source_logger_name, dispatcher_input_params.source_logger_name)
			assert.are.same("passthrough_h", dispatcher_calls_list[1].config.id)
		end

		assert.are.same(0, #get_stderr_messages())
	end)
end)
