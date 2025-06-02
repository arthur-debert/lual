package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua;../lua/?.lua;../lua/?/init.lua"
local schema = require("lual.schema")
local config_schema = require("lual.schema.config_schema")

describe("Schema Validation", function()
    describe("Config validation", function()
        it("should validate a valid config", function()
            local config = {
                name = "test.logger",
                level = "info",
                propagate = true,
                dispatchers = {
                    { type = "console", presenter = "text", timezone = "utc" },
                    { type = "file",    presenter = "json", path = "test.log", timezone = "utc" }
                }
            }

            local result = schema.validate_config(config)

            assert.is_table(result)
            assert.is_table(result.data)
            assert.is_table(result._errors)
            assert.is_true(next(result._errors) == nil, "Should have no errors")
            assert.are.same(config.name, result.data.name)
            assert.are.same(config.level, result.data.level)
        end)

        it("should validate config with minimal fields", function()
            local config = {}

            local result = schema.validate_config(config)

            assert.is_table(result)
            assert.is_true(next(result._errors) == nil, "Should have no errors for empty config")
        end)

        it("should reject invalid level", function()
            local config = {
                level = "invalid_level"
            }

            local result = schema.validate_config(config)

            assert.is_not_nil(result._errors.level)
            assert.matches("Invalid level", result._errors.level)
            assert.matches("Valid values are:", result._errors.level)
        end)

        it("should reject invalid timezone in dispatcher", function()
            local config = {
                dispatchers = {
                    { type = "console", presenter = "text", timezone = "invalid_timezone" }
                }
            }

            local result = schema.validate_config(config)

            assert.is_not_nil(result._errors["dispatchers[1]"])
            assert.is_not_nil(result._errors["dispatchers[1]"].timezone)
            assert.matches("Invalid timezone", result._errors["dispatchers[1]"].timezone)
        end)

        it("should reject invalid type for name", function()
            local config = {
                name = 123
            }

            local result = schema.validate_config(config)

            assert.is_not_nil(result._errors.name)
            local expected_error = config_schema.generate_expected_error("ConfigSchema", "name", "type")
            assert.are.equal(expected_error, result._errors.name)
        end)

        it("should reject unknown fields", function()
            local config = {
                unknown_field = "value"
            }

            local result = schema.validate_config(config)

            assert.is_not_nil(result._errors.unknown_field)
            assert.matches("Unknown config key", result._errors.unknown_field)
        end)
    end)

    describe("dispatcher validation", function()
        it("should validate a valid console dispatcher", function()
            local dispatcher = {
                type = "console",
                presenter = "text"
            }

            local result = schema.validate_dispatcher(dispatcher)

            assert.is_true(next(result._errors) == nil, "Should have no errors")
            assert.are.same(dispatcher.type, result.data.type)
            assert.are.same(dispatcher.presenter, result.data.presenter)
        end)

        it("should validate a valid file dispatcher", function()
            local dispatcher = {
                type = "file",
                presenter = "json",
                path = "test.log"
            }

            local result = schema.validate_dispatcher(dispatcher)

            assert.is_true(next(result._errors) == nil, "Should have no errors")
            assert.are.same(dispatcher.path, result.data.path)
        end)

        it("should require type field", function()
            local dispatcher = {
                presenter = "text"
            }

            local result = schema.validate_dispatcher(dispatcher)

            assert.is_not_nil(result._errors.type)
            local expected_error = config_schema.generate_expected_error("dispatcherschema", "type", "required")
            assert.are.equal(expected_error, result._errors.type)
        end)

        it("should require presenter field", function()
            local dispatcher = {
                type = "console"
            }

            local result = schema.validate_dispatcher(dispatcher)

            assert.is_not_nil(result._errors.presenter)
            local expected_error = config_schema.generate_expected_error("dispatcherschema", "presenter", "required")
            assert.are.equal(expected_error, result._errors.presenter)
        end)

        it("should require path for file dispatchers", function()
            local dispatcher = {
                type = "file",
                presenter = "text"
            }

            local result = schema.validate_dispatcher(dispatcher)

            assert.is_not_nil(result._errors.path)
            local expected_error = config_schema.generate_expected_error("dispatcherschema", "path", "conditional")
            assert.are.equal(expected_error, result._errors.path)
        end)

        it("should reject invalid dispatcher type", function()
            local dispatcher = {
                type = "invalid",
                presenter = "text"
            }

            local result = schema.validate_dispatcher(dispatcher)

            assert.is_not_nil(result._errors.type)
            local expected_error = config_schema.generate_expected_error("dispatcherschema", "type", "invalid_value",
                "invalid")
            assert.are.equal(expected_error, result._errors.type)
        end)

        it("should reject invalid presenter type", function()
            local dispatcher = {
                type = "console",
                presenter = "invalid"
            }

            local result = schema.validate_dispatcher(dispatcher)

            assert.is_not_nil(result._errors.presenter)
            local expected_error = config_schema.generate_expected_error("dispatcherschema", "presenter", "invalid_value",
                "invalid")
            assert.are.equal(expected_error, result._errors.presenter)
        end)
    end)

    describe("Nested validation", function()
        it("should validate nested dispatchers array", function()
            local config = {
                dispatchers = {
                    { type = "console", presenter = "text" },
                    { type = "file",    presenter = "json", path = "test.log" }
                }
            }

            local result = schema.validate_config(config)

            assert.is_true(next(result._errors) == nil, "Should have no errors")
            assert.are.same(2, #result.data.dispatchers)
        end)

        it("should report errors in nested dispatchers", function()
            local config = {
                dispatchers = {
                    { type = "console", presenter = "text" },
                    { type = "invalid", presenter = "text" }
                }
            }

            local result = schema.validate_config(config)

            assert.is_not_nil(result._errors["dispatchers[2]"])
            assert.is_not_nil(result._errors["dispatchers[2]"].type)
            assert.matches("Invalid dispatcher type", result._errors["dispatchers[2]"].type)
        end)
    end)

    describe("Case insensitive validation", function()
        it("should accept case insensitive level values", function()
            local config = {
                level = "INFO"
            }

            local result = schema.validate_config(config)

            assert.is_true(next(result._errors) == nil, "Should accept uppercase level")
        end)

        it("should accept case insensitive timezone values in dispatcher", function()
            local config = {
                dispatchers = {
                    { type = "console", presenter = "text", timezone = "UTC" }
                }
            }

            local result = schema.validate_config(config)

            assert.is_true(next(result._errors) == nil, "Should accept uppercase timezone")
        end)
    end)
end)
