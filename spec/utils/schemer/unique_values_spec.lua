local schemer = require("lual.utils.schemer")

describe("schemer unique_values validation", function()
    describe("basic uniqueness validation", function()
        it("should pass when all values are unique", function()
            local schema = {
                fields = {
                    levels = {
                        type = "table",
                        unique_values = true
                    }
                }
            }

            local data = { levels = { debug = 10, info = 20, warn = 30, error = 40 } }
            local err, result = schemer.validate(data, schema)
            assert.is_nil(err)
            assert.are.same(data, result)
        end)

        it("should fail when duplicate values exist", function()
            local schema = {
                fields = {
                    levels = {
                        type = "table",
                        unique_values = true
                    }
                }
            }

            local data = { levels = { debug = 10, info = 20, warn = 20, error = 40 } }
            local err, result = schemer.validate(data, schema)
            assert.is_not_nil(err)
            assert.is_not_nil(err.fields.levels)
            assert.are.equal(schemer.ERROR_CODES.DUPLICATE_VALUE, err.fields.levels[1][1])
            assert.matches("duplicate value '20'", err.fields.levels[1][2])
            -- Both keys should be mentioned in the error message
            assert.matches("'info'", err.fields.levels[1][2])
            assert.matches("'warn'", err.fields.levels[1][2])
        end)

        it("should work with array-style tables", function()
            local schema = {
                fields = {
                    items = {
                        type = "table",
                        unique_values = true
                    }
                }
            }

            local data = { items = { "apple", "banana", "cherry" } }
            local err, result = schemer.validate(data, schema)
            assert.is_nil(err)
            assert.are.same(data, result)
        end)

        it("should detect duplicates in array-style tables", function()
            local schema = {
                fields = {
                    items = {
                        type = "table",
                        unique_values = true
                    }
                }
            }

            local data = { items = { "apple", "banana", "apple" } }
            local err, result = schemer.validate(data, schema)
            assert.is_not_nil(err)
            assert.is_not_nil(err.fields.items)
            assert.are.equal(schemer.ERROR_CODES.DUPLICATE_VALUE, err.fields.items[1][1])
            assert.matches("duplicate value 'apple'", err.fields.items[1][2])
            -- Both indices should be mentioned in the error message
            assert.matches("'1'", err.fields.items[1][2])
            assert.matches("'3'", err.fields.items[1][2])
        end)
    end)

    describe("different value types", function()
        it("should work with numeric values", function()
            local schema = {
                fields = {
                    numbers = {
                        type = "table",
                        unique_values = true
                    }
                }
            }

            local data = { numbers = { 1, 2, 3, 4, 5 } }
            local err, result = schemer.validate(data, schema)
            assert.is_nil(err)

            -- Test with duplicates
            data = { numbers = { 1, 2, 3, 2, 5 } }
            err, result = schemer.validate(data, schema)
            assert.is_not_nil(err)
            assert.are.equal(schemer.ERROR_CODES.DUPLICATE_VALUE, err.fields.numbers[1][1])
        end)

        it("should work with boolean values", function()
            local schema = {
                fields = {
                    flags = {
                        type = "table",
                        unique_values = true
                    }
                }
            }

            local data = { flags = { a = true, b = false } }
            local err, result = schemer.validate(data, schema)
            assert.is_nil(err)

            -- Test with duplicates
            data = { flags = { a = true, b = false, c = true } }
            err, result = schemer.validate(data, schema)
            assert.is_not_nil(err)
            assert.are.equal(schemer.ERROR_CODES.DUPLICATE_VALUE, err.fields.flags[1][1])
        end)

        it("should work with mixed value types", function()
            local schema = {
                fields = {
                    mixed = {
                        type = "table",
                        unique_values = true
                    }
                }
            }

            local data = { mixed = { a = 1, b = "hello", c = true, d = 2.5 } }
            local err, result = schemer.validate(data, schema)
            assert.is_nil(err)

            -- Test with duplicates
            data = { mixed = { a = 1, b = "hello", c = 1 } }
            err, result = schemer.validate(data, schema)
            assert.is_not_nil(err)
            assert.are.equal(schemer.ERROR_CODES.DUPLICATE_VALUE, err.fields.mixed[1][1])
        end)
    end)

    describe("combined with other validations", function()
        it("should work with count validation", function()
            local schema = {
                fields = {
                    items = {
                        type = "table",
                        count = { 2, 5 },
                        unique_values = true
                    }
                }
            }

            local data = { items = { "a", "b", "c" } }
            local err, result = schemer.validate(data, schema)
            assert.is_nil(err)

            -- Test count violation
            data = { items = { "a" } }
            err, result = schemer.validate(data, schema)
            assert.is_not_nil(err)
            assert.are.equal(schemer.ERROR_CODES.INVALID_COUNT, err.fields.items[1][1])

            -- Test uniqueness violation
            data = { items = { "a", "b", "a" } }
            err, result = schemer.validate(data, schema)
            assert.is_not_nil(err)
            assert.are.equal(schemer.ERROR_CODES.DUPLICATE_VALUE, err.fields.items[1][1])
        end)

        it("should work with each element validation", function()
            local schema = {
                fields = {
                    numbers = {
                        type = "table",
                        unique_values = true,
                        each = { type = "number", min = 1, max = 100 }
                    }
                }
            }

            local data = { numbers = { 10, 20, 30 } }
            local err, result = schemer.validate(data, schema)
            assert.is_nil(err)

            -- Test element validation failure
            data = { numbers = { 10, 200, 30 } }
            err, result = schemer.validate(data, schema)
            assert.is_not_nil(err)
            assert.are.equal(schemer.ERROR_CODES.NUMBER_TOO_LARGE, err.fields.numbers[1][1])

            -- Test uniqueness failure
            data = { numbers = { 10, 20, 10 } }
            err, result = schemer.validate(data, schema)
            assert.is_not_nil(err)
            assert.are.equal(schemer.ERROR_CODES.DUPLICATE_VALUE, err.fields.numbers[1][1])
        end)

        it("should report both count and uniqueness errors", function()
            local schema = {
                fields = {
                    items = {
                        type = "table",
                        count = { 5, 10 },
                        unique_values = true
                    }
                }
            }

            -- Test case where both count and uniqueness fail
            local data = { items = { "a", "b", "a" } } -- Too few items + duplicate
            local err, result = schemer.validate(data, schema)
            assert.is_not_nil(err)

            -- Should have both errors
            local has_count_error = false
            local has_duplicate_error = false
            for _, error_item in ipairs(err.fields.items) do
                if error_item[1] == schemer.ERROR_CODES.INVALID_COUNT then
                    has_count_error = true
                elseif error_item[1] == schemer.ERROR_CODES.DUPLICATE_VALUE then
                    has_duplicate_error = true
                end
            end
            assert.is_true(has_count_error)
            assert.is_true(has_duplicate_error)
        end)
    end)

    describe("edge cases", function()
        it("should handle empty tables", function()
            local schema = {
                fields = {
                    empty = {
                        type = "table",
                        unique_values = true
                    }
                }
            }

            local data = { empty = {} }
            local err, result = schemer.validate(data, schema)
            assert.is_nil(err)
            assert.are.same(data, result)
        end)

        it("should handle single element", function()
            local schema = {
                fields = {
                    single = {
                        type = "table",
                        unique_values = true
                    }
                }
            }

            local data = { single = { only = "value" } }
            local err, result = schemer.validate(data, schema)
            assert.is_nil(err)
            assert.are.same(data, result)
        end)

        it("should handle nil values in table", function()
            local schema = {
                fields = {
                    with_nils = {
                        type = "table",
                        unique_values = true
                    }
                }
            }

            -- Lua tables can't actually have nil values as values (they would be removed)
            -- So this tests the boundary case
            local data = { with_nils = { a = 1, b = 2 } }
            local err, result = schemer.validate(data, schema)
            assert.is_nil(err)
        end)

        it("should handle table-type values", function()
            local schema = {
                fields = {
                    nested = {
                        type = "table",
                        unique_values = true
                    }
                }
            }

            local table1 = { x = 1 }
            local table2 = { y = 2 }
            local data = { nested = { a = table1, b = table2 } }
            local err, result = schemer.validate(data, schema)
            assert.is_nil(err)

            -- Test with same table reference (should be duplicate)
            data = { nested = { a = table1, b = table1 } }
            err, result = schemer.validate(data, schema)
            assert.is_not_nil(err)
            assert.are.equal(schemer.ERROR_CODES.DUPLICATE_VALUE, err.fields.nested[1][1])
        end)
    end)

    describe("real-world use case: level mappings", function()
        it("should validate level configuration like lual.levels", function()
            local schema = {
                fields = {
                    custom_levels = {
                        type = "table",
                        unique_values = true,
                        each = { type = "number", min = 1 }
                    }
                }
            }

            -- Valid configuration
            local data = {
                custom_levels = {
                    TRACE = 5,
                    DEBUG = 10,
                    INFO = 20,
                    WARN = 30,
                    ERROR = 40
                }
            }
            local err, result = schemer.validate(data, schema)
            assert.is_nil(err)

            -- Invalid: duplicate level values
            data = {
                custom_levels = {
                    DEBUG = 10,
                    INFO = 20,
                    VERBOSE = 10 -- Duplicate value!
                }
            }
            err, result = schemer.validate(data, schema)
            assert.is_not_nil(err)
            assert.are.equal(schemer.ERROR_CODES.DUPLICATE_VALUE, err.fields.custom_levels[1][1])
            assert.matches("duplicate value '10'", err.fields.custom_levels[1][2])
        end)
    end)
end)
