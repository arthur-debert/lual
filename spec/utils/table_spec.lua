describe("table utils", function()
    local table_utils = require("lual.utils.table")

    describe("key_diff", function()
        it("should identify added keys", function()
            local t1 = { a = 1, b = 2 }
            local t2 = { a = 1, b = 2, c = 3, d = 4 }

            local diff = table_utils.key_diff(t1, t2)

            assert.equals(2, #diff.added_keys)
            -- Check keys are in added_keys without caring about order
            assert.is_true(diff.added_keys[1] == "c" or diff.added_keys[1] == "d")
            assert.is_true(diff.added_keys[2] == "c" or diff.added_keys[2] == "d")
            assert.is_true(diff.added_keys[1] ~= diff.added_keys[2])
            assert.equals(0, #diff.removed_keys)
            assert.same({}, diff.changed_keys)
        end)

        it("should identify removed keys", function()
            local t1 = { a = 1, b = 2, c = 3, d = 4 }
            local t2 = { a = 1, b = 2 }

            local diff = table_utils.key_diff(t1, t2)

            assert.equals(0, #diff.added_keys)
            assert.equals(2, #diff.removed_keys)
            -- Check keys are in removed_keys without caring about order
            assert.is_true(diff.removed_keys[1] == "c" or diff.removed_keys[1] == "d")
            assert.is_true(diff.removed_keys[2] == "c" or diff.removed_keys[2] == "d")
            assert.is_true(diff.removed_keys[1] ~= diff.removed_keys[2])
            assert.same({}, diff.changed_keys)
        end)

        it("should identify changed keys", function()
            local t1 = { a = 1, b = 2, c = 3 }
            local t2 = { a = 1, b = 5, c = 3 }

            local diff = table_utils.key_diff(t1, t2)

            assert.equals(0, #diff.added_keys)
            assert.equals(0, #diff.removed_keys)
            assert.equals(5, diff.changed_keys.b.new_value)
            assert.equals(2, diff.changed_keys.b.old_value)
        end)

        it("should handle deep comparison of nested tables", function()
            local t1 = { a = { x = 1, y = 2 }, b = 2 }
            local t2 = { a = { x = 1, y = 3 }, b = 2 }

            local diff = table_utils.key_diff(t1, t2, true)

            assert.equals(0, #diff.added_keys)
            assert.equals(0, #diff.removed_keys)
            assert.is_table(diff.changed_keys.a)
            assert.equals(3, diff.changed_keys.a.changed_keys.y.new_value)
            assert.equals(2, diff.changed_keys.a.changed_keys.y.old_value)
        end)

        it("should handle deep comparison with nested differences", function()
            local t1 = {
                a = {
                    x = 1,
                    y = {
                        deep = 10,
                        unchanged = "same"
                    }
                },
                b = 2
            }
            local t2 = {
                a = {
                    x = 1,
                    y = {
                        deep = 20,
                        unchanged = "same",
                        added = true
                    }
                },
                b = 2
            }

            local diff = table_utils.key_diff(t1, t2, true)

            assert.equals(0, #diff.added_keys)
            assert.equals(0, #diff.removed_keys)
            assert.is_table(diff.changed_keys.a)
            assert.is_table(diff.changed_keys.a.changed_keys.y)
            assert.equals(1, #diff.changed_keys.a.changed_keys.y.added_keys)
            assert.equals("added", diff.changed_keys.a.changed_keys.y.added_keys[1])
            assert.equals(20, diff.changed_keys.a.changed_keys.y.changed_keys.deep.new_value)
            assert.equals(10, diff.changed_keys.a.changed_keys.y.changed_keys.deep.old_value)
        end)

        it("should handle empty tables", function()
            local diff = table_utils.key_diff({}, {})

            assert.equals(0, #diff.added_keys)
            assert.equals(0, #diff.removed_keys)
            assert.same({}, diff.changed_keys)
        end)
    end)

    describe("dump_table", function()
        it("should format a simple table as a string", function()
            local t = { a = 1, b = "test", c = true }
            local result = table_utils.dump(t)

            -- The order of keys is not guaranteed, so we check for the existence of each part
            assert.truthy(result:match("a: 1"))
            assert.truthy(result:match("b: test"))
            assert.truthy(result:match("c: true"))
        end)

        it("should handle nested tables", function()
            local t = {
                a = 1,
                b = {
                    x = 10,
                    y = 20
                }
            }
            local result = table_utils.dump(t)

            assert.truthy(result:match("a: 1"))
            assert.truthy(result:match("b: {"))
            assert.truthy(result:match("  x: 10"))
            assert.truthy(result:match("  y: 20"))
        end)

        it("should handle empty tables", function()
            local result = table_utils.dump({})
            assert.equals("", result)
        end)
    end)

    describe("deepcopy", function()
        it("should copy simple values", function()
            assert.equals(5, table_utils.deepcopy(5))
            assert.equals("test", table_utils.deepcopy("test"))
            assert.equals(true, table_utils.deepcopy(true))
            assert.equals(nil, table_utils.deepcopy(nil))
        end)

        it("should create a deep copy of a table", function()
            local original = { a = 1, b = 2, c = { x = 10, y = 20 } }
            local copy = table_utils.deepcopy(original)

            -- Copy should equal original
            assert.same(original, copy)

            -- But they should be different tables
            assert.is_not(original, copy)
            assert.is_not(original.c, copy.c)

            -- Modifying copy should not affect original
            copy.a = 99
            copy.c.x = 99
            assert.equals(1, original.a)
            assert.equals(10, original.c.x)
        end)

        it("should handle table keys", function()
            local key1 = { "key1" }
            local key2 = { "key2" }
            local original = {}
            original[key1] = "value1"
            original[key2] = "value2"

            local copy = table_utils.deepcopy(original)

            -- Both tables should have two keys
            local count = 0
            for _ in pairs(copy) do count = count + 1 end
            assert.equals(2, count)

            -- Since table keys are deep copied, we can't directly check them
            -- Instead, we check that the copy has the correct values
            local found_value1 = false
            local found_value2 = false

            for _, v in pairs(copy) do
                if v == "value1" then found_value1 = true end
                if v == "value2" then found_value2 = true end
            end

            assert.is_true(found_value1)
            assert.is_true(found_value2)
        end)

        it("should handle cyclic references", function()
            local original = { a = 1 }
            original.self = original

            local copy = table_utils.deepcopy(original)

            assert.equals(1, copy.a)
            assert.is_table(copy.self)
            assert.is(copy, copy.self)         -- The copy should reference itself
            assert.is_not(original, copy.self) -- But not the original
        end)

        it("should copy metatables", function()
            local mt = { __index = function() return "test" end }
            local original = {}
            setmetatable(original, mt)

            local copy = table_utils.deepcopy(original)

            assert.is_not_nil(getmetatable(copy))
            assert.equals("test", copy.non_existent_key)
        end)

        it("should handle previously copied tables", function()
            local shared = { shared_key = "shared_value" }
            local original = {
                a = shared,
                b = shared -- Same table used twice
            }

            local copy = table_utils.deepcopy(original)

            -- The copy should maintain internal references
            assert.is(copy.a, copy.b) -- They should be the same table in the copy

            -- But not reference the original
            assert.is_not(original.a, copy.a)
        end)

        it("should handle metatables with tables", function()
            local mt_table = { nested = { value = 123 } }
            local mt = { __index = mt_table }
            local original = {}
            setmetatable(original, mt)

            local copy = table_utils.deepcopy(original)
            local copy_mt = getmetatable(copy)

            assert.equals(123, copy.nested.value)
            assert.is_not(mt, copy_mt)               -- Different metatable objects
            assert.is_not(mt_table, copy_mt.__index) -- Different __index tables
        end)
    end)
end)
