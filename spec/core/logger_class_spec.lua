#!/usr/bin/env lua
package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua;../lua/?.lua;../lua/?/init.lua"

-- local lualog = require("lual.logger") -- Will require lual.core.logger_class directly or via a facade
local logger_class = require("lual.core.logger_class")
local core_levels = require("lual.core.levels")
local ingest = require("lual.ingest")
local spy = require("luassert.spy")
local match = require("luassert.match")
-- local utils = require("luassert.utils") -- For stringify - remove debug prints later

describe("lual.core.logger_class", function()
    describe("logger_class.get_logger(name)", function()
        it("should create a root logger correctly", function()
            package.loaded["lual.core.logger_class"] = nil
            package.loaded["lual.core.levels"] = nil
            local fresh_core_levels = require("lual.core.levels")
            local fresh_logger_class = require("lual.core.logger_class")
            fresh_logger_class.reset_cache() -- Ensure cache is clean

            local root_logger = fresh_logger_class.get_logger()
            assert.are.same("root", root_logger.name)
            assert.is_nil(root_logger.parent)
            assert.are.same(fresh_core_levels.definition.INFO, root_logger.level) -- Default level

            local root_logger_named = fresh_logger_class.get_logger("root")
            assert.are.same(root_logger, root_logger_named)
        end)

        it("should create a named logger and its parents", function()
            package.loaded["lual.core.logger_class"] = nil
            package.loaded["lual.core.levels"] = nil
            local fresh_core_levels = require("lual.core.levels")
            local fresh_logger_class = require("lual.core.logger_class")
            fresh_logger_class.reset_cache()

            local logger_a_b = fresh_logger_class.get_logger("spec_a.spec_b")
            assert.are.same("spec_a.spec_b", logger_a_b.name)
            assert.is_not_nil(logger_a_b.parent)
            assert.are.same("spec_a", logger_a_b.parent.name)
            assert.is_not_nil(logger_a_b.parent.parent)
            assert.are.same("root", logger_a_b.parent.parent.name)
            assert.is_nil(logger_a_b.parent.parent.parent)
        end)

        it("should cache loggers", function()
            package.loaded["lual.core.logger_class"] = nil
            local fresh_logger_class = require("lual.core.logger_class")
            fresh_logger_class.reset_cache()

            local logger1 = fresh_logger_class.get_logger("spec_cache_test")
            local logger2 = fresh_logger_class.get_logger("spec_cache_test")
            assert.are.same(logger1, logger2)
        end)

        it("should have propagation enabled by default", function()
            package.loaded["lual.core.logger_class"] = nil
            local fresh_logger_class = require("lual.core.logger_class")
            fresh_logger_class.reset_cache()
            local logger = fresh_logger_class.get_logger("spec_prop_test")
            assert.is_true(logger.propagate)
        end)
    end)

    describe("Logger Instance Methods", function()
        local test_logger
        local C_LEVELS_DEF = require("lual.core.levels").definition

        before_each(function()
            package.loaded["lual.core.logger_class"] = nil
            package.loaded["lual.core.levels"] = nil
            package.loaded["lual.ingest"] = nil
            local current_logger_class_module = require("lual.core.logger_class")
            ingest = require("lual.ingest")

            current_logger_class_module.reset_cache()
            test_logger = current_logger_class_module.get_logger("suite_logger_methods")

            local current_dispatch = ingest.dispatch_log_event
            if type(current_dispatch) == 'table' and current_dispatch.revert then
                current_dispatch:revert()
            end
            spy.on(ingest, "dispatch_log_event")
        end)

        after_each(function()
            local current_dispatch = ingest.dispatch_log_event
            if type(current_dispatch) == 'table' and current_dispatch.revert then
                current_dispatch:revert()
            end
            current_dispatch = ingest.dispatch_log_event
            if type(current_dispatch) == 'table' and current_dispatch.clear then
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

                    assert.spy(ingest.dispatch_log_event).was.called_with(match.is_table(), match.is_function(),
                        match.is_table())

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
                    assert.truthy(string.find(record.filename, "spec/core/logger_class_spec.lua", 1, true) or
                        string.find(record.filename, "logger_class_spec.lua", 1, true))
                    assert.is_number(record.lineno)

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

            test_logger:add_handler(mock_handler_fn, mock_formatter_fn, nil)
            assert.are.same(2, #test_logger.handlers)
            local entry_nil_config = test_logger.handlers[2]
            assert.is_table(entry_nil_config.handler_config)
            assert.are.same(0, #entry_nil_config.handler_config)
        end)

        describe("logger:get_effective_handlers()", function()
            local test_cl_module_for_handlers
            local test_clevels_module_for_handlers
            local logger_root, logger_p, logger_c

            before_each(function()
                package.loaded["lual.core.logger_class"] = nil
                package.loaded["lual.core.levels"] = nil
                test_cl_module_for_handlers = require("lual.core.logger_class")
                test_clevels_module_for_handlers = require("lual.core.levels")
                test_cl_module_for_handlers.reset_cache()

                logger_root = test_cl_module_for_handlers.get_logger("eff_root")
                logger_p = test_cl_module_for_handlers.get_logger("eff_root.p")
                logger_c = test_cl_module_for_handlers.get_logger("eff_root.p.c")

                logger_root.handlers = {} -- Clear any default handlers on eff_root itself
                logger_p.handlers = {}
                logger_c.handlers = {}

                logger_root.level = test_clevels_module_for_handlers.definition.DEBUG
                logger_p.level = test_clevels_module_for_handlers.definition.DEBUG
                logger_c.level = test_clevels_module_for_handlers.definition.DEBUG
                logger_root.propagate = true
                logger_p.propagate = true
                logger_c.propagate = true

                -- Crucially, ensure the canonical "root" logger (parent of eff_root) also has clean handlers for this test
                local canonical_root = test_cl_module_for_handlers.get_logger("root")
                if canonical_root then canonical_root.handlers = {} end
            end)

            local mock_h_fn = function() end
            local mock_f_fn = function() end

            it("should collect handlers from self and propagating parents (clean root)", function()
                logger_c:add_handler(mock_h_fn, mock_f_fn, { id = "hc" })
                logger_p:add_handler(mock_h_fn, mock_f_fn, { id = "hp" })
                logger_root:add_handler(mock_h_fn, mock_f_fn, { id = "h_eff_root" })

                local c_handlers = logger_c:get_effective_handlers()
                assert.are.same(3, #c_handlers)
                assert.are.same("eff_root.p.c", c_handlers[1].owner_logger_name)
                assert.are.same("eff_root.p", c_handlers[2].owner_logger_name)
                assert.are.same("eff_root", c_handlers[3].owner_logger_name)
            end)

            it("should stop collecting if propagate is false on child", function()
                logger_c:add_handler(mock_h_fn, mock_f_fn, { id = "hc" })
                logger_p:add_handler(mock_h_fn, mock_f_fn, { id = "hp" })
                logger_root:add_handler(mock_h_fn, mock_f_fn, { id = "h_eff_root" })

                logger_c.propagate = false
                local c_handlers = logger_c:get_effective_handlers()
                assert.are.same(1, #c_handlers)
                assert.are.same("eff_root.p.c", c_handlers[1].owner_logger_name)
            end)

            it("should stop collecting if propagate is false on parent", function()
                logger_c:add_handler(mock_h_fn, mock_f_fn, { id = "hc" })
                logger_p:add_handler(mock_h_fn, mock_f_fn, { id = "hp" })
                logger_root:add_handler(mock_h_fn, mock_f_fn, { id = "h_eff_root" })

                logger_p.propagate = false
                local c_handlers = logger_c:get_effective_handlers()
                assert.are.same(2, #c_handlers)
                assert.are.same("eff_root.p.c", c_handlers[1].owner_logger_name)
                assert.are.same("eff_root.p", c_handlers[2].owner_logger_name)
            end)
        end)
    end)
end)
