#!/usr/bin/env lua
package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua;../lua/?.lua;../lua/?/init.lua"

local caller_info = require("lual.core.caller_info")
local assert = require("luassert")

describe("lual.core.caller_info", function()
    describe("get_caller_info()", function()
        it("should return filename and line number for direct call", function()
            local filename, lineno, lua_path = caller_info.get_caller_info()

            assert.is_string(filename)
            assert.is_number(lineno)

            -- Should contain the test file name
            assert.truthy(string.find(filename, "caller_info_spec.lua", 1, true))

            -- Line number should be reasonable (not 0 or negative)
            assert.is_true(lineno > 0)

            -- lua_path might be nil if not findable in package.path
            -- Just check it's either nil or string
            assert.truthy(lua_path == nil or type(lua_path) == "string")
        end)

        it("should return correct info when called through a wrapper function", function()
            local function wrapper_function()
                return caller_info.get_caller_info() -- Automatically skip lual internals
            end

            local filename, lineno, lua_path = wrapper_function() -- This line should be captured



            -- Use assert.are.equal to get clear failure messages showing both expected and actual values
            assert.are.equal("string", type(filename)) -- This will show the actual type if it fails
            assert.are.equal("number", type(lineno))   -- This will show the actual type if it fails

            -- This will show the exact filename value if it fails
            assert.are.equal("spec/core/caller_info_spec.lua", filename)

            -- Line number should be positive
            assert.is_true(lineno > 0)

            -- lua_path might be nil or string
            assert.truthy(lua_path == nil or type(lua_path) == "string")
        end)

        it("should handle @ prefix in filename correctly", function()
            -- Mock debug.getinfo to return a filename with @ prefix
            local original_getinfo = debug.getinfo
            debug.getinfo = function(level, what)
                if level >= 2 and what == "Sl" then -- Any level >= 2 should return our test file
                    return {
                        source = "@/path/to/test_file.lua",
                        short_src = "@/path/to/test_file.lua",
                        currentline = 42
                    }
                end
                return original_getinfo(level, what)
            end

            local filename, lineno, lua_path = caller_info.get_caller_info()

            -- Restore original function
            debug.getinfo = original_getinfo

            assert.are.equal("/path/to/test_file.lua", filename)
            assert.are.equal(42, lineno)
            -- lua_path should be generated from the mocked path
            assert.are.equal("path.to.test_file", lua_path)
        end)

        it("should handle filename without @ prefix", function()
            -- Mock debug.getinfo to return a filename without @ prefix
            local original_getinfo = debug.getinfo
            debug.getinfo = function(level, what)
                if level >= 2 and what == "Sl" then -- Any level >= 2 should return our test file
                    return {
                        source = "stdin",
                        short_src = "stdin",
                        currentline = 10
                    }
                end
                return original_getinfo(level, what)
            end

            local filename, lineno, lua_path = caller_info.get_caller_info()

            -- Restore original function
            debug.getinfo = original_getinfo

            assert.are.equal("stdin", filename)
            assert.are.equal(10, lineno)
            -- lua_path should be generated for stdin
            assert.are.equal("stdin", lua_path)
        end)

        it("should return nil values when debug info is unavailable", function()
            -- Mock debug.getinfo to return nil for all levels
            local original_getinfo = debug.getinfo
            debug.getinfo = function(level, what)
                return nil -- Always return nil to simulate no debug info
            end

            local filename, lineno, lua_path = caller_info.get_caller_info()

            -- Restore original function
            debug.getinfo = original_getinfo

            assert.is_nil(filename)
            assert.is_nil(lineno)
            assert.is_nil(lua_path)
        end)

        it("should use default start level when not specified", function()
            local filename1, lineno1, lua_path1 = caller_info.get_caller_info()  -- No start level specified
            local filename2, lineno2, lua_path2 = caller_info.get_caller_info(2) -- Explicit start level 2

            assert.are.equal(filename1, filename2)
            -- Line numbers might differ by 1 due to the different call lines
            assert.is_true(math.abs(lineno1 - lineno2) <= 1)
            -- lua_path should be the same
            assert.are.equal(lua_path1, lua_path2)
        end)

        it("should automatically skip lual internal files", function()
            -- This test verifies that the function automatically finds non-lual files
            local filename, lineno, lua_path = caller_info.get_caller_info()

            assert.is_string(filename)
            assert.is_number(lineno)
            assert.truthy(string.find(filename, "caller_info_spec.lua", 1, true))
            assert.is_true(lineno > 0)

            -- Verify it doesn't return lual internal files
            assert.is_false(string.find(filename, "caller_info.lua", 1, true) ~= nil)
            assert.is_false(string.find(filename, "engine.lua", 1, true) ~= nil)

            -- lua_path check
            assert.truthy(lua_path == nil or type(lua_path) == "string")
        end)

        it("should handle edge case with empty filename", function()
            -- Mock debug.getinfo to return empty short_src
            local original_getinfo = debug.getinfo
            debug.getinfo = function(level, what)
                if level >= 2 and what == "Sl" then -- Any level >= 2 should return our test file
                    return {
                        source = "",
                        short_src = "",
                        currentline = 5
                    }
                end
                return original_getinfo(level, what)
            end

            local filename, lineno, lua_path = caller_info.get_caller_info()

            -- Restore original function
            debug.getinfo = original_getinfo

            assert.are.equal("", filename)
            assert.are.equal(5, lineno)
            assert.is_nil(lua_path)
        end)

        it("should handle edge case with nil filename", function()
            -- Mock debug.getinfo to return nil short_src
            local original_getinfo = debug.getinfo
            debug.getinfo = function(level, what)
                if level >= 2 and what == "Sl" then -- Any level >= 2 should return our test file
                    return {
                        source = nil,
                        short_src = nil,
                        currentline = 7
                    }
                end
                return original_getinfo(level, what)
            end

            local filename, lineno, lua_path = caller_info.get_caller_info()

            -- Restore original function
            debug.getinfo = original_getinfo

            assert.is_nil(filename)
            assert.are.equal(7, lineno)
            assert.is_nil(lua_path)
        end)
    end)

    describe("get_caller_info() with dot notation", function()
        it("should convert filename to dot notation when use_dot_notation is true", function()
            -- Mock debug.getinfo to return a path with separators
            local original_getinfo = debug.getinfo
            debug.getinfo = function(level, what)
                if level >= 2 and what == "Sl" then
                    return {
                        source = "@path/to/my/module.lua",
                        short_src = "@path/to/my/module.lua",
                        currentline = 42
                    }
                end
                return original_getinfo(level, what)
            end

            local filename, lineno, lua_path = caller_info.get_caller_info(nil, true)

            -- Restore original function
            debug.getinfo = original_getinfo

            assert.are.equal("path.to.my.module", filename)
            assert.are.equal(42, lineno)
            -- lua_path should be generated from the mocked path
            assert.are.equal("path.to.my.module", lua_path)
        end)

        it("should handle Windows-style paths with dot notation", function()
            -- Mock debug.getinfo to return a Windows path
            local original_getinfo = debug.getinfo
            debug.getinfo = function(level, what)
                if level >= 2 and what == "Sl" then
                    return {
                        source = "C:\\Users\\test\\project\\module.lua",
                        short_src = "C:\\Users\\test\\project\\module.lua",
                        currentline = 10
                    }
                end
                return original_getinfo(level, what)
            end

            local filename, lineno, lua_path = caller_info.get_caller_info(nil, true)

            -- Restore original function
            debug.getinfo = original_getinfo

            assert.are.equal("C:.Users.test.project.module", filename)
            assert.are.equal(10, lineno)
            assert.are.equal("C:.Users.test.project.module", lua_path)
        end)


        it("should handle files without .lua extension with dot notation", function()
            -- Mock debug.getinfo to return a non-lua file
            local original_getinfo = debug.getinfo
            debug.getinfo = function(level, what)
                if level >= 2 and what == "Sl" then
                    return {
                        source = "scripts/deploy.sh",
                        short_src = "scripts/deploy.sh",
                        currentline = 20
                    }
                end
                return original_getinfo(level, what)
            end

            local filename, lineno, lua_path = caller_info.get_caller_info(nil, true)

            -- Restore original function
            debug.getinfo = original_getinfo

            assert.are.equal("scripts.deploy.sh", filename)
            assert.are.equal(20, lineno)
            assert.are.equal("scripts.deploy.sh", lua_path) -- Non-lua files keep their extension
        end)

        it("should return nil filename when dot notation results in empty string", function()
            -- Mock debug.getinfo to return a problematic filename
            local original_getinfo = debug.getinfo
            debug.getinfo = function(level, what)
                if level >= 2 and what == "Sl" then
                    return {
                        source = ".lua", -- Would become empty after processing
                        short_src = ".lua",
                        currentline = 25
                    }
                end
                return original_getinfo(level, what)
            end

            local filename, lineno, lua_path = caller_info.get_caller_info(nil, true)

            -- Restore original function
            debug.getinfo = original_getinfo

            assert.is_nil(filename)
            assert.are.equal(25, lineno)
            assert.is_nil(lua_path)
        end)

        it("should not convert when use_dot_notation is false", function()
            -- Mock debug.getinfo to return a path with separators
            local original_getinfo = debug.getinfo
            debug.getinfo = function(level, what)
                if level >= 2 and what == "Sl" then
                    return {
                        source = "@path/to/my/module.lua",
                        short_src = "@path/to/my/module.lua",
                        currentline = 30
                    }
                end
                return original_getinfo(level, what)
            end

            local filename, lineno, lua_path = caller_info.get_caller_info(nil, false)

            -- Restore original function
            debug.getinfo = original_getinfo

            assert.are.equal("path/to/my/module.lua", filename)
            assert.are.equal(30, lineno)
            assert.are.equal("path.to.my.module", lua_path) -- Should extract lua_path
        end)

        it("should default to false for use_dot_notation when not specified", function()
            -- Mock debug.getinfo to return a path with separators
            local original_getinfo = debug.getinfo
            debug.getinfo = function(level, what)
                if level >= 2 and what == "Sl" then
                    return {
                        source = "@path/to/my/module.lua",
                        short_src = "@path/to/my/module.lua",
                        currentline = 35
                    }
                end
                return original_getinfo(level, what)
            end

            local filename, lineno, lua_path = caller_info.get_caller_info()

            -- Restore original function
            debug.getinfo = original_getinfo

            assert.are.equal("path/to/my/module.lua", filename)
            assert.are.equal(35, lineno)
            assert.are.equal("path.to.my.module", lua_path) -- Should extract lua_path
        end)
    end)
end)
