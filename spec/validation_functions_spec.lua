package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua;../lua/?.lua;../lua/?/init.lua"
local config = require("lual.config")
local lualog = require("lual.logger")

describe("Validation Functions", function()
    before_each(function()
        -- Reset modules for clean state
        package.loaded["lual.logger"] = nil
        package.loaded["lual.core.engine"] = nil
        package.loaded["lual.config"] = nil
        config = require("lual.config")
        lualog = require("lual.logger")
    end)

    describe("validate_level", function()
        it("should accept nil level", function()
            -- Note: validate_level is not directly exposed, but we can test it through process_config
            local result = config.process_config({ outputs = {} }, { level = nil })
            assert.is_not_nil(result)
        end)

        it("should accept valid string levels", function()
            local levels = { "debug", "info", "warning", "error", "critical", "none" }
            for _, level in ipairs(levels) do
                local result = config.process_config({ level = level, outputs = {} })
                assert.is_not_nil(result, "Failed for level: " .. level)
            end
        end)

        it("should accept valid string levels (case insensitive)", function()
            local levels = { "DEBUG", "Info", "WARNING", "Error", "CRITICAL", "None" }
            for _, level in ipairs(levels) do
                local result = config.process_config({ level = level, outputs = {} })
                assert.is_not_nil(result, "Failed for level: " .. level)
            end
        end)

        it("should accept numeric levels", function()
            local result = config.process_config({ level = 20, outputs = {} })
            assert.is_not_nil(result)
        end)

        it("should reject invalid string levels", function()
            assert.has_error(function()
                config.process_config({ level = "invalid", outputs = {} })
            end)
        end)

        it("should reject invalid level types", function()
            assert.has_error(function()
                config.process_config({ level = true, outputs = {} })
            end)
        end)
    end)

    describe("validate_single_output", function()
        it("should accept valid console output", function()
            local result = config.process_config({
                outputs = {
                    { type = "console", formatter = "text" }
                }
            })
            assert.is_not_nil(result)
        end)

        it("should accept valid file output", function()
            local result = config.process_config({
                outputs = {
                    { type = "file", formatter = "color", path = "test.log" }
                }
            })
            assert.is_not_nil(result)
        end)

        it("should accept console output with valid stream", function()
            local result = config.process_config({
                outputs = {
                    { type = "console", formatter = "text", stream = io.stderr }
                }
            })
            assert.is_not_nil(result)
        end)

        it("should reject output without type", function()
            assert.has_error(function()
                config.process_config({
                    outputs = {
                        { formatter = "text" }
                    }
                })
            end)
        end)

        it("should reject output without formatter", function()
            assert.has_error(function()
                config.process_config({
                    outputs = {
                        { type = "console" }
                    }
                })
            end)
        end)

        it("should reject file output without path", function()
            assert.has_error(function()
                config.process_config({
                    outputs = {
                        { type = "file", formatter = "text" }
                    }
                })
            end)
        end)

        it("should reject console output with invalid stream", function()
            assert.has_error(function()
                config.process_config({
                    outputs = {
                        { type = "console", formatter = "text", stream = "invalid" }
                    }
                })
            end)
        end)
    end)

    describe("validate_outputs", function()
        it("should accept nil outputs", function()
            local result = config.process_config({})
            assert.is_not_nil(result)
        end)

        it("should accept empty outputs array", function()
            local result = config.process_config({ outputs = {} })
            assert.is_not_nil(result)
        end)

        it("should accept valid outputs array", function()
            local result = config.process_config({
                outputs = {
                    { type = "console", formatter = "text" },
                    { type = "file",    formatter = "color", path = "test.log" }
                }
            })
            assert.is_not_nil(result)
        end)

        it("should reject non-table outputs", function()
            assert.has_error(function()
                config.process_config({ outputs = "not a table" })
            end)
        end)

        it("should reject outputs with invalid output", function()
            assert.has_error(function()
                config.process_config({
                    outputs = {
                        { type = "console", formatter = "text" },
                        { type = "invalid", formatter = "text" }
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
                outputs = {}
            })
            assert.is_not_nil(result)
        end)

        it("should accept config with nil fields", function()
            local result = config.process_config({ outputs = {} })
            assert.is_not_nil(result)
        end)

        it("should reject invalid name type", function()
            assert.has_error(function()
                config.process_config({ name = 123, outputs = {} })
            end)
        end)

        it("should reject invalid propagate type", function()
            assert.has_error(function()
                config.process_config({ propagate = "yes", outputs = {} })
            end)
        end)
    end)

    describe("validate_known_keys", function()
        it("should accept config with valid keys", function()
            local result = config.process_config({
                name = "test",
                level = "info",
                outputs = {},
                propagate = true
            })
            assert.is_not_nil(result)
        end)

        it("should accept config with subset of valid keys", function()
            local result = config.process_config({
                name = "test",
                level = "info",
                outputs = {}
            })
            assert.is_not_nil(result)
        end)

        it("should reject config with unknown keys", function()
            assert.has_error(function()
                config.process_config({
                    name = "test",
                    unknown_key = "value",
                    outputs = {}
                })
            end)
        end)
    end)

    describe("Shortcut API validation", function()
        it("should detect shortcut config", function()
            assert.is_true(config.is_shortcut_config({ output = "console", formatter = "text" }))
            assert.is_false(config.is_shortcut_config({ outputs = {} }))
        end)

        it("should validate shortcut config", function()
            local result = config.process_config({
                output = "console",
                formatter = "text"
            })
            assert.is_not_nil(result)
        end)

        it("should reject invalid shortcut config", function()
            assert.has_error(function()
                config.process_config({
                    output = "console"
                    -- missing formatter
                })
            end)
        end)

        it("should transform shortcut to declarative", function()
            local shortcut = {
                name = "test",
                output = "console",
                formatter = "text"
            }
            local declarative = config.shortcut_to_declarative_config(shortcut)
            assert.are.same("test", declarative.name)
            assert.are.same(1, #declarative.outputs)
            assert.are.same("console", declarative.outputs[1].type)
            assert.are.same("text", declarative.outputs[1].formatter)
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
                local result = config.process_config({ level = level_name, outputs = {} })
                assert.is_not_nil(result, "Failed for level: " .. level_name)
            end
        end)
    end)
end)
