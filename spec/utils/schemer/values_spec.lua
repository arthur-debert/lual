#!/usr/bin/env lua
package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua;../lua/?.lua;../lua/?/init.lua"

local schemer = require("lual.utils.schemer")

describe("schemer values and enum validation", function()
    describe("simple values list", function()
        it("should validate against simple values list", function()
            local schema = {
                fields = {
                    status = {
                        type = "string",
                        values = { "active", "inactive", "pending" }
                    }
                }
            }

            local data = { status = "active" }
            local err, result = schemer.validate(data, schema)
            assert.is_nil(err)
            assert.are.same(data, result)
        end)

        it("should fail for invalid value in simple list", function()
            local schema = {
                fields = {
                    status = {
                        type = "string",
                        values = { "active", "inactive", "pending" }
                    }
                }
            }

            local data = { status = "unknown" }
            local err, result = schemer.validate(data, schema)
            assert.is_not_nil(err)
            assert.is_not_nil(err.fields.status)
            assert.are.equal(schemer.ERROR_CODES.INVALID_VALUE, err.fields.status[1][1])
        end)

        it("should work with numeric values", function()
            local schema = {
                fields = {
                    priority = {
                        type = "number",
                        values = { 1, 2, 3, 4, 5 }
                    }
                }
            }

            local data = { priority = 3 }
            local err, result = schemer.validate(data, schema)
            assert.is_nil(err)
            assert.are.same(data, result)
        end)
    end)

    describe("enum without reverse lookup", function()
        it("should validate against enum values", function()
            local LEVELS = { DEBUG = 1, INFO = 2, WARN = 3, ERROR = 4 }
            local schema = {
                fields = {
                    level = {
                        type = "number",
                        values = schemer.enum(LEVELS)
                    }
                }
            }

            local data = { level = 2 }
            local err, result = schemer.validate(data, schema)
            assert.is_nil(err)
            assert.are.same(data, result)
        end)

        it("should fail for invalid enum value", function()
            local LEVELS = { DEBUG = 1, INFO = 2, WARN = 3, ERROR = 4 }
            local schema = {
                fields = {
                    level = {
                        type = "number",
                        values = schemer.enum(LEVELS)
                    }
                }
            }

            local data = { level = 99 }
            local err, result = schemer.validate(data, schema)
            assert.is_not_nil(err)
            assert.is_not_nil(err.fields.level)
            assert.are.equal(schemer.ERROR_CODES.INVALID_VALUE, err.fields.level[1][1])
        end)
    end)

    describe("enum with reverse lookup", function()
        it("should transform string key to enum value", function()
            local LEVELS = { DEBUG = 1, INFO = 2, WARN = 3, ERROR = 4 }
            local schema = {
                fields = {
                    level = {
                        type = "number",
                        values = schemer.enum(LEVELS, { reverse = true })
                    }
                }
            }

            local data = { level = "DEBUG" }
            local err, result = schemer.validate(data, schema)
            assert.is_nil(err)
            assert.are.equal(1, result.level)
        end)

        it("should accept direct enum values with reverse lookup enabled", function()
            local LEVELS = { DEBUG = 1, INFO = 2, WARN = 3, ERROR = 4 }
            local schema = {
                fields = {
                    level = {
                        type = "number",
                        values = schemer.enum(LEVELS, { reverse = true })
                    }
                }
            }

            local data = { level = 2 }
            local err, result = schemer.validate(data, schema)
            assert.is_nil(err)
            assert.are.equal(2, result.level)
        end)

        it("should fail for invalid key in reverse lookup", function()
            local LEVELS = { DEBUG = 1, INFO = 2, WARN = 3, ERROR = 4 }
            local schema = {
                fields = {
                    level = {
                        type = "number",
                        values = schemer.enum(LEVELS, { reverse = true })
                    }
                }
            }

            local data = { level = "INVALID" }
            local err, result = schemer.validate(data, schema)
            assert.is_not_nil(err)
            assert.is_not_nil(err.fields.level)
            assert.are.equal(schemer.ERROR_CODES.INVALID_VALUE, err.fields.level[1][1])
        end)

        it("should handle string enum with reverse lookup", function()
            local FORMATS = { JSON = "json", XML = "xml", CSV = "csv" }
            local schema = {
                fields = {
                    format = {
                        type = "string",
                        values = schemer.enum(FORMATS, { reverse = true })
                    }
                }
            }

            local data = { format = "JSON" }
            local err, result = schemer.validate(data, schema)
            assert.is_nil(err)
            assert.are.equal("json", result.format)
        end)
    end)

    describe("enum helper function", function()
        it("should create proper enum structure without options", function()
            local LEVELS = { DEBUG = 1, INFO = 2 }
            local enum_def = schemer.enum(LEVELS)

            assert.are.same(LEVELS, enum_def.enum)
            assert.is_false(enum_def.reverse)
        end)

        it("should create proper enum structure with reverse option", function()
            local LEVELS = { DEBUG = 1, INFO = 2 }
            local enum_def = schemer.enum(LEVELS, { reverse = true })

            assert.are.same(LEVELS, enum_def.enum)
            assert.is_true(enum_def.reverse)
        end)

        it("should default reverse to false when not specified", function()
            local LEVELS = { DEBUG = 1, INFO = 2 }
            local enum_def = schemer.enum(LEVELS, {})

            assert.are.same(LEVELS, enum_def.enum)
            assert.is_false(enum_def.reverse)
        end)
    end)

    describe("mixed validation scenarios", function()
        it("should combine values validation with type validation", function()
            local schema = {
                fields = {
                    status = {
                        type = "string",
                        values = { "active", "inactive" }
                    }
                }
            }

            -- Should fail type validation first
            local data = { status = 123 }
            local err, result = schemer.validate(data, schema)
            assert.is_not_nil(err)
            assert.is_not_nil(err.fields.status)
            assert.are.equal(schemer.ERROR_CODES.INVALID_TYPE, err.fields.status[1][1])
        end)

        it("should work with enum in array elements", function()
            local LEVELS = { DEBUG = 1, INFO = 2, WARN = 3 }
            local schema = {
                fields = {
                    levels = {
                        type = "table",
                        each = {
                            type = "number",
                            values = schemer.enum(LEVELS, { reverse = true })
                        }
                    }
                }
            }

            local data = { levels = { "DEBUG", 2, "WARN" } }
            local err, result = schemer.validate(data, schema)
            assert.is_nil(err)
            assert.are.same({ 1, 2, 3 }, result.levels)
        end)

        it("should fail enum validation in array elements", function()
            local LEVELS = { DEBUG = 1, INFO = 2, WARN = 3 }
            local schema = {
                fields = {
                    levels = {
                        type = "table",
                        each = {
                            type = "number",
                            values = schemer.enum(LEVELS, { reverse = true })
                        }
                    }
                }
            }

            local data = { levels = { "DEBUG", "INVALID", "WARN" } }
            local err, result = schemer.validate(data, schema)
            assert.is_not_nil(err)
            assert.is_not_nil(err.fields.levels)
            assert.are.equal(schemer.ERROR_CODES.INVALID_VALUE, err.fields.levels[1][1])
        end)
    end)

    describe("edge cases", function()
        it("should handle empty values list", function()
            local schema = {
                fields = {
                    status = {
                        type = "string",
                        values = {}
                    }
                }
            }

            local data = { status = "anything" }
            local err, result = schemer.validate(data, schema)
            assert.is_not_nil(err)
            assert.is_not_nil(err.fields.status)
            assert.are.equal(schemer.ERROR_CODES.INVALID_VALUE, err.fields.status[1][1])
        end)

        it("should handle empty enum", function()
            local schema = {
                fields = {
                    status = {
                        type = "string",
                        values = schemer.enum({})
                    }
                }
            }

            local data = { status = "anything" }
            local err, result = schemer.validate(data, schema)
            assert.is_not_nil(err)
            assert.is_not_nil(err.fields.status)
            assert.are.equal(schemer.ERROR_CODES.INVALID_VALUE, err.fields.status[1][1])
        end)

        it("should handle nil values in enum", function()
            local LEVELS = { DEBUG = 1, INFO = nil, WARN = 3 }
            local schema = {
                fields = {
                    level = {
                        type = "number",
                        values = schemer.enum(LEVELS, { reverse = true })
                    }
                }
            }

            local data = { level = "INFO" }
            local err, result = schemer.validate(data, schema)
            assert.is_nil(err)
            assert.is_nil(result.level)
        end)
    end)
end)
