#!/usr/bin/env lua
package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua;../lua/?.lua;../lua/?/init.lua"

local lual = require("lual.logger")
local assert = require("luassert")

describe("get_config functionality", function()
    before_each(function()
        -- Reset the logger system for each test
        package.loaded["lual.logger"] = nil
        package.loaded["lual.core.logging"] = nil
        lual = require("lual.logger")

        -- Reset the logger cache
        local engine = require("lual.core.logging")
        engine.reset_cache()
    end)

    describe("lual.get_config()", function()
        it("should return nil when no root logger is configured", function()
            local config = lual.get_config()
            assert.is_nil(config)
        end)

        it("should return root logger config when root logger is configured", function()
            -- Configure root logger
            lual.config({
                level = "warning",
                dispatchers = {
                    { type = "console", presenter = "text", timezone = "utc" }
                }
            })

            local config = lual.get_config()
            assert.is_not_nil(config)
            assert.are.equal("root", config.name)
            assert.are.equal(lual.warning, config.level)
            assert.is_false(config.propagate) -- Root logger doesn't propagate
            assert.are.equal(1, #config.dispatchers)
        end)
    end)

    describe("logger:get_config()", function()
        it("should return individual logger config", function()
            -- Configure root logger first
            lual.config({ level = "info" })

            local logger = lual.logger("app.database", {
                level = "debug",
                dispatchers = {
                    { type = "console", presenter = "color", timezone = "local" }
                },
                propagate = true
            })

            local config = logger:get_config()
            assert.is_not_nil(config)
            assert.are.equal("app.database", config.name)
            assert.are.equal(lual.debug, config.level)
            assert.is_true(config.propagate)
            assert.are.equal(1, #config.dispatchers)
        end)

        it("should return config for simple logger", function()
            local logger = lual.logger("simple.logger")

            local config = logger:get_config()
            assert.is_not_nil(config)
            assert.are.equal("simple.logger", config.name)
            assert.are.equal(lual.info, config.level) -- Default level
            assert.is_true(config.propagate)          -- Default propagate
            assert.are.equal(0, #config.dispatchers)  -- No dispatchers by default
        end)
    end)

    describe("logger:get_config(true) - full hierarchy", function()
        it("should return hierarchy configs for deep logger", function()
            -- Configure root logger
            lual.config({
                level = "error",
                dispatchers = {
                    { type = "console", presenter = "text" }
                }
            })

            -- Create a hierarchy: root -> app -> app.database -> app.database.connection
            local app_logger = lual.logger("app", {
                level = "warning",
                dispatchers = {
                    { type = "console", presenter = "color" }
                }
            })

            local db_logger = lual.logger("app.database") -- Default config

            local conn_logger = lual.logger("app.database.connection", {
                level = "debug",
                dispatchers = {
                    { type = "console", presenter = "text",      timezone = "utc" },
                    { type = "file",    path = "connection.log", presenter = "json", timezone = "utc" }
                }
            })

            local hierarchy = conn_logger:get_config(true)

            -- Should have 4 loggers in hierarchy
            assert.is_table(hierarchy)
            assert.is_not_nil(hierarchy["root"])
            assert.is_not_nil(hierarchy["app"])
            assert.is_not_nil(hierarchy["app.database"])
            assert.is_not_nil(hierarchy["app.database.connection"])

            -- Check root logger config
            local root_config = hierarchy["root"]
            assert.are.equal("root", root_config.name)
            assert.are.equal(lual.error, root_config.level)
            assert.is_nil(root_config.parent_name)
            assert.is_false(root_config.propagate)

            -- Check app logger config
            local app_config = hierarchy["app"]
            assert.are.equal("app", app_config.name)
            assert.are.equal(lual.warning, app_config.level)
            assert.are.equal("root", app_config.parent_name)
            assert.is_true(app_config.propagate)

            -- Check database logger config (default settings)
            local db_config = hierarchy["app.database"]
            assert.are.equal("app.database", db_config.name)
            assert.are.equal(lual.info, db_config.level) -- Default
            assert.are.equal("app", db_config.parent_name)
            assert.is_true(db_config.propagate)

            -- Check connection logger config
            local conn_config = hierarchy["app.database.connection"]
            assert.are.equal("app.database.connection", conn_config.name)
            assert.are.equal(lual.debug, conn_config.level)
            assert.are.equal("app.database", conn_config.parent_name)
            assert.are.equal(2, #conn_config.dispatchers)
        end)

        it("should return hierarchy configs for top-level logger", function()
            -- Configure root logger
            lual.config({ level = "info" })

            local app_logger = lual.logger("app", {
                level = "debug",
                dispatchers = {
                    { type = "console", presenter = "text" }
                }
            })

            local hierarchy = app_logger:get_config(true)

            -- Should have 2 loggers in hierarchy
            assert.is_table(hierarchy)
            assert.is_not_nil(hierarchy["root"])
            assert.is_not_nil(hierarchy["app"])

            -- Check counts
            local count = 0
            for _ in pairs(hierarchy) do count = count + 1 end
            assert.are.equal(2, count)

            -- Check app logger
            local app_config = hierarchy["app"]
            assert.are.equal("app", app_config.name)
            assert.are.equal(lual.debug, app_config.level)
            assert.are.equal("root", app_config.parent_name)

            -- Check root logger
            local root_config = hierarchy["root"]
            assert.are.equal("root", root_config.name)
            assert.is_nil(root_config.parent_name)
        end)

        it("should handle logger without root logger configured", function()
            local logger = lual.logger("standalone")

            local hierarchy = logger:get_config(true)

            -- Should only have the standalone logger (no root)
            assert.is_table(hierarchy)
            assert.is_not_nil(hierarchy["standalone"])
            assert.is_nil(hierarchy["root"])

            -- Check counts
            local count = 0
            for _ in pairs(hierarchy) do count = count + 1 end
            assert.are.equal(1, count)

            local config = hierarchy["standalone"]
            assert.are.equal("standalone", config.name)
            assert.is_nil(config.parent_name)
        end)
    end)

    describe("Edge cases", function()
        it("should handle root logger get_config with hierarchy", function()
            lual.config({
                level = "critical",
                dispatchers = {
                    { type = "console", presenter = "text", timezone = "utc" }
                }
            })

            local engine = require("lual.core.logging")
            local root_logger = engine.get_root_logger()

            local hierarchy = root_logger:get_config(true)

            -- Should only have the root logger
            assert.is_table(hierarchy)
            assert.is_not_nil(hierarchy["root"])

            local count = 0
            for _ in pairs(hierarchy) do count = count + 1 end
            assert.are.equal(1, count)

            local root_config = hierarchy["root"]
            assert.are.equal("root", root_config.name)
            assert.are.equal(lual.critical, root_config.level)
            assert.is_nil(root_config.parent_name)
        end)

        it("should handle logger with partial hierarchy", function()
            -- Create middle logger without configuring root
            local middle_logger = lual.logger("app.middle")
            local deep_logger = lual.logger("app.middle.deep")

            local hierarchy = deep_logger:get_config(true)

            -- Should have 3 loggers: app, app.middle, app.middle.deep
            assert.is_table(hierarchy)
            assert.is_not_nil(hierarchy["app"])
            assert.is_not_nil(hierarchy["app.middle"])
            assert.is_not_nil(hierarchy["app.middle.deep"])

            local count = 0
            for _ in pairs(hierarchy) do count = count + 1 end
            assert.are.equal(3, count)

            -- Check parent relationships
            assert.is_nil(hierarchy["app"].parent_name) -- No root configured
            assert.are.equal("app", hierarchy["app.middle"].parent_name)
            assert.are.equal("app.middle", hierarchy["app.middle.deep"].parent_name)
        end)
    end)
end)
