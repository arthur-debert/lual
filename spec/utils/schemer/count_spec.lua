#!/usr/bin/env lua

local schemer = require("lual.utils.schemer")

describe("schemer count validation", function()
    describe("basic count validation", function()
        it("should validate exact count", function()
            local schema = {
                fields = {
                    items = {
                        type = "table",
                        count = { 2, 2 }
                    }
                }
            }

            local data = { items = { "a", "b" } }
            local err, result = schemer.validate(data, schema)
            assert.is_nil(err)
            assert.are.same(data, result)
        end)

        it("should fail when count is too low", function()
            local schema = {
                fields = {
                    items = {
                        type = "table",
                        count = { 2, 4 }
                    }
                }
            }

            local data = { items = { "a" } }
            local err, result = schemer.validate(data, schema)
            assert.is_not_nil(err)
            assert.is_not_nil(err.fields.items)
            assert.are.equal(schemer.ERROR_CODES.INVALID_COUNT, err.fields.items[1][1])
        end)

        it("should fail when count is too high", function()
            local schema = {
                fields = {
                    items = {
                        type = "table",
                        count = { 1, 2 }
                    }
                }
            }

            local data = { items = { "a", "b", "c" } }
            local err, result = schemer.validate(data, schema)
            assert.is_not_nil(err)
            assert.is_not_nil(err.fields.items)
            assert.are.equal(schemer.ERROR_CODES.INVALID_COUNT, err.fields.items[1][1])
        end)
    end)

    describe("count with wildcard (*)", function()
        it("should allow unlimited items with '*'", function()
            local schema = {
                fields = {
                    items = {
                        type = "table",
                        count = { 1, "*" }
                    }
                }
            }

            local data = { items = { "a", "b", "c", "d", "e" } }
            local err, result = schemer.validate(data, schema)
            assert.is_nil(err)
            assert.are.same(data, result)
        end)

        it("should enforce minimum with '*'", function()
            local schema = {
                fields = {
                    items = {
                        type = "table",
                        count = { 2, "*" }
                    }
                }
            }

            local data = { items = { "a" } }
            local err, result = schemer.validate(data, schema)
            assert.is_not_nil(err)
            assert.is_not_nil(err.fields.items)
            assert.are.equal(schemer.ERROR_CODES.INVALID_COUNT, err.fields.items[1][1])
        end)

        it("should allow zero minimum with '*'", function()
            local schema = {
                fields = {
                    items = {
                        type = "table",
                        count = { 0, "*" }
                    }
                }
            }

            local data = { items = {} }
            local err, result = schemer.validate(data, schema)
            assert.is_nil(err)
            assert.are.same(data, result)
        end)
    end)

    describe("count with each validation", function()
        it("should validate count and each element", function()
            local schema = {
                fields = {
                    items = {
                        type = "table",
                        count = { 1, 3 },
                        each = { type = "string" }
                    }
                }
            }

            local data = { items = { "a", "b" } }
            local err, result = schemer.validate(data, schema)
            assert.is_nil(err)
            assert.are.same(data, result)
        end)

        it("should fail when count is valid but elements are invalid", function()
            local schema = {
                fields = {
                    items = {
                        type = "table",
                        count = { 1, 3 },
                        each = { type = "string" }
                    }
                }
            }

            local data = { items = { "a", 123 } }
            local err, result = schemer.validate(data, schema)
            assert.is_not_nil(err)
            assert.is_not_nil(err.fields.items)
            assert.are.equal(schemer.ERROR_CODES.INVALID_TYPE, err.fields.items[1][1])
        end)

        it("should fail when elements are valid but count is invalid", function()
            local schema = {
                fields = {
                    items = {
                        type = "table",
                        count = { 1, 2 },
                        each = { type = "string" }
                    }
                }
            }

            local data = { items = { "a", "b", "c" } }
            local err, result = schemer.validate(data, schema)
            assert.is_not_nil(err)
            assert.is_not_nil(err.fields.items)
            -- Should have count error
            local has_count_error = false
            for _, error_item in ipairs(err.fields.items) do
                if error_item[1] == schemer.ERROR_CODES.INVALID_COUNT then
                    has_count_error = true
                    break
                end
            end
            assert.is_true(has_count_error)
        end)
    end)

    describe("error messages", function()
        it("should provide descriptive error message for range", function()
            local schema = {
                fields = {
                    items = {
                        type = "table",
                        count = { 2, 4 }
                    }
                }
            }

            local data = { items = { "a" } }
            local err, result = schemer.validate(data, schema)
            assert.is_not_nil(err)
            assert.is_not_nil(err.fields.items)
            assert.matches("Expected between 2 and 4 items, got 1", err.fields.items[1][2])
        end)

        it("should provide descriptive error message for minimum with wildcard", function()
            local schema = {
                fields = {
                    items = {
                        type = "table",
                        count = { 3, "*" }
                    }
                }
            }

            local data = { items = { "a", "b" } }
            local err, result = schemer.validate(data, schema)
            assert.is_not_nil(err)
            assert.is_not_nil(err.fields.items)
            assert.matches("Expected at least 3 items, got 2", err.fields.items[1][2])
        end)
    end)

    describe("edge cases", function()
        it("should handle empty table", function()
            local schema = {
                fields = {
                    items = {
                        type = "table",
                        count = { 0, 1 }
                    }
                }
            }

            local data = { items = {} }
            local err, result = schemer.validate(data, schema)
            assert.is_nil(err)
            assert.are.same(data, result)
        end)

        it("should count all table elements, not just array elements", function()
            local schema = {
                fields = {
                    items = {
                        type = "table",
                        count = { 3, 3 }
                    }
                }
            }

            local data = { items = { a = 1, b = 2, c = 3 } }
            local err, result = schemer.validate(data, schema)
            assert.is_nil(err)
            assert.are.same(data, result)
        end)

        it("should count mixed table elements", function()
            local schema = {
                fields = {
                    items = {
                        type = "table",
                        count = { 4, 4 }
                    }
                }
            }

            local data = { items = { "a", "b", x = 1, y = 2 } }
            local err, result = schemer.validate(data, schema)
            assert.is_nil(err)
            assert.are.same(data, result)
        end)
    end)
end)
