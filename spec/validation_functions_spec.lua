package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua;../lua/?.lua;../lua/?/init.lua"
local config = require("lual.config")
local lualog = require("lual.logger")

describe("Validation Functions", function()
    before_each(function()
        -- Reset the module cache
        package.loaded["lual.config"] = nil
        config = require("lual.config")
    end)

    describe("Unified API validation", function()
        it("should detect convenience syntax", function()
            assert.is_true(config.is_convenience_config_syntax({ dispatcher = "console", presenter = "text" }))
            assert.is_false(config.is_convenience_config_syntax({ dispatchers = { { type = "console", presenter = "text" } } }))
        end)

        it("should transform convenience syntax to full format", function()
            local shortcut = {
                name = "test",
                dispatcher = "console",
                presenter = "text",
                level = "debug"
            }

            local result = config.transform_convenience_config_to_full(shortcut)

            assert.are.same("test", result.name)
            assert.are.same("debug", result.level)
            assert.are.same(1, #result.dispatchers)
            assert.are.same("console", result.dispatchers[1].type)
            assert.are.same("text", result.dispatchers[1].presenter)
        end)

        it("should transform convenience syntax to full format with timezone", function()
            local shortcut = {
                dispatcher = "console",
                presenter = "color",
                timezone = "utc"
            }

            local result = config.transform_convenience_config_to_full(shortcut)

            assert.are.same(1, #result.dispatchers)
            assert.are.same("console", result.dispatchers[1].type)
            assert.are.same("color", result.dispatchers[1].presenter)
            assert.are.same("utc", result.dispatchers[1].timezone)
        end)
    end)
end)
