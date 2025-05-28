#!/usr/bin/env lua
package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua;../lua/?.lua;../lua/?/init.lua"

-- local lualog = require("lual.logger") -- Will require lual.core.logging directly or via a facade
local engine = require("lual.core.logging")
local core_levels = require("lual.core.levels")
local ingest = require("lual.ingest")
local spy = require("luassert.spy")
local match = require("luassert.match")
local caller_info = require("lual.core.caller_info")
-- local utils = require("luassert.utils") -- For stringify - remove debug prints later

-- Get the current test file's name dynamically
local current_test_filename = caller_info.get_caller_info(1, true) or "unknown_test"

describe("lual.core.logging", function()
	describe("engine.logger(name)", function()
		it("should create a logger with auto-generated name when no name provided", function()
			package.loaded["lual.core.logging"] = nil
			package.loaded["lual.core.levels"] = nil
			local fresh_core_levels = require("lual.core.levels")
			local fresh_engine = require("lual.core.logging")
			fresh_engine.reset_cache() -- Ensure cache is clean

			local auto_logger = fresh_engine.logger()
			-- Should use the test filename (without .lua extension)
			assert.truthy(string.find(auto_logger.name, current_test_filename, 1, true))
			assert.is_false(string.find(auto_logger.name, ".lua", 1, true) ~= nil)
			assert.are.same(fresh_core_levels.definition.INFO, auto_logger.level) -- Default level

			local root_logger_named = fresh_engine.logger("root")
			assert.are.same("root", root_logger_named.name)
			assert.is_nil(root_logger_named.parent)
		end)

		it("should create a named logger and its parents", function()
			package.loaded["lual.core.logging"] = nil
			package.loaded["lual.core.levels"] = nil
			local fresh_core_levels = require("lual.core.levels")
			local fresh_engine = require("lual.core.logging")
			fresh_engine.reset_cache()

			local logger_a_b = fresh_engine.logger("spec_a.spec_b")
			assert.are.same("spec_a.spec_b", logger_a_b.name)
			assert.is_not_nil(logger_a_b.parent)
			assert.are.same("spec_a", logger_a_b.parent.name)
			assert.is_not_nil(logger_a_b.parent.parent)
			assert.are.same("root", logger_a_b.parent.parent.name)
			assert.is_nil(logger_a_b.parent.parent.parent)
		end)

		it("should cache loggers", function()
			package.loaded["lual.core.logging"] = nil
			local fresh_engine = require("lual.core.logging")
			fresh_engine.reset_cache()

			local logger1 = fresh_engine.logger("spec_cache_test")
			local logger2 = fresh_engine.logger("spec_cache_test")
			assert.are.same(logger1, logger2)
		end)

		it("should have propagation enabled by default", function()
			package.loaded["lual.core.logging"] = nil
			local fresh_engine = require("lual.core.logging")
			fresh_engine.reset_cache()
			local logger = fresh_engine.logger("spec_prop_test")
			assert.is_true(logger.propagate)
		end)
	end)

	describe("Logger Instance Methods", function()
		local test_logger
		local C_LEVELS_DEF = require("lual.core.levels").definition

		before_each(function()
			package.loaded["lual.core.logging"] = nil
			package.loaded["lual.core.levels"] = nil
			package.loaded["lual.ingest"] = nil
			local current_engine_module = require("lual.core.logging")
			ingest = require("lual.ingest")

			current_engine_module.reset_cache()
			test_logger = current_engine_module.logger("suite_logger_methods")

			local current_dispatch = ingest.dispatch_log_event
			if type(current_dispatch) == "table" and current_dispatch.revert then
				current_dispatch:revert()
			end
			spy.on(ingest, "dispatch_log_event")
		end)

		after_each(function()
			local current_dispatch = ingest.dispatch_log_event
			if type(current_dispatch) == "table" and current_dispatch.revert then
				current_dispatch:revert()
			end
			current_dispatch = ingest.dispatch_log_event
			if type(current_dispatch) == "table" and current_dispatch.clear then
				current_dispatch:clear()
			end
		end)

		it("logger:set_level(level) should update the logger's level", function()
			test_logger:set_level(C_LEVELS_DEF.DEBUG)
			assert.are.same(C_LEVELS_DEF.DEBUG, test_logger.level)
			test_logger:set_level(C_LEVELS_DEF.ERROR)
			assert.are.same(C_LEVELS_DEF.ERROR, test_logger.level)
		end)

		it("logger:is_enabled_for(level_no) should return correct boolean", function()
			test_logger:set_level(C_LEVELS_DEF.WARNING)
			assert.is_true(test_logger:is_enabled_for(C_LEVELS_DEF.ERROR))
			assert.is_true(test_logger:is_enabled_for(C_LEVELS_DEF.CRITICAL))
			assert.is_true(test_logger:is_enabled_for(C_LEVELS_DEF.WARNING))
			assert.is_false(test_logger:is_enabled_for(C_LEVELS_DEF.INFO))
			assert.is_false(test_logger:is_enabled_for(C_LEVELS_DEF.DEBUG))

			test_logger:set_level(C_LEVELS_DEF.NONE)
			assert.is_false(test_logger:is_enabled_for(C_LEVELS_DEF.CRITICAL))
			assert.is_true(test_logger:is_enabled_for(C_LEVELS_DEF.NONE))
		end)

		local function test_log_method(method_name, level_enum, level_name_str, actual_levels_table)
			describe("logger:" .. method_name .. "()", function()
				it("should call ingest.dispatch_log_event when level is enabled", function()
					test_logger:set_level(level_enum)

					local arg1 = "world"
					local arg2 = 123
					test_logger[method_name](test_logger, "Hello %s num %d", arg1, arg2)

					assert
						.spy(ingest.dispatch_log_event).was
						.called_with(match.is_table(), match.is_function(), match.is_table())

					local all_calls = ingest.dispatch_log_event.calls
					assert.are.same(1, #all_calls)
					local record = all_calls[1].vals[1]

					assert.are.same(level_enum, record.level_no)
					assert.are.same(level_name_str, record.level_name)
					assert.are.same(test_logger.name, record.logger_name)
					assert.are.same(test_logger.name, record.source_logger_name)
					assert.are.same("Hello %s num %d", record.message_fmt)

					assert.is_table(record.args)
					assert.are.same(2, record.args.n)
					assert.are.same(arg1, record.args[1])
					assert.are.same(arg2, record.args[2])

					assert.is_number(record.timestamp)
					assert.is_string(record.filename)
					-- Extract base filename from record.filename (remove path and extension)
					local record_basename = string.match(record.filename, "([^/\\]+)%.lua$") or
						string.match(record.filename, "([^/\\]+)$")
					-- Extract base filename from current_test_filename (remove path)
					local test_basename = string.match(current_test_filename, "([^%.]+)$") or current_test_filename
					-- Check that the base filenames match
					assert.truthy(record_basename and string.find(record_basename, test_basename, 1, true))

					ingest.dispatch_log_event:clear()
				end)

				it("should NOT call ingest.dispatch_log_event when level is disabled", function()
					if level_enum < actual_levels_table.CRITICAL then
						test_logger:set_level(level_enum + 10)
					else
						test_logger:set_level(actual_levels_table.NONE)
					end

					test_logger[method_name](test_logger, "Disabled message")
					assert.spy(ingest.dispatch_log_event).was.not_called()
					ingest.dispatch_log_event:clear()
				end)
			end)
		end

		test_log_method("debug", C_LEVELS_DEF.DEBUG, "DEBUG", C_LEVELS_DEF)
		test_log_method("info", C_LEVELS_DEF.INFO, "INFO", C_LEVELS_DEF)
		test_log_method("warn", C_LEVELS_DEF.WARNING, "WARNING", C_LEVELS_DEF)
		test_log_method("error", C_LEVELS_DEF.ERROR, "ERROR", C_LEVELS_DEF)
		test_log_method("critical", C_LEVELS_DEF.CRITICAL, "CRITICAL", C_LEVELS_DEF)

		it("logger:add_dispatcher(dispatcher_func, presenter_func, dispatcher_config) should add dispatcher correctly",
			function()
				local mock_dispatcher_fn = function() end
				local mock_presenter_fn = function() end
				local mock_cfg = { type = "test" }

				test_logger:add_dispatcher(mock_dispatcher_fn, mock_presenter_fn, mock_cfg)
				assert.are.same(1, #test_logger.dispatchers)
				local entry = test_logger.dispatchers[1]
				assert.are.same(mock_dispatcher_fn, entry.dispatcher_func)
				assert.are.same(mock_presenter_fn, entry.presenter_func)
				assert.are.same(mock_cfg, entry.dispatcher_config)

				test_logger:add_dispatcher(mock_dispatcher_fn, mock_presenter_fn, nil)
				assert.are.same(2, #test_logger.dispatchers)
				local entry_nil_config = test_logger.dispatchers[2]
				assert.is_table(entry_nil_config.dispatcher_config)
				assert.are.same(0, #entry_nil_config.dispatcher_config)
			end)

		describe("logger:get_effective_dispatchers()", function()
			local test_cl_module_for_dispatchers
			local test_clevels_module_for_dispatchers
			local logger_root, logger_p, logger_c

			before_each(function()
				package.loaded["lual.core.logging"] = nil
				package.loaded["lual.core.levels"] = nil
				test_cl_module_for_dispatchers = require("lual.core.logging")
				test_clevels_module_for_dispatchers = require("lual.core.levels")
				test_cl_module_for_dispatchers.reset_cache()

				logger_root = test_cl_module_for_dispatchers.logger("eff_root")
				logger_p = test_cl_module_for_dispatchers.logger("eff_root.p")
				logger_c = test_cl_module_for_dispatchers.logger("eff_root.p.c")

				logger_root.dispatchers = {} -- Clear any default dispatchers on eff_root itself
				logger_p.dispatchers = {}
				logger_c.dispatchers = {}

				logger_root.level = test_clevels_module_for_dispatchers.definition.DEBUG
				logger_p.level = test_clevels_module_for_dispatchers.definition.DEBUG
				logger_c.level = test_clevels_module_for_dispatchers.definition.DEBUG
				logger_root.propagate = true
				logger_p.propagate = true
				logger_c.propagate = true

				-- Crucially, ensure the canonical "root" logger (parent of eff_root) also has clean dispatchers for this test
				local canonical_root = test_cl_module_for_dispatchers.logger("root")
				if canonical_root then
					canonical_root.dispatchers = {}
				end
			end)

			local mock_h_fn = function() end
			local mock_f_fn = function() end

			it("should collect dispatchers from self and propagating parents (clean root)", function()
				logger_c:add_dispatcher(mock_h_fn, mock_f_fn, { id = "hc" })
				logger_p:add_dispatcher(mock_h_fn, mock_f_fn, { id = "hp" })
				logger_root:add_dispatcher(mock_h_fn, mock_f_fn, { id = "h_eff_root" })

				local c_dispatchers = logger_c:get_effective_dispatchers()
				assert.are.same(3, #c_dispatchers)
				assert.are.same("eff_root.p.c", c_dispatchers[1].owner_logger_name)
				assert.are.same("eff_root.p", c_dispatchers[2].owner_logger_name)
				assert.are.same("eff_root", c_dispatchers[3].owner_logger_name)
			end)

			it("should stop collecting if propagate is false on child", function()
				logger_c:add_dispatcher(mock_h_fn, mock_f_fn, { id = "hc" })
				logger_p:add_dispatcher(mock_h_fn, mock_f_fn, { id = "hp" })
				logger_root:add_dispatcher(mock_h_fn, mock_f_fn, { id = "h_eff_root" })

				logger_c.propagate = false
				local c_dispatchers = logger_c:get_effective_dispatchers()
				assert.are.same(1, #c_dispatchers)
				assert.are.same("eff_root.p.c", c_dispatchers[1].owner_logger_name)
			end)

			it("should stop collecting if propagate is false on parent", function()
				logger_c:add_dispatcher(mock_h_fn, mock_f_fn, { id = "hc" })
				logger_p:add_dispatcher(mock_h_fn, mock_f_fn, { id = "hp" })
				logger_root:add_dispatcher(mock_h_fn, mock_f_fn, { id = "h_eff_root" })

				logger_p.propagate = false
				local c_dispatchers = logger_c:get_effective_dispatchers()
				assert.are.same(2, #c_dispatchers)
				assert.are.same("eff_root.p.c", c_dispatchers[1].owner_logger_name)
				assert.are.same("eff_root.p", c_dispatchers[2].owner_logger_name)
			end)
		end)
	end)
end)
