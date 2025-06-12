#!/usr/bin/env lua

local schemer = require("lual.utils.schemer")

describe("schemer basic validation", function()
    describe("type validation", function()
        it("should validate string type", function()
            local schema = {
                fields = {
                    name = { type = "string" }
                }
            }

            local data = { name = "John" }
            local err, result = schemer.validate(data, schema)
            assert.is_nil(err)
            assert.are.same(data, result)
        end)

        it("should validate number type", function()
            local schema = {
                fields = {
                    age = { type = "number" }
                }
            }

            local data = { age = 25 }
            local err, result = schemer.validate(data, schema)
            assert.is_nil(err)
            assert.are.same(data, result)
        end)

        it("should validate boolean type", function()
            local schema = {
                fields = {
                    active = { type = "boolean" }
                }
            }

            local data = { active = true }
            local err, result = schemer.validate(data, schema)
            assert.is_nil(err)
            assert.are.same(data, result)
        end)

        it("should validate table type", function()
            local schema = {
                fields = {
                    config = { type = "table" }
                }
            }

            local data = { config = {} }
            local err, result = schemer.validate(data, schema)
            assert.is_nil(err)
            assert.are.same(data, result)
        end)

        it("should validate function type", function()
            local schema = {
                fields = {
                    callback = { type = "function" }
                }
            }

            local data = { callback = function() end }
            local err, result = schemer.validate(data, schema)
            assert.is_nil(err)
            assert.are.same(data, result)
        end)

        it("should fail type validation", function()
            local schema = {
                fields = {
                    age = { type = "number" }
                }
            }

            local data = { age = "25" }
            local err, result = schemer.validate(data, schema)
            assert.is_not_nil(err)
            assert.is_not_nil(err.fields.age)
            assert.are.equal(schemer.ERROR_CODES.INVALID_TYPE, err.fields.age[1][1])
            assert.matches("must be of type number, got string", err.fields.age[1][2])
        end)
    end)

    describe("required validation", function()
        it("should pass when required field is present", function()
            local schema = {
                fields = {
                    name = { type = "string", required = true }
                }
            }

            local data = { name = "John" }
            local err, result = schemer.validate(data, schema)
            assert.is_nil(err)
            assert.are.same(data, result)
        end)

        it("should fail when required field is missing", function()
            local schema = {
                fields = {
                    name = { type = "string", required = true }
                }
            }

            local data = {}
            local err, result = schemer.validate(data, schema)
            assert.is_not_nil(err)
            assert.is_not_nil(err.fields.name)
            assert.are.equal(schemer.ERROR_CODES.REQUIRED_FIELD, err.fields.name[1][1])
            assert.matches("Field 'name' is required", err.fields.name[1][2])
        end)

        it("should pass when optional field is missing", function()
            local schema = {
                fields = {
                    name = { type = "string", required = false }
                }
            }

            local data = {}
            local err, result = schemer.validate(data, schema)
            assert.is_nil(err)
            assert.are.same(data, result)
        end)

        it("should pass when field without required flag is missing", function()
            local schema = {
                fields = {
                    name = { type = "string" }
                }
            }

            local data = {}
            local err, result = schemer.validate(data, schema)
            assert.is_nil(err)
            assert.are.same(data, result)
        end)
    end)

    describe("default values", function()
        it("should apply default when field is missing", function()
            local schema = {
                fields = {
                    status = { type = "string", default = "active" }
                }
            }

            local data = {}
            local err, result = schemer.validate(data, schema)
            assert.is_nil(err)
            assert.are.equal("active", result.status)
        end)

        it("should not apply default when field is present", function()
            local schema = {
                fields = {
                    status = { type = "string", default = "active" }
                }
            }

            local data = { status = "inactive" }
            local err, result = schemer.validate(data, schema)
            assert.is_nil(err)
            assert.are.equal("inactive", result.status)
        end)

        it("should apply numeric default", function()
            local schema = {
                fields = {
                    count = { type = "number", default = 10 }
                }
            }

            local data = {}
            local err, result = schemer.validate(data, schema)
            assert.is_nil(err)
            assert.are.equal(10, result.count)
        end)

        it("should apply boolean default", function()
            local schema = {
                fields = {
                    enabled = { type = "boolean", default = true }
                }
            }

            local data = {}
            local err, result = schemer.validate(data, schema)
            assert.is_nil(err)
            assert.is_true(result.enabled)
        end)
    end)

    describe("string validation", function()
        it("should validate minimum length", function()
            local schema = {
                fields = {
                    name = { type = "string", min_len = 3 }
                }
            }

            local data = { name = "John" }
            local err, result = schemer.validate(data, schema)
            assert.is_nil(err)
            assert.are.same(data, result)
        end)

        it("should fail minimum length validation", function()
            local schema = {
                fields = {
                    name = { type = "string", min_len = 5 }
                }
            }

            local data = { name = "Jo" }
            local err, result = schemer.validate(data, schema)
            assert.is_not_nil(err)
            assert.is_not_nil(err.fields.name)
            assert.are.equal(schemer.ERROR_CODES.STRING_TOO_SHORT, err.fields.name[1][1])
            assert.matches("must be at least 5 characters long", err.fields.name[1][2])
        end)

        it("should validate maximum length", function()
            local schema = {
                fields = {
                    name = { type = "string", max_len = 10 }
                }
            }

            local data = { name = "John" }
            local err, result = schemer.validate(data, schema)
            assert.is_nil(err)
            assert.are.same(data, result)
        end)

        it("should fail maximum length validation", function()
            local schema = {
                fields = {
                    name = { type = "string", max_len = 3 }
                }
            }

            local data = { name = "John" }
            local err, result = schemer.validate(data, schema)
            assert.is_not_nil(err)
            assert.is_not_nil(err.fields.name)
            assert.are.equal(schemer.ERROR_CODES.STRING_TOO_LONG, err.fields.name[1][1])
            assert.matches("must be at most 3 characters long", err.fields.name[1][2])
        end)

        it("should validate pattern", function()
            local schema = {
                fields = {
                    email = { type = "string", pattern = "^[%w%.]+@[%w%.]+%.[%w]+$" }
                }
            }

            local data = { email = "user@example.com" }
            local err, result = schemer.validate(data, schema)
            assert.is_nil(err)
            assert.are.same(data, result)
        end)

        it("should fail pattern validation", function()
            local schema = {
                fields = {
                    email = { type = "string", pattern = "^[%w%.]+@[%w%.]+%.[%w]+$" }
                }
            }

            local data = { email = "invalid-email" }
            local err, result = schemer.validate(data, schema)
            assert.is_not_nil(err)
            assert.is_not_nil(err.fields.email)
            assert.are.equal(schemer.ERROR_CODES.PATTERN_MISMATCH, err.fields.email[1][1])
            assert.matches("does not match required pattern", err.fields.email[1][2])
        end)

        it("should combine string validations", function()
            local schema = {
                fields = {
                    username = {
                        type = "string",
                        min_len = 3,
                        max_len = 15,
                        pattern = "^%w+$"
                    }
                }
            }

            local data = { username = "john123" }
            local err, result = schemer.validate(data, schema)
            assert.is_nil(err)
            assert.are.same(data, result)
        end)
    end)

    describe("number validation", function()
        it("should validate minimum value", function()
            local schema = {
                fields = {
                    age = { type = "number", min = 18 }
                }
            }

            local data = { age = 25 }
            local err, result = schemer.validate(data, schema)
            assert.is_nil(err)
            assert.are.same(data, result)
        end)

        it("should fail minimum value validation", function()
            local schema = {
                fields = {
                    age = { type = "number", min = 18 }
                }
            }

            local data = { age = 16 }
            local err, result = schemer.validate(data, schema)
            assert.is_not_nil(err)
            assert.is_not_nil(err.fields.age)
            assert.are.equal(schemer.ERROR_CODES.NUMBER_TOO_SMALL, err.fields.age[1][1])
            assert.matches("must be at least 18", err.fields.age[1][2])
        end)

        it("should validate maximum value", function()
            local schema = {
                fields = {
                    percentage = { type = "number", max = 100 }
                }
            }

            local data = { percentage = 85 }
            local err, result = schemer.validate(data, schema)
            assert.is_nil(err)
            assert.are.same(data, result)
        end)

        it("should fail maximum value validation", function()
            local schema = {
                fields = {
                    percentage = { type = "number", max = 100 }
                }
            }

            local data = { percentage = 150 }
            local err, result = schemer.validate(data, schema)
            assert.is_not_nil(err)
            assert.is_not_nil(err.fields.percentage)
            assert.are.equal(schemer.ERROR_CODES.NUMBER_TOO_LARGE, err.fields.percentage[1][1])
            assert.matches("must be at most 100", err.fields.percentage[1][2])
        end)

        it("should validate range", function()
            local schema = {
                fields = {
                    score = { type = "number", min = 0, max = 100 }
                }
            }

            local data = { score = 85 }
            local err, result = schemer.validate(data, schema)
            assert.is_nil(err)
            assert.are.same(data, result)
        end)

        it("should accept boundary values", function()
            local schema = {
                fields = {
                    score = { type = "number", min = 0, max = 100 }
                }
            }

            local data1 = { score = 0 }
            local err1, result1 = schemer.validate(data1, schema)
            assert.is_nil(err1)
            assert.are.same(data1, result1)

            local data2 = { score = 100 }
            local err2, result2 = schemer.validate(data2, schema)
            assert.is_nil(err2)
            assert.are.same(data2, result2)
        end)
    end)

    describe("validation order and early termination", function()
        it("should fail on type mismatch before other validations", function()
            local schema = {
                fields = {
                    age = {
                        type = "number",
                        min = 18,
                        max = 65,
                        required = true
                    }
                }
            }

            local data = { age = "not a number" }
            local err, result = schemer.validate(data, schema)
            assert.is_not_nil(err)
            assert.is_not_nil(err.fields.age)
            -- Should only have type error, not min/max errors
            assert.are.equal(1, #err.fields.age)
            assert.are.equal(schemer.ERROR_CODES.INVALID_TYPE, err.fields.age[1][1])
        end)
    end)
end)
