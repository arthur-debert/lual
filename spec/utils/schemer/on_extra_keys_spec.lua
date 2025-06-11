describe("schemer on_extra_keys", function()
    local schemer = require("lual.utils.schemer")

    describe("default behavior (error)", function()
        it("should error on unknown keys by default", function()
            local schema = {
                fields = {
                    name = { type = "string", required = true },
                    age = { type = "number" }
                }
            }
            local data = {
                name = "Alice",
                age = 30,
                unknown_field = "extra"
            }

            local err, result = schemer.validate(data, schema)

            assert.is_not_nil(err)
            assert.is_nil(result)
            assert.is_not_nil(err.fields.unknown_field)
            assert.are.equal(1, #err.fields.unknown_field)
            assert.are.equal(schemer.ERROR_CODES.UNKNOWN_KEY, err.fields.unknown_field[1][1])
            assert.matches("Unknown field 'unknown_field'", err.fields.unknown_field[1][2])
        end)

        it("should error on multiple unknown keys", function()
            local schema = {
                fields = {
                    name = { type = "string", required = true }
                }
            }
            local data = {
                name = "Alice",
                extra1 = "value1",
                extra2 = "value2"
            }

            local err, result = schemer.validate(data, schema)

            assert.is_not_nil(err)
            assert.is_nil(result)
            assert.is_not_nil(err.fields.extra1)
            assert.is_not_nil(err.fields.extra2)
            assert.are.equal(schemer.ERROR_CODES.UNKNOWN_KEY, err.fields.extra1[1][1])
            assert.are.equal(schemer.ERROR_CODES.UNKNOWN_KEY, err.fields.extra2[1][1])
        end)
    end)

    describe("on_extra_keys = 'error'", function()
        it("should explicitly error on unknown keys", function()
            local schema = {
                fields = {
                    name = { type = "string", required = true }
                },
                on_extra_keys = "error"
            }
            local data = {
                name = "Alice",
                unknown = "value"
            }

            local err, result = schemer.validate(data, schema)

            assert.is_not_nil(err)
            assert.is_nil(result)
            assert.is_not_nil(err.fields.unknown)
            assert.are.equal(schemer.ERROR_CODES.UNKNOWN_KEY, err.fields.unknown[1][1])
        end)

        it("should error on unknown keys even when other validation passes", function()
            local schema = {
                fields = {
                    name = { type = "string", default = "default_name" }
                },
                on_extra_keys = "error"
            }
            local data = {
                unknown = "value"
            }

            local err, result = schemer.validate(data, schema)

            assert.is_not_nil(err)
            assert.is_nil(result)
            assert.is_not_nil(err.fields.unknown)
            assert.are.equal(schemer.ERROR_CODES.UNKNOWN_KEY, err.fields.unknown[1][1])
        end)
    end)

    describe("on_extra_keys = 'ignore'", function()
        it("should ignore unknown keys and keep them in result", function()
            local schema = {
                fields = {
                    name = { type = "string", required = true },
                    age = { type = "number" }
                },
                on_extra_keys = "ignore"
            }
            local data = {
                name = "Alice",
                age = 30,
                extra_field = "extra_value",
                another_extra = 42
            }

            local err, result = schemer.validate(data, schema)

            assert.is_nil(err)
            assert.is_not_nil(result)
            assert.are.equal("Alice", result.name)
            assert.are.equal(30, result.age)
            assert.are.equal("extra_value", result.extra_field)
            assert.are.equal(42, result.another_extra)
        end)

        it("should ignore unknown keys while applying defaults", function()
            local schema = {
                fields = {
                    name = { type = "string", default = "default_name" },
                    enabled = { type = "boolean", default = true }
                },
                on_extra_keys = "ignore"
            }
            local data = {
                extra1 = "value1",
                extra2 = false
            }

            local err, result = schemer.validate(data, schema)

            assert.is_nil(err)
            assert.is_not_nil(result)
            assert.are.equal("default_name", result.name)
            assert.are.equal(true, result.enabled)
            assert.are.equal("value1", result.extra1)
            assert.are.equal(false, result.extra2)
        end)

        it("should ignore unknown keys while still validating known fields", function()
            local schema = {
                fields = {
                    age = { type = "number", required = true }
                },
                on_extra_keys = "ignore"
            }
            local data = {
                age = "invalid_type",
                extra = "value"
            }

            local err, result = schemer.validate(data, schema)

            assert.is_not_nil(err)
            assert.is_nil(result)
            assert.is_not_nil(err.fields.age)
            assert.are.equal(schemer.ERROR_CODES.INVALID_TYPE, err.fields.age[1][1])
            -- Should not have error for the extra field
            assert.is_nil(err.fields.extra)
        end)
    end)

    describe("on_extra_keys = 'remove'", function()
        it("should remove unknown keys from result", function()
            local schema = {
                fields = {
                    name = { type = "string", required = true },
                    age = { type = "number" }
                },
                on_extra_keys = "remove"
            }
            local data = {
                name = "Alice",
                age = 30,
                extra_field = "extra_value",
                another_extra = 42
            }

            local err, result = schemer.validate(data, schema)

            assert.is_nil(err)
            assert.is_not_nil(result)
            assert.are.equal("Alice", result.name)
            assert.are.equal(30, result.age)
            assert.is_nil(result.extra_field)
            assert.is_nil(result.another_extra)
        end)

        it("should remove unknown keys while applying defaults", function()
            local schema = {
                fields = {
                    name = { type = "string", default = "default_name" },
                    enabled = { type = "boolean", default = true }
                },
                on_extra_keys = "remove"
            }
            local data = {
                extra1 = "value1",
                extra2 = false
            }

            local err, result = schemer.validate(data, schema)

            assert.is_nil(err)
            assert.is_not_nil(result)
            assert.are.equal("default_name", result.name)
            assert.are.equal(true, result.enabled)
            assert.is_nil(result.extra1)
            assert.is_nil(result.extra2)
        end)

        it("should remove unknown keys while still validating known fields", function()
            local schema = {
                fields = {
                    age = { type = "number", required = true }
                },
                on_extra_keys = "remove"
            }
            local data = {
                age = "invalid_type",
                extra = "value"
            }

            local err, result = schemer.validate(data, schema)

            assert.is_not_nil(err)
            assert.is_nil(result)
            assert.is_not_nil(err.fields.age)
            assert.are.equal(schemer.ERROR_CODES.INVALID_TYPE, err.fields.age[1][1])
            -- Should not have error for the extra field
            assert.is_nil(err.fields.extra)
        end)

        it("should succeed when only unknown keys are present", function()
            local schema = {
                fields = {
                    name = { type = "string", default = "default_name" }
                },
                on_extra_keys = "remove"
            }
            local data = {
                extra1 = "value1",
                extra2 = "value2"
            }

            local err, result = schemer.validate(data, schema)

            assert.is_nil(err)
            assert.is_not_nil(result)
            assert.are.equal("default_name", result.name)
            assert.is_nil(result.extra1)
            assert.is_nil(result.extra2)
        end)
    end)

    describe("edge cases", function()
        it("should handle empty data with on_extra_keys = 'ignore'", function()
            local schema = {
                fields = {
                    name = { type = "string", default = "default" }
                },
                on_extra_keys = "ignore"
            }
            local data = {}

            local err, result = schemer.validate(data, schema)

            assert.is_nil(err)
            assert.is_not_nil(result)
            assert.are.equal("default", result.name)
        end)

        it("should handle empty data with on_extra_keys = 'remove'", function()
            local schema = {
                fields = {
                    name = { type = "string", default = "default" }
                },
                on_extra_keys = "remove"
            }
            local data = {}

            local err, result = schemer.validate(data, schema)

            assert.is_nil(err)
            assert.is_not_nil(result)
            assert.are.equal("default", result.name)
        end)

        it("should handle schema with no fields defined", function()
            local schema = {
                on_extra_keys = "ignore"
            }
            local data = {
                anything = "value",
                whatever = 42
            }

            local err, result = schemer.validate(data, schema)

            assert.is_nil(err)
            assert.is_not_nil(result)
            assert.are.equal("value", result.anything)
            assert.are.equal(42, result.whatever)
        end)

        it("should work with cross-field validations and extra keys", function()
            local schema = {
                fields = {
                    field_a = { type = "string" },
                    field_b = { type = "string" }
                },
                one_of = { "field_a", "field_b" },
                on_extra_keys = "ignore"
            }
            local data = {
                field_a = "value",
                extra = "ignored"
            }

            local err, result = schemer.validate(data, schema)

            assert.is_nil(err)
            assert.is_not_nil(result)
            assert.are.equal("value", result.field_a)
            assert.are.equal("ignored", result.extra)
        end)

        it("should work with nested field validation", function()
            local schema = {
                fields = {
                    config = {
                        type = "table",
                        fields = {
                            name = { type = "string", required = true }
                        }
                    }
                },
                on_extra_keys = "remove"
            }
            local data = {
                config = {
                    name = "test",
                    nested_extra = "causes_error"
                },
                top_level_extra = "removed"
            }

            local err, result = schemer.validate(data, schema)

            -- Nested validation should fail because nested schemas use default "error" behavior
            assert.is_not_nil(err)
            assert.is_nil(result)
            assert.is_not_nil(err.fields.config)
            assert.matches("config.nested_extra", err.fields.config[1][2])
        end)
    end)

    describe("invalid on_extra_keys values", function()
        it("should treat invalid on_extra_keys value as 'error'", function()
            local schema = {
                fields = {
                    name = { type = "string", required = true }
                },
                on_extra_keys = "invalid_value"
            }
            local data = {
                name = "Alice",
                extra = "value"
            }

            local err, result = schemer.validate(data, schema)

            -- Should behave like "error" mode for unknown values
            assert.is_not_nil(err)
            assert.is_nil(result)
            assert.is_not_nil(err.fields.extra)
            assert.are.equal(schemer.ERROR_CODES.UNKNOWN_KEY, err.fields.extra[1][1])
        end)
    end)
end)
