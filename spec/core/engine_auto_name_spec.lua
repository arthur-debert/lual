#!/usr/bin/env lua
package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua;../lua/?.lua;../lua/?/init.lua"

local engine = require("lual.core.logging")
local caller_info = require("lual.core.caller_info")
local assert = require("luassert")

-- Get the current test file's name dynamically
local current_test_filename, _, _ = caller_info.get_caller_info(1, true)
current_test_filename = current_test_filename or "unknown_test"

describe("lual.core.engine auto-naming", function()
    before_each(function()
        -- Reset cache before each test
        engine.reset_cache()
    end)

    describe("logger() with automatic naming", function()
        it("should use filename as logger name when no name provided", function()
            local logger = engine.logger()

            -- Debug: Show what we actually got vs expected
            print("DEBUG: current_test_filename =", current_test_filename)
            print("DEBUG: logger.name =", logger.name)

            -- Should use the test filename (without .lua extension)
            assert.are.equal("string", type(logger.name), "logger.name should be a string")
            assert.are.equal(current_test_filename, logger.name, "logger.name should match current_test_filename")
            assert.is_false(string.find(logger.name, ".lua", 1, true) ~= nil)
        end)

        it("should convert path separators to dots", function()
            -- Mock caller_info to return a path with separators
            local original_get_caller_info = caller_info.get_caller_info
            caller_info.get_caller_info = function(start_level, use_dot_notation)
                if use_dot_notation then
                    return "path.to.my.module", 42
                else
                    return "path/to/my/module.lua", 42
                end
            end

            local logger = engine.logger()

            -- Restore original function
            caller_info.get_caller_info = original_get_caller_info

            assert.are.equal("path.to.my.module", logger.name)
        end)

        it("should handle Windows-style path separators", function()
            -- Mock caller_info to return a Windows path
            local original_get_caller_info = caller_info.get_caller_info
            caller_info.get_caller_info = function(start_level, use_dot_notation)
                if use_dot_notation then
                    return "C:.Users.test.project.module", 42
                else
                    return "C:\\Users\\test\\project\\module.lua", 42
                end
            end

            local logger = engine.logger()

            -- Restore original function
            caller_info.get_caller_info = original_get_caller_info

            assert.are.equal("C:.Users.test.project.module", logger.name)
        end)

        it("should remove leading dots", function()
            -- Mock caller_info to return a path starting with ./
            local original_get_caller_info = caller_info.get_caller_info
            caller_info.get_caller_info = function(start_level, use_dot_notation)
                if use_dot_notation then
                    return "src.module", 42
                else
                    return "./src/module.lua", 42
                end
            end

            local logger = engine.logger()

            -- Restore original function
            caller_info.get_caller_info = original_get_caller_info

            assert.are.equal("src.module", logger.name)
        end)

        it("should handle files without .lua extension", function()
            -- Mock caller_info to return a non-lua file
            local original_get_caller_info = caller_info.get_caller_info
            caller_info.get_caller_info = function(start_level, use_dot_notation)
                if use_dot_notation then
                    return "scripts.deploy.sh", 42
                else
                    return "scripts/deploy.sh", 42
                end
            end

            local logger = engine.logger()

            -- Restore original function
            caller_info.get_caller_info = original_get_caller_info

            assert.are.equal("scripts.deploy.sh", logger.name)
        end)

        it("should fall back to root when filename processing results in empty string", function()
            -- Mock caller_info to return a problematic filename
            local original_get_caller_info = caller_info.get_caller_info
            caller_info.get_caller_info = function(start_level, use_dot_notation)
                if use_dot_notation then
                    return nil, 42 -- Would become nil after processing
                else
                    return ".lua", 42
                end
            end

            local logger = engine.logger()

            -- Restore original function
            caller_info.get_caller_info = original_get_caller_info

            assert.are.equal("_root", logger.name)
        end)

        it("should fall back to root when caller_info returns nil", function()
            -- Mock caller_info to return nil
            local original_get_caller_info = caller_info.get_caller_info
            caller_info.get_caller_info = function(start_level, use_dot_notation)
                return nil, nil
            end

            local logger = engine.logger()

            -- Restore original function
            caller_info.get_caller_info = original_get_caller_info

            assert.are.equal("_root", logger.name)
        end)

        it("should still use provided name when explicitly given", function()
            local logger = engine.logger("my.custom.logger")

            assert.are.equal("my.custom.logger", logger.name)
        end)

        it("should still use provided name even when empty string", function()
            local logger = engine.logger("")

            -- Debug: Show what we actually got vs expected
            print("DEBUG: current_test_filename =", current_test_filename)
            print("DEBUG: logger.name =", logger.name)

            -- Empty string should trigger auto-naming
            assert.are.equal("string", type(logger.name), "logger.name should be a string")
            assert.are.equal(current_test_filename, logger.name, "logger.name should match current_test_filename")
        end)

        it("should cache loggers with auto-generated names", function()
            local logger1 = engine.logger()
            local logger2 = engine.logger()

            -- Should be the same instance
            assert.are.same(logger1, logger2)
            assert.are.equal(logger1.name, logger2.name)
        end)

        it("should create proper hierarchy with auto-generated names", function()
            -- First configure a root logger to enable full hierarchy
            local lual = require("lual.logger")
            lual.config({ level = "info" })

            -- Mock caller_info to return a nested path
            local original_get_caller_info = caller_info.get_caller_info
            caller_info.get_caller_info = function(start_level, use_dot_notation)
                if use_dot_notation then
                    return "app.services.database", 42
                else
                    return "app/services/database.lua", 42
                end
            end

            local logger = engine.logger()

            -- Restore original function
            caller_info.get_caller_info = original_get_caller_info

            assert.are.equal("app.services.database", logger.name)
            assert.is_not_nil(logger.parent)
            assert.are.equal("app.services", logger.parent.name)
            assert.is_not_nil(logger.parent.parent)
            assert.are.equal("app", logger.parent.parent.name)
            assert.is_not_nil(logger.parent.parent.parent)
            assert.are.equal("_root", logger.parent.parent.parent.name)
        end)

        it("should create entire hierarchy with auto-generated names", function()
            local deep_logger = engine.logger("a.b.c.d")

            -- Should create entire hierarchy: a -> a.b -> a.b.c -> a.b.c.d
            -- Starting from parent instead of great-great-grandparent for clarity
            assert.is_not_nil(deep_logger.parent)                  -- a.b.c
            assert.is_not_nil(deep_logger.parent.parent)           -- a.b
            assert.is_not_nil(deep_logger.parent.parent.parent)    -- a
            assert.are.equal("a", deep_logger.parent.parent.parent.name)
            assert.is_nil(deep_logger.parent.parent.parent.parent) -- No parent for a (no root configured)
        end)
    end)
end)
