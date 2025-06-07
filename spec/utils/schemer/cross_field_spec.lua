#!/usr/bin/env lua
package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua;../lua/?.lua;../lua/?/init.lua"

local schemer = require("lual.utils.schemer")

describe("schemer cross-field and nested validation", function()
    describe("one_of validation", function()
        it("should pass when one required field is present", function()
            local schema = {
                fields = {
                    user_id = { type = "number" },
                    session_id = { type = "string" }
                },
                one_of = { "user_id", "session_id" }
            }

            local data = { user_id = 123 }
            local err, result = schemer.validate(data, schema)
            assert.is_nil(err)
            assert.are.same(data, result)
        end)

        it("should pass when multiple fields from one_of are present", function()
            local schema = {
                fields = {
                    user_id = { type = "number" },
                    session_id = { type = "string" }
                },
                one_of = { "user_id", "session_id" }
            }

            local data = { user_id = 123, session_id = "abc" }
            local err, result = schemer.validate(data, schema)
            assert.is_nil(err)
            assert.are.same(data, result)
        end)

        it("should fail when no field from one_of is present", function()
            local schema = {
                fields = {
                    user_id = { type = "number" },
                    session_id = { type = "string" },
                    other_field = { type = "string" }
                },
                one_of = { "user_id", "session_id" }
            }

            local data = { other_field = "value" }
            local err, result = schemer.validate(data, schema)
            assert.is_not_nil(err)
            assert.is_not_nil(err.all)
            assert.are.equal(schemer.ERROR_CODES.ONE_OF_MISSING, err.all[1][1])
            assert.matches("At least one of these fields must be present: user_id, session_id", err.all[1][2])
        end)

        it("should work with multiple one_of groups", function()
            local schema = {
                fields = {
                    user_id = { type = "number" },
                    session_id = { type = "string" },
                    email = { type = "string" },
                    phone = { type = "string" }
                },
                one_of = { "user_id", "session_id" }
            }

            local data = { user_id = 123, email = "test@example.com" }
            local err, result = schemer.validate(data, schema)
            assert.is_nil(err)
            assert.are.same(data, result)
        end)
    end)

    describe("depends_on validation", function()
        it("should pass when both field and dependency are present", function()
            local schema = {
                fields = {
                    password = { type = "string" },
                    password_confirm = { type = "string" }
                },
                depends_on = { field = "password_confirm", requires = "password" }
            }

            local data = { password = "secret", password_confirm = "secret" }
            local err, result = schemer.validate(data, schema)
            assert.is_nil(err)
            assert.are.same(data, result)
        end)

        it("should pass when dependent field is absent", function()
            local schema = {
                fields = {
                    password = { type = "string" },
                    password_confirm = { type = "string" }
                },
                depends_on = { field = "password_confirm", requires = "password" }
            }

            local data = { password = "secret" }
            local err, result = schemer.validate(data, schema)
            assert.is_nil(err)
            assert.are.same(data, result)
        end)

        it("should fail when dependent field is present but required field is missing", function()
            local schema = {
                fields = {
                    password = { type = "string" },
                    password_confirm = { type = "string" }
                },
                depends_on = { field = "password_confirm", requires = "password" }
            }

            local data = { password_confirm = "secret" }
            local err, result = schemer.validate(data, schema)
            assert.is_not_nil(err)
            assert.is_not_nil(err.all)
            assert.are.equal(schemer.ERROR_CODES.DEPENDENCY_MISSING, err.all[1][1])
            assert.matches("Field 'password_confirm' requires field 'password' to be present", err.all[1][2])
        end)

        it("should pass when neither field is present", function()
            local schema = {
                fields = {
                    password = { type = "string" },
                    password_confirm = { type = "string" }
                },
                depends_on = { field = "password_confirm", requires = "password" }
            }

            local data = {}
            local err, result = schemer.validate(data, schema)
            assert.is_nil(err)
            assert.are.same(data, result)
        end)
    end)

    describe("exclusive validation", function()
        it("should pass when only one exclusive field is present", function()
            local schema = {
                fields = {
                    debug_mode = { type = "boolean" },
                    production_mode = { type = "boolean" }
                },
                exclusive = { "debug_mode", "production_mode" }
            }

            local data = { debug_mode = true }
            local err, result = schemer.validate(data, schema)
            assert.is_nil(err)
            assert.are.same(data, result)
        end)

        it("should pass when no exclusive fields are present", function()
            local schema = {
                fields = {
                    debug_mode = { type = "boolean" },
                    production_mode = { type = "boolean" },
                    other_field = { type = "string" }
                },
                exclusive = { "debug_mode", "production_mode" }
            }

            local data = { other_field = "value" }
            local err, result = schemer.validate(data, schema)
            assert.is_nil(err)
            assert.are.same(data, result)
        end)

        it("should fail when multiple exclusive fields are present", function()
            local schema = {
                fields = {
                    debug_mode = { type = "boolean" },
                    production_mode = { type = "boolean" }
                },
                exclusive = { "debug_mode", "production_mode" }
            }

            local data = { debug_mode = true, production_mode = false }
            local err, result = schemer.validate(data, schema)
            assert.is_not_nil(err)
            assert.is_not_nil(err.all)
            assert.are.equal(schemer.ERROR_CODES.EXCLUSIVE_CONFLICT, err.all[1][1])
            assert.matches("These fields cannot be present together: debug_mode, production_mode", err.all[1][2])
        end)

        it("should work with more than two exclusive fields", function()
            local schema = {
                fields = {
                    option_a = { type = "boolean" },
                    option_b = { type = "boolean" },
                    option_c = { type = "boolean" }
                },
                exclusive = { "option_a", "option_b", "option_c" }
            }

            local data = { option_a = true, option_c = true }
            local err, result = schemer.validate(data, schema)
            assert.is_not_nil(err)
            assert.is_not_nil(err.all)
            assert.are.equal(schemer.ERROR_CODES.EXCLUSIVE_CONFLICT, err.all[1][1])
            assert.matches("These fields cannot be present together: option_a, option_c", err.all[1][2])
        end)
    end)

    describe("combined cross-field validations", function()
        it("should handle multiple cross-field rules", function()
            local schema = {
                fields = {
                    user_id = { type = "number" },
                    session_id = { type = "string" },
                    password = { type = "string" },
                    password_confirm = { type = "string" },
                    debug_mode = { type = "boolean" },
                    production_mode = { type = "boolean" }
                },
                one_of = { "user_id", "session_id" },
                depends_on = { field = "password_confirm", requires = "password" },
                exclusive = { "debug_mode", "production_mode" }
            }

            local data = {
                user_id = 123,
                password = "secret",
                password_confirm = "secret",
                debug_mode = true
            }
            local err, result = schemer.validate(data, schema)
            assert.is_nil(err)
            assert.are.same(data, result)
        end)

        it("should fail multiple cross-field rules", function()
            local schema = {
                fields = {
                    user_id = { type = "number" },
                    session_id = { type = "string" },
                    password = { type = "string" },
                    password_confirm = { type = "string" },
                    debug_mode = { type = "boolean" },
                    production_mode = { type = "boolean" }
                },
                one_of = { "user_id", "session_id" },
                depends_on = { field = "password_confirm", requires = "password" },
                exclusive = { "debug_mode", "production_mode" }
            }

            local data = {
                password_confirm = "secret", -- Missing password (depends_on violation)
                debug_mode = true,
                production_mode = false      -- Exclusive violation
                -- Missing user_id or session_id (one_of violation)
            }
            local err, result = schemer.validate(data, schema)
            assert.is_not_nil(err)
            assert.is_not_nil(err.all)
            assert.are.equal(3, #err.all) -- Should have all three cross-field errors
        end)
    end)

    describe("nested validation", function()
        it("should validate nested fields", function()
            local schema = {
                fields = {
                    user = {
                        type = "table",
                        fields = {
                            name = { type = "string", required = true },
                            age = { type = "number", min = 0 }
                        }
                    }
                }
            }

            local data = {
                user = {
                    name = "John",
                    age = 25
                }
            }
            local err, result = schemer.validate(data, schema)
            assert.is_nil(err)
            assert.are.same(data, result)
        end)

        it("should fail nested field validation", function()
            local schema = {
                fields = {
                    user = {
                        type = "table",
                        fields = {
                            name = { type = "string", required = true },
                            age = { type = "number", min = 0 }
                        }
                    }
                }
            }

            local data = {
                user = {
                    age = -5 -- Missing required name, invalid age
                }
            }
            local err, result = schemer.validate(data, schema)
            assert.is_not_nil(err)
            assert.is_not_nil(err.fields.user)
            -- Should have nested field errors
            local has_name_error = false
            local has_age_error = false
            for _, error_item in ipairs(err.fields.user) do
                if string.match(error_item[2], "name.*required") then
                    has_name_error = true
                elseif string.match(error_item[2], "age.*must be at least") then
                    has_age_error = true
                end
            end
            assert.is_true(has_name_error)
            assert.is_true(has_age_error)
        end)

        it("should apply defaults in nested validation", function()
            local schema = {
                fields = {
                    config = {
                        type = "table",
                        fields = {
                            timeout = { type = "number", default = 30 },
                            retry = { type = "boolean", default = true }
                        }
                    }
                }
            }

            local data = { config = {} }
            local err, result = schemer.validate(data, schema)
            assert.is_nil(err)
            assert.are.equal(30, result.config.timeout)
            assert.is_true(result.config.retry)
        end)

        it("should handle deeply nested validation", function()
            local schema = {
                fields = {
                    app = {
                        type = "table",
                        fields = {
                            database = {
                                type = "table",
                                fields = {
                                    host = { type = "string", required = true },
                                    port = { type = "number", min = 1, max = 65535, default = 5432 }
                                }
                            }
                        }
                    }
                }
            }

            local data = {
                app = {
                    database = {
                        host = "localhost"
                    }
                }
            }
            local err, result = schemer.validate(data, schema)
            assert.is_nil(err)
            assert.are.equal("localhost", result.app.database.host)
            assert.are.equal(5432, result.app.database.port) -- Default applied
        end)
    end)

    describe("error structure", function()
        it("should provide comprehensive error structure", function()
            local schema = {
                fields = {
                    name = { type = "string", required = true },
                    age = { type = "number", min = 18 },
                    user_id = { type = "number" },
                    session_id = { type = "string" }
                },
                one_of = { "user_id", "session_id" }
            }

            local data = { age = 16 } -- Missing required name, invalid age, missing one_of
            local err, result = schemer.validate(data, schema)
            assert.is_not_nil(err)

            -- Should have field errors
            assert.is_not_nil(err.fields)
            assert.is_not_nil(err.fields.name)
            assert.is_not_nil(err.fields.age)

            -- Should have cross-field errors
            assert.is_not_nil(err.all)
            assert.are.equal(1, #err.all)

            -- Should have error message
            assert.is_not_nil(err.error)
            assert.matches("Validation failed for fields", err.error)

            -- Should preserve original data and schema
            assert.are.same(data, err.data)
            assert.are.same(schema, err.schema)
        end)

        it("should handle validation with non-table data", function()
            local schema = { fields = { name = { type = "string" } } }
            local data = "not a table"

            local err, result = schemer.validate(data, schema)
            assert.is_not_nil(err)
            assert.are.equal("Data must be a table", err.error)
            assert.is_not_nil(err.all)
            assert.are.equal(schemer.ERROR_CODES.INVALID_TYPE, err.all[1][1])
        end)
    end)
end)
