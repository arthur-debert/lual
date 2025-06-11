local command_line = require("lual.config.command_line")
local lual = require("lual")
local schemer = require("lual.utils.schemer")

-- Helper function to get detailed validation errors for testing
local function get_command_line_validation_error(config_table)
    local command_line_schema = {
        fields = {
            mapping = { type = "table", required = false },
            auto_detect = { type = "boolean", required = false }
        }
    }
    local errors = schemer.validate(config_table, command_line_schema)
    return errors
end

describe("Command line verbosity", function()
    before_each(function()
        lual.reset_config()
        _G.arg = {} -- Reset command line arguments
    end)

    after_each(function()
        lual.reset_config()
        _G.arg = {} -- Reset command line arguments
    end)

    describe("validation", function()
        it("validates that config is a table", function()
            local result, msg = command_line.validate("not a table")
            assert.is_false(result)
            assert.matches("must be a table", msg)
        end)

        it("validates that mapping is a table if provided", function()
            local result, msg = command_line.validate({ mapping = "not a table" })
            assert.is_false(result)

            -- Test specific error code
            local error_info = get_command_line_validation_error({ mapping = "not a table" })
            assert.is_not_nil(error_info)
            assert.is_not_nil(error_info.fields)
            assert.is_not_nil(error_info.fields.mapping)
            assert.are.equal("INVALID_TYPE", error_info.fields.mapping[1][1])
        end)

        it("validates mapping key types", function()
            -- String keys should still be required for the mapping itself
            local result, msg = command_line.validate({ mapping = { [123] = "info" } })
            -- TODO: This test might need to be adjusted depending on schemer's key validation
            -- For now, let's see if schemer validates this
            assert.is_false(result)
        end)

        it("accepts both string and numeric mapping values", function()
            -- String level names should work
            local result = command_line.validate({ mapping = { v = "warning" } })
            assert.is_true(result)

            -- Numeric level values should also work
            result = command_line.validate({ mapping = { v = 30 } })
            assert.is_true(result)

            -- Invalid types should fail
            result = command_line.validate({ mapping = { v = true } })
            assert.is_false(result)
        end)

        it("validates mapping level names and values", function()
            -- Invalid level name should fail
            local result, msg = command_line.validate({ mapping = { v = "not_a_level" } })
            assert.is_false(result)
            assert.matches("invalid level value", msg)

            -- Invalid level number should fail
            result, msg = command_line.validate({ mapping = { v = 999 } })
            assert.is_false(result)
            assert.matches("invalid level value", msg)
        end)

        it("validates auto_detect type", function()
            local result, msg = command_line.validate({ auto_detect = "not a boolean" })
            assert.is_false(result)

            -- Test specific error code
            local error_info = get_command_line_validation_error({ auto_detect = "not a boolean" })
            assert.is_not_nil(error_info)
            assert.is_not_nil(error_info.fields)
            assert.is_not_nil(error_info.fields.auto_detect)
            assert.are.equal("INVALID_TYPE", error_info.fields.auto_detect[1][1])
        end)

        it("validates a proper config", function()
            local result = command_line.validate({
                mapping = { v = "warning", vv = "info", vvv = "debug" },
                auto_detect = true
            })
            assert.is_true(result)
        end)
    end)

    describe("normalization", function()
        it("uses default mapping when not provided", function()
            local result = command_line.normalize({})
            assert.is_table(result.mapping)
            assert.is_same(command_line.DEFAULT_MAPPING, result.mapping)
        end)

        it("uses custom mapping when provided", function()
            local custom_mapping = { v = "warning", loud = "critical" }
            local result = command_line.normalize({ mapping = custom_mapping })
            assert.is_same(custom_mapping, result.mapping)
        end)

        it("defaults auto_detect to true", function()
            local result = command_line.normalize({})
            assert.is_true(result.auto_detect)
        end)

        it("preserves auto_detect value when provided", function()
            local result = command_line.normalize({ auto_detect = false })
            assert.is_false(result.auto_detect)
        end)
    end)

    describe("detection", function()
        it("handles short flags", function()
            _G.arg = { "-v" }
            local level = command_line.detect_verbosity_from_cli(command_line.DEFAULT_MAPPING)
            assert.equals(lual.warning, level)
        end)

        it("handles long flags", function()
            _G.arg = { "--verbose" }
            local level = command_line.detect_verbosity_from_cli(command_line.DEFAULT_MAPPING)
            assert.equals(lual.info, level)
        end)

        it("handles repeated v flags", function()
            _G.arg = { "-vvv" }
            local level = command_line.detect_verbosity_from_cli(command_line.DEFAULT_MAPPING)
            assert.equals(lual.debug, level)
        end)

        it("handles direct level setting", function()
            _G.arg = { "--log-level=debug" }
            local level = command_line.detect_verbosity_from_cli({
                ["log-level"] = "debug"
            })
            assert.equals(lual.debug, level)
        end)

        it("returns nil when no matching flags found", function()
            _G.arg = { "--unrelated" }
            local level = command_line.detect_verbosity_from_cli(command_line.DEFAULT_MAPPING)
            assert.is_nil(level)
        end)

        it("uses the last matching flag", function()
            _G.arg = { "-v", "-vvv" }
            local level = command_line.detect_verbosity_from_cli(command_line.DEFAULT_MAPPING)
            assert.equals(lual.debug, level)
        end)
    end)

    describe("integration", function()
        it("changes the root logger level via configuration", function()
            _G.arg = { "-vvv" } -- Debug level

            -- Initial root level is WARNING
            assert.equals(lual.warning, lual.get_config().level)

            -- Configure command line verbosity
            lual.config({
                command_line_verbosity = { auto_detect = true }
            })

            -- Level should be changed to DEBUG from command line
            assert.equals(lual.debug, lual.get_config().level)
        end)

        it("doesn't apply when auto_detect is false", function()
            _G.arg = { "-vvv" } -- Debug level

            -- Configure command line verbosity
            lual.config({
                command_line_verbosity = { auto_detect = false }
            })

            -- Level should remain WARNING
            assert.equals(lual.warning, lual.get_config().level)
        end)

        it("works with custom mapping", function()
            _G.arg = { "--trace" } -- Custom flag

            -- Configure command line verbosity with custom mapping
            lual.config({
                command_line_verbosity = {
                    mapping = { trace = "debug" },
                    auto_detect = true
                }
            })

            -- Level should be changed to DEBUG from command line
            assert.equals(lual.debug, lual.get_config().level)
        end)

        it("works with convenience function", function()
            _G.arg = { "-vv" } -- Info level

            -- Use convenience function
            lual.set_command_line_verbosity({})

            -- Level should be changed to INFO from command line
            assert.equals(lual.info, lual.get_config().level)
        end)
    end)
end)
