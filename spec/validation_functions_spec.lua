package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua;../lua/?.lua;../lua/?/init.lua"
local config = require("lual.config")
local lualog = require("lual.logger")
local schema = require("lual.config.schema")
local normalization = require("lual.config.normalization")

describe("Validation Functions", function()
    before_each(function()
        -- Reset the module cache
        package.loaded["lual.config"] = nil
        config = require("lual.config")
    end)

    describe("Unified API validation", function()
        it("should detect convenience syntax", function()
            assert.is_true(schema.is_convenience_syntax({ dispatcher = "console", presenter = "text" }))
            assert.is_false(schema.is_convenience_syntax({ dispatchers = { { type = "console", presenter = "text" } } }))
        end)

        it("should transform convenience syntax to full format", function()
            local shortcut = {
                name = "test",
                dispatcher = "console",
                presenter = "text",
                level = "debug"
            }

            local result = normalization.convenience_to_full_config(shortcut)

            assert.are.same("test", result.name)
            assert.are.same("debug", result.level)
            assert.are.same(1, #result.dispatchers)
            assert.are.same("console", result.dispatchers[1].type)
            assert.are.same("text", result.dispatchers[1].presenter)
        end)
    end)
end)
