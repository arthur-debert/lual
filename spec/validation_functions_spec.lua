package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua;../lua/?.lua;../lua/?/init.lua"
local engine = require("lual.core.engine")
local lualog = require("lual.logger")

describe("Validation Functions", function()
    before_each(function()
        -- Reset modules for clean state
        package.loaded["lual.logger"] = nil
        package.loaded["lual.core.engine"] = nil
        engine = require("lual.core.engine")
        lualog = require("lual.logger")
    end)

    describe("validate_level", function()
        it("should accept nil level", function()
            local valid, err = engine.validate_level(nil)
            assert.is_true(valid)
            assert.is_nil(err)
        end)

        it("should accept valid string levels", function()
            local levels = { "debug", "info", "warning", "error", "critical", "none" }
            for _, level in ipairs(levels) do
                local valid, err = engine.validate_level(level)
                assert.is_true(valid, "Failed for level: " .. level)
                assert.is_nil(err)
            end
        end)

        it("should accept valid string levels (case insensitive)", function()
            local levels = { "DEBUG", "Info", "WARNING", "Error", "CRITICAL", "None" }
            for _, level in ipairs(levels) do
                local valid, err = engine.validate_level(level)
                assert.is_true(valid, "Failed for level: " .. level)
                assert.is_nil(err)
            end
        end)

        it("should accept numeric levels", function()
            local valid, err = engine.validate_level(20)
            assert.is_true(valid)
            assert.is_nil(err)
        end)

        it("should reject invalid string levels", function()
            local valid, err = engine.validate_level("invalid")
            assert.is_false(valid)
            assert.is_string(err)
            assert.truthy(string.find(err, "Invalid level string"))
        end)

        it("should reject invalid level types", function()
            local valid, err = engine.validate_level(true)
            assert.is_false(valid)
            assert.are.same("Config.level must be a string or number", err)
        end)
    end)

    describe("validate_output_and_formatter_types", function()
        it("should accept valid console/text combination", function()
            local valid, err = engine.validate_output_and_formatter_types("console", "text")
            assert.is_true(valid)
            assert.is_nil(err)
        end)

        it("should accept valid file/color combination", function()
            local valid, err = engine.validate_output_and_formatter_types("file", "color")
            assert.is_true(valid)
            assert.is_nil(err)
        end)

        it("should reject invalid output type", function()
            local valid, err = engine.validate_output_and_formatter_types("invalid", "text")
            assert.is_false(valid)
            assert.truthy(string.find(err, "Unknown output type"))
        end)

        it("should reject invalid formatter type", function()
            local valid, err = engine.validate_output_and_formatter_types("console", "invalid")
            assert.is_false(valid)
            assert.truthy(string.find(err, "Unknown formatter type"))
        end)
    end)

    describe("validate_single_output", function()
        it("should accept valid console output", function()
            local output = {
                type = "console",
                formatter = "text"
            }
            local valid, err = engine.validate_single_output(output, 1)
            assert.is_true(valid)
            assert.is_nil(err)
        end)

        it("should accept valid file output", function()
            local output = {
                type = "file",
                formatter = "color",
                path = "test.log"
            }
            local valid, err = engine.validate_single_output(output, 1)
            assert.is_true(valid)
            assert.is_nil(err)
        end)

        it("should accept console output with valid stream", function()
            local output = {
                type = "console",
                formatter = "text",
                stream = io.stderr
            }
            local valid, err = engine.validate_single_output(output, 1)
            assert.is_true(valid)
            assert.is_nil(err)
        end)

        it("should reject non-table output", function()
            local valid, err = engine.validate_single_output("not a table", 1)
            assert.is_false(valid)
            assert.are.same("Each output must be a table", err)
        end)

        it("should reject output without type", function()
            local output = { formatter = "text" }
            local valid, err = engine.validate_single_output(output, 1)
            assert.is_false(valid)
            assert.are.same("Each output must have a 'type' string field", err)
        end)

        it("should reject output without formatter", function()
            local output = { type = "console" }
            local valid, err = engine.validate_single_output(output, 1)
            assert.is_false(valid)
            assert.are.same("Each output must have a 'formatter' string field", err)
        end)

        it("should reject file output without path", function()
            local output = {
                type = "file",
                formatter = "text"
            }
            local valid, err = engine.validate_single_output(output, 1)
            assert.is_false(valid)
            assert.are.same("File output must have a 'path' string field", err)
        end)

        it("should reject console output with invalid stream", function()
            local output = {
                type = "console",
                formatter = "text",
                stream = "invalid"
            }
            local valid, err = engine.validate_single_output(output, 1)
            assert.is_false(valid)
            assert.are.same("Console output 'stream' field must be a file handle", err)
        end)
    end)

    describe("validate_outputs", function()
        it("should accept nil outputs", function()
            local valid, err = engine.validate_outputs(nil)
            assert.is_true(valid)
            assert.is_nil(err)
        end)

        it("should accept empty outputs array", function()
            local valid, err = engine.validate_outputs({})
            assert.is_true(valid)
            assert.is_nil(err)
        end)

        it("should accept valid outputs array", function()
            local outputs = {
                { type = "console", formatter = "text" },
                { type = "file",    formatter = "color", path = "test.log" }
            }
            local valid, err = engine.validate_outputs(outputs)
            assert.is_true(valid)
            assert.is_nil(err)
        end)

        it("should reject non-table outputs", function()
            local valid, err = engine.validate_outputs("not a table")
            assert.is_false(valid)
            assert.are.same("Config.outputs must be a table", err)
        end)

        it("should reject outputs with invalid output", function()
            local outputs = {
                { type = "console", formatter = "text" },
                { type = "invalid", formatter = "text" }
            }
            local valid, err = engine.validate_outputs(outputs)
            assert.is_false(valid)
            assert.truthy(string.find(err, "Unknown output type"))
        end)
    end)

    describe("validate_basic_fields", function()
        it("should accept valid config", function()
            local config = {
                name = "test.logger",
                propagate = true
            }
            local valid, err = engine.validate_basic_fields(config)
            assert.is_true(valid)
            assert.is_nil(err)
        end)

        it("should accept config with nil fields", function()
            local config = {}
            local valid, err = engine.validate_basic_fields(config)
            assert.is_true(valid)
            assert.is_nil(err)
        end)

        it("should reject invalid name type", function()
            local config = { name = 123 }
            local valid, err = engine.validate_basic_fields(config)
            assert.is_false(valid)
            assert.are.same("Config.name must be a string", err)
        end)

        it("should reject invalid propagate type", function()
            local config = { propagate = "yes" }
            local valid, err = engine.validate_basic_fields(config)
            assert.is_false(valid)
            assert.are.same("Config.propagate must be a boolean", err)
        end)
    end)

    describe("validate_known_keys", function()
        it("should accept config with valid keys", function()
            local config = {
                name = "test",
                level = "info",
                outputs = {},
                propagate = true
            }
            local valid, err = engine.validate_known_keys(config)
            assert.is_true(valid)
            assert.is_nil(err)
        end)

        it("should accept config with subset of valid keys", function()
            local config = {
                name = "test",
                level = "info"
            }
            local valid, err = engine.validate_known_keys(config)
            assert.is_true(valid)
            assert.is_nil(err)
        end)

        it("should reject config with unknown keys", function()
            local config = {
                name = "test",
                unknown_key = "value"
            }
            local valid, err = engine.validate_known_keys(config)
            assert.is_false(valid)
            assert.are.same("Unknown config key: unknown_key", err)
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
                local valid, err = engine.validate_level(level_name)
                assert.is_true(valid, "Failed for level: " .. level_name)
                assert.is_nil(err)
            end
        end)
    end)
end)
