-- Tests for custom levels functionality

local lual = require("lual.logger")
local core_levels = require("lual.levels")

describe("Custom Levels", function()
    local original_custom_levels

    before_each(function()
        -- Reset logger cache and config for each test
        lual.reset_cache()
        lual.reset_config()

        -- Save and clear custom levels
        original_custom_levels = core_levels.get_custom_levels()
        core_levels.set_custom_levels({})
    end)

    after_each(function()
        -- Restore original custom levels
        core_levels.set_custom_levels(original_custom_levels)
        lual.reset_cache()
        lual.reset_config()
    end)

    describe("Level validation", function()
        it("validates level names correctly", function()
            local valid, err = core_levels.validate_custom_level_name("verbose")
            assert.is_true(valid)
            assert.is_nil(err)

            valid, err = core_levels.validate_custom_level_name("trace")
            assert.is_true(valid)
            assert.is_nil(err)

            valid, err = core_levels.validate_custom_level_name("my_level")
            assert.is_true(valid)
            assert.is_nil(err)
        end)

        it("rejects invalid level names", function()
            local valid, err = core_levels.validate_custom_level_name("VERBOSE")
            assert.is_false(valid)
            assert.matches("must be lowercase", err)

            valid, err = core_levels.validate_custom_level_name("_reserved")
            assert.is_false(valid)
            assert.matches("reserved", err)

            valid, err = core_levels.validate_custom_level_name("invalid-name")
            assert.is_false(valid)
            assert.matches("valid Lua identifier", err)

            valid, err = core_levels.validate_custom_level_name("")
            assert.is_false(valid)
            assert.matches("cannot be empty", err)

            valid, err = core_levels.validate_custom_level_name(123)
            assert.is_false(valid)
            assert.matches("must be a string", err)
        end)

        it("validates level values correctly", function()
            local valid, err = core_levels.validate_custom_level_value(25)
            assert.is_true(valid)
            assert.is_nil(err)

            valid, err = core_levels.validate_custom_level_value(15)
            assert.is_true(valid)
            assert.is_nil(err)

            valid, err = core_levels.validate_custom_level_value(35)
            assert.is_true(valid)
            assert.is_nil(err)
        end)

        it("rejects invalid level values", function()
            local valid, err = core_levels.validate_custom_level_value(5)
            assert.is_false(valid)
            assert.matches("must be between", err)

            valid, err = core_levels.validate_custom_level_value(50)
            assert.is_false(valid)
            assert.matches("must be between", err)

            valid, err = core_levels.validate_custom_level_value(10)
            assert.is_false(valid)
            assert.matches("must be between", err) -- 10 equals DEBUG, which is <= DEBUG boundary

            valid, err = core_levels.validate_custom_level_value(40)
            assert.is_false(valid)
            assert.matches("must be between", err) -- 40 equals ERROR, which is >= ERROR boundary

            valid, err = core_levels.validate_custom_level_value(25.5)
            assert.is_false(valid)
            assert.matches("must be an integer", err)

            valid, err = core_levels.validate_custom_level_value("25")
            assert.is_false(valid)
            assert.matches("must be a number", err)
        end)

        it("rejects built-in level conflicts in valid range", function()
            -- Test values that are in valid range but conflict with built-ins
            local valid, err = core_levels.validate_custom_level_value(20) -- INFO level
            assert.is_false(valid)
            assert.matches("conflicts with a built%-in level", err)

            valid, err = core_levels.validate_custom_level_value(30) -- WARNING level
            assert.is_false(valid)
            assert.matches("conflicts with a built%-in level", err)
        end)

        it("detects conflicts between custom levels", function()
            core_levels.set_custom_levels({ verbose = 25 })

            local valid, err = core_levels.validate_custom_level_value(25)
            assert.is_false(valid)
            assert.matches("conflicts with an existing custom level", err)
        end)
    end)

    describe("Setting custom levels", function()
        it("sets valid custom levels", function()
            core_levels.set_custom_levels({
                verbose = 25,
                trace = 15
            })

            assert.is_true(core_levels.is_custom_level("verbose"))
            assert.is_true(core_levels.is_custom_level("trace"))
            assert.equals(25, core_levels.get_custom_level_value("verbose"))
            assert.equals(15, core_levels.get_custom_level_value("trace"))
        end)

        it("replaces all existing custom levels", function()
            core_levels.set_custom_levels({ verbose = 25 })
            assert.is_true(core_levels.is_custom_level("verbose"))

            core_levels.set_custom_levels({ trace = 15 })
            assert.is_false(core_levels.is_custom_level("verbose"))
            assert.is_true(core_levels.is_custom_level("trace"))
        end)

        it("rejects duplicate values in the same call", function()
            -- Test that duplicate values are rejected (order may vary)
            local ok, err = pcall(function()
                core_levels.set_custom_levels({
                    verbose = 25,
                    trace = 25
                })
            end)
            assert.is_false(ok)
            assert.matches("Duplicate level value 25", err)
        end)

        it("rejects invalid level configurations", function()
            -- Test uppercase level name (should contain key validation concepts)
            local ok, err = pcall(function()
                core_levels.set_custom_levels({
                    VERBOSE = 25
                })
            end)
            assert.is_false(ok)
            assert.matches("VERBOSE", err)       -- Name should be mentioned
            assert.matches("[Ll]evel name", err) -- Should mention level name validation

            -- Test invalid level value (should contain range validation concepts)
            local ok2, err2 = pcall(function()
                core_levels.set_custom_levels({
                    verbose = 5
                })
            end)
            assert.is_false(ok2)
            assert.matches("verbose", err2) -- Name should be mentioned
            assert.matches("10", err2)      -- Should mention DEBUG level (10) boundary
        end)
    end)

    describe("Level name resolution", function()
        before_each(function()
            core_levels.set_custom_levels({
                verbose = 25,
                trace = 15
            })
        end)

        it("resolves built-in level names", function()
            assert.equals("DEBUG", core_levels.get_level_name(10))
            assert.equals("INFO", core_levels.get_level_name(20))
            assert.equals("WARNING", core_levels.get_level_name(30))
        end)

        it("resolves custom level names", function()
            assert.equals("VERBOSE", core_levels.get_level_name(25))
            assert.equals("TRACE", core_levels.get_level_name(15))
        end)

        it("handles unknown levels", function()
            assert.equals("UNKNOWN_LEVEL_NO_99", core_levels.get_level_name(99))
        end)

        it("get_level_by_name resolves both built-in and custom levels", function()
            -- Test built-in levels
            local name, value = core_levels.get_level_by_name("debug")
            assert.equals("DEBUG", name)
            assert.equals(10, value)

            name, value = core_levels.get_level_by_name("DEBUG")
            assert.equals("DEBUG", name)
            assert.equals(10, value)

            name, value = core_levels.get_level_by_name("info")
            assert.equals("INFO", name)
            assert.equals(20, value)

            -- Test custom levels
            name, value = core_levels.get_level_by_name("verbose")
            assert.equals("VERBOSE", name)
            assert.equals(25, value)

            name, value = core_levels.get_level_by_name("trace")
            assert.equals("TRACE", name)
            assert.equals(15, value)

            -- Test case-insensitivity for custom levels
            name, value = core_levels.get_level_by_name("VERBOSE")
            assert.equals("VERBOSE", name)
            assert.equals(25, value)

            -- Test unknown level
            name, value = core_levels.get_level_by_name("unknown")
            assert.is_nil(name)
            assert.is_nil(value)
        end)
    end)

    describe("get_all_levels()", function()
        it("returns built-in levels when no custom levels are set", function()
            local all_levels = core_levels.get_all_levels()

            assert.equals(core_levels.definition.DEBUG, all_levels.DEBUG)
            assert.equals(core_levels.definition.INFO, all_levels.INFO)
            assert.equals(core_levels.definition.WARNING, all_levels.WARNING)
            assert.equals(core_levels.definition.ERROR, all_levels.ERROR)
            assert.equals(core_levels.definition.CRITICAL, all_levels.CRITICAL)
        end)

        it("includes custom levels with built-in levels", function()
            core_levels.set_custom_levels({
                verbose = 25,
                trace = 15
            })

            local all_levels = core_levels.get_all_levels()

            -- Built-in levels should still be present
            assert.equals(core_levels.definition.DEBUG, all_levels.DEBUG)
            assert.equals(core_levels.definition.INFO, all_levels.INFO)

            -- Custom levels should be present (in uppercase)
            assert.equals(25, all_levels.VERBOSE)
            assert.equals(15, all_levels.TRACE)
        end)
    end)

    describe("API methods", function()
        it("lual.get_levels() returns all levels", function()
            core_levels.set_custom_levels({
                verbose = 25,
                trace = 15
            })

            local levels = lual.get_levels()
            assert.equals(core_levels.definition.DEBUG, levels.DEBUG)
            assert.equals(25, levels.VERBOSE)
            assert.equals(15, levels.TRACE)
        end)

        it("lual.set_levels() sets custom levels", function()
            lual.set_levels({
                verbose = 25,
                trace = 15
            })

            assert.is_true(core_levels.is_custom_level("verbose"))
            assert.is_true(core_levels.is_custom_level("trace"))
            assert.equals(25, core_levels.get_custom_level_value("verbose"))
            assert.equals(15, core_levels.get_custom_level_value("trace"))
        end)
    end)

    describe("Configuration integration", function()
        it("accepts custom_levels in config", function()
            assert.has_no.errors(function()
                lual.config({
                    custom_levels = {
                        verbose = 25,
                        trace = 15
                    }
                })
            end)

            assert.is_true(core_levels.is_custom_level("verbose"))
            assert.is_true(core_levels.is_custom_level("trace"))
        end)

        it("validates custom_levels in config", function()
            -- Test uppercase level name (should contain key validation concepts)
            local ok, err = pcall(function()
                lual.config({
                    custom_levels = {
                        VERBOSE = 25 -- Uppercase not allowed
                    }
                })
            end)
            assert.is_false(ok)
            assert.matches("Invalid configuration", err) -- Should mention it's a config error
            assert.matches("VERBOSE", err)               -- Name should be mentioned
            assert.matches("[Ll]evel name", err)         -- Should mention level name validation

            -- Test invalid level value (should contain range validation concepts)
            local ok2, err2 = pcall(function()
                lual.config({
                    custom_levels = {
                        verbose = 5 -- Out of range
                    }
                })
            end)
            assert.is_false(ok2)
            assert.matches("Invalid configuration", err2) -- Should mention it's a config error
            assert.matches("verbose", err2)               -- Name should be mentioned
            assert.matches("10", err2)                    -- Should mention DEBUG level (10) boundary
        end)

        it("allows using custom levels as root level", function()
            lual.config({
                custom_levels = {
                    verbose = 25
                },
                level = 25 -- Use custom level as root level
            })

            local config = lual.get_config()
            assert.equals(25, config.level)
        end)
    end)

    describe("Logger usage", function()
        before_each(function()
            lual.config({
                custom_levels = {
                    verbose = 25,
                    trace = 15
                },
                level = lual.debug -- Allow all levels
            })
        end)

        it("supports logger.log(level_name, message)", function()
            local logger = lual.logger("test")
            local output_captured = false
            local captured_record = nil

            -- Mock output to capture log record
            local mock_output = function(record, config)
                output_captured = true
                captured_record = record
            end

            logger:add_pipeline({
                outputs = { mock_output },
                presenter = function(record) return record.message end
            })

            assert.has_no.errors(function()
                logger:log("verbose", "This is a verbose message")
            end)

            assert.is_true(output_captured)
            assert.equals(25, captured_record.level_no)
            assert.equals("VERBOSE", captured_record.level_name)
            assert.equals("This is a verbose message", captured_record.message)
        end)

        it("supports dynamic method calls", function()
            local logger = lual.logger("test")
            local output_captured = false
            local captured_record = nil

            -- Mock output to capture log record
            local mock_output = function(record, config)
                output_captured = true
                captured_record = record
            end

            logger:add_pipeline({
                outputs = { mock_output },
                presenter = function(record) return record.message end
            })

            assert.has_no.errors(function()
                logger:verbose("This is a verbose message")
            end)

            assert.is_true(output_captured)
            assert.equals(25, captured_record.level_no)
            assert.equals("VERBOSE", captured_record.level_name)
            assert.equals("This is a verbose message", captured_record.message)
        end)

        it("respects level thresholds for custom levels", function()
            lual.config({
                custom_levels = {
                    verbose = 25,
                    trace = 15
                },
                level = 20 -- Only INFO and above
            })

            local logger = lual.logger("test")
            local output_count = 0

            -- Mock output to count calls
            local mock_output = function(record, config)
                output_count = output_count + 1
            end

            logger:add_pipeline({
                outputs = { mock_output },
                presenter = function(record) return record.message end
            })

            logger:trace("Should not appear") -- Level 15, below threshold
            logger:verbose("Should appear")   -- Level 25, above threshold

            assert.equals(1, output_count)
        end)

        it("handles unknown custom level names", function()
            local logger = lual.logger("test")

            assert.has_error(function()
                logger:log("unknown_level", "message")
            end, "Unknown level name: unknown_level")
        end)

        it("continues to support numeric levels", function()
            local logger = lual.logger("test")
            local output_captured = false
            local captured_record = nil

            -- Mock output to capture log record
            local mock_output = function(record, config)
                output_captured = true
                captured_record = record
            end

            logger:add_pipeline({
                outputs = { mock_output },
                presenter = function(record) return record.message end
            })

            assert.has_no.errors(function()
                logger:log(34, "Numeric level message")
            end)

            assert.is_true(output_captured)
            assert.equals(34, captured_record.level_no)
            assert.equals("UNKNOWN_LEVEL_NO_34", captured_record.level_name)
            assert.equals("Numeric level message", captured_record.message)
        end)
    end)
end)
