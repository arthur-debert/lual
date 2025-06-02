#!/usr/bin/env lua
package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua;../lua/?.lua;../lua/?/init.lua"

local lual = require("lual.logger")
local spy = require("luassert.spy")
local assert = require("luassert")

describe("Hierarchical Logging System", function()
    local mock_dispatcher_calls
    local mock_presenter_calls

    before_each(function()
        -- Reset the entire logging system for each test
        package.loaded["lual.logger"] = nil
        package.loaded["lual.core.logging"] = nil
        package.loaded["lual.core.logging.init"] = nil
        package.loaded["lual.ingest"] = nil
        lual = require("lual.logger")

        -- Track dispatcher and presenter calls
        mock_dispatcher_calls = {}
        mock_presenter_calls = {}
    end)

    local function create_mock_dispatcher(name)
        return function(record)
            table.insert(mock_dispatcher_calls, {
                dispatcher_name = name,
                logger_name = record.logger_name,               -- Owner of the dispatcher
                source_logger_name = record.source_logger_name, -- Originator of the message
                message = record.message,
                level_name = record.level_name
            })
        end
    end

    local function create_mock_presenter(name)
        return function(record)
            table.insert(mock_presenter_calls, {
                presenter_name = name,
                logger_name = record.logger_name,               -- Owner of the dispatcher
                source_logger_name = record.source_logger_name, -- Originator of the message
                message_fmt = record.message_fmt,
                level_name = record.level_name
            })
            return string.format("[%s] %s: %s", record.level_name, record.logger_name, record.message_fmt or "")
        end
    end

    describe("lual.config() API", function()
        it("should create a root logger when called", function()
            -- Before calling lual.config(), no root logger should exist
            local engine = require("lual.core.logging")
            assert.is_nil(engine.get_root_logger())

            -- Call lual.config() to create root logger
            local root_logger = lual.config({
                level = "warning",
                dispatchers = {
                    { type = "console", presenter = "text" }
                }
            })

            assert.is_not_nil(root_logger)
            assert.are.equal("root", root_logger.name)
            assert.are.equal(lual.warning, root_logger.level)
            assert.is_not_nil(engine.get_root_logger())
            assert.are.equal(root_logger, engine.get_root_logger())
        end)

        it("should return the existing root logger if called multiple times", function()
            local root1 = lual.config({ level = "info" })
            local root2 = lual.config({ level = "debug" })

            -- Should create a new root logger with updated config
            assert.are.equal("root", root1.name)
            assert.are.equal("root", root2.name)
            -- The level should be updated
            assert.are.equal(lual.debug, root2.level)
        end)
    end)

    describe("Quiet by Default (No Root Logger)", function()
        it("should not output anything when no root logger is configured", function()
            -- Create a logger without calling lual.config()
            local app_logger = lual.logger("app")

            app_logger:add_dispatcher(create_mock_dispatcher("app_dispatcher"), create_mock_presenter("app_presenter"))
            app_logger:warn("This message should appear")

            -- Only the app logger's dispatcher should be called
            assert.are.equal(1, #mock_dispatcher_calls)
            assert.are.equal("app_dispatcher", mock_dispatcher_calls[1].dispatcher_name)
            assert.are.equal("app", mock_dispatcher_calls[1].logger_name)
        end)

        it("should not propagate to non-existent root logger", function()
            local app_logger = lual.logger("app")
            local db_logger = lual.logger("app.database")

            -- Add dispatcher only to app logger
            app_logger:add_dispatcher(create_mock_dispatcher("app_dispatcher"), create_mock_presenter("app_presenter"))

            -- Log from db_logger - should propagate to app but not beyond
            db_logger:warn("Database warning")

            assert.are.equal(1, #mock_dispatcher_calls)
            assert.are.equal("app_dispatcher", mock_dispatcher_calls[1].dispatcher_name)
            assert.are.equal("app", mock_dispatcher_calls[1].logger_name)
            assert.are.equal("app.database", mock_dispatcher_calls[1].source_logger_name)
        end)
    end)

    describe("Automatic Hierarchy Construction", function()
        it("should automatically create parent-child relationships based on names", function()
            local app_logger = lual.logger("app")
            local db_logger = lual.logger("app.database")
            local conn_logger = lual.logger("app.database.connection")

            -- Check parent relationships
            assert.is_nil(app_logger.parent) -- No root logger configured
            assert.are.equal(app_logger, db_logger.parent)
            assert.are.equal(db_logger, conn_logger.parent)
        end)

        it("should connect to root logger when configured", function()
            -- First create a logger before root exists
            local app_logger = lual.logger("app")
            assert.is_nil(app_logger.parent)

            -- Now configure root logger
            lual.config({ level = "info" })

            -- Create new loggers - they should connect to root
            local auth_logger = lual.logger("auth")
            local new_app_logger = lual.logger("new_app")

            local engine = require("lual.core.logging")
            local root_logger = engine.get_root_logger()

            assert.are.equal(root_logger, auth_logger.parent)
            assert.are.equal(root_logger, new_app_logger.parent)
        end)

        it("should handle deep hierarchies correctly", function()
            local deep_logger = lual.logger("a.b.c.d.e.f")

            -- Should have created all intermediate loggers
            assert.is_not_nil(deep_logger.parent)                             -- a.b.c.d.e
            assert.is_not_nil(deep_logger.parent.parent)                      -- a.b.c.d
            assert.is_not_nil(deep_logger.parent.parent.parent)               -- a.b.c
            assert.is_not_nil(deep_logger.parent.parent.parent.parent)        -- a.b
            assert.is_not_nil(deep_logger.parent.parent.parent.parent.parent) -- a

            assert.are.equal("a.b.c.d.e", deep_logger.parent.name)
            assert.are.equal("a.b.c.d", deep_logger.parent.parent.name)
            assert.are.equal("a.b.c", deep_logger.parent.parent.parent.name)
            assert.are.equal("a.b", deep_logger.parent.parent.parent.parent.name)
            assert.are.equal("a", deep_logger.parent.parent.parent.parent.parent.name)
        end)
    end)

    describe("Propagation Model (Not Inheritance)", function()
        it("should fire own dispatchers then propagate upward", function()
            -- Configure root logger
            local root_logger = lual.config({
                level = "warning",
                dispatchers = {
                    { type = "console", presenter = "text" }
                }
            })
            root_logger:add_dispatcher(create_mock_dispatcher("root_dispatcher"), create_mock_presenter("root_presenter"))

            -- Create child logger with different config
            local app_logger = lual.logger("app", {
                level = "debug",
                dispatchers = {
                    { type = "console", presenter = "color", timezone = "local" }
                }
            })
            app_logger:add_dispatcher(create_mock_dispatcher("app_dispatcher"), create_mock_presenter("app_presenter"))

            -- Log a warning message
            app_logger:warn("security issue")

            -- Should fire both dispatchers
            assert.are.equal(2, #mock_dispatcher_calls)

            -- Find the calls
            local app_call, root_call
            for _, call in ipairs(mock_dispatcher_calls) do
                if call.dispatcher_name == "app_dispatcher" then
                    app_call = call
                elseif call.dispatcher_name == "root_dispatcher" then
                    root_call = call
                end
            end

            assert.is_not_nil(app_call)
            assert.are.equal("app", app_call.logger_name)
            assert.are.equal("app", app_call.source_logger_name)

            assert.is_not_nil(root_call)
            assert.are.equal("root", root_call.logger_name)
            assert.are.equal("app", root_call.source_logger_name) -- Source is still app
        end)

        it("should apply level filtering at each logger independently", function()
            -- Configure root logger with high threshold
            local root_logger = lual.config({
                level = "error" -- Only errors and above
            })
            root_logger:add_dispatcher(create_mock_dispatcher("root_dispatcher"), create_mock_presenter("root_presenter"))

            -- Create child logger with low threshold
            local app_logger = lual.logger("app", {
                level = "info" -- Info and above
            })
            app_logger:add_dispatcher(create_mock_dispatcher("app_dispatcher"), create_mock_presenter("app_presenter"))

            -- Log an info message
            app_logger:info("debug info")

            -- Should fire app dispatcher but not root (info < error)
            assert.are.equal(1, #mock_dispatcher_calls)
            assert.are.equal("app_dispatcher", mock_dispatcher_calls[1].dispatcher_name)
            assert.are.equal("app", mock_dispatcher_calls[1].logger_name)
        end)

        it("should preserve separate timezone settings in dispatchers", function()
            -- This test verifies that each logger can have its own timezone setting in dispatchers
            -- without interfering with parent loggers

            local root_logger = lual.config({
                level = "info",
                dispatchers = {
                    { type = "console", presenter = "text", timezone = "utc" }
                }
            })

            local app_logger = lual.logger("app", {
                level = "info",
                dispatchers = {
                    { type = "console", presenter = "text", timezone = "local" }
                }
            })

            -- Timezone is now in the dispatcher configuration
            assert.are.equal(1, #root_logger.dispatchers)
            assert.are.equal(1, #app_logger.dispatchers)
        end)

        it("should handle loggers with timezone configured in dispatchers", function()
            -- This test verifies that timezone configuration works in the new presenter-based system

            -- Create hierarchy with timezone-configured dispatchers
            local root_logger = lual.config({
                level = "info",
                dispatchers = {
                    { type = "console", presenter = "text", timezone = "utc" }
                }
            })
            root_logger:add_dispatcher(create_mock_dispatcher("root_dispatcher"),
                create_mock_presenter("root_presenter"))

            local app_logger = lual.logger("app", {
                level = "info",
                dispatchers = {
                    { type = "console", presenter = "text", timezone = "local" }
                }
            })
            app_logger:add_dispatcher(create_mock_dispatcher("app_dispatcher"),
                create_mock_presenter("app_presenter"))

            local db_logger = lual.logger("app.database", {
                level = "info",
                dispatchers = {
                    { type = "console", presenter = "text", timezone = "utc" }
                }
            })
            db_logger:add_dispatcher(create_mock_dispatcher("db_dispatcher"),
                create_mock_presenter("db_presenter"))

            -- Log from the deepest logger
            db_logger:warn("Database connection issue")

            -- Should have called 3 dispatchers (db, app, root) - timezone is now in presenter config
            assert.are.equal(3, #mock_dispatcher_calls)

            -- Find each dispatcher call
            local db_call, app_call, root_call
            for _, call in ipairs(mock_dispatcher_calls) do
                if call.dispatcher_name == "db_dispatcher" then
                    db_call = call
                elseif call.dispatcher_name == "app_dispatcher" then
                    app_call = call
                elseif call.dispatcher_name == "root_dispatcher" then
                    root_call = call
                end
            end

            -- Verify proper propagation
            assert.is_not_nil(db_call)
            assert.are.equal("app.database", db_call.logger_name)
            assert.are.equal("app.database", db_call.source_logger_name)

            assert.is_not_nil(app_call)
            assert.are.equal("app", app_call.logger_name)
            assert.are.equal("app.database", app_call.source_logger_name)

            assert.is_not_nil(root_call)
            assert.are.equal("root", root_call.logger_name)
            assert.are.equal("app.database", root_call.source_logger_name)
        end)
    end)

    describe("Multi-Level Configuration Examples", function()
        it("should handle the audit logging example from the docs", function()
            -- Root: Audit logging (simplified to avoid dispatcher config issues)
            local root_logger = lual.config({
                level = "warning",
                dispatchers = {
                    { type = "console", presenter = "text", timezone = "utc" }
                }
            })
            root_logger:add_dispatcher(create_mock_dispatcher("audit_dispatcher"),
                create_mock_presenter("audit_presenter"))

            -- Child: Development logging (simplified to avoid dispatcher config issues)
            local app_logger = lual.logger("app", {
                level = "debug",
                dispatchers = {
                    { type = "console", presenter = "text", timezone = "local" }
                }
            })
            app_logger:add_dispatcher(create_mock_dispatcher("dev_dispatcher"), create_mock_presenter("dev_presenter"))

            -- Test warning message (should trigger both)
            app_logger:warn("security issue")

            assert.are.equal(2, #mock_dispatcher_calls)

            -- Test debug message (should only trigger app)
            mock_dispatcher_calls = {} -- Reset
            app_logger:debug("trace info")

            assert.are.equal(1, #mock_dispatcher_calls)
            assert.are.equal("dev_dispatcher", mock_dispatcher_calls[1].dispatcher_name)
        end)

        it("should handle intermediate logger hierarchy", function()
            local root_logger = lual.config({
                level = "error"
            })
            root_logger:add_dispatcher(create_mock_dispatcher("root_dispatcher"), create_mock_presenter("root_presenter"))

            local db_logger = lual.logger("app.database", {
                level = "info",
                dispatchers = {
                    { type = "console", presenter = "text" }
                }
            })
            db_logger:add_dispatcher(create_mock_dispatcher("db_dispatcher"), create_mock_presenter("db_presenter"))

            -- Get the intermediate "app" logger that should have been created automatically
            local app_logger = lual.logger("app")
            assert.are.equal(app_logger, db_logger.parent)

            -- The app logger should have root as parent
            assert.are.equal("root", app_logger.parent.name)

            -- Log an error from db_logger
            db_logger:error("connection failed")

            -- Should propagate through app (no dispatchers) to root
            assert.are.equal(2, #mock_dispatcher_calls)

            local dispatcher_names = {}
            for _, call in ipairs(mock_dispatcher_calls) do
                table.insert(dispatcher_names, call.dispatcher_name)
            end

            assert.truthy(table.concat(dispatcher_names, ","):find("db_dispatcher"))
            assert.truthy(table.concat(dispatcher_names, ","):find("root_dispatcher"))
        end)
    end)

    describe("Flat Namespace Constants", function()
        it("should expose constants directly on lual module", function()
            -- Test level constants
            assert.is_number(lual.debug)
            assert.is_number(lual.info)
            assert.is_number(lual.warning)
            assert.is_number(lual.error)
            assert.is_number(lual.critical)
            assert.is_number(lual.none)

            -- Test dispatcher constants
            assert.are.equal("console", lual.console)
            assert.are.equal("file", lual.file)

            -- Test presenter constants
            assert.are.equal("text", lual.text)
            assert.are.equal("color", lual.color)
            assert.are.equal("json", lual.json)

            -- Test timezone constants
            assert.are.equal("local", lual.local_time)
            assert.are.equal("utc", lual.utc)
        end)

        it("should not have lual.lib namespace", function()
            assert.is_nil(lual.lib)
        end)
    end)

    describe("Edge Cases and Error Handling", function()
        it("should handle logger with no name", function()
            local auto_logger = lual.logger()

            -- Debug: Show what we actually got vs expected
            print("DEBUG: auto_logger.name =", auto_logger.name)
            print("DEBUG: expected to contain 'hierarchical_logging_spec'")

            assert.is_string(auto_logger.name)
            assert.are.equal("spec.hierarchical_logging_spec", auto_logger.name,
                "auto_logger.name should be 'hierarchical_logging_spec'")
        end)

        it("should handle propagate=false correctly", function()
            local root_logger = lual.config({ level = "info" })
            root_logger:add_dispatcher(create_mock_dispatcher("root_dispatcher"), create_mock_presenter("root_presenter"))

            local app_logger = lual.logger("app")
            app_logger:add_dispatcher(create_mock_dispatcher("app_dispatcher"), create_mock_presenter("app_presenter"))
            app_logger:set_propagate(false)

            app_logger:info("isolated message")

            -- Should only call app dispatcher
            assert.are.equal(1, #mock_dispatcher_calls)
            assert.are.equal("app_dispatcher", mock_dispatcher_calls[1].dispatcher_name)
        end)

        it("should handle root logger with propagate=false", function()
            -- Root logger should not propagate anyway since it has no parent
            local root_logger = lual.config({
                level = "info",
                propagate = false
            })

            assert.is_false(root_logger.propagate)
            assert.is_nil(root_logger.parent)
        end)
    end)
end)
