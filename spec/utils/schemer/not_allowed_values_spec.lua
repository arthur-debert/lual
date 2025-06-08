#!/usr/bin/env lua
package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua;../lua/?.lua;../lua/?/init.lua"

local schemer = require("lual.utils.schemer")

describe("schemer not_allowed_values validation", function()
    describe("basic forbidden values validation", function()
        it("should pass when value is not in forbidden list", function()
            local schema = {
                fields = {
                    port = {
                        type = "number",
                        not_allowed_values = { 22, 80, 443 }
                    }
                }
            }

            local data = { port = 8080 }
            local err, result = schemer.validate(data, schema)
            assert.is_nil(err)
            assert.are.same(data, result)
        end)

        it("should fail when value is in forbidden list", function()
            local schema = {
                fields = {
                    port = {
                        type = "number",
                        not_allowed_values = { 22, 80, 443 }
                    }
                }
            }

            local data = { port = 80 }
            local err, result = schemer.validate(data, schema)
            assert.is_not_nil(err)
            assert.is_not_nil(err.fields.port)
            assert.are.equal(schemer.ERROR_CODES.FORBIDDEN_VALUE, err.fields.port[1][1])
            assert.matches("forbidden value '80'", err.fields.port[1][2])
        end)

        it("should work with string values", function()
            local schema = {
                fields = {
                    username = {
                        type = "string",
                        not_allowed_values = { "admin", "root", "system" }
                    }
                }
            }

            -- Valid username
            local data = { username = "john_doe" }
            local err, result = schemer.validate(data, schema)
            assert.is_nil(err)

            -- Forbidden username
            data = { username = "admin" }
            err, result = schemer.validate(data, schema)
            assert.is_not_nil(err)
            assert.are.equal(schemer.ERROR_CODES.FORBIDDEN_VALUE, err.fields.username[1][1])
        end)

        it("should work with mixed value types", function()
            local schema = {
                fields = {
                    value = {
                        not_allowed_values = { 0, "null", false }
                    }
                }
            }

            -- Valid values
            local data = { value = 1 }
            local err = schemer.validate(data, schema)
            assert.is_nil(err)

            data = { value = "hello" }
            err = schemer.validate(data, schema)
            assert.is_nil(err)

            data = { value = true }
            err = schemer.validate(data, schema)
            assert.is_nil(err)

            -- Forbidden values
            data = { value = 0 }
            err = schemer.validate(data, schema)
            assert.is_not_nil(err)
            assert.are.equal(schemer.ERROR_CODES.FORBIDDEN_VALUE, err.fields.value[1][1])

            data = { value = "null" }
            err = schemer.validate(data, schema)
            assert.is_not_nil(err)
            assert.are.equal(schemer.ERROR_CODES.FORBIDDEN_VALUE, err.fields.value[1][1])

            data = { value = false }
            err = schemer.validate(data, schema)
            assert.is_not_nil(err)
            assert.are.equal(schemer.ERROR_CODES.FORBIDDEN_VALUE, err.fields.value[1][1])
        end)
    end)

    describe("case insensitive matching", function()
        it("should support case insensitive forbidden values", function()
            local schema = {
                fields = {
                    command = {
                        type = "string",
                        not_allowed_values = { "DELETE", "DROP", "TRUNCATE" },
                        case_insensitive = true
                    }
                }
            }

            -- Valid command
            local data = { command = "select" }
            local err, result = schemer.validate(data, schema)
            assert.is_nil(err)

            -- Forbidden command (case insensitive)
            data = { command = "delete" }
            err, result = schemer.validate(data, schema)
            assert.is_not_nil(err)
            assert.are.equal(schemer.ERROR_CODES.FORBIDDEN_VALUE, err.fields.command[1][1])

            data = { command = "Delete" }
            err, result = schemer.validate(data, schema)
            assert.is_not_nil(err)
            assert.are.equal(schemer.ERROR_CODES.FORBIDDEN_VALUE, err.fields.command[1][1])

            data = { command = "DELETE" }
            err, result = schemer.validate(data, schema)
            assert.is_not_nil(err)
            assert.are.equal(schemer.ERROR_CODES.FORBIDDEN_VALUE, err.fields.command[1][1])
        end)

        it("should not match case insensitively when disabled", function()
            local schema = {
                fields = {
                    command = {
                        type = "string",
                        not_allowed_values = { "DELETE", "DROP", "TRUNCATE" },
                        case_insensitive = false
                    }
                }
            }

            -- Should pass because case doesn't match
            local data = { command = "delete" }
            local err, result = schemer.validate(data, schema)
            assert.is_nil(err)

            -- Should fail because case matches exactly
            data = { command = "DELETE" }
            err, result = schemer.validate(data, schema)
            assert.is_not_nil(err)
            assert.are.equal(schemer.ERROR_CODES.FORBIDDEN_VALUE, err.fields.command[1][1])
        end)
    end)

    describe("interaction with other validations", function()
        it("should work with type validation", function()
            local schema = {
                fields = {
                    level = {
                        type = "number",
                        not_allowed_values = { 0, 10, 20 }
                    }
                }
            }

            -- Type error should take precedence
            local data = { level = "invalid" }
            local err, result = schemer.validate(data, schema)
            assert.is_not_nil(err)
            assert.are.equal(schemer.ERROR_CODES.INVALID_TYPE, err.fields.level[1][1])

            -- Forbidden value error
            data = { level = 10 }
            err, result = schemer.validate(data, schema)
            assert.is_not_nil(err)
            assert.are.equal(schemer.ERROR_CODES.FORBIDDEN_VALUE, err.fields.level[1][1])
        end)

        it("should work with values (allowed values)", function()
            local schema = {
                fields = {
                    status = {
                        type = "string",
                        values = { "active", "inactive", "pending", "suspended" },
                        not_allowed_values = { "suspended" } -- Can't use suspended status
                    }
                }
            }

            -- Valid allowed value
            local data = { status = "active" }
            local err, result = schemer.validate(data, schema)
            assert.is_nil(err)

            -- Invalid - not in allowed values
            data = { status = "unknown" }
            err, result = schemer.validate(data, schema)
            assert.is_not_nil(err)
            assert.are.equal(schemer.ERROR_CODES.INVALID_VALUE, err.fields.status[1][1])

            -- Invalid - in forbidden values (but also in allowed)
            data = { status = "suspended" }
            err, result = schemer.validate(data, schema)
            assert.is_not_nil(err)
            assert.are.equal(schemer.ERROR_CODES.FORBIDDEN_VALUE, err.fields.status[1][1])
        end)

        it("should work with min/max validation", function()
            local schema = {
                fields = {
                    port = {
                        type = "number",
                        min = 1,
                        max = 65535,
                        not_allowed_values = { 22, 80, 443 } -- Reserved ports
                    }
                }
            }

            -- Valid port
            local data = { port = 8080 }
            local err, result = schemer.validate(data, schema)
            assert.is_nil(err)

            -- Too small
            data = { port = 0 }
            err, result = schemer.validate(data, schema)
            assert.is_not_nil(err)
            assert.are.equal(schemer.ERROR_CODES.NUMBER_TOO_SMALL, err.fields.port[1][1])

            -- Forbidden (but in valid range)
            data = { port = 80 }
            err, result = schemer.validate(data, schema)
            assert.is_not_nil(err)
            assert.are.equal(schemer.ERROR_CODES.FORBIDDEN_VALUE, err.fields.port[1][1])
        end)
    end)

    describe("edge cases", function()
        it("should handle empty forbidden values list", function()
            local schema = {
                fields = {
                    value = {
                        type = "string",
                        not_allowed_values = {}
                    }
                }
            }

            local data = { value = "anything" }
            local err, result = schemer.validate(data, schema)
            assert.is_nil(err)
            assert.are.same(data, result)
        end)

        it("should handle nil values correctly", function()
            local schema = {
                fields = {
                    optional_field = {
                        type = "string",
                        required = false,
                        not_allowed_values = { "forbidden" }
                    }
                }
            }

            -- Nil value should not trigger forbidden validation
            local data = {}
            local err, result = schemer.validate(data, schema)
            assert.is_nil(err)
        end)

        it("should handle table values", function()
            local table1 = { x = 1 }
            local table2 = { y = 2 }
            local forbidden_table = { z = 3 }

            local schema = {
                fields = {
                    config = {
                        type = "table",
                        not_allowed_values = { forbidden_table }
                    }
                }
            }

            -- Valid table
            local data = { config = table1 }
            local err, result = schemer.validate(data, schema)
            assert.is_nil(err)

            -- Forbidden table (same reference)
            data = { config = forbidden_table }
            err, result = schemer.validate(data, schema)
            assert.is_not_nil(err)
            assert.are.equal(schemer.ERROR_CODES.FORBIDDEN_VALUE, err.fields.config[1][1])
        end)
    end)

    describe("real-world use case: level validation", function()
        it("should validate custom levels like lual.levels", function()
            -- Simulate the levels.definition built-in values
            local builtin_levels = { 0, 10, 20, 30, 40, 50, 100 }

            local schema = {
                fields = {
                    custom_level = {
                        type = "number",
                        min = 11,
                        max = 39,
                        not_allowed_values = builtin_levels -- Cannot conflict with built-ins
                    }
                }
            }

            -- Valid custom level
            local data = { custom_level = 25 }
            local err, result = schemer.validate(data, schema)
            assert.is_nil(err)

            -- Invalid: conflicts with built-in level
            data = { custom_level = 20 } -- INFO level
            err, result = schemer.validate(data, schema)
            assert.is_not_nil(err)
            assert.are.equal(schemer.ERROR_CODES.FORBIDDEN_VALUE, err.fields.custom_level[1][1])
            assert.matches("forbidden value '20'", err.fields.custom_level[1][2])

            -- Invalid: out of range
            data = { custom_level = 5 }
            err, result = schemer.validate(data, schema)
            assert.is_not_nil(err)
            assert.are.equal(schemer.ERROR_CODES.NUMBER_TOO_SMALL, err.fields.custom_level[1][1])
        end)
    end)
end)
