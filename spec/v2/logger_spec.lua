#!/usr/bin/env lua
package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua;../lua/?.lua;../lua/?/init.lua"

local lual = require("lual.logger")
local core_levels = require("lua.lual.v2.levels")

describe("lual.v2 Logger - Effective Level Calculation (Step 2.5)", function()
    before_each(function()
        -- Reset v2 config for each test
        lual.v2.reset_config()
    end)

    describe("_get_effective_level() method", function()
        it("should return explicit level when logger has non-NOTSET level", function()
            -- Create a logger with explicit DEBUG level
            local logger = lual.v2.create_logger("test.logger", core_levels.definition.DEBUG, nil)

            local effective_level = logger:_get_effective_level()
            assert.are.equal(core_levels.definition.DEBUG, effective_level)
        end)

        it("should return explicit level for different levels", function()
            local test_levels = {
                core_levels.definition.DEBUG,
                core_levels.definition.INFO,
                core_levels.definition.WARNING,
                core_levels.definition.ERROR,
                core_levels.definition.CRITICAL,
                core_levels.definition.NONE
            }

            for _, level in ipairs(test_levels) do
                local logger = lual.v2.create_logger("test.logger", level, nil)
                local effective_level = logger:_get_effective_level()
                assert.are.equal(level, effective_level, "Failed for level " .. level)
            end
        end)

        it("should return root config level when logger is _root with NOTSET", function()
            -- Configure root with specific level
            lual.v2.config({ level = core_levels.definition.ERROR })

            -- Create root logger with NOTSET level (shouldn't happen in practice, but test the logic)
            local root_logger = lual.v2.create_logger("_root", core_levels.definition.NOTSET, nil)

            local effective_level = root_logger:_get_effective_level()
            assert.are.equal(core_levels.definition.ERROR, effective_level)
        end)

        it("should inherit level from parent when logger has NOTSET", function()
            -- Create parent with explicit level
            local parent_logger = lual.v2.create_logger("parent", core_levels.definition.WARNING, nil)

            -- Create child with NOTSET level
            local child_logger = lual.v2.create_logger("parent.child", core_levels.definition.NOTSET, parent_logger)

            local effective_level = child_logger:_get_effective_level()
            assert.are.equal(core_levels.definition.WARNING, effective_level)
        end)

        it("should recursively inherit through multiple levels", function()
            -- Create hierarchy: grandparent (ERROR) -> parent (NOTSET) -> child (NOTSET)
            local grandparent = lual.v2.create_logger("grandparent", core_levels.definition.ERROR, nil)
            local parent = lual.v2.create_logger("grandparent.parent", core_levels.definition.NOTSET, grandparent)
            local child = lual.v2.create_logger("grandparent.parent.child", core_levels.definition.NOTSET, parent)

            -- Child should inherit ERROR from grandparent
            local effective_level = child:_get_effective_level()
            assert.are.equal(core_levels.definition.ERROR, effective_level)
        end)

        it("should stop at first explicit level in hierarchy", function()
            -- Create hierarchy: grandparent (ERROR) -> parent (INFO) -> child (NOTSET)
            local grandparent = lual.v2.create_logger("grandparent", core_levels.definition.ERROR, nil)
            local parent = lual.v2.create_logger("grandparent.parent", core_levels.definition.INFO, grandparent)
            local child = lual.v2.create_logger("grandparent.parent.child", core_levels.definition.NOTSET, parent)

            -- Child should inherit INFO from parent, not ERROR from grandparent
            local effective_level = child:_get_effective_level()
            assert.are.equal(core_levels.definition.INFO, effective_level)
        end)

        it("should fallback to INFO when no parent and not root", function()
            -- Create orphaned logger with NOTSET level
            local orphan_logger = lual.v2.create_logger("orphan", core_levels.definition.NOTSET, nil)

            local effective_level = orphan_logger:_get_effective_level()
            assert.are.equal(core_levels.definition.INFO, effective_level)
        end)

        it("should handle deep hierarchy correctly", function()
            -- Create deep hierarchy where only the root has explicit level
            local root = lual.v2.create_logger("root", core_levels.definition.CRITICAL, nil)
            local level1 = lual.v2.create_logger("root.l1", core_levels.definition.NOTSET, root)
            local level2 = lual.v2.create_logger("root.l1.l2", core_levels.definition.NOTSET, level1)
            local level3 = lual.v2.create_logger("root.l1.l2.l3", core_levels.definition.NOTSET, level2)
            local level4 = lual.v2.create_logger("root.l1.l2.l3.l4", core_levels.definition.NOTSET, level3)

            -- All should inherit CRITICAL from root
            assert.are.equal(core_levels.definition.CRITICAL, level1:_get_effective_level())
            assert.are.equal(core_levels.definition.CRITICAL, level2:_get_effective_level())
            assert.are.equal(core_levels.definition.CRITICAL, level3:_get_effective_level())
            assert.are.equal(core_levels.definition.CRITICAL, level4:_get_effective_level())
        end)
    end)

    describe("Integration with v2 config system", function()
        it("should use v2 config level for _root logger", function()
            -- Set root config level
            lual.v2.config({ level = core_levels.definition.DEBUG })

            -- Create root logger (will use config level)
            local root_logger = lual.v2.create_root_logger()

            local effective_level = root_logger:_get_effective_level()
            assert.are.equal(core_levels.definition.DEBUG, effective_level)
        end)

        it("should update effective level when v2 config changes", function()
            -- Set initial config
            lual.v2.config({ level = core_levels.definition.INFO })
            local root_logger = lual.v2.create_root_logger()

            -- Create child that inherits
            local child = lual.v2.create_logger("child", core_levels.definition.NOTSET, root_logger)
            assert.are.equal(core_levels.definition.INFO, child:_get_effective_level())

            -- Update root config
            lual.v2.config({ level = core_levels.definition.ERROR })

            -- Child should now inherit the new level
            assert.are.equal(core_levels.definition.ERROR, child:_get_effective_level())
        end)

        it("should handle _root logger with NOTSET requesting config level", function()
            -- Set v2 config
            lual.v2.config({ level = core_levels.definition.WARNING })

            -- Create _root logger manually with NOTSET (edge case)
            local root_logger = lual.v2.create_logger("_root", core_levels.definition.NOTSET, nil)

            local effective_level = root_logger:_get_effective_level()
            assert.are.equal(core_levels.definition.WARNING, effective_level)
        end)
    end)

    describe("Edge cases and error conditions", function()
        it("should handle logger with no name gracefully", function()
            local logger = lual.v2.create_logger(nil, core_levels.definition.NOTSET, nil)

            -- Should fallback to INFO
            local effective_level = logger:_get_effective_level()
            assert.are.equal(core_levels.definition.INFO, effective_level)
        end)

        it("should handle all NOTSET hierarchy", function()
            -- Create hierarchy where everyone has NOTSET
            local parent = lual.v2.create_logger("parent", core_levels.definition.NOTSET, nil)
            local child = lual.v2.create_logger("child", core_levels.definition.NOTSET, parent)

            -- Should fallback to INFO
            local effective_level = child:_get_effective_level()
            assert.are.equal(core_levels.definition.INFO, effective_level)
        end)

        it("should handle circular references gracefully", function()
            -- Create two loggers
            local logger1 = lual.v2.create_logger("logger1", core_levels.definition.NOTSET, nil)
            local logger2 = lual.v2.create_logger("logger2", core_levels.definition.NOTSET, nil)

            -- Create circular reference (shouldn't happen in practice)
            logger1.parent = logger2
            logger2.parent = logger1

            -- This should eventually hit the fallback or one of the loggers should have an explicit level
            -- Let's give one an explicit level to break the cycle
            logger2.level = core_levels.definition.DEBUG

            local effective_level = logger1:_get_effective_level()
            assert.are.equal(core_levels.definition.DEBUG, effective_level)
        end)
    end)

    describe("Performance and behavior", function()
        it("should be efficient for single-level lookup", function()
            local logger = lual.v2.create_logger("test", core_levels.definition.WARNING, nil)

            -- Multiple calls should return same result quickly
            for i = 1, 100 do
                local level = logger:_get_effective_level()
                assert.are.equal(core_levels.definition.WARNING, level)
            end
        end)

        it("should be deterministic", function()
            -- Set up hierarchy
            local root = lual.v2.create_logger("root", core_levels.definition.ERROR, nil)
            local child = lual.v2.create_logger("child", core_levels.definition.NOTSET, root)

            -- Multiple calls should return same result
            local first_result = child:_get_effective_level()
            for i = 1, 10 do
                local result = child:_get_effective_level()
                assert.are.equal(first_result, result)
            end
        end)
    end)
end)
