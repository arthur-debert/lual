-- Tests for union type validation in schemer

local schemer = require("lual.utils.schemer")

describe("Union Types", function()
    describe("Basic union validation", function()
        it("should validate when value matches first union member", function()
            local schema = {
                fields = {
                    value = {
                        union = {
                            { type = "string", min_len = 1 },
                            { type = "number", min = 0 }
                        }
                    }
                }
            }

            local errors, result = schemer.validate({ value = "hello" }, schema)
            assert.is_nil(errors)
            assert.equals("hello", result.value)
        end)

        it("should validate when value matches second union member", function()
            local schema = {
                fields = {
                    value = {
                        union = {
                            { type = "string", min_len = 1 },
                            { type = "number", min = 0 }
                        }
                    }
                }
            }

            local errors, result = schemer.validate({ value = 42 }, schema)
            assert.is_nil(errors)
            assert.equals(42, result.value)
        end)

        it("should fail when value matches no union members", function()
            local schema = {
                fields = {
                    value = {
                        union = {
                            { type = "string", min_len = 1 },
                            { type = "number", min = 0 }
                        }
                    }
                }
            }

            local errors, result = schemer.validate({ value = true }, schema)
            assert.is_not_nil(errors)
            assert.equals("UNION_MISMATCH", errors.fields.value[1][1])
            assert.matches("doesn't match any union type", errors.fields.value[1][2])
        end)
    end)

    describe("Union with complex types", function()
        it("should handle string vs table union", function()
            local schema = {
                fields = {
                    timeout = {
                        union = {
                            { type = "number", min = 1 },
                            { type = "string", values = { "infinite", "never" } },
                            {
                                type = "table",
                                fields = {
                                    min = { type = "number", min = 0 },
                                    max = { type = "number", min = 0 }
                                }
                            }
                        }
                    }
                }
            }

            -- Test number
            local errors, result = schemer.validate({ timeout = 30 }, schema)
            assert.is_nil(errors)
            assert.equals(30, result.timeout)

            -- Test string
            errors, result = schemer.validate({ timeout = "infinite" }, schema)
            assert.is_nil(errors)
            assert.equals("infinite", result.timeout)

            -- Test table
            errors, result = schemer.validate({ timeout = { min = 5, max = 30 } }, schema)
            assert.is_nil(errors)
            assert.equals(5, result.timeout.min)
            assert.equals(30, result.timeout.max)
        end)

        it("should fail table validation within union when fields are invalid", function()
            local schema = {
                fields = {
                    config = {
                        union = {
                            { type = "string" },
                            {
                                type = "table",
                                fields = {
                                    name = { type = "string", required = true }
                                }
                            }
                        }
                    }
                }
            }

            local errors, result = schemer.validate({ config = {} }, schema)
            assert.is_not_nil(errors)
            assert.equals("UNION_MISMATCH", errors.fields.config[1][1])
        end)
    end)

    describe("Union with enums and transformations", function()
        it("should handle enum transformation in union", function()
            local LEVELS = { DEBUG = 10, INFO = 20, WARN = 30 }
            local schema = {
                fields = {
                    level = {
                        union = {
                            { type = "number", values = schemer.enum(LEVELS, { reverse = true }) },
                            { type = "string", values = { "off", "inherit" } }
                        }
                    }
                }
            }

            -- Test enum transformation
            local errors, result = schemer.validate({ level = "DEBUG" }, schema)
            assert.is_nil(errors)
            assert.equals(10, result.level)

            -- Test string value
            errors, result = schemer.validate({ level = "off" }, schema)
            assert.is_nil(errors)
            assert.equals("off", result.level)
        end)
    end)

    describe("Union with value constraints", function()
        it("should validate constraints within union members", function()
            local schema = {
                fields = {
                    size = {
                        union = {
                            { type = "number", min = 1,                  max = 100 },
                            { type = "string", pattern = "^%d+%%$" }, -- percentage strings like "50%"
                            { type = "string", values = { "auto", "fill" } }
                        }
                    }
                }
            }

            -- Valid number
            local errors, result = schemer.validate({ size = 50 }, schema)
            assert.is_nil(errors)
            assert.equals(50, result.size)

            -- Valid percentage string
            errors, result = schemer.validate({ size = "75%" }, schema)
            assert.is_nil(errors)
            assert.equals("75%", result.size)

            -- Valid keyword
            errors, result = schemer.validate({ size = "auto" }, schema)
            assert.is_nil(errors)
            assert.equals("auto", result.size)

            -- Invalid number (out of range)
            errors, result = schemer.validate({ size = 150 }, schema)
            assert.is_not_nil(errors)
            assert.equals("UNION_MISMATCH", errors.fields.size[1][1])

            -- Invalid string (doesn't match any pattern/values)
            errors, result = schemer.validate({ size = "invalid" }, schema)
            assert.is_not_nil(errors)
            assert.equals("UNION_MISMATCH", errors.fields.size[1][1])
        end)
    end)

    describe("Union with required and defaults", function()
        it("should handle required union fields", function()
            local schema = {
                fields = {
                    id = {
                        required = true,
                        union = {
                            { type = "string", min_len = 1 },
                            { type = "number", min = 1 }
                        }
                    }
                }
            }

            -- Missing required field
            local errors, result = schemer.validate({}, schema)
            assert.is_not_nil(errors)
            assert.equals("REQUIRED_FIELD", errors.fields.id[1][1])
        end)

        it("should handle defaults in union members", function()
            local schema = {
                fields = {
                    config = {
                        union = {
                            { type = "string", default = "default" },
                            {
                                type = "table",
                                fields = {
                                    name = { type = "string", default = "unnamed" }
                                }
                            }
                        }
                    }
                }
            }

            -- Test default application for first union member
            local errors, result = schemer.validate({}, schema)
            assert.is_nil(errors)
            assert.equals("default", result.config)
        end)
    end)

    describe("Nested unions", function()
        it("should handle unions within table fields", function()
            local schema = {
                fields = {
                    items = {
                        type = "table",
                        each = {
                            union = {
                                { type = "string", min_len = 1 },
                                { type = "number", min = 0 },
                                {
                                    type = "table",
                                    fields = {
                                        name = { type = "string" },
                                        value = { type = "number" }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            local data = {
                items = {
                    "string_item",
                    42,
                    { name = "complex", value = 123 }
                }
            }

            local errors, result = schemer.validate(data, schema)
            assert.is_nil(errors)
            assert.equals("string_item", result.items[1])
            assert.equals(42, result.items[2])
            assert.equals("complex", result.items[3].name)
            assert.equals(123, result.items[3].value)
        end)
    end)

    describe("Union error reporting", function()
        it("should provide helpful error messages listing failed options", function()
            local schema = {
                fields = {
                    value = {
                        union = {
                            { type = "string", min_len = 5 },
                            { type = "number", min = 100 },
                            { type = "boolean" }
                        }
                    }
                }
            }

            -- Value that fails all union members
            local errors, result = schemer.validate({ value = "hi" }, schema)
            assert.is_not_nil(errors)
            assert.equals("UNION_MISMATCH", errors.fields.value[1][1])
            assert.matches("option 1 failed", errors.fields.value[1][2])
            assert.matches("option 2 failed", errors.fields.value[1][2])
            assert.matches("option 3 failed", errors.fields.value[1][2])
        end)
    end)

    describe("Union with forbidden values and constraints", function()
        it("should handle not_allowed_values within union members", function()
            local schema = {
                fields = {
                    port = {
                        union = {
                            { type = "number", min = 1,                    max = 65535, not_allowed_values = { 22, 80, 443 } },
                            { type = "string", values = { "auto", "random" } }
                        }
                    }
                }
            }

            -- Valid number port
            local errors, result = schemer.validate({ port = 8080 }, schema)
            assert.is_nil(errors)
            assert.equals(8080, result.port)

            -- Valid string port
            errors, result = schemer.validate({ port = "auto" }, schema)
            assert.is_nil(errors)
            assert.equals("auto", result.port)

            -- Forbidden number port
            errors, result = schemer.validate({ port = 22 }, schema)
            assert.is_not_nil(errors)
            assert.equals("UNION_MISMATCH", errors.fields.port[1][1])
        end)
    end)

    describe("Union with unique_values", function()
        it("should handle unique_values constraint within union table member", function()
            local schema = {
                fields = {
                    data = {
                        union = {
                            { type = "string" },
                            { type = "table", unique_values = true }
                        }
                    }
                }
            }

            -- Valid string
            local errors, result = schemer.validate({ data = "simple" }, schema)
            assert.is_nil(errors)
            assert.equals("simple", result.data)

            -- Valid table with unique values
            errors, result = schemer.validate({ data = { a = 1, b = 2, c = 3 } }, schema)
            assert.is_nil(errors)

            -- Invalid table with duplicate values
            errors, result = schemer.validate({ data = { a = 1, b = 2, c = 1 } }, schema)
            assert.is_not_nil(errors)
            assert.equals("UNION_MISMATCH", errors.fields.data[1][1])
        end)
    end)
end)
