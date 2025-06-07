local live_level = require("lual.config.live_level")
local lual = require("lual")
local schemer = require("lual.utils.schemer")

-- Helper function to get detailed validation errors for testing
local function get_live_level_validation_error(config_table)
    local live_level_schema = {
        fields = {
            env_var = { type = "string", required = false },
            check_interval = { type = "number", required = false, min = 1 },
            enabled = { type = "boolean", required = false }
        }
    }
    local errors = schemer.validate(config_table, live_level_schema)
    return errors
end

-- Mock environment variable for testing
local mock_env = {}
local function mock_getenv(name)
    return mock_env[name]
end

describe("Live level changes", function()
    before_each(function()
        lual.reset_config()
        live_level.reset()
        mock_env = {}
        live_level.set_env_func(mock_getenv)
    end)

    after_each(function()
        lual.reset_config()
        live_level.reset()
        mock_env = {}
    end)

    describe("validation", function()
        it("validates that config is a table", function()
            local result, msg = live_level.validate("not a table")
            assert.is_false(result)
            assert.matches("must be a table", msg)
        end)

        it("validates env_var type", function()
            local result, msg = live_level.validate({ env_var = 123 })
            assert.is_false(result)

            -- Test specific error code
            local error_info = get_live_level_validation_error({ env_var = 123 })
            assert.is_not_nil(error_info)
            assert.is_not_nil(error_info.fields)
            assert.is_not_nil(error_info.fields.env_var)
            assert.are.equal("INVALID_TYPE", error_info.fields.env_var[1][1])
        end)

        it("validates check_interval type", function()
            local result, msg = live_level.validate({ check_interval = "not a number" })
            assert.is_false(result)

            -- Test specific error code
            local error_info = get_live_level_validation_error({ check_interval = "not a number" })
            assert.is_not_nil(error_info)
            assert.is_not_nil(error_info.fields)
            assert.is_not_nil(error_info.fields.check_interval)
            assert.are.equal("INVALID_TYPE", error_info.fields.check_interval[1][1])
        end)

        it("validates check_interval minimum value", function()
            local result, msg = live_level.validate({ check_interval = 0 })
            assert.is_false(result)

            -- Test specific error code
            local error_info = get_live_level_validation_error({ check_interval = 0 })
            assert.is_not_nil(error_info)
            assert.is_not_nil(error_info.fields)
            assert.is_not_nil(error_info.fields.check_interval)
            assert.are.equal("NUMBER_TOO_SMALL", error_info.fields.check_interval[1][1])
        end)

        it("validates enabled type", function()
            local result, msg = live_level.validate({ enabled = "not a boolean" })
            assert.is_false(result)

            -- Test specific error code
            local error_info = get_live_level_validation_error({ enabled = "not a boolean" })
            assert.is_not_nil(error_info)
            assert.is_not_nil(error_info.fields)
            assert.is_not_nil(error_info.fields.enabled)
            assert.are.equal("INVALID_TYPE", error_info.fields.enabled[1][1])
        end)

        it("validates a proper config", function()
            local result = live_level.validate({
                env_var = "LOG_LEVEL",
                check_interval = 10,
                enabled = true
            })
            assert.is_true(result)
        end)
    end)

    describe("normalization", function()
        it("does not set env_var when not provided", function()
            local result = live_level.normalize({})
            assert.is_nil(result.env_var)
        end)

        it("uses custom env_var when provided", function()
            local result = live_level.normalize({ env_var = "MY_LOG_LEVEL" })
            assert.equals("MY_LOG_LEVEL", result.env_var)
        end)

        it("uses default check_interval when not provided", function()
            local result = live_level.normalize({})
            assert.equals(100, result.check_interval)
        end)

        it("uses custom check_interval when provided", function()
            local result = live_level.normalize({ check_interval = 50 })
            assert.equals(50, result.check_interval)
        end)

        it("defaults enabled based on env_var", function()
            local result1 = live_level.normalize({})
            assert.is_false(result1.enabled)

            local result2 = live_level.normalize({ env_var = "TEST" })
            assert.is_true(result2.enabled)
        end)

        it("uses explicit enabled value when provided", function()
            local result = live_level.normalize({ env_var = "TEST", enabled = false })
            assert.is_false(result.enabled)
        end)
    end)

    describe("level parsing", function()
        it("parses numeric levels", function()
            assert.equals(10, live_level.parse_level_value("10"))
            assert.equals(20, live_level.parse_level_value("20"))
            assert.equals(42, live_level.parse_level_value("42"))
        end)

        it("parses uppercase level names", function()
            assert.equals(lual.debug, live_level.parse_level_value("DEBUG"))
            assert.equals(lual.info, live_level.parse_level_value("INFO"))
            assert.equals(lual.warning, live_level.parse_level_value("WARNING"))
            assert.equals(lual.error, live_level.parse_level_value("ERROR"))
            assert.equals(lual.critical, live_level.parse_level_value("CRITICAL"))
        end)

        it("parses lowercase level names", function()
            assert.equals(lual.debug, live_level.parse_level_value("debug"))
            assert.equals(lual.info, live_level.parse_level_value("info"))
            assert.equals(lual.warning, live_level.parse_level_value("warning"))
            assert.equals(lual.error, live_level.parse_level_value("error"))
            assert.equals(lual.critical, live_level.parse_level_value("critical"))
        end)

        it("returns nil for invalid values", function()
            assert.is_nil(live_level.parse_level_value(nil))
            assert.is_nil(live_level.parse_level_value(""))
            assert.is_nil(live_level.parse_level_value("not_a_level"))
            assert.is_nil(live_level.parse_level_value("abc123"))
        end)
    end)

    describe("level change detection", function()
        it("returns false when disabled", function()
            live_level.apply({ enabled = false, env_var = "TEST" }, {})
            mock_env.TEST = "debug"
            local changed, level = live_level.check_level_change({})
            assert.is_false(changed)
            assert.is_nil(level)
        end)

        it("returns false when no env_var is set", function()
            live_level.apply({ enabled = true, env_var = nil }, {})
            local changed, level = live_level.check_level_change({})
            assert.is_false(changed)
            assert.is_nil(level)
        end)

        it("only checks on interval", function()
            live_level.apply({ enabled = true, env_var = "TEST", check_interval = 10 }, {})
            mock_env.TEST = "debug"

            -- First 9 calls should not check
            for i = 1, 9 do
                local changed, _ = live_level.check_level_change({})
                assert.is_false(changed)
            end

            -- 10th call should check and detect the change
            local changed, level = live_level.check_level_change({})
            assert.is_true(changed)
            assert.equals(lual.debug, level)
        end)

        it("detects level changes", function()
            live_level.apply({ enabled = true, env_var = "TEST", check_interval = 1 }, {})

            -- No value initially
            local changed1, level1 = live_level.check_level_change({})
            assert.is_false(changed1)
            assert.is_nil(level1)

            -- Set to debug
            mock_env.TEST = "debug"
            local changed2, level2 = live_level.check_level_change({})
            assert.is_true(changed2)
            assert.equals(lual.debug, level2)

            -- No change
            local changed3, level3 = live_level.check_level_change({})
            assert.is_false(changed3)
            assert.is_nil(level3)

            -- Change to info
            mock_env.TEST = "info"
            local changed4, level4 = live_level.check_level_change({})
            assert.is_true(changed4)
            assert.equals(lual.info, level4)

            -- Change to numeric value
            mock_env.TEST = "42"
            local changed5, level5 = live_level.check_level_change({})
            assert.is_true(changed5)
            assert.equals(42, level5)
        end)

        it("ignores invalid level values", function()
            live_level.apply({ enabled = true, env_var = "TEST", check_interval = 1 }, {})

            -- Invalid value
            mock_env.TEST = "not_a_level"
            local changed, level = live_level.check_level_change({})
            assert.is_false(changed)
            assert.is_nil(level)
        end)
    end)

    describe("integration", function()
        it("changes root logger level via config", function()
            -- Initial root level is WARNING
            assert.equals(lual.warning, lual.get_config().level)

            -- Configure live level with mock env
            lual.config({
                live_level = {
                    env_var = "TEST_LEVEL",
                    check_interval = 1,
                    enabled = true
                }
            })

            -- No change initially
            local logger = lual.logger("test")
            logger:warn("Test message")
            assert.equals(lual.warning, lual.get_config().level)

            -- Set env var to debug
            mock_env.TEST_LEVEL = "debug"

            -- Log to trigger check
            logger:warn("This should trigger a level change")

            -- Level should be changed to DEBUG
            assert.equals(lual.debug, lual.get_config().level)
        end)

        it("applies initial env value", function()
            -- Set env var before config
            mock_env.TEST_LEVEL = "debug"

            -- Configure live level
            lual.config({
                live_level = {
                    env_var = "TEST_LEVEL",
                    enabled = true
                }
            })

            -- Level should be immediately set to DEBUG
            assert.equals(lual.debug, lual.get_config().level)
        end)

        it("works with convenience function", function()
            -- Initial root level is WARNING
            assert.equals(lual.warning, lual.get_config().level)

            -- Use convenience function
            lual.set_live_level("TEST_LEVEL", 1)

            -- Set env var to info
            mock_env.TEST_LEVEL = "info"

            -- Log to trigger check
            local logger = lual.logger("test")
            logger:warn("This should trigger a level change")

            -- Level should be changed to INFO
            assert.equals(lual.info, lual.get_config().level)
        end)

        it("handles numeric custom levels", function()
            -- Set env var to a custom numeric level
            mock_env.TEST_LEVEL = "25"

            -- Configure live level
            lual.set_live_level("TEST_LEVEL", 1)

            -- Log to trigger check
            local logger = lual.logger("test")
            logger:warn("This should trigger a level change")

            -- Level should be changed to 25
            assert.equals(25, lual.get_config().level)
        end)
    end)
end)
