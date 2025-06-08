#!/usr/bin/env lua
package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua;../lua/?.lua;../lua/?/init.lua"

local schemer = require("lual.utils.schemer")

describe("schemer case insensitive validation", function()
    describe("simple values list with case insensitive", function()
        it("should validate case insensitive values", function()
            local schema = {
                fields = {
                    status = {
                        type = "string",
                        values = { "ACTIVE", "INACTIVE", "PENDING" },
                        case_insensitive = true
                    }
                }
            }

            local data = { status = "active" }
            local err, result = schemer.validate(data, schema)
            assert.is_nil(err)
            assert.are.equal("ACTIVE", result.status) -- Should transform to canonical case
        end)

        it("should validate exact case matches with case insensitive enabled", function()
            local schema = {
                fields = {
                    status = {
                        type = "string",
                        values = { "ACTIVE", "INACTIVE", "PENDING" },
                        case_insensitive = true
                    }
                }
            }

            local data = { status = "ACTIVE" }
            local err, result = schemer.validate(data, schema)
            assert.is_nil(err)
            assert.are.equal("ACTIVE", result.status)
        end)

        it("should validate mixed case inputs", function()
            local schema = {
                fields = {
                    status = {
                        type = "string",
                        values = { "ACTIVE", "INACTIVE", "PENDING" },
                        case_insensitive = true
                    }
                }
            }

            local test_cases = {
                { input = "Active",   expected = "ACTIVE" },
                { input = "INACTIVE", expected = "INACTIVE" },
                { input = "pending",  expected = "PENDING" },
                { input = "InAcTiVe", expected = "INACTIVE" }
            }

            for _, test_case in ipairs(test_cases) do
                local data = { status = test_case.input }
                local err, result = schemer.validate(data, schema)
                assert.is_nil(err, "Failed for input: " .. test_case.input)
                assert.are.equal(test_case.expected, result.status, "Wrong canonical value for: " .. test_case.input)
            end
        end)

        it("should fail for invalid values even with case insensitive", function()
            local schema = {
                fields = {
                    status = {
                        type = "string",
                        values = { "ACTIVE", "INACTIVE", "PENDING" },
                        case_insensitive = true
                    }
                }
            }

            local data = { status = "unknown" }
            local err, result = schemer.validate(data, schema)
            assert.is_not_nil(err)
            assert.is_not_nil(err.fields.status)
            assert.are.equal(schemer.ERROR_CODES.INVALID_VALUE, err.fields.status[1][1])
        end)

        it("should work normally when case_insensitive is false", function()
            local schema = {
                fields = {
                    status = {
                        type = "string",
                        values = { "ACTIVE", "INACTIVE", "PENDING" },
                        case_insensitive = false
                    }
                }
            }

            -- Should pass for exact match
            local data1 = { status = "ACTIVE" }
            local err1, result1 = schemer.validate(data1, schema)
            assert.is_nil(err1)
            assert.are.equal("ACTIVE", result1.status)

            -- Should fail for case mismatch
            local data2 = { status = "active" }
            local err2, result2 = schemer.validate(data2, schema)
            assert.is_not_nil(err2)
            assert.is_not_nil(err2.fields.status)
            assert.are.equal(schemer.ERROR_CODES.INVALID_VALUE, err2.fields.status[1][1])
        end)

        it("should handle non-string values correctly", function()
            local schema = {
                fields = {
                    level = {
                        type = "number",
                        values = { 1, 2, 3 },
                        case_insensitive = true -- Should be ignored for numbers
                    }
                }
            }

            local data = { level = 2 }
            local err, result = schemer.validate(data, schema)
            assert.is_nil(err)
            assert.are.equal(2, result.level)
        end)
    end)

    describe("enum with case insensitive", function()
        it("should handle case insensitive enum without reverse lookup", function()
            local LEVELS = { DEBUG = 1, INFO = 2, WARN = 3, ERROR = 4 }
            local schema = {
                fields = {
                    level = {
                        type = "number",
                        values = schemer.enum(LEVELS, { case_insensitive = true })
                    }
                }
            }

            -- Should accept exact enum values
            local data = { level = 2 }
            local err, result = schemer.validate(data, schema)
            assert.is_nil(err)
            assert.are.equal(2, result.level)
        end)

        it("should handle case insensitive enum with reverse lookup", function()
            local LEVELS = { DEBUG = 1, INFO = 2, WARN = 3, ERROR = 4 }
            local schema = {
                fields = {
                    level = {
                        type = "number",
                        values = schemer.enum(LEVELS, { reverse = true, case_insensitive = true })
                    }
                }
            }

            local test_cases = {
                { input = "debug", expected = 1 },
                { input = "DEBUG", expected = 1 },
                { input = "Info",  expected = 2 },
                { input = "WARN",  expected = 3 },
                { input = "error", expected = 4 }
            }

            for _, test_case in ipairs(test_cases) do
                local data = { level = test_case.input }
                local err, result = schemer.validate(data, schema)
                assert.is_nil(err, "Failed for input: " .. test_case.input)
                assert.are.equal(test_case.expected, result.level, "Wrong transformed value for: " .. test_case.input)
            end
        end)

        it("should fail for invalid keys with case insensitive reverse lookup", function()
            local LEVELS = { DEBUG = 1, INFO = 2, WARN = 3, ERROR = 4 }
            local schema = {
                fields = {
                    level = {
                        type = "number",
                        values = schemer.enum(LEVELS, { reverse = true, case_insensitive = true })
                    }
                }
            }

            local data = { level = "invalid" }
            local err, result = schemer.validate(data, schema)
            assert.is_not_nil(err)
            assert.is_not_nil(err.fields.level)
            assert.are.equal(schemer.ERROR_CODES.INVALID_VALUE, err.fields.level[1][1])
        end)

        it("should handle string enum values with case insensitive", function()
            local FORMATS = { JSON = "json", XML = "xml", CSV = "csv" }
            local schema = {
                fields = {
                    format = {
                        type = "string",
                        values = schemer.enum(FORMATS, { reverse = true, case_insensitive = true })
                    }
                }
            }

            local test_cases = {
                { input = "json", expected = "json" }, -- Direct value match
                { input = "JSON", expected = "json" }, -- Key match
                { input = "Json", expected = "json" }, -- Case insensitive key match
                { input = "xml",  expected = "xml" },
                { input = "XML",  expected = "xml" },
                { input = "csv",  expected = "csv" },
                { input = "CSV",  expected = "csv" }
            }

            for _, test_case in ipairs(test_cases) do
                local data = { format = test_case.input }
                local err, result = schemer.validate(data, schema)
                assert.is_nil(err, "Failed for input: " .. test_case.input)
                assert.are.equal(test_case.expected, result.format, "Wrong value for: " .. test_case.input)
            end
        end)
    end)

    describe("field-level case_insensitive property", function()
        it("should support case_insensitive at field level for simple values", function()
            local schema = {
                fields = {
                    status = {
                        type = "string",
                        values = { "ACTIVE", "INACTIVE" },
                        case_insensitive = true
                    }
                }
            }

            local data = { status = "active" }
            local err, result = schemer.validate(data, schema)
            assert.is_nil(err)
            assert.are.equal("ACTIVE", result.status)
        end)

        it("should support case_insensitive at field level for enums", function()
            local LEVELS = { DEBUG = 1, INFO = 2 }
            local schema = {
                fields = {
                    level = {
                        type = "number",
                        values = schemer.enum(LEVELS, { reverse = true }),
                        case_insensitive = true
                    }
                }
            }

            local data = { level = "debug" }
            local err, result = schemer.validate(data, schema)
            assert.is_nil(err)
            assert.are.equal(1, result.level)
        end)

        it("should prefer enum-level case_insensitive over field-level", function()
            local LEVELS = { DEBUG = 1, INFO = 2 }
            local schema = {
                fields = {
                    level = {
                        type = "number",
                        values = schemer.enum(LEVELS, { reverse = true, case_insensitive = false }),
                        case_insensitive = true -- This should be overridden by enum setting
                    }
                }
            }

            -- Should fail because enum-level case_insensitive is false
            local data = { level = "debug" }
            local err, result = schemer.validate(data, schema)
            assert.is_not_nil(err)
            assert.is_not_nil(err.fields.level)
            assert.are.equal(schemer.ERROR_CODES.INVALID_VALUE, err.fields.level[1][1])
        end)
    end)

    describe("case insensitive in array elements", function()
        it("should work with case insensitive in each element validation", function()
            local schema = {
                fields = {
                    statuses = {
                        type = "table",
                        each = {
                            type = "string",
                            values = { "ACTIVE", "INACTIVE" },
                            case_insensitive = true
                        }
                    }
                }
            }

            local data = { statuses = { "active", "INACTIVE", "Active" } }
            local err, result = schemer.validate(data, schema)
            assert.is_nil(err)
            assert.are.same({ "ACTIVE", "INACTIVE", "ACTIVE" }, result.statuses)
        end)
    end)

    describe("edge cases", function()
        it("should handle empty string values", function()
            local schema = {
                fields = {
                    value = {
                        type = "string",
                        values = { "", "EMPTY" },
                        case_insensitive = true
                    }
                }
            }

            local data = { value = "" }
            local err, result = schemer.validate(data, schema)
            assert.is_nil(err)
            assert.are.equal("", result.value)
        end)

        it("should handle unicode strings", function()
            local schema = {
                fields = {
                    greeting = {
                        type = "string",
                        values = { "HELLO", "HËLLO" },
                        case_insensitive = true
                    }
                }
            }

            local data = { greeting = "hello" }
            local err, result = schemer.validate(data, schema)
            assert.is_nil(err)
            assert.are.equal("HELLO", result.greeting)
        end)

        it("should handle mixed type enums", function()
            local MIXED = { ONE = 1, TWO = "two", THREE = 3 }
            local schema = {
                fields = {
                    value = {
                        values = schemer.enum(MIXED, { reverse = true, case_insensitive = true })
                    }
                }
            }

            -- String key
            local data1 = { value = "one" }
            local err1, result1 = schemer.validate(data1, schema)
            assert.is_nil(err1)
            assert.are.equal(1, result1.value)

            -- Direct number value
            local data2 = { value = 3 }
            local err2, result2 = schemer.validate(data2, schema)
            assert.is_nil(err2)
            assert.are.equal(3, result2.value)

            -- String value
            local data3 = { value = "two" }
            local err3, result3 = schemer.validate(data3, schema)
            assert.is_nil(err3)
            assert.are.equal("two", result3.value)
        end)
    end)
end)
