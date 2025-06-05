#!/usr/bin/env lua
package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua;../lua/?.lua;../lua/?/init.lua"

local lual = require("lual.logger")
local core_levels = require("lua.lual.levels")

--- Tests that assert() correctly returns the raw function for backwards compatibility,
-- but does not return the same output table to preserve immutability
local function assert_output_is_function(result, expected_func)
    assert.is_table(result) -- We're now returning the normalized form
    assert.are.equal(expected_func, result.func)
end

-- This is the core test for basic configuration API
describe("lual.config() API", function()
    -- Reset before each test
    before_each(function()
        lual.reset_config()
    end)

    describe("Basic functionality", function()
        it("should update configuration with provided keys", function()
            local result = lual.config({
                level = core_levels.definition.DEBUG
            })

            assert.are.equal(core_levels.definition.DEBUG, result.level)

            -- Default output should be preserved
            local outputs = result.outputs
            assert.is_table(outputs)
            assert.are.equal(1, #outputs)
            assert_output_is_function(outputs[1], lual.outputs.console_output)
        end)

        it("should preserve existing configuration for unspecified keys", function()
            -- First set a non-default level
            lual.config({
                level = core_levels.definition.INFO
            })

            -- Then modify a different key
            local result = lual.config({
                propagate = false
            })

            -- The previously-set level should be preserved
            assert.are.equal(core_levels.definition.INFO, result.level)
            assert.is_false(result.propagate)

            -- Default output should still be there
            local outputs = result.outputs
            assert.is_table(outputs)
            assert.are.equal(1, #outputs)
            assert_output_is_function(outputs[1], lual.outputs.console_output)
        end)

        it("should allow updating outputs", function()
            local custom_output = function() end

            local result = lual.config({
                outputs = { custom_output }
            })

            local outputs = result.outputs
            assert.is_table(outputs)
            assert.are.equal(1, #outputs)
            assert_output_is_function(outputs[1], custom_output)
        end)

        it("should allow updating propagate", function()
            local result = lual.config({
                propagate = false
            })

            assert.is_false(result.propagate)

            -- Default output should still be there
            local outputs = result.outputs
            assert.is_table(outputs)
            assert.are.equal(1, #outputs)
            assert_output_is_function(outputs[1], lual.outputs.console_output)
        end)

        it("should allow updating multiple keys at once", function()
            local custom_output = function() end

            local result = lual.config({
                level = core_levels.definition.ERROR,
                propagate = false,
                outputs = { custom_output }
            })

            assert.are.equal(core_levels.definition.ERROR, result.level)
            assert.is_false(result.propagate)

            local outputs = result.outputs
            assert.is_table(outputs)
            assert.are.equal(1, #outputs)
            assert_output_is_function(outputs[1], custom_output)
        end)
    end)

    describe("Validation - Unknown keys", function()
        it("should reject unknown configuration keys", function()
            assert.has_error(function()
                    lual.config({
                        level = core_levels.definition.DEBUG,
                        unknown_key = "value"
                    })
                end,
                "Invalid configuration: Unknown configuration key 'unknown_key'. Valid keys are: level, outputs, propagate")
        end)

        it("should reject multiple unknown keys with helpful message", function()
            assert.has_error(function()
                lual.config({
                    bad_key1 = "value1",
                    bad_key2 = "value2"
                })
            end)
            -- Should contain "Unknown configuration key" somewhere in the error
        end)
    end)

    describe("Validation - Type checking", function()
        it("should reject non-table configuration", function()
            assert.has_error(function()
                lual.config("not_a_table")
            end, "Invalid configuration: Configuration must be a table, got string")
        end)

        it("should reject unknown configuration keys", function()
            assert.has_error(function()
                    lual.config({
                        unknown_key = "value"
                    })
                end,
                "Invalid configuration: Unknown configuration key 'unknown_key'. Valid keys are: level, outputs, propagate")
        end)

        it("should reject invalid level type", function()
            assert.has_error(function()
                    lual.config({
                        level = "not_a_number"
                    })
                end,
                "Invalid configuration: Invalid type for 'level': expected number, got string. Logging level (use lual.DEBUG, lual.INFO, etc.)")
        end)

        it("should reject invalid level values", function()
            local ok, err = pcall(function()
                lual.config({
                    level = 999 -- Not a valid level constant
                })
            end)

            assert.is_false(ok)
            assert.matches("Invalid configuration: Invalid level value 999. Valid levels are:", err)
        end)

        it("should reject NOTSET level for root logger", function()
            assert.has_error(function()
                lual.config({
                    level = core_levels.definition.NOTSET
                })
            end, "Invalid configuration: Root logger level cannot be set to NOTSET")
        end)

        it("should reject invalid propagate type", function()
            assert.has_error(function()
                    lual.config({
                        propagate = "not_a_boolean"
                    })
                end,
                "Invalid configuration: Invalid type for 'propagate': expected boolean, got string. Whether to propagate messages (always true for root)")
        end)

        it("should reject invalid outputs type", function()
            assert.has_error(function()
                    lual.config({
                        outputs = "not_an_array"
                    })
                end,
                "Invalid configuration: Invalid type for 'outputs': expected table, got string. Array of output functions or configuration tables")
        end)

        it("should reject outputs containing non-functions", function()
            assert.has_error(function()
                    lual.config({
                        outputs = { "not_a_output" }
                    })
                end,
                "Invalid configuration: outputs[1] must be a function or a table with function as first element, got string")
        end)

        it("should accept all valid level values", function()
            local valid_levels = {
                core_levels.definition.NOTSET,
                core_levels.definition.DEBUG,
                core_levels.definition.INFO,
                core_levels.definition.WARNING,
                core_levels.definition.ERROR,
                core_levels.definition.CRITICAL,
                core_levels.definition.NONE
            }

            for _, level in ipairs(valid_levels) do
                assert.has_no_error(function()
                    lual.config({ level = level })
                end, "Should accept level " .. level)
            end
        end)

        it("should reject invalid propagate type", function()
            assert.has_error(function()
                    lual.config({
                        propagate = 1 -- Should be boolean, not number
                    })
                end,
                "Invalid configuration: Invalid type for 'propagate': expected boolean, got number. Whether to propagate messages (always true for root)")
        end)

        it("should reject invalid outputs type", function()
            assert.has_error(function()
                    lual.config({
                        outputs = 123
                    })
                end,
                "Invalid configuration: Invalid type for 'outputs': expected table, got number. Array of output functions or configuration tables")
        end)

        it("should accept empty outputs array", function()
            assert.has_no_error(function()
                lual.config({
                    outputs = {}
                })
            end)
        end)

        it("should accept valid outputs array", function()
            local mock_output1 = function() end
            local mock_output2 = function() end

            assert.has_no_error(function()
                lual.config({
                    outputs = { mock_output1, mock_output2 }
                })
            end)
        end)
    end)

    describe("get_config() functionality", function()
        it("should return current configuration", function()
            -- Set up a custom configuration
            local custom_output = function() end

            lual.config({
                level = core_levels.definition.DEBUG,
                outputs = { custom_output },
                propagate = false
            })

            -- Get the current configuration
            local config = lual.get_config()

            -- Verify all keys
            assert.are.equal(core_levels.definition.DEBUG, config.level)
            assert.is_false(config.propagate)

            -- Verify outputs
            assert.is_table(config.outputs)
            assert.are.equal(1, #config.outputs)
            assert_output_is_function(config.outputs[1], custom_output)

            -- Verify that modifying the returned config doesn't affect the internal state
            config.level = core_levels.definition.ERROR
            local config2 = lual.get_config()
            assert.are.equal(core_levels.definition.DEBUG, config2.level) -- Still the original value
        end)

        it("should return default configuration initially", function()
            -- Get default configuration (without setting anything)
            local config = lual.get_config()

            -- Verify default values
            assert.are.equal(core_levels.definition.WARNING, config.level)
            assert.is_true(config.propagate)

            -- Verify default output
            assert.is_table(config.outputs)
            assert.are.equal(1, #config.outputs)
            assert_output_is_function(config.outputs[1], lual.outputs.console_output)
        end)
    end)

    describe("reset_config() functionality", function()
        it("should reset configuration to defaults", function()
            -- First set a custom configuration
            local custom_output = function() end

            lual.config({
                level = core_levels.definition.DEBUG,
                outputs = { custom_output },
                propagate = false
            })

            -- Verify custom configuration is in effect
            local before_reset = lual.get_config()
            assert.are.equal(core_levels.definition.DEBUG, before_reset.level)
            assert.is_false(before_reset.propagate)
            assert.is_table(before_reset.outputs)
            assert.are.equal(1, #before_reset.outputs)
            assert_output_is_function(before_reset.outputs[1], custom_output)

            -- Reset the configuration
            lual.reset_config()

            -- Verify defaults have been restored
            local after_reset = lual.get_config()
            assert.are.equal(core_levels.definition.WARNING, after_reset.level)
            assert.is_true(after_reset.propagate)
            assert.is_table(after_reset.outputs)
            assert.are.equal(1, #after_reset.outputs)
            assert_output_is_function(after_reset.outputs[1], lual.outputs.console_output)
        end)
    end)

    describe("Integration with main lual module", function()
        it("should be accessible via lual.config", function()
            assert.is_function(lual.config)
            assert.is_function(lual.get_config)
            assert.is_function(lual.reset_config)
        end)

        it("should work through lual namespace", function()
            local updated_config = lual.config({
                level = core_levels.definition.INFO
            })

            assert.are.equal(core_levels.definition.INFO, updated_config.level)

            local retrieved_config = lual.get_config()
            assert.are.equal(core_levels.definition.INFO, retrieved_config.level)
        end)

        it("should have logger implemented", function()
            assert.is_function(lual.logger)

            -- Should be able to create loggers now
            assert.has_no_error(function()
                local logger = lual.logger("test.implemented")
                assert.is_not_nil(logger)
                assert.are.equal("test.implemented", logger.name)
            end)
        end)
    end)

    describe("Edge cases", function()
        it("should handle empty configuration table", function()
            local config_before = lual.get_config()
            local updated_config = lual.config({})
            local config_after = lual.get_config()

            -- Should be unchanged
            assert.are.same(config_before, updated_config)
            assert.are.same(config_before, config_after)
        end)

        it("should handle configuration with nil values (should not update)", function()
            lual.config({
                level = core_levels.definition.ERROR
            })

            -- This should not change the level since we're not passing it
            local updated_config = lual.config({
                propagate = false
            })

            assert.are.equal(core_levels.definition.ERROR, updated_config.level) -- Preserved
            assert.are.equal(false, updated_config.propagate)                    -- Updated
        end)
    end)
end)
