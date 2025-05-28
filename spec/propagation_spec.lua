#!/usr/bin/env lua
package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua;../lua/?.lua;../lua/?/init.lua"

local lual = require("lual.logger")
local spy = require("luassert.spy")
local assert = require("luassert")

describe("Logger Propagation", function()
    local mock_output_calls
    local mock_formatter_calls

    before_each(function()
        -- Reset the logger system for each test
        package.loaded["lual.logger"] = nil
        package.loaded["lual.core.engine"] = nil
        package.loaded["lual.ingest"] = nil
        lual = require("lual.logger")

        -- Track output and formatter calls
        mock_output_calls = {}
        mock_formatter_calls = {}

        -- Clear any default outputs that might be set up
        local root_logger = lual.logger("root")
        -- Clear outputs directly for test setup (this is acceptable for tests)
        root_logger.outputs = {}
    end)

    local function create_mock_output(name)
        return function(record)
            table.insert(mock_output_calls, {
                output_name = name,
                logger_name = record.logger_name,               -- Owner of the output
                source_logger_name = record.source_logger_name, -- Originator of the message
                message = record.message,
                level_name = record.level_name
            })
        end
    end

    local function create_mock_formatter(name)
        return function(record)
            table.insert(mock_formatter_calls, {
                formatter_name = name,
                logger_name = record.logger_name,               -- Owner of the output
                source_logger_name = record.source_logger_name, -- Originator of the message
                message_fmt = record.message_fmt,
                level_name = record.level_name
            })
            return string.format("[%s] %s: %s", record.level_name, record.logger_name, record.message_fmt)
        end
    end

    describe("Basic Propagation", function()
        it("should propagate messages from child to parent loggers", function()
            local root_logger = lual.logger("root")
            local app_logger = lual.logger("app")
            local db_logger = lual.logger("app.database")

            -- Add outputs to different levels
            root_logger:add_output(create_mock_output("root_output"), create_mock_formatter("root_formatter"))
            app_logger:add_output(create_mock_output("app_output"), create_mock_formatter("app_formatter"))

            -- Log from the deepest logger
            db_logger:info("Database connection established")

            -- Should have called outputs from both app and root loggers
            assert.are.equal(2, #mock_output_calls)

            -- Check that app logger output was called
            local app_call = nil
            local root_call = nil
            for _, call in ipairs(mock_output_calls) do
                if call.output_name == "app_output" then
                    app_call = call
                elseif call.output_name == "root_output" then
                    root_call = call
                end
            end

            assert.is_not_nil(app_call)
            assert.are.equal("app", app_call.logger_name)                 -- Owner of the output
            assert.are.equal("app.database", app_call.source_logger_name) -- Originator of the message
            assert.are.equal("INFO", app_call.level_name)

            assert.is_not_nil(root_call)
            assert.are.equal("root", root_call.logger_name)                -- Owner of the output
            assert.are.equal("app.database", root_call.source_logger_name) -- Originator of the message
            assert.are.equal("INFO", root_call.level_name)

            -- Check formatters were called
            assert.are.equal(2, #mock_formatter_calls)
        end)

        it("should include logger's own outputs when propagating", function()
            local app_logger = lual.logger("app")
            local db_logger = lual.logger("app.database")

            app_logger:add_output(create_mock_output("app_output"), create_mock_formatter("app_formatter"))
            db_logger:add_output(create_mock_output("db_output"), create_mock_formatter("db_formatter"))

            db_logger:warn("Connection timeout")

            -- Should call both db_logger's own output and app_logger's output
            assert.are.equal(2, #mock_output_calls)

            local db_call = nil
            local app_call = nil
            for _, call in ipairs(mock_output_calls) do
                if call.output_name == "db_output" then
                    db_call = call
                elseif call.output_name == "app_output" then
                    app_call = call
                end
            end

            assert.is_not_nil(db_call)
            assert.is_not_nil(app_call)
            assert.are.equal("app.database", db_call.logger_name)         -- db_logger owns its output
            assert.are.equal("app.database", db_call.source_logger_name)  -- db_logger originated the message
            assert.are.equal("app", app_call.logger_name)                 -- app_logger owns its output
            assert.are.equal("app.database", app_call.source_logger_name) -- db_logger originated the message
        end)
    end)

    describe("Propagation Control", function()
        it("should stop propagation when propagate is false", function()
            local root_logger = lual.logger("root")
            local app_logger = lual.logger("app")
            local security_logger = lual.logger("app.security")

            root_logger:add_output(create_mock_output("root_output"), create_mock_formatter("root_formatter"))
            app_logger:add_output(create_mock_output("app_output"), create_mock_formatter("app_formatter"))
            security_logger:add_output(create_mock_output("security_output"), create_mock_formatter("security_formatter"))

            -- Disable propagation on security logger
            security_logger:set_propagate(false)

            security_logger:error("Security violation detected")

            -- Should only call security logger's output, not parent outputs
            assert.are.equal(1, #mock_output_calls)
            assert.are.equal("security_output", mock_output_calls[1].output_name)
            assert.are.equal("app.security", mock_output_calls[1].logger_name)
            assert.are.equal("app.security", mock_output_calls[1].source_logger_name)
        end)

        it("should stop propagation at the logger where propagate is false", function()
            local root_logger = lual.logger("root")
            local app_logger = lual.logger("app")
            local db_logger = lual.logger("app.database")
            local conn_logger = lual.logger("app.database.connection")

            root_logger:add_output(create_mock_output("root_output"), create_mock_formatter("root_formatter"))
            app_logger:add_output(create_mock_output("app_output"), create_mock_formatter("app_formatter"))
            db_logger:add_output(create_mock_output("db_output"), create_mock_formatter("db_formatter"))
            conn_logger:add_output(create_mock_output("conn_output"), create_mock_formatter("conn_formatter"))

            -- Disable propagation at database level
            db_logger:set_propagate(false)

            conn_logger:info("Connection pool status") -- Use INFO instead of DEBUG to ensure it passes level filters

            -- Should call conn and db outputs, but not app or root
            assert.are.equal(2, #mock_output_calls)

            local output_names = {}
            for _, call in ipairs(mock_output_calls) do
                table.insert(output_names, call.output_name)
                -- All should have the same source
                assert.are.equal("app.database.connection", call.source_logger_name)
            end

            assert.truthy(table.concat(output_names, ","):find("conn_output"))
            assert.truthy(table.concat(output_names, ","):find("db_output"))
            assert.is_nil(table.concat(output_names, ","):find("app_output"))
            assert.is_nil(table.concat(output_names, ","):find("root_output"))
        end)
    end)

    describe("Level Filtering in Propagation", function()
        it("should apply level filtering at each logger in the hierarchy", function()
            local root_logger = lual.logger("root")
            local app_logger = lual.logger("app")
            local debug_logger = lual.logger("app.debug")

            -- Set different levels
            root_logger:set_level(lual.levels.WARNING) -- Only warnings and above
            app_logger:set_level(lual.levels.INFO)     -- Info and above
            debug_logger:set_level(lual.levels.DEBUG)  -- Everything

            root_logger:add_output(create_mock_output("root_output"), create_mock_formatter("root_formatter"))
            app_logger:add_output(create_mock_output("app_output"), create_mock_formatter("app_formatter"))
            debug_logger:add_output(create_mock_output("debug_output"), create_mock_formatter("debug_formatter"))

            -- Log an INFO message from debug logger
            debug_logger:info("Debug session started")

            -- Should be processed by debug_logger and app_logger, but filtered by root_logger
            assert.are.equal(2, #mock_output_calls)

            local output_names = {}
            for _, call in ipairs(mock_output_calls) do
                table.insert(output_names, call.output_name)
                -- All should have the same source
                assert.are.equal("app.debug", call.source_logger_name)
            end

            assert.truthy(table.concat(output_names, ","):find("debug_output"))
            assert.truthy(table.concat(output_names, ","):find("app_output"))
            assert.is_nil(table.concat(output_names, ","):find("root_output"))
        end)

        it("should not propagate if the originating logger filters the message", function()
            local app_logger = lual.logger("app")
            local db_logger = lual.logger("app.database")

            app_logger:add_output(create_mock_output("app_output"), create_mock_formatter("app_formatter"))
            db_logger:add_output(create_mock_output("db_output"), create_mock_formatter("db_formatter"))

            -- Set db_logger to only accept ERROR and above
            db_logger:set_level(lual.levels.ERROR)

            -- Try to log an INFO message
            db_logger:info("This should be filtered out")

            -- No outputs should be called since the message is filtered at the source
            assert.are.equal(0, #mock_output_calls)
            assert.are.equal(0, #mock_formatter_calls)
        end)
    end)

    describe("Complex Hierarchy Propagation", function()
        it("should handle deep hierarchies correctly", function()
            local loggers = {
                lual.logger("root"),
                lual.logger("webapp"),
                lual.logger("webapp.api"),
                lual.logger("webapp.api.v1"),
                lual.logger("webapp.api.v1.users"),
                lual.logger("webapp.api.v1.users.auth")
            }

            -- Add outputs to each logger
            for i, logger in ipairs(loggers) do
                logger:add_output(
                    create_mock_output("output_" .. i),
                    create_mock_formatter("formatter_" .. i)
                )
            end

            -- Log from the deepest logger
            loggers[6]:critical("Authentication failed")

            -- Should propagate through all 6 loggers
            assert.are.equal(6, #mock_output_calls)

            -- Check that each output has the correct owner and source
            local expected_owners = { "webapp.api.v1.users.auth", "webapp.api.v1.users", "webapp.api.v1", "webapp.api",
                "webapp", "root" }
            for i, call in ipairs(mock_output_calls) do
                assert.are.equal("webapp.api.v1.users.auth", call.source_logger_name) -- Same source for all
                assert.are.equal("CRITICAL", call.level_name)
                -- The owner should be one of the expected owners
                assert.truthy(table.concat(expected_owners, ","):find(call.logger_name))
            end
        end)

        it("should handle multiple outputs per logger", function()
            local app_logger = lual.logger("app")
            local db_logger = lual.logger("app.database")

            -- Add multiple outputs to app logger
            app_logger:add_output(create_mock_output("app_console"), create_mock_formatter("app_console_fmt"))
            app_logger:add_output(create_mock_output("app_file"), create_mock_formatter("app_file_fmt"))

            -- Add one output to db logger
            db_logger:add_output(create_mock_output("db_debug"), create_mock_formatter("db_debug_fmt"))

            db_logger:error("Database error occurred")

            -- Should call all 3 outputs (1 from db, 2 from app)
            assert.are.equal(3, #mock_output_calls)

            local output_names = {}
            for _, call in ipairs(mock_output_calls) do
                table.insert(output_names, call.output_name)
                -- All should have the same source
                assert.are.equal("app.database", call.source_logger_name)
            end

            assert.truthy(table.concat(output_names, ","):find("db_debug"))
            assert.truthy(table.concat(output_names, ","):find("app_console"))
            assert.truthy(table.concat(output_names, ","):find("app_file"))
        end)
    end)

    describe("Edge Cases", function()
        it("should handle logger with no outputs but propagating parents", function()
            local root_logger = lual.logger("root")
            local app_logger = lual.logger("app")
            local db_logger = lual.logger("app.database")

            -- Only root has outputs
            root_logger:add_output(create_mock_output("root_output"), create_mock_formatter("root_formatter"))

            -- app_logger and db_logger have no outputs

            db_logger:info("Database query completed")

            -- Should still propagate to root
            assert.are.equal(1, #mock_output_calls)
            assert.are.equal("root_output", mock_output_calls[1].output_name)
            assert.are.equal("root", mock_output_calls[1].logger_name)                -- Root owns the output
            assert.are.equal("app.database", mock_output_calls[1].source_logger_name) -- db_logger originated the message
        end)

        it("should handle root logger with propagate=false", function()
            local root_logger = lual.logger("root")
            local app_logger = lual.logger("app")

            root_logger:add_output(create_mock_output("root_output"), create_mock_formatter("root_formatter"))
            app_logger:add_output(create_mock_output("app_output"), create_mock_formatter("app_formatter"))

            -- Disable propagation on root (shouldn't matter since it has no parent)
            root_logger:set_propagate(false)

            app_logger:warn("Application warning")

            -- Should still call both outputs since root is the top of the hierarchy
            assert.are.equal(2, #mock_output_calls)

            for _, call in ipairs(mock_output_calls) do
                assert.are.equal("app", call.source_logger_name) -- app_logger originated the message
            end
        end)

        it("should handle logger with same name as parent", function()
            -- This tests the edge case where someone might try to create conflicting names
            local app_logger = lual.logger("app")
            local app_sub_logger = lual.logger("app.app") -- Confusing but valid

            app_logger:add_output(create_mock_output("app_output"), create_mock_formatter("app_formatter"))
            app_sub_logger:add_output(create_mock_output("app_sub_output"), create_mock_formatter("app_sub_formatter"))

            app_sub_logger:info("Confusing hierarchy test")

            assert.are.equal(2, #mock_output_calls)

            -- Check that each output has the correct owner and source
            for _, call in ipairs(mock_output_calls) do
                assert.are.equal("app.app", call.source_logger_name) -- app_sub_logger originated the message
                -- The owner should be either "app.app" or "app"
                assert.truthy(call.logger_name == "app.app" or call.logger_name == "app")
            end
        end)
    end)
end)
