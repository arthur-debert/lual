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
  local formatter_calls = {}
  local handler_calls = {}
  local handler_calls_ok = {} -- For tests with mixed erroring/non-erroring handlers
  local stderr_messages = {}

  local function create_mock_logger(name, level, handlers, propagate, parent)
    local logger = {
      name = name,
      level = level,
      handlers = handlers or {},
      propagate = propagate,
      parent = parent,
      is_enabled_for = function(self, message_level)
        return message_level >= (self.level or mock_log_levels.INFO)
      end,
      -- This mock get_effective_handlers needs to match the structure expected by the new ingest.dispatch_log_event
      get_effective_handlers = function(self)
        local collected_handlers = {}
        local current = self
        while current do
          if current.handlers then
            for _, h_entry in ipairs(current.handlers) do
              -- Ensure h_entry has handler_func, formatter_func, etc.
              table.insert(collected_handlers, {
                handler_func = h_entry.handler_func,
                formatter_func = h_entry.formatter_func,
                handler_config = h_entry.handler_config,
                owner_logger_name = current.name,  -- Add owner context
                owner_logger_level = current.level -- Add owner context
              })
            end
          end
          if not current.propagate or not current.parent then
            break
          end
          current = current.parent
        end
        return collected_handlers
      end,
    }
    return logger
  end

  local function set_mock_loggers(loggers_map)
    registered_mock_loggers = loggers_map
  end

  local function mock_get_logger_internal(logger_name)
    return registered_mock_loggers[logger_name]
  end

  local function mock_formatter_func(base_record)
    table.insert(formatter_calls, { params = base_record })
    -- Format the message using message_fmt and args
    local original_msg = string.format(base_record.message_fmt, unpack(base_record.args or {}))
    return string.format("Formatted: %s", original_msg)
  end

  local function mock_erroring_formatter_func(base_record)
    error("Formatter error")
  end

  local function get_formatter_calls()
    return formatter_calls
  end

  local function clear_formatter_calls()
    formatter_calls = {}
  end

  local function mock_handler_func(record, config)
    table.insert(handler_calls, { params = record, config = config })
  end

  local function mock_erroring_handler_func(record, config)
    error("Handler error")
  end

  local function get_handler_calls()
    return handler_calls
  end

  local function clear_handler_calls()
    handler_calls = {}
  end

  local function mock_handler_func_ok(record, config)
    table.insert(handler_calls_ok, { params = record, config = config }) -- Adjusted for consistency, though not strictly required by subtask
  end

  local function get_handler_calls_ok()
    return handler_calls_ok
  end

  local function clear_handler_calls_ok()
    handler_calls_ok = {}
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
    clear_formatter_calls()
    clear_handler_calls()
    clear_handler_calls_ok()
    clear_stderr_messages()
    registered_mock_loggers = {}
  end

  -- Setup global log object
  _G.log = {}
  _G.log.levels = mock_log_levels
  _G.log.get_logger_internal =
      mock_get_logger_internal -- Retain for other potential internal uses or direct logger method tests.

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

  it("should load ingest module and mock get_logger_internal", function()
    assert.is_function(ingest.dispatch_log_event)
    assert.is_function(mock_get_logger_internal)
  end)

  it("should call handler and formatter for a single logger", function()
    set_mock_loggers({
      main_logger = create_mock_logger("main_logger", _G.log.levels.INFO, {
        { formatter_func = mock_formatter_func, handler_func = mock_handler_func, handler_config = { dest = "mock_output" } }
      })
    })

    local event_details = {
      level_no = _G.log.levels.INFO,
      level_name = "INFO",
      message_fmt = "Event: %s occurred",
      args = { "login" },
      timestamp = 1678886400,
      filename = "app.lua",
      lineno = 42,
      source_logger_name = "main_logger"
    }

    print("Event Level No: " .. tostring(event_details.level_no))
    print("Event Source Logger: " .. tostring(event_details.source_logger_name))
    local logger = _G.log.get_logger_internal("main_logger")
    print("Logger Name: " .. tostring(logger.name))
    print("Logger Level: " .. tostring(logger.level))
    print("Logger Handlers Count: " .. tostring(#logger.handlers))
    if #logger.handlers > 0 then
      print("Formatter func is mock_formatter_func: " ..
        tostring(logger.handlers[1].formatter_func == mock_formatter_func))
    end
    if #logger.handlers > 0 then
      print("Handler func is mock_handler_func: " ..
        tostring(logger.handlers[1].handler_func == mock_handler_func))
    end

    ingest.dispatch_log_event(event_details, mock_get_logger_internal, mock_log_levels)

    print("#formatter_calls after dispatch: " .. tostring(#get_formatter_calls()))
    print("#handler_calls after dispatch: " .. tostring(#get_handler_calls()))

    local formatter_calls_list = get_formatter_calls()
    assert.are.same(1, #formatter_calls_list)
    if #formatter_calls_list > 0 then
      local fc = formatter_calls_list[1]
      assert.are.same("INFO", fc.params.level_name)
      assert.are.same("main_logger", fc.params.logger_name)
      assert.are.same("Event: %s occurred", fc.params.message_fmt)
      assert.are.same("login", fc.params.args[1])
      assert.are.same(1678886400, fc.params.timestamp)
      assert.are.same("app.lua", fc.params.filename)
      assert.are.same(42, fc.params.lineno)
    end

    local handler_calls_list = get_handler_calls()
    assert.are.same(1, #handler_calls_list)
    if #handler_calls_list > 0 then
      local hc_params = handler_calls_list[1].params
      local hc_config = handler_calls_list[1].config
      assert.are.same("INFO", hc_params.level_name)
      assert.are.same("main_logger", hc_params.logger_name)
      -- Expected message is based on mock_formatter_func's behavior
      -- The mock_formatter_func creates a message like "Formatted: %s" where %s is base_record.message
      -- The base_record.message is string.format(event_details.message_fmt, unpack(event_details.args))
      local expected_formatted_message = string.format("Formatted: %s",
        string.format(event_details.message_fmt, unpack(event_details.args)))
      assert.are.same(expected_formatted_message, hc_params.message)
      assert.are.same(1678886400, hc_params.timestamp)
      assert.are.same("app.lua", hc_params.filename)
      assert.are.same(42, hc_params.lineno)
      assert.are.same("Event: %s occurred", hc_params.raw_message_fmt)
      assert.are.same("login", hc_params.raw_args[1])
      assert.are.same("main_logger", hc_params.source_logger_name)
      assert.are.same("mock_output", hc_config.dest)
    end

    assert.are.same(0, #get_stderr_messages())
  end)

  it("should ignore message if its level is below logger's level", function()
    set_mock_loggers({
      filter_logger = create_mock_logger("filter_logger", _G.log.levels.WARNING, {
        { formatter_func = mock_formatter_func, handler_func = mock_handler_func, handler_config = {} }
      })
    })

    local event_details = {
      level_no = _G.log.levels.INFO,
      level_name = "INFO",
      message_fmt = "Debug info",
      args = {},
      timestamp = 1678886401,
      filename = "filter_app.lua",
      lineno = 10,
      source_logger_name = "filter_logger"
    }

    ingest.dispatch_log_event(event_details, mock_get_logger_internal, mock_log_levels)

    assert.are.same(0, #get_formatter_calls())
    assert.are.same(0, #get_handler_calls())
    assert.are.same(0, #get_stderr_messages())
  end)

  it("should process message if its level is equal to logger's level", function()
    set_mock_loggers({
      filter_logger = create_mock_logger("filter_logger", _G.log.levels.INFO, {
        { formatter_func = mock_formatter_func, handler_func = mock_handler_func, handler_config = {} }
      })
    })

    local event_details = {
      level_no = _G.log.levels.INFO,
      level_name = "INFO",
      message_fmt = "Regular info",
      args = {},
      timestamp = 1678886402,
      filename = "filter_app.lua",
      lineno = 20,
      source_logger_name = "filter_logger"
    }

    ingest.dispatch_log_event(event_details, mock_get_logger_internal, mock_log_levels)

    assert.are.same(1, #get_formatter_calls())
    assert.are.same(1, #get_handler_calls())
    assert.are.same(0, #get_stderr_messages())
  end)

  it("should process message if its level is above logger's level", function()
    set_mock_loggers({
      filter_logger = create_mock_logger("filter_logger", _G.log.levels.INFO, {
        { formatter_func = mock_formatter_func, handler_func = mock_handler_func, handler_config = {} }
      })
    })

    local event_details = {
      level_no = _G.log.levels.ERROR,
      level_name = "ERROR",
      message_fmt = "Critical failure",
      args = {},
      timestamp = 1678886403,
      filename = "filter_app.lua",
      lineno = 30,
      source_logger_name = "filter_logger"
    }

    ingest.dispatch_log_event(event_details, mock_get_logger_internal, mock_log_levels)

    local formatter_calls_list = get_formatter_calls()
    assert.are.same(1, #formatter_calls_list)
    if #formatter_calls_list > 0 then
      assert.are.same("ERROR", formatter_calls_list[1].params.level_name)
    end

    local handler_calls_list = get_handler_calls()
    assert.are.same(1, #handler_calls_list)
    if #handler_calls_list > 0 then
      assert.are.same("ERROR", handler_calls_list[1].params.level_name)
    end
    assert.are.same(0, #get_stderr_messages())
  end)

  it("should propagate from child to parent, both processing", function()
    local parent_logger = create_mock_logger("parent_logger", _G.log.levels.DEBUG, {
      { formatter_func = mock_formatter_func, handler_func = mock_handler_func, handler_config = { id = "parent_h" } }
    })
    local child_logger = create_mock_logger("child_logger", _G.log.levels.DEBUG, {
      { formatter_func = mock_formatter_func, handler_func = mock_handler_func, handler_config = { id = "child_h" } }
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
      source_logger_name = "child_logger"
    }
    ingest.dispatch_log_event(event_details, mock_get_logger_internal, mock_log_levels)

    local fc_list = get_formatter_calls()
    local hc_list = get_handler_calls()
    assert.are.same(2, #fc_list)
    assert.are.same(2, #hc_list)

    if #fc_list == 2 then
      assert.are.same("child_logger", fc_list[1].params.logger_name)
      assert.are.same("parent_logger", fc_list[2].params.logger_name)
    end
    if #hc_list == 2 then
      assert.are.same("child_logger", hc_list[1].params.logger_name)
      assert.are.same("child_h", hc_list[1].config.id)
      assert.are.same("parent_logger", hc_list[2].params.logger_name)
      assert.are.same("parent_h", hc_list[2].config.id)
      -- Check that the message for the parent's handler was formatted by the parent's formatter.
      -- Our mock_formatter_func prepends "Formatted: " to the original message.
      -- The original message for the parent logger's formatter is the *already formatted* message from the child.
      -- However, the dispatch_log_event re-formats for each logger based on the *original* event_details.
      local expected_parent_formatted_message = string.format("Formatted: %s",
        string.format(event_details.message_fmt, unpack(event_details.args)))
      assert.are.same(expected_parent_formatted_message, hc_list[2].params.message)
    end
    assert.are.same(0, #get_stderr_messages())
  end)

  it("should not propagate if child's propagate is false", function()
    local parent_logger_no_prop = create_mock_logger("parent_logger_no_prop", _G.log.levels.DEBUG, {
      { formatter_func = mock_formatter_func, handler_func = mock_handler_func }
    })
    local child_logger_no_prop = create_mock_logger("child_logger_no_prop", _G.log.levels.DEBUG, {
      { formatter_func = mock_formatter_func, handler_func = mock_handler_func }
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
      source_logger_name = "child_logger_no_prop"
    }
    ingest.dispatch_log_event(event_details, mock_get_logger_internal, mock_log_levels)

    assert.are.same(1, #get_formatter_calls())
    assert.are.same(1, #get_handler_calls())
    if #get_formatter_calls() == 1 then
      assert.are.same("child_logger_no_prop", get_formatter_calls()[1].params.logger_name)
    end
    assert.are.same(0, #get_stderr_messages())
  end)

  it("should propagate up a three-level hierarchy", function()
    local root_logger = create_mock_logger("root_logger", _G.log.levels.DEBUG, {
      { formatter_func = mock_formatter_func, handler_func = mock_handler_func, handler_config = { id = "root_h" } }
    })
    local mid_logger = create_mock_logger("mid_logger", _G.log.levels.DEBUG, {
      { formatter_func = mock_formatter_func, handler_func = mock_handler_func, handler_config = { id = "mid_h" } }
    }, true, root_logger)
    local leaf_logger = create_mock_logger("leaf_logger", _G.log.levels.DEBUG, {
      { formatter_func = mock_formatter_func, handler_func = mock_handler_func, handler_config = { id = "leaf_h" } }
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
      source_logger_name = "leaf_logger"
    }
    ingest.dispatch_log_event(event_details, mock_get_logger_internal, mock_log_levels)

    local fc_list = get_formatter_calls()
    local hc_list = get_handler_calls()
    assert.are.same(3, #fc_list)
    assert.are.same(3, #hc_list)

    if #fc_list == 3 then
      assert.are.same("leaf_logger", fc_list[1].params.logger_name)
      assert.are.same("mid_logger", fc_list[2].params.logger_name)
      assert.are.same("root_logger", fc_list[3].params.logger_name)
    end
    if #hc_list == 3 then
      assert.are.same("leaf_logger", hc_list[1].params.logger_name)
      assert.are.same("leaf_h", hc_list[1].config.id)
      assert.are.same("mid_logger", hc_list[2].params.logger_name)
      assert.are.same("mid_h", hc_list[2].config.id)
      assert.are.same("root_logger", hc_list[3].params.logger_name)
      assert.are.same("root_h", hc_list[3].config.id)
    end
    assert.are.same(0, #get_stderr_messages())
  end)

  it("parent should filter propagated message based on its own level", function()
    local parent_filter_logger = create_mock_logger("parent_filter_logger", _G.log.levels.WARNING, {
      { formatter_func = mock_formatter_func, handler_func = mock_handler_func }
    })
    local child_source_logger = create_mock_logger("child_source_logger", _G.log.levels.INFO, {
      { formatter_func = mock_formatter_func, handler_func = mock_handler_func }
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
      source_logger_name = "child_source_logger"
    }
    ingest.dispatch_log_event(event_details, mock_get_logger_internal, mock_log_levels)

    local fc_list = get_formatter_calls()
    local hc_list = get_handler_calls()
    assert.are.same(1, #fc_list)
    assert.are.same(1, #hc_list)

    if #fc_list == 1 then
      assert.are.same("child_source_logger", fc_list[1].params.logger_name)
    end
    if #hc_list == 1 then
      assert.are.same("child_source_logger", hc_list[1].params.logger_name)
    end
    assert.are.same(0, #get_stderr_messages())
  end)

  it("should handle formatter error gracefully and use fallback message", function()
    set_mock_loggers({
      error_logger = create_mock_logger("error_logger", _G.log.levels.INFO, {
        { formatter_func = mock_erroring_formatter_func, handler_func = mock_handler_func, handler_config = { id = "h_after_fmt_err" } }
      })
    })

    local event_details = {
      level_no = _G.log.levels.INFO,
      level_name = "INFO",
      message_fmt = "original message %s",
      args = { "arg1" },
      timestamp = 1678886408,
      filename = "error_app.lua",
      lineno = 50,
      source_logger_name = "error_logger"
    }
    ingest.dispatch_log_event(event_details, mock_get_logger_internal, mock_log_levels)

    assert.are.same(0, #get_formatter_calls()) -- Formatter errored, so no call recorded by mock_formatter_func

    local hc_list = get_handler_calls()
    assert.are.same(1, #hc_list)

    if #hc_list > 0 then
      local hc_params_data = hc_list[1].params
      local raw_message_to_check = string.format(event_details.message_fmt, unpack(event_details.args or {}))

      local texts_to_find = {
        "FORMATTER ERROR",
        event_details.level_name,
        event_details.filename,
        tostring(event_details.lineno),
        raw_message_to_check,
        event_details.source_logger_name
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
      assert.is_true(string.find(stderr_list[1], "Logging system error: Formatter", 1, true) ~= nil)
      assert.is_true(string.find(stderr_list[1], "error_logger", 1, true) ~= nil)
      assert.is_true(string.find(stderr_list[1], "Formatter error", 1, true) ~= nil) -- The error from mock_erroring_formatter_func
    end
  end)

  it("should handle handler error gracefully", function()
    set_mock_loggers({
      error_logger = create_mock_logger("error_logger", _G.log.levels.INFO, {
        { formatter_func = mock_formatter_func, handler_func = mock_erroring_handler_func }
      })
    })

    local event_details = {
      level_no = _G.log.levels.INFO,
      level_name = "INFO",
      message_fmt = "Message for erroring handler",
      args = {},
      timestamp = 1678886409,
      filename = "error_app.lua",
      lineno = 60,
      source_logger_name = "error_logger"
    }
    ingest.dispatch_log_event(event_details, mock_get_logger_internal, mock_log_levels)

    assert.are.same(1, #get_formatter_calls()) -- Formatter should have been called
    assert.are.same(0, #get_handler_calls())   -- Erroring handler does not record its call

    local stderr_list = get_stderr_messages()
    assert.are.same(1, #stderr_list)
    if #stderr_list > 0 then
      assert.is_true(string.find(stderr_list[1], "Logging system error: Handler", 1, true) ~= nil)
      assert.is_true(string.find(stderr_list[1], "error_logger", 1, true) ~= nil)
      assert.is_true(string.find(stderr_list[1], "Handler error", 1, true) ~= nil) -- The error from mock_erroring_handler_func
    end
  end)

  it("error in one handler should not affect subsequent handlers for the same logger", function()
    set_mock_loggers({
      multi_handler_logger = create_mock_logger("multi_handler_logger", _G.log.levels.INFO, {
        { formatter_func = mock_formatter_func, handler_func = mock_erroring_handler_func, handler_config = { id = "error_handler" } },
        { formatter_func = mock_formatter_func, handler_func = mock_handler_func_ok,       handler_config = { id = "ok_handler" } }
      })
    })

    local event_details = {
      level_no = _G.log.levels.INFO,
      level_name = "INFO",
      message_fmt = "Test for multi-handler with error",
      args = {},
      timestamp = 1678886410,
      filename = "error_app.lua",
      lineno = 70,
      source_logger_name = "multi_handler_logger"
    }
    ingest.dispatch_log_event(event_details, mock_get_logger_internal, mock_log_levels)

    assert.are.same(2, #get_formatter_calls()) -- Both formatters should be called
    assert.are.same(0, #get_handler_calls())   -- Erroring handler does not record

    local hc_ok_list = get_handler_calls_ok()
    assert.are.same(1, #hc_ok_list)
    if #hc_ok_list > 0 then
      assert.are.same("ok_handler", hc_ok_list[1].config.id)
      local expected_message = string.format("Formatted: %s",
        string.format(event_details.message_fmt, unpack(event_details.args)))
      assert.are.same(expected_message, hc_ok_list[1].params.message)
    end

    local stderr_list = get_stderr_messages()
    assert.are.same(1, #stderr_list) -- Only one error message from the first handler
    if #stderr_list > 0 then
      -- First error message should mention both "Handler" and failed
      assert.is_true(string.find(stderr_list[1], "Handler", 1, true) ~= nil)
      assert.is_true(string.find(stderr_list[1], "multi_handler_logger", 1, true) ~= nil)
      assert.is_true(string.find(stderr_list[1], "failed", 1, true) ~= nil)
      assert.is_true(string.find(stderr_list[1], "Handler error", 1, true) ~= nil)
    end
  end)

  it("error in child's handler should not affect propagation to parent", function()
    local parent_logger_prop = create_mock_logger("parent_logger_prop", _G.log.levels.INFO, {
      { formatter_func = mock_formatter_func, handler_func = mock_handler_func_ok, handler_config = { id = "parent_ok_h" } }
    })
    local child_logger_prop_error = create_mock_logger("child_logger_prop_error", _G.log.levels.INFO, {
      { formatter_func = mock_formatter_func, handler_func = mock_erroring_handler_func, handler_config = { id = "child_err_h" } }
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
      source_logger_name = "child_logger_prop_error"
    }
    ingest.dispatch_log_event(event_details, mock_get_logger_internal, mock_log_levels)

    local fc_list = get_formatter_calls()
    assert.are.same(2, #fc_list) -- Child's formatter, then Parent's formatter
    if #fc_list == 2 then
      assert.are.same("child_logger_prop_error", fc_list[1].params.logger_name)
      assert.are.same("parent_logger_prop", fc_list[2].params.logger_name)
    end

    assert.are.same(0, #get_handler_calls()) -- Child's erroring handler does not record

    local hc_ok_list = get_handler_calls_ok()
    assert.are.same(1, #hc_ok_list) -- Parent's OK handler should be called
    if #hc_ok_list > 0 then
      assert.are.same("parent_logger_prop", hc_ok_list[1].params.logger_name)
      assert.are.same("parent_ok_h", hc_ok_list[1].config.id)
      local expected_message = string.format("Formatted: %s",
        string.format(event_details.message_fmt, unpack(event_details.args)))
      assert.are.same(expected_message, hc_ok_list[1].params.message)
    end

    local stderr_list = get_stderr_messages()
    assert.are.same(1, #stderr_list) -- Error from child's handler
    if #stderr_list > 0 then
      -- First error message should mention both "Handler" and failed
      assert.is_true(string.find(stderr_list[1], "Handler", 1, true) ~= nil)
      assert.is_true(string.find(stderr_list[1], "child_logger_prop_error", 1, true) ~= nil)
      assert.is_true(string.find(stderr_list[1], "failed", 1, true) ~= nil)
      assert.is_true(string.find(stderr_list[1], "Handler error", 1, true) ~= nil)
    end
  end)

  it("should pass all event_details fields correctly to formatter and handler", function()
    -- We need both the emitter and the passthrough logger
    local passthrough_logger = create_mock_logger("passthrough_logger", _G.log.levels.INFO, {
      { formatter_func = mock_formatter_func, handler_func = mock_handler_func, handler_config = { id = "passthrough_h" } }
    })

    set_mock_loggers({
      passthrough_logger = passthrough_logger,
      emitter_logger = create_mock_logger("emitter_logger", _G.log.levels.INFO, {}, true, passthrough_logger)
    })

    local event_details = {
      level_no = _G.log.levels.INFO,
      level_name = "NOTIFY", -- Custom name for testing
      message_fmt = "Event ID: %d, Data: %s",
      args = { 1001, "SampleData" },
      timestamp = 1678880000, -- Unique timestamp
      filename = "modules/core.lua",
      lineno = 256,
      source_logger_name = "emitter_logger" -- Different from passthrough_logger
    }

    ingest.dispatch_log_event(event_details, mock_get_logger_internal, mock_log_levels)

    local formatter_calls_list = get_formatter_calls()
    assert.are.same(1, #formatter_calls_list)
    if #formatter_calls_list > 0 then
      local formatter_params = formatter_calls_list[1].params
      assert.are.equal(event_details.level_name, formatter_params.level_name)
      assert.are.equal(event_details.level_no, formatter_params.level_no)
      assert.are.equal("passthrough_logger", formatter_params.logger_name) -- Logger processing it
      assert.are.equal(event_details.message_fmt, formatter_params.message_fmt)
      assert.are.same(event_details.args, formatter_params.args)
      assert.are.equal(event_details.timestamp, formatter_params.timestamp)
      assert.are.equal(event_details.filename, formatter_params.filename)
      assert.are.equal(event_details.lineno, formatter_params.lineno)
      -- source_logger_name is part of the base_record which is now formatter_calls_list[1].params
      assert.are.equal(event_details.source_logger_name, formatter_params.source_logger_name) -- This line was already correct in the read_files output for turn 13.
    end

    local handler_calls_list = get_handler_calls()
    assert.are.same(1, #handler_calls_list)
    if #handler_calls_list > 0 then
      local handler_input_params = handler_calls_list[1].params
      assert.are.equal(event_details.level_name, handler_input_params.level_name)
      assert.are.equal(event_details.level_no, handler_input_params.level_no)
      assert.are.equal("passthrough_logger", handler_input_params.logger_name)
      assert.is_string(handler_input_params.message) -- Actual content checked by mock_formatter_func behavior
      local expected_formatted_message = string.format("Formatted: %s",
        string.format(event_details.message_fmt, unpack(event_details.args)))
      assert.are.equal(expected_formatted_message, handler_input_params.message)
      assert.are.equal(event_details.timestamp, handler_input_params.timestamp)
      assert.are.equal(event_details.filename, handler_input_params.filename)
      assert.are.equal(event_details.lineno, handler_input_params.lineno)
      assert.are.equal(event_details.message_fmt, handler_input_params.raw_message_fmt)
      assert.are.same(event_details.args, handler_input_params.raw_args)
      assert.are.equal(event_details.source_logger_name, handler_input_params.source_logger_name)
      assert.are.same("passthrough_h", handler_calls_list[1].config.id)
    end

    assert.are.same(0, #get_stderr_messages())
  end)
end)
