#!/usr/bin/env lua
package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua;../lua/?.lua;../lua/?/init.lua"

local lual = require("lual.logger")
local spy = require("luassert.spy")
local assert = require("luassert")

describe("Logger Propagation", function()
    local mock_dispatcher_calls
    local mock_presenter_calls

    before_each(function()
        -- Reset the logger system for each test
        package.loaded["lual.logger"] = nil
        package.loaded["lual.core.logging"] = nil
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
            return string.format("[%s] %s: %s", record.level_name, record.logger_name, record.message_fmt)
        end
    end

    describe("Basic Propagation", function()
        it("should propagate messages from child to parent loggers", function()
            -- Configure a root logger to enable full hierarchy propagation
            local root_logger = lual.config({
                level = "info",
                dispatchers = {}
            })
            root_logger:add_dispatcher(create_mock_dispatcher("root_dispatcher"), create_mock_presenter("root_presenter"))

            local app_logger = lual.logger("app")
            local db_logger = lual.logger("app.database")

            -- Add dispatchers to different levels
            app_logger:add_dispatcher(create_mock_dispatcher("app_dispatcher"), create_mock_presenter("app_presenter"))

            -- Log from the deepest logger
            db_logger:info("Database connection established")

            -- Should have called dispatchers from both app and root loggers
            assert.are.equal(2, #mock_dispatcher_calls)

            -- Check that app logger dispatcher was called
            local app_call = nil
            local root_call = nil
            for _, call in ipairs(mock_dispatcher_calls) do
                if call.dispatcher_name == "app_dispatcher" then
                    app_call = call
                elseif call.dispatcher_name == "root_dispatcher" then
                    root_call = call
                end
            end

            assert.is_not_nil(app_call)
            assert.are.equal("app", app_call.logger_name)                 -- Owner of the dispatcher
            assert.are.equal("app.database", app_call.source_logger_name) -- Originator of the message
            assert.are.equal("INFO", app_call.level_name)

            assert.is_not_nil(root_call)
            assert.are.equal("root", root_call.logger_name)                -- Owner of the dispatcher
            assert.are.equal("app.database", root_call.source_logger_name) -- Originator of the message
            assert.are.equal("INFO", root_call.level_name)

            -- Check presenters were called
            assert.are.equal(2, #mock_presenter_calls)
        end)

        it("should include logger's own dispatchers when propagating", function()
            local app_logger = lual.logger("app")
            local db_logger = lual.logger("app.database")

            app_logger:add_dispatcher(create_mock_dispatcher("app_dispatcher"), create_mock_presenter("app_presenter"))
            db_logger:add_dispatcher(create_mock_dispatcher("db_dispatcher"), create_mock_presenter("db_presenter"))

            db_logger:warn("Connection timeout")

            -- Should call both db_logger's own dispatcher and app_logger's dispatcher
            assert.are.equal(2, #mock_dispatcher_calls)

            local db_call = nil
            local app_call = nil
            for _, call in ipairs(mock_dispatcher_calls) do
                if call.dispatcher_name == "db_dispatcher" then
                    db_call = call
                elseif call.dispatcher_name == "app_dispatcher" then
                    app_call = call
                end
            end

            assert.is_not_nil(db_call)
            assert.is_not_nil(app_call)
            assert.are.equal("app.database", db_call.logger_name)         -- db_logger owns its dispatcher
            assert.are.equal("app.database", db_call.source_logger_name)  -- db_logger originated the message
            assert.are.equal("app", app_call.logger_name)                 -- app_logger owns its dispatcher
            assert.are.equal("app.database", app_call.source_logger_name) -- db_logger originated the message
        end)
    end)

    describe("Propagation Control", function()
        it("should stop propagation when propagate is false", function()
            -- Configure root logger for full hierarchy
            local root_logger = lual.config({
                level = "info",
                dispatchers = {}
            })
            root_logger:add_dispatcher(create_mock_dispatcher("root_dispatcher"), create_mock_presenter("root_presenter"))

            local app_logger = lual.logger("app")
            local security_logger = lual.logger("app.security")

            app_logger:add_dispatcher(create_mock_dispatcher("app_dispatcher"), create_mock_presenter("app_presenter"))
            security_logger:add_dispatcher(create_mock_dispatcher("security_dispatcher"),
                create_mock_presenter("security_presenter"))

            -- Disable propagation on security logger
            security_logger:set_propagate(false)

            security_logger:error("Security violation detected")

            -- Should only call security logger's dispatcher, not parent dispatchers
            assert.are.equal(1, #mock_dispatcher_calls)
            assert.are.equal("security_dispatcher", mock_dispatcher_calls[1].dispatcher_name)
            assert.are.equal("app.security", mock_dispatcher_calls[1].logger_name)
            assert.are.equal("app.security", mock_dispatcher_calls[1].source_logger_name)
        end)

        it("should stop propagation at the logger where propagate is false", function()
            -- Configure root logger for full hierarchy
            local root_logger = lual.config({
                level = "info",
                dispatchers = {}
            })
            root_logger:add_dispatcher(create_mock_dispatcher("root_dispatcher"), create_mock_presenter("root_presenter"))

            local app_logger = lual.logger("app")
            local db_logger = lual.logger("app.database")
            local conn_logger = lual.logger("app.database.connection")

            app_logger:add_dispatcher(create_mock_dispatcher("app_dispatcher"), create_mock_presenter("app_presenter"))
            db_logger:add_dispatcher(create_mock_dispatcher("db_dispatcher"), create_mock_presenter("db_presenter"))
            conn_logger:add_dispatcher(create_mock_dispatcher("conn_dispatcher"), create_mock_presenter("conn_presenter"))

            -- Disable propagation at database level
            db_logger:set_propagate(false)

            conn_logger:info("Connection pool status") -- Use INFO instead of DEBUG to ensure it passes level filters

            -- Should call conn and db dispatchers, but not app or root
            assert.are.equal(2, #mock_dispatcher_calls)

            local dispatcher_names = {}
            for _, call in ipairs(mock_dispatcher_calls) do
                table.insert(dispatcher_names, call.dispatcher_name)
                -- All should have the same source
                assert.are.equal("app.database.connection", call.source_logger_name)
            end

            assert.truthy(table.concat(dispatcher_names, ","):find("conn_dispatcher"))
            assert.truthy(table.concat(dispatcher_names, ","):find("db_dispatcher"))
            assert.is_nil(table.concat(dispatcher_names, ","):find("app_dispatcher"))
            assert.is_nil(table.concat(dispatcher_names, ","):find("root_dispatcher"))
        end)
    end)

    describe("Level Filtering in Propagation", function()
        it("should apply level filtering at each logger in the hierarchy", function()
            -- Configure root logger for full hierarchy
            local root_logger = lual.config({
                level = "warning", -- Only warnings and above
                dispatchers = {}
            })
            root_logger:add_dispatcher(create_mock_dispatcher("root_dispatcher"), create_mock_presenter("root_presenter"))

            local app_logger = lual.logger("app")
            local debug_logger = lual.logger("app.debug")

            -- Set different levels
            app_logger:set_level(lual.levels.INFO)    -- Info and above
            debug_logger:set_level(lual.levels.DEBUG) -- Everything

            app_logger:add_dispatcher(create_mock_dispatcher("app_dispatcher"), create_mock_presenter("app_presenter"))
            debug_logger:add_dispatcher(create_mock_dispatcher("debug_dispatcher"),
                create_mock_presenter("debug_presenter"))

            -- Log an INFO message from debug logger
            debug_logger:info("Debug session started")

            -- Should be processed by debug_logger and app_logger, but filtered by root_logger
            assert.are.equal(2, #mock_dispatcher_calls)

            local dispatcher_names = {}
            for _, call in ipairs(mock_dispatcher_calls) do
                table.insert(dispatcher_names, call.dispatcher_name)
                -- All should have the same source
                assert.are.equal("app.debug", call.source_logger_name)
            end

            assert.truthy(table.concat(dispatcher_names, ","):find("debug_dispatcher"))
            assert.truthy(table.concat(dispatcher_names, ","):find("app_dispatcher"))
            assert.is_nil(table.concat(dispatcher_names, ","):find("root_dispatcher"))
        end)

        it("should not propagate if the originating logger filters the message", function()
            local app_logger = lual.logger("app")
            local db_logger = lual.logger("app.database")

            app_logger:add_dispatcher(create_mock_dispatcher("app_dispatcher"), create_mock_presenter("app_presenter"))
            db_logger:add_dispatcher(create_mock_dispatcher("db_dispatcher"), create_mock_presenter("db_presenter"))

            -- Set db_logger to only accept ERROR and above
            db_logger:set_level(lual.levels.ERROR)

            -- Try to log an INFO message
            db_logger:info("This should be filtered out")

            -- No dispatchers should be called since the message is filtered at the source
            assert.are.equal(0, #mock_dispatcher_calls)
            assert.are.equal(0, #mock_presenter_calls)
        end)
    end)

    describe("Complex Hierarchy Propagation", function()
        it("should handle deep hierarchies correctly", function()
            -- Configure root logger to enable full hierarchy propagation
            local root_logger = lual.config({
                level = "info",
                dispatchers = {}
            })

            local loggers = {
                root_logger,
                lual.logger("webapp"),
                lual.logger("webapp.api"),
                lual.logger("webapp.api.v1"),
                lual.logger("webapp.api.v1.users"),
                lual.logger("webapp.api.v1.users.auth")
            }

            -- Add dispatchers to each logger
            for i, logger in ipairs(loggers) do
                logger:add_dispatcher(
                    create_mock_dispatcher("dispatcher_" .. i),
                    create_mock_presenter("presenter_" .. i)
                )
            end

            -- Log from the deepest logger
            loggers[6]:critical("Authentication failed")

            -- Should propagate through all 6 loggers
            assert.are.equal(6, #mock_dispatcher_calls)

            -- Check that each dispatcher has the correct owner and source
            local expected_owners = { "webapp.api.v1.users.auth", "webapp.api.v1.users", "webapp.api.v1", "webapp.api",
                "webapp", "root" }
            for i, call in ipairs(mock_dispatcher_calls) do
                assert.are.equal("webapp.api.v1.users.auth", call.source_logger_name) -- Same source for all
                assert.are.equal("CRITICAL", call.level_name)
                -- The owner should be one of the expected owners
                assert.truthy(table.concat(expected_owners, ","):find(call.logger_name))
            end
        end)

        it("should handle multiple dispatchers per logger", function()
            local app_logger = lual.logger("app")
            local db_logger = lual.logger("app.database")

            -- Add multiple dispatchers to app logger
            app_logger:add_dispatcher(create_mock_dispatcher("app_console"), create_mock_presenter("app_console_fmt"))
            app_logger:add_dispatcher(create_mock_dispatcher("app_file"), create_mock_presenter("app_file_fmt"))

            -- Add one dispatcher to db logger
            db_logger:add_dispatcher(create_mock_dispatcher("db_debug"), create_mock_presenter("db_debug_fmt"))

            db_logger:error("Database error occurred")

            -- Should call all 3 dispatchers (1 from db, 2 from app)
            assert.are.equal(3, #mock_dispatcher_calls)

            local dispatcher_names = {}
            for _, call in ipairs(mock_dispatcher_calls) do
                table.insert(dispatcher_names, call.dispatcher_name)
                -- All should have the same source
                assert.are.equal("app.database", call.source_logger_name)
            end

            assert.truthy(table.concat(dispatcher_names, ","):find("db_debug"))
            assert.truthy(table.concat(dispatcher_names, ","):find("app_console"))
            assert.truthy(table.concat(dispatcher_names, ","):find("app_file"))
        end)
    end)

    describe("Edge Cases", function()
        it("should handle logger with no dispatchers but propagating parents", function()
            -- Configure root logger to enable propagation to it
            local root_logger = lual.config({
                level = "info",
                dispatchers = {}
            })
            root_logger:add_dispatcher(create_mock_dispatcher("root_dispatcher"), create_mock_presenter("root_presenter"))

            local app_logger = lual.logger("app")
            local db_logger = lual.logger("app.database")

            -- app_logger and db_logger have no dispatchers

            db_logger:info("Database query completed")

            -- Should still propagate to root
            assert.are.equal(1, #mock_dispatcher_calls)
            assert.are.equal("root_dispatcher", mock_dispatcher_calls[1].dispatcher_name)
            assert.are.equal("root", mock_dispatcher_calls[1].logger_name)                -- Root owns the dispatcher
            assert.are.equal("app.database", mock_dispatcher_calls[1].source_logger_name) -- db_logger originated the message
        end)

        it("should handle root logger with propagate=false", function()
            -- Configure root logger
            local root_logger = lual.config({
                level = "info",
                dispatchers = {}
            })
            root_logger:add_dispatcher(create_mock_dispatcher("root_dispatcher"), create_mock_presenter("root_presenter"))

            local app_logger = lual.logger("app")
            app_logger:add_dispatcher(create_mock_dispatcher("app_dispatcher"), create_mock_presenter("app_presenter"))

            -- Disable propagation on root (shouldn't matter since it has no parent)
            root_logger:set_propagate(false)

            app_logger:warn("Application warning")

            -- Should still call both dispatchers since root is the top of the hierarchy
            assert.are.equal(2, #mock_dispatcher_calls)

            for _, call in ipairs(mock_dispatcher_calls) do
                assert.are.equal("app", call.source_logger_name) -- app_logger originated the message
            end
        end)

        it("should handle logger with same name as parent", function()
            -- This tests the edge case where someone might try to create conflicting names
            local app_logger = lual.logger("app")
            local app_sub_logger = lual.logger("app.app") -- Confusing but valid

            app_logger:add_dispatcher(create_mock_dispatcher("app_dispatcher"), create_mock_presenter("app_presenter"))
            app_sub_logger:add_dispatcher(create_mock_dispatcher("app_sub_dispatcher"),
                create_mock_presenter("app_sub_presenter"))

            app_sub_logger:info("Confusing hierarchy test")

            assert.are.equal(2, #mock_dispatcher_calls)

            -- Check that each dispatcher has the correct owner and source
            for _, call in ipairs(mock_dispatcher_calls) do
                assert.are.equal("app.app", call.source_logger_name) -- app_sub_logger originated the message
                -- The owner should be either "app.app" or "app"
                assert.truthy(call.logger_name == "app.app" or call.logger_name == "app")
            end
        end)
    end)
end)
