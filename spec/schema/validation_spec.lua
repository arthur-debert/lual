package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua;../lua/?.lua;../lua/?/init.lua"
local schema = require("lual.schema")

describe("Schema Validation", function()
    describe("Config validation", function()
        it("should validate a valid config", function()
            local config = {
                name = "test.logger",
                level = "info",
                propagate = true,
                timezone = "utc",
                outputs = {
                    { type = "console", formatter = "text" },
                    { type = "file",    formatter = "json", path = "test.log" }
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
        end)

        it("should reject invalid timezone", function()
            local config = {
                timezone = "invalid_timezone"
            }

            local result = schema.validate_config(config)

            assert.is_not_nil(result._errors.timezone)
            assert.matches("Invalid timezone", result._errors.timezone)
        end)

        it("should reject invalid type for name", function()
            local config = {
                name = 123
            }

            local result = schema.validate_config(config)

            assert.is_not_nil(result._errors.name)
            assert.matches("Name must be a string", result._errors.name)
        end)

        it("should reject unknown fields", function()
            local config = {
                unknown_field = "value"
            }

            local result = schema.validate_config(config)

            assert.is_not_nil(result._errors.unknown_field)
            assert.matches("Unknown field", result._errors.unknown_field)
        end)
    end)

    describe("Output validation", function()
        it("should validate a valid console output", function()
            local output = {
                type = "console",
                formatter = "text"
            }

            local result = schema.validate_output(output)

            assert.is_true(next(result._errors) == nil, "Should have no errors")
            assert.are.same(output.type, result.data.type)
            assert.are.same(output.formatter, result.data.formatter)
        end)

        it("should validate a valid file output", function()
            local output = {
                type = "file",
                formatter = "json",
                path = "test.log"
            }

            local result = schema.validate_output(output)

            assert.is_true(next(result._errors) == nil, "Should have no errors")
            assert.are.same(output.path, result.data.path)
        end)

        it("should require type field", function()
            local output = {
                formatter = "text"
            }

            local result = schema.validate_output(output)

            assert.is_not_nil(result._errors.type)
            assert.matches("Type is required", result._errors.type)
        end)

        it("should require formatter field", function()
            local output = {
                type = "console"
            }

            local result = schema.validate_output(output)

            assert.is_not_nil(result._errors.formatter)
            assert.matches("Formatter is required", result._errors.formatter)
        end)

        it("should require path for file outputs", function()
            local output = {
                type = "file",
                formatter = "text"
            }

            local result = schema.validate_output(output)

            assert.is_not_nil(result._errors.path)
            assert.matches("Path is required when type is file", result._errors.path)
        end)

        it("should reject invalid output type", function()
            local output = {
                type = "invalid",
                formatter = "text"
            }

            local result = schema.validate_output(output)

            assert.is_not_nil(result._errors.type)
            assert.matches("Invalid type", result._errors.type)
        end)

        it("should reject invalid formatter type", function()
            local output = {
                type = "console",
                formatter = "invalid"
            }

            local result = schema.validate_output(output)

            assert.is_not_nil(result._errors.formatter)
            assert.matches("Invalid formatter", result._errors.formatter)
        end)
    end)

    describe("Nested validation", function()
        it("should validate nested outputs array", function()
            local config = {
                outputs = {
                    { type = "console", formatter = "text" },
                    { type = "file",    formatter = "json", path = "test.log" }
                }
            }

            local result = schema.validate_config(config)

            assert.is_true(next(result._errors) == nil, "Should have no errors")
            assert.are.same(2, #result.data.outputs)
        end)

        it("should report errors in nested outputs", function()
            local config = {
                outputs = {
                    { type = "console", formatter = "text" },
                    { type = "invalid", formatter = "text" }
                }
            }

            local result = schema.validate_config(config)

            assert.is_not_nil(result._errors["outputs[2]"])
            assert.is_not_nil(result._errors["outputs[2]"].type)
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

        it("should accept case insensitive timezone values", function()
            local config = {
                timezone = "UTC"
            }

            local result = schema.validate_config(config)

            assert.is_true(next(result._errors) == nil, "Should accept uppercase timezone")
        end)
    end)
end)
