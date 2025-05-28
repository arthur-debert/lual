package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua;../lua/?.lua;../lua/?/init.lua"
local config = require("lual.config")
local lualog = require("lual.logger")

describe("Validation Functions", function()
    before_each(function()
        -- Reset modules for clean state
        package.loaded["lual.logger"] = nil
        package.loaded["lual.core.logging"] = nil
        package.loaded["lual.config"] = nil
        config = require("lual.config")
        lualog = require("lual.logger")
    end)

    describe("validate_level", function()
        it("should accept nil level", function()
            -- Note: validate_level is not directly exposed, but we can test it through process_config
            local result = config.process_config({ dispatchers = {} }, { level = nil })
            assert.is_not_nil(result)
        end)

        it("should accept valid string levels", function()
            local levels = { "debug", "info", "warning", "error", "critical", "none" }
            for _, level in ipairs(levels) do
                local result = config.process_config({ level = level, dispatchers = {} })
                assert.is_not_nil(result, "Failed for level: " .. level)
            end
        end)

        it("should accept valid string levels (case insensitive)", function()
            local levels = { "DEBUG", "Info", "WARNING", "Error", "CRITICAL", "None" }
            for _, level in ipairs(levels) do
                local result = config.process_config({ level = level, dispatchers = {} })
                assert.is_not_nil(result, "Failed for level: " .. level)
            end
        end)

        it("should accept numeric levels", function()
            local result = config.process_config({ level = 20, dispatchers = {} })
            assert.is_not_nil(result)
        end)

        it("should reject invalid string levels", function()
            assert.has_error(function()
                config.process_config({ level = "invalid", dispatchers = {} })
            end)
        end)

        it("should reject invalid level types", function()
            assert.has_error(function()
                config.process_config({ level = true, dispatchers = {} })
            end)
        end)
    end)

    describe("validate_single_dispatcher", function()
        it("should accept valid console dispatcher", function()
            local result = config.process_config({
                dispatchers = {
                    { type = "console", presenter = "text" }
                }
            })
            assert.is_not_nil(result)
        end)

        it("should accept valid file dispatcher", function()
            local result = config.process_config({
                dispatchers = {
                    { type = "file", presenter = "color", path = "test.log" }
                }
            })
            assert.is_not_nil(result)
        end)

        it("should accept console dispatcher with valid stream", function()
            local result = config.process_config({
                dispatchers = {
                    { type = "console", presenter = "text", stream = io.stderr }
                }
            })
            assert.is_not_nil(result)
        end)

        it("should reject dispatcher without type", function()
            assert.has_error(function()
                config.process_config({
                    dispatchers = {
                        { presenter = "text" }
                    }
                })
            end)
        end)

        it("should reject dispatcher without presenter", function()
            assert.has_error(function()
                config.process_config({
                    dispatchers = {
                        { type = "console" }
                    }
                })
            end)
        end)

        it("should reject file dispatcher without path", function()
            assert.has_error(function()
                config.process_config({
                    dispatchers = {
                        { type = "file", presenter = "text" }
                    }
                })
            end)
        end)

        it("should reject console dispatcher with invalid stream", function()
            assert.has_error(function()
                config.process_config({
                    dispatchers = {
                        { type = "console", presenter = "text", stream = "invalid" }
                    }
                })
            end)
        end)
    end)

    describe("validate_dispatchers", function()
        it("should accept nil dispatchers", function()
            local result = config.process_config({})
            assert.is_not_nil(result)
        end)

        it("should accept empty dispatchers array", function()
            local result = config.process_config({ dispatchers = {} })
            assert.is_not_nil(result)
        end)

        it("should accept valid dispatchers array", function()
            local result = config.process_config({
                dispatchers = {
                    { type = "console", presenter = "text" },
                    { type = "file",    presenter = "color", path = "test.log" }
                }
            })
            assert.is_not_nil(result)
        end)

        it("should reject non-table dispatchers", function()
            assert.has_error(function()
                config.process_config({ dispatchers = "not a table" })
            end)
        end)

        it("should reject dispatchers with invalid dispatcher", function()
            assert.has_error(function()
                config.process_config({
                    dispatchers = {
                        { type = "console", presenter = "text" },
                        { type = "invalid", presenter = "text" }
                    }
                })
            end)
        end)
    end)

    describe("validate_basic_fields", function()
        it("should accept valid config", function()
            local result = config.process_config({
                name = "test.logger",
                propagate = true,
                dispatchers = {}
            })
            assert.is_not_nil(result)
        end)

        it("should accept config with nil fields", function()
            local result = config.process_config({ dispatchers = {} })
            assert.is_not_nil(result)
        end)

        it("should reject invalid name type", function()
            assert.has_error(function()
                config.process_config({ name = 123, dispatchers = {} })
            end)
        end)

        it("should reject invalid propagate type", function()
            assert.has_error(function()
                config.process_config({ propagate = "yes", dispatchers = {} })
            end)
        end)
    end)

    describe("validate_timezone", function()
        it("should accept nil timezone", function()
            local result = config.process_config({ dispatchers = {} })
            assert.is_not_nil(result)
        end)

        it("should accept valid timezone 'local'", function()
            local result = config.process_config({ timezone = "local", dispatchers = {} })
            assert.is_not_nil(result)
        end)

        it("should accept valid timezone 'utc'", function()
            local result = config.process_config({ timezone = "utc", dispatchers = {} })
            assert.is_not_nil(result)
        end)

        it("should accept valid timezone 'UTC' (case insensitive)", function()
            local result = config.process_config({ timezone = "UTC", dispatchers = {} })
            assert.is_not_nil(result)
        end)

        it("should accept valid timezone 'LOCAL' (case insensitive)", function()
            local result = config.process_config({ timezone = "LOCAL", dispatchers = {} })
            assert.is_not_nil(result)
        end)

        it("should reject invalid timezone string", function()
            assert.has_error(function()
                config.process_config({ timezone = "invalid", dispatchers = {} })
            end)
        end)

        it("should reject invalid timezone type", function()
            assert.has_error(function()
                config.process_config({ timezone = 123, dispatchers = {} })
            end)
        end)

        it("should reject boolean timezone", function()
            assert.has_error(function()
                config.process_config({ timezone = true, dispatchers = {} })
            end)
        end)
    end)

    describe("validate_known_keys", function()
        it("should accept config with valid keys", function()
            local result = config.process_config({
                name = "test",
                level = "info",
                dispatchers = {},
                propagate = true,
                timezone = "utc"
            })
            assert.is_not_nil(result)
        end)

        it("should accept config with subset of valid keys", function()
            local result = config.process_config({
                name = "test",
                level = "info",
                dispatchers = {}
            })
            assert.is_not_nil(result)
        end)

        it("should reject config with unknown keys", function()
            assert.has_error(function()
                config.process_config({
                    name = "test",
                    unknown_key = "value",
                    dispatchers = {}
                })
            end)
        end)
    end)

    describe("Shortcut API validation", function()
        it("should detect shortcut config", function()
            assert.is_true(config.is_shortcut_config({ dispatcher = "console", presenter = "text" }))
            assert.is_false(config.is_shortcut_config({ dispatchers = {} }))
        end)

        it("should validate shortcut config", function()
            local result = config.process_config({
                dispatcher = "console",
                presenter = "text"
            })
            assert.is_not_nil(result)
        end)

        it("should reject invalid shortcut config", function()
            assert.has_error(function()
                config.process_config({
                    dispatcher = "console"
                    -- missing presenter
                })
            end)
        end)

        it("should transform shortcut to declarative", function()
            local shortcut = {
                name = "test",
                dispatcher = "console",
                presenter = "text"
            }
            local declarative = config.shortcut_to_declarative_config(shortcut)
            assert.are.same("test", declarative.name)
            assert.are.same(1, #declarative.dispatchers)
            assert.are.same("console", declarative.dispatchers[1].type)
            assert.are.same("text", declarative.dispatchers[1].presenter)
        end)

        it("should transform shortcut to declarative with timezone", function()
            local shortcut = {
                name = "test",
                dispatcher = "console",
                presenter = "text",
                timezone = "utc"
            }
            local declarative = config.shortcut_to_declarative_config(shortcut)
            assert.are.same("test", declarative.name)
            assert.are.same("utc", declarative.timezone)
            assert.are.same(1, #declarative.dispatchers)
            assert.are.same("console", declarative.dispatchers[1].type)
            assert.are.same("text", declarative.dispatchers[1].presenter)
        end)

        it("should validate shortcut config with timezone", function()
            local result = config.process_config({
                dispatcher = "console",
                presenter = "text",
                timezone = "utc"
            })
            assert.is_not_nil(result)
        end)
    end)

    describe("Integration with lualog.LEVELS", function()
        it("should use lualog.LEVELS for validation", function()
            -- Test that the validation uses the LEVELS from the main module
            assert.is_table(lualog.LEVELS)
            assert.is_number(lualog.LEVELS.debug)
            assert.is_number(lualog.LEVELS.info)
            assert.is_number(lualog.LEVELS.warning)
            assert.is_number(lualog.LEVELS.error)
            assert.is_number(lualog.LEVELS.critical)
            assert.is_number(lualog.LEVELS.none)

            -- Test that validation works with these levels
            for level_name, _ in pairs(lualog.LEVELS) do
                local result = config.process_config({ level = level_name, dispatchers = {} })
                assert.is_not_nil(result, "Failed for level: " .. level_name)
            end
        end)
    end)
end)
