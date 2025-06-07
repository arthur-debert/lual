#!/usr/bin/env lua
package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua;../lua/?.lua;../lua/?/init.lua"

local lual = require("lual.logger")
local core_levels = require("lual.levels")
local get_logger_tree = require("lual.log.get_logger_tree")

describe("lual.log.get_logger_tree", function()
    before_each(function()
        lual.reset_config()
        lual.reset_cache()
    end)

    describe("get_logger_tree() function", function()
        it("should return a list with just the logger when it's the root logger", function()
            local root_logger = lual.logger("_root")
            local tree = get_logger_tree.get_logger_tree(root_logger)

            assert.are.equal(1, #tree)
            assert.are.equal("_root", tree[1].name)
        end)

        it("should return a list with the logger and its parent for a simple hierarchy", function()
            local parent_logger = lual.logger("parent")
            local child_logger = lual.logger("parent.child")

            local tree = get_logger_tree.get_logger_tree(child_logger)

            assert.are.equal(3, #tree) -- child, parent, and _root
            assert.are.equal("parent.child", tree[1].name)
            assert.are.equal("parent", tree[2].name)
            assert.are.equal("_root", tree[3].name)
        end)

        it("should return the full hierarchy up to root for a deep hierarchy", function()
            local level1 = lual.logger("level1")
            local level2 = lual.logger("level1.level2")
            local level3 = lual.logger("level1.level2.level3")
            local level4 = lual.logger("level1.level2.level3.level4")

            local tree = get_logger_tree.get_logger_tree(level4)

            assert.are.equal(5, #tree)
            assert.are.equal("level1.level2.level3.level4", tree[1].name)
            assert.are.equal("level1.level2.level3", tree[2].name)
            assert.are.equal("level1.level2", tree[3].name)
            assert.are.equal("level1", tree[4].name)
            assert.are.equal("_root", tree[5].name)
        end)

        it("should stop at the logger with propagate=false", function()
            local parent_logger = lual.logger("parent")
            local child_logger = lual.logger("parent.child", { propagate = false })
            local grandchild_logger = lual.logger("parent.child.grandchild")

            local tree = get_logger_tree.get_logger_tree(grandchild_logger)

            assert.are.equal(2, #tree)
            assert.are.equal("parent.child.grandchild", tree[1].name)
            assert.are.equal("parent.child", tree[2].name)
        end)

        it("should include all loggers regardless of their level", function()
            lual.config({ level = core_levels.definition.ERROR })

            local parent_logger = lual.logger("parent", { level = core_levels.definition.WARNING })
            local child_logger = lual.logger("parent.child", { level = core_levels.definition.DEBUG })

            local tree = get_logger_tree.get_logger_tree(child_logger)

            assert.are.equal(3, #tree)
            assert.are.equal("parent.child", tree[1].name)
            assert.are.equal("parent", tree[2].name)
            assert.are.equal("_root", tree[3].name)
        end)
    end)
end)
