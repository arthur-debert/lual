describe("lual.utils.table", function()
    local table_utils = require("lual.utils.table")

    describe("deepcopy", function()
        it("should copy simple tables", function()
            local original = { a = 1, b = 2, c = "hello" }
            local copy = table_utils.deepcopy(original)

            assert.are_not.equal(original, copy) -- Different table objects
            assert.are.same(original, copy)      -- Same content
        end)

        it("should copy nested tables", function()
            local original = {
                a = 1,
                b = {
                    c = 2,
                    d = { e = 3 }
                }
            }
            local copy = table_utils.deepcopy(original)

            assert.are_not.equal(original, copy)
            assert.are_not.equal(original.b, copy.b)
            assert.are_not.equal(original.b.d, copy.b.d)
            assert.are.same(original, copy)
        end)

        it("should handle tables with mixed data types", function()
            local original = {
                num = 42,
                str = "test",
                bool = true,
                nested = { inner = "value" },
                func = function() return "test" end
            }
            local copy = table_utils.deepcopy(original)

            assert.are.equal(original.num, copy.num)
            assert.are.equal(original.str, copy.str)
            assert.are.equal(original.bool, copy.bool)
            assert.are_not.equal(original.nested, copy.nested)
            assert.are.same(original.nested, copy.nested)
            assert.are.equal(original.func, copy.func) -- Functions are copied by reference
        end)

        it("should handle circular references", function()
            local original = { a = 1 }
            original.self = original

            local copy = table_utils.deepcopy(original)

            assert.are_not.equal(original, copy)
            assert.are.equal(copy, copy.self) -- Circular reference preserved
            assert.are.equal(copy.a, 1)
        end)

        it("should copy tables with metatables", function()
            local mt = { __tostring = function() return "test" end }
            local original = setmetatable({ a = 1 }, mt)

            local copy = table_utils.deepcopy(original)

            assert.are_not.equal(original, copy)
            assert.are.equal(getmetatable(original).__tostring, getmetatable(copy).__tostring)
            assert.are.equal(copy.a, 1)
        end)

        it("should handle non-table values", function()
            assert.are.equal(table_utils.deepcopy(42), 42)
            assert.are.equal(table_utils.deepcopy("hello"), "hello")
            assert.are.equal(table_utils.deepcopy(true), true)
            assert.are.equal(table_utils.deepcopy(nil), nil)
        end)

        it("should handle empty tables", function()
            local original = {}
            local copy = table_utils.deepcopy(original)

            assert.are_not.equal(original, copy)
            assert.are.same(original, copy)
        end)

        it("should handle tables with numeric keys", function()
            local original = { [1] = "one", [2] = "two", [100] = "hundred" }
            local copy = table_utils.deepcopy(original)

            assert.are_not.equal(original, copy)
            assert.are.same(original, copy)
        end)

        it("should handle complex circular structures", function()
            local a = { name = "a" }
            local b = { name = "b", ref_a = a }
            a.ref_b = b

            local copy_a = table_utils.deepcopy(a)

            assert.are_not.equal(a, copy_a)
            assert.are_not.equal(b, copy_a.ref_b)
            assert.are.equal(copy_a, copy_a.ref_b.ref_a) -- Circular reference preserved
            assert.are.equal(copy_a.name, "a")
            assert.are.equal(copy_a.ref_b.name, "b")
        end)
    end)

    describe("key_diff", function()
        it("should detect added keys", function()
            local t1 = { a = 1, b = 2 }
            local t2 = { a = 1, b = 2, c = 3 }

            local diff = table_utils.key_diff(t1, t2)

            assert.are.same({ "c" }, diff.added_keys)
            assert.are.same({}, diff.removed_keys)
            assert.are.same({}, diff.changed_keys)
        end)

        it("should detect removed keys", function()
            local t1 = { a = 1, b = 2, c = 3 }
            local t2 = { a = 1, b = 2 }

            local diff = table_utils.key_diff(t1, t2)

            assert.are.same({}, diff.added_keys)
            assert.are.same({ "c" }, diff.removed_keys)
            assert.are.same({}, diff.changed_keys)
        end)

        it("should detect changed values (shallow)", function()
            local t1 = { a = 1, b = 2, c = 3 }
            local t2 = { a = 1, b = 5, c = 3 }

            local diff = table_utils.key_diff(t1, t2)

            assert.are.same({}, diff.added_keys)
            assert.are.same({}, diff.removed_keys)
            assert.are.equal(diff.changed_keys.b.old_value, 2)
            assert.are.equal(diff.changed_keys.b.new_value, 5)
        end)

        it("should detect multiple differences", function()
            local t1 = { a = 1, b = 2, d = 4 }
            local t2 = { a = 1, b = 5, c = 3 }

            local diff = table_utils.key_diff(t1, t2)

            assert.are.same({ "c" }, diff.added_keys)
            assert.are.same({ "d" }, diff.removed_keys)
            assert.are.equal(diff.changed_keys.b.old_value, 2)
            assert.are.equal(diff.changed_keys.b.new_value, 5)
        end)

        it("should handle identical tables", function()
            local t1 = { a = 1, b = 2, c = 3 }
            local t2 = { a = 1, b = 2, c = 3 }

            local diff = table_utils.key_diff(t1, t2)

            assert.are.same({}, diff.added_keys)
            assert.are.same({}, diff.removed_keys)
            assert.are.same({}, diff.changed_keys)
        end)

        it("should handle empty tables", function()
            local t1 = {}
            local t2 = {}

            local diff = table_utils.key_diff(t1, t2)

            assert.are.same({}, diff.added_keys)
            assert.are.same({}, diff.removed_keys)
            assert.are.same({}, diff.changed_keys)
        end)

        it("should detect nested table changes without deep compare", function()
            local t1 = { a = 1, nested = { x = 1 } }
            local t2 = { a = 1, nested = { x = 2 } }

            local diff = table_utils.key_diff(t1, t2, false)

            -- Without deep compare, nested tables are compared by reference
            assert.are.same({}, diff.added_keys)
            assert.are.same({}, diff.removed_keys)
        end)

        it("should perform deep comparison when enabled", function()
            local t1 = {
                a = 1,
                nested = {
                    x = 1,
                    y = 2,
                    deep = { z = 3 }
                }
            }
            local t2 = {
                a = 1,
                nested = {
                    x = 1,
                    y = 5,                  -- Changed
                    deep = { z = 3, w = 4 } -- Added key in deep nested
                }
            }

            local diff = table_utils.key_diff(t1, t2, true)

            assert.are.same({}, diff.added_keys)
            assert.are.same({}, diff.removed_keys)

            local nested_diff = diff.changed_keys.nested
            assert.are.same({}, nested_diff.added_keys)
            assert.are.same({}, nested_diff.removed_keys)
            assert.are.equal(nested_diff.changed_keys.y.old_value, 2)
            assert.are.equal(nested_diff.changed_keys.y.new_value, 5)
            assert.are.equal(nested_diff.changed_keys.deep.added_keys[1], "w")
        end)

        it("should handle nil values", function()
            local t1 = { a = 1, c = 3 } -- b is effectively nil (absent)
            local t2 = { a = 1, b = 2 } -- c is effectively nil (absent)

            local diff = table_utils.key_diff(t1, t2)

            -- In Lua, nil values don't exist in pairs iteration
            local function contains(tbl, val)
                for _, v in ipairs(tbl) do
                    if v == val then return true end
                end
                return false
            end

            assert.is_true(contains(diff.added_keys, "b"))
            assert.is_true(contains(diff.removed_keys, "c"))
        end)

        it("should handle different data types", function()
            local t1 = { a = "string", b = 42, c = true }
            local t2 = { a = 123, b = "changed", c = false }

            local diff = table_utils.key_diff(t1, t2)

            assert.are.same({}, diff.added_keys)
            assert.are.same({}, diff.removed_keys)
            assert.are.equal(diff.changed_keys.a.old_value, "string")
            assert.are.equal(diff.changed_keys.a.new_value, 123)
            assert.are.equal(diff.changed_keys.b.old_value, 42)
            assert.are.equal(diff.changed_keys.b.new_value, "changed")
            assert.are.equal(diff.changed_keys.c.old_value, true)
            assert.are.equal(diff.changed_keys.c.new_value, false)
        end)
    end)

    describe("dump", function()
        it("should dump simple tables", function()
            local t = { a = 1, b = "hello" }
            local result = table_utils.dump(t)

            -- Check that output contains the key-value pairs
            assert.matches("a: 1", result)
            assert.matches("b: hello", result)
        end)

        it("should dump nested tables with indentation", function()
            local t = {
                level1 = {
                    level2 = {
                        value = "deep"
                    }
                }
            }
            local result = table_utils.dump(t)

            -- Check for proper nesting structure
            assert.matches("level1: {", result)
            assert.matches("level2: {", result)
            assert.matches("value: deep", result)
        end)

        it("should handle empty tables", function()
            local t = {}
            local result = table_utils.dump(t)

            assert.are.equal("", result)
        end)
    end)
end)
