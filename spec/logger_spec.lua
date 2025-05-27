package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua"
local unpack = unpack or table.unpack
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

  describe("lualog.get_logger(name)", function()
    it("should create a root logger correctly", function()
      -- Use a unique name for root to avoid cache from other tests if any test used "root" explicitly
      -- However, get_logger() or get_logger("root") should always return the canonical root.
      -- Forcing a reload for pristine cache is complex here. Assuming "root" is testable.
      package.loaded["lual.logger"] = nil -- Attempt to reset cache by reloading module
      local fresh_lualog = require("lual.logger")

      local root_logger = fresh_lualog.get_logger()
      assert.are.same("root", root_logger.name)
      assert.is_nil(root_logger.parent)
      assert.are.same(fresh_lualog.levels.INFO, root_logger.level) -- Default level

      local root_logger_named = fresh_lualog.get_logger("root")
      assert.are.same(root_logger, root_logger_named)
    end)

    it("should create a named logger and its parents", function()
      package.loaded["lual.logger"] = nil
      local fresh_lualog = require("lual.logger")

      local logger_a_b = fresh_lualog.get_logger("spec_a.spec_b")
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

      local logger1 = fresh_lualog.get_logger("spec_cache_test")
      local logger2 = fresh_lualog.get_logger("spec_cache_test")
      assert.are.same(logger1, logger2)
    end)

    it("should have propagation enabled by default", function()
      package.loaded["lual.logger"] = nil
      local fresh_lualog = require("lual.logger")
      local logger = fresh_lualog.get_logger("spec_prop_test")
      assert.is_true(logger.propagate)
    end)
  end)

  describe("Logger Methods", function()
    local test_logger

    -- Create a fresh logger for each test in this block to avoid interference
    before_each(function()
      package.loaded["lual.logger"] = nil
      local fresh_lualog_for_method_tests = require("lual.logger")
      test_logger = fresh_lualog_for_method_tests.get_logger("suite_logger_methods")
      -- Reset spy on ingest for method tests if already a spy, then apply new one
      if type(ingest.dispatch_log_event) == "table" and ingest.dispatch_log_event.revert then
        ingest.dispatch_log_event:revert()
      end
      spy.on(ingest, "dispatch_log_event")
    end)

    after_each(function()
      local current_dispatch = ingest.dispatch_log_event
      if type(current_dispatch) == 'table' and current_dispatch.revert then
        current_dispatch:revert()
      end
      -- Clear any calls on the spy that might remain if a test failed early
      -- or if the spy object persists after revert (though it usually shouldn't for luassert.spy)
      current_dispatch = ingest.dispatch_log_event -- Re-fetch in case revert changed it
      if type(current_dispatch) == 'table' and current_dispatch.clear then
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

          assert.spy(ingest.dispatch_log_event).was.called_with(match.is_table(), match.is_function(), match.is_table())

          local all_calls = ingest.dispatch_log_event.calls
          assert.are.same(1, #all_calls)
          -- print("SPY CALL RECORD: " .. utils.stringify(all_calls[1])) -- DEBUG PRINT
          print("---- START SPY CALL RECORD INSPECTION ----")
          if type(all_calls[1]) == "table" then
            for k, v_inspect in pairs(all_calls[1]) do -- Changed v to v_inspect to avoid conflict
              print("  KEY:", tostring(k), "TYPE:", type(v_inspect))
              if k == "args" then
                if type(v_inspect) == "table" then
                  print("    ARGS COUNT:", #v_inspect)
                  for i_arg, arg_val in ipairs(v_inspect) do
                    print("      ARG[" .. i_arg .. "] TYPE:", type(arg_val))
                  end
                else
                  print("    args is not a table, type is:", type(v_inspect))
                end
              end
            end
          else
            print("  all_calls[1] is not a table, type is:", type(all_calls[1]))
          end
          print("---- END SPY CALL RECORD INSPECTION ----")
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

    it("logger:add_handler(handler_func, formatter_func, handler_config) should add handler correctly", function()
      local mock_handler_fn = function() end
      local mock_formatter_fn = function() end
      local mock_cfg = { type = "test" }

      test_logger:add_handler(mock_handler_fn, mock_formatter_fn, mock_cfg)
      assert.are.same(1, #test_logger.handlers)
      local entry = test_logger.handlers[1]
      assert.are.same(mock_handler_fn, entry.handler_func)
      assert.are.same(mock_formatter_fn, entry.formatter_func)
      assert.are.same(mock_cfg, entry.handler_config)

      -- Test with nil config
      test_logger:add_handler(mock_handler_fn, mock_formatter_fn, nil)
      assert.are.same(2, #test_logger.handlers)
      local entry_nil_config = test_logger.handlers[2]
      assert.is_table(entry_nil_config.handler_config) -- Should default to {}
      assert.are.same(0, #entry_nil_config.handler_config)
    end)

    describe("logger:get_effective_handlers()", function()
      local fresh_lualog_for_handlers
      local logger_root, logger_p, logger_c

      before_each(function()
        package.loaded["lual.logger"] = nil
        fresh_lualog_for_handlers = require("lual.logger")
        -- Use unique names for this test block to ensure clean hierarchy
        logger_root = fresh_lualog_for_handlers.get_logger("eff_root")
        logger_p = fresh_lualog_for_handlers.get_logger("eff_root.p")
        logger_c = fresh_lualog_for_handlers.get_logger("eff_root.p.c")

        -- Reset levels and handlers for these specific loggers
        logger_root.level = fresh_lualog_for_handlers.levels.DEBUG
        logger_p.level = fresh_lualog_for_handlers.levels.DEBUG
        logger_c.level = fresh_lualog_for_handlers.levels.DEBUG
        logger_root.handlers = {}
        logger_p.handlers = {}
        logger_c.handlers = {}
        logger_root.propagate = true
        logger_p.propagate = true
        logger_c.propagate = true
      end)

      local mock_h_fn = function() end
      local mock_f_fn = function() end

      it("should collect handlers from self and propagating parents", function()
        logger_c:add_handler(mock_h_fn, mock_f_fn, { id = "hc" })
        logger_p:add_handler(mock_h_fn, mock_f_fn, { id = "hp" })
        logger_root:add_handler(mock_h_fn, mock_f_fn, { id = "h_root" })

        local c_handlers = logger_c:get_effective_handlers()
        assert.are.same(4, #c_handlers) -- Expect 3 local + 1 from actual root
        assert.are.same("eff_root.p.c", c_handlers[1].owner_logger_name)
        assert.are.same("eff_root.p", c_handlers[2].owner_logger_name)
        assert.are.same("eff_root", c_handlers[3].owner_logger_name)
        assert.are.same("root", c_handlers[4].owner_logger_name) -- Check the propagated root handler
      end)

      it("should stop collecting if propagate is false on child", function()
        logger_c:add_handler(mock_h_fn, mock_f_fn, { id = "hc" })
        logger_p:add_handler(mock_h_fn, mock_f_fn, { id = "hp" })
        logger_root:add_handler(mock_h_fn, mock_f_fn, { id = "h_root" })

        logger_c.propagate = false
        local c_handlers = logger_c:get_effective_handlers()
        assert.are.same(1, #c_handlers)
        assert.are.same("eff_root.p.c", c_handlers[1].owner_logger_name)
      end)

      it("should stop collecting if propagate is false on parent", function()
        logger_c:add_handler(mock_h_fn, mock_f_fn, { id = "hc" })
        logger_p:add_handler(mock_h_fn, mock_f_fn, { id = "hp" })
        logger_root:add_handler(mock_h_fn, mock_f_fn, { id = "h_root" })

        logger_p.propagate = false -- c propagates to p, but p doesn't propagate to root
        local c_handlers = logger_c:get_effective_handlers()
        assert.are.same(2, #c_handlers)
        assert.are.same("eff_root.p.c", c_handlers[1].owner_logger_name)
        assert.are.same("eff_root.p", c_handlers[2].owner_logger_name)
      end)
    end)
  end)
end)
