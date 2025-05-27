package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua;../lua/?.lua;../lua/?/init.lua"
local to_accessor = require("lual.utils.to_accessor")

describe("to_accessor utility", function()
    describe("Basic functionality", function()
        it("should create a simple accessor with default storage", function()
            local obj = {}
            to_accessor.to_accessors(obj, "test_prop")

            -- Test setting and getting
            obj.test_prop = "hello"
            assert.are.same("hello", obj.test_prop)

            obj.test_prop = 42
            assert.are.same(42, obj.test_prop)
        end)

        it("should preserve existing values when converting to accessor", function()
            local obj = { existing_prop = "initial_value" }
            to_accessor.to_accessors(obj, "existing_prop")

            -- Should still have the initial value
            assert.are.same("initial_value", obj.existing_prop)

            -- Should be able to update it
            obj.existing_prop = "updated_value"
            assert.are.same("updated_value", obj.existing_prop)
        end)

        it("should work with multiple properties on the same table", function()
            local obj = {}
            to_accessor.to_accessors(obj, "prop1")
            to_accessor.to_accessors(obj, "prop2")

            obj.prop1 = "value1"
            obj.prop2 = "value2"

            assert.are.same("value1", obj.prop1)
            assert.are.same("value2", obj.prop2)

            -- Properties should be independent
            obj.prop1 = "new_value1"
            assert.are.same("new_value1", obj.prop1)
            assert.are.same("value2", obj.prop2)
        end)

        it("should not interfere with non-accessor properties", function()
            local obj = { normal_prop = "normal" }
            to_accessor.to_accessors(obj, "accessor_prop")

            obj.accessor_prop = "accessor_value"
            obj.normal_prop = "updated_normal"
            obj.another_normal = "another"

            assert.are.same("accessor_value", obj.accessor_prop)
            assert.are.same("updated_normal", obj.normal_prop)
            assert.are.same("another", obj.another_normal)
        end)
    end)

    describe("Custom getter and setter functions", function()
        it("should call custom getter function", function()
            local obj = {}
            local getter_called = false
            local getter_args = {}

            local custom_getter = function(tbl, key, storage)
                getter_called = true
                getter_args = { tbl = tbl, key = key, storage = storage }
                return "custom_get_value"
            end

            to_accessor.to_accessors(obj, "custom_prop", custom_getter)

            local result = obj.custom_prop

            assert.is_true(getter_called)
            assert.are.same("custom_get_value", result)
            assert.are.same(obj, getter_args.tbl)
            assert.are.same("custom_prop", getter_args.key)
            assert.is_table(getter_args.storage)
        end)

        it("should call custom setter function", function()
            local obj = {}
            local setter_called = false
            local setter_args = {}

            local custom_setter = function(tbl, key, value, storage)
                setter_called = true
                setter_args = { tbl = tbl, key = key, value = value, storage = storage }
                storage[key] = "modified_" .. tostring(value)
            end

            to_accessor.to_accessors(obj, "custom_prop", nil, custom_setter)

            obj.custom_prop = "test_value"

            assert.is_true(setter_called)
            assert.are.same(obj, setter_args.tbl)
            assert.are.same("custom_prop", setter_args.key)
            assert.are.same("test_value", setter_args.value)
            assert.is_table(setter_args.storage)

            -- Verify the modified value is stored
            assert.are.same("modified_test_value", obj.custom_prop)
        end)

        it("should work with both custom getter and setter", function()
            local obj = {}
            local get_count = 0
            local set_count = 0

            local custom_getter = function(tbl, key, storage)
                get_count = get_count + 1
                return storage[key] or "default"
            end

            local custom_setter = function(tbl, key, value, storage)
                set_count = set_count + 1
                storage[key] = string.upper(tostring(value))
            end

            to_accessor.to_accessors(obj, "prop", custom_getter, custom_setter)

            -- Test initial get (should return default)
            assert.are.same("default", obj.prop)
            assert.are.same(1, get_count)
            assert.are.same(0, set_count)

            -- Test set
            obj.prop = "hello"
            assert.are.same(1, get_count)
            assert.are.same(1, set_count)

            -- Test get after set
            assert.are.same("HELLO", obj.prop)
            assert.are.same(2, get_count)
            assert.are.same(1, set_count)
        end)

        it("should provide isolated storage for each property", function()
            local obj = {}
            local storage1, storage2

            local getter1 = function(tbl, key, storage)
                storage1 = storage
                return storage[key]
            end

            local getter2 = function(tbl, key, storage)
                storage2 = storage
                return storage[key]
            end

            to_accessor.to_accessors(obj, "prop1", getter1)
            to_accessor.to_accessors(obj, "prop2", getter2)

            obj.prop1 = "value1"
            obj.prop2 = "value2"

            -- Access both to trigger getters
            local _ = obj.prop1
            local _ = obj.prop2

            -- Storage tables should be different
            assert.are_not.same(storage1, storage2)
            assert.are.same("value1", storage1.prop1)
            assert.are.same("value2", storage2.prop2)
            assert.is_nil(storage1.prop2)
            assert.is_nil(storage2.prop1)
        end)
    end)

    describe("Metatable preservation", function()
        it("should work with tables that already have metatables", function()
            local obj = {}
            local original_meta = {
                __tostring = function() return "custom_tostring" end
            }
            setmetatable(obj, original_meta)

            to_accessor.to_accessors(obj, "test_prop")

            -- Accessor should work
            obj.test_prop = "test_value"
            assert.are.same("test_value", obj.test_prop)

            -- Original metatable functionality should be preserved
            assert.are.same("custom_tostring", tostring(obj))
        end)

        it("should preserve existing __index metamethod", function()
            local obj = {}
            local fallback_table = { fallback_prop = "fallback_value" }
            local original_meta = {
                __index = fallback_table
            }
            setmetatable(obj, original_meta)

            to_accessor.to_accessors(obj, "accessor_prop")

            -- Accessor should work
            obj.accessor_prop = "accessor_value"
            assert.are.same("accessor_value", obj.accessor_prop)

            -- Fallback should still work for non-accessor properties
            assert.are.same("fallback_value", obj.fallback_prop)
        end)

        it("should preserve existing __index function", function()
            local obj = {}
            local index_called = false
            local original_meta = {
                __index = function(tbl, key)
                    index_called = true
                    if key == "dynamic_prop" then
                        return "dynamic_value"
                    end
                    return nil
                end
            }
            setmetatable(obj, original_meta)

            to_accessor.to_accessors(obj, "accessor_prop")

            -- Accessor should work
            obj.accessor_prop = "accessor_value"
            assert.are.same("accessor_value", obj.accessor_prop)

            -- Original __index function should still work
            assert.are.same("dynamic_value", obj.dynamic_prop)
            assert.is_true(index_called)
        end)

        it("should preserve existing __newindex metamethod", function()
            local obj = {}
            local external_storage = {}
            local original_meta = {
                __newindex = function(tbl, key, value)
                    external_storage[key] = "external_" .. tostring(value)
                end
            }
            setmetatable(obj, original_meta)

            to_accessor.to_accessors(obj, "accessor_prop")

            -- Accessor should work normally
            obj.accessor_prop = "accessor_value"
            assert.are.same("accessor_value", obj.accessor_prop)

            -- Non-accessor properties should use original __newindex
            obj.normal_prop = "normal_value"
            assert.are.same("external_normal_value", external_storage.normal_prop)
            assert.is_nil(rawget(obj, "normal_prop"))
        end)

        it("should preserve existing __newindex table", function()
            local obj = {}
            local external_table = {}
            local original_meta = {
                __newindex = external_table
            }
            setmetatable(obj, original_meta)

            to_accessor.to_accessors(obj, "accessor_prop")

            -- Accessor should work normally
            obj.accessor_prop = "accessor_value"
            assert.are.same("accessor_value", obj.accessor_prop)

            -- Non-accessor properties should go to external table
            obj.normal_prop = "normal_value"
            assert.are.same("normal_value", external_table.normal_prop)
            assert.is_nil(rawget(obj, "normal_prop"))
        end)
    end)

    describe("Error handling and validation", function()
        it("should error when tbl is not a table", function()
            assert.has_error(function()
                to_accessor.to_accessors("not a table", "prop")
            end, "Expected a table for 'tbl'")

            assert.has_error(function()
                to_accessor.to_accessors(42, "prop")
            end, "Expected a table for 'tbl'")

            assert.has_error(function()
                to_accessor.to_accessors(nil, "prop")
            end, "Expected a table for 'tbl'")
        end)

        it("should error when property_name is not a string", function()
            local obj = {}

            assert.has_error(function()
                to_accessor.to_accessors(obj, 42)
            end, "Expected a non-empty string for 'property_name'")

            assert.has_error(function()
                to_accessor.to_accessors(obj, nil)
            end, "Expected a non-empty string for 'property_name'")

            assert.has_error(function()
                to_accessor.to_accessors(obj, true)
            end, "Expected a non-empty string for 'property_name'")
        end)

        it("should error when property_name is an empty string", function()
            local obj = {}

            assert.has_error(function()
                to_accessor.to_accessors(obj, "")
            end, "Expected a non-empty string for 'property_name'")
        end)
    end)

    describe("Edge cases and complex scenarios", function()
        it("should handle nil values correctly", function()
            local obj = {}
            to_accessor.to_accessors(obj, "nil_prop")

            -- Setting to nil should work
            obj.nil_prop = nil
            assert.is_nil(obj.nil_prop)

            -- Setting to a value and back to nil
            obj.nil_prop = "value"
            assert.are.same("value", obj.nil_prop)
            obj.nil_prop = nil
            assert.is_nil(obj.nil_prop)
        end)

        it("should handle complex data types", function()
            local obj = {}
            to_accessor.to_accessors(obj, "complex_prop")

            local complex_value = {
                nested = { deep = "value" },
                array = { 1, 2, 3 },
                func = function() return "test" end
            }

            obj.complex_prop = complex_value
            local retrieved = obj.complex_prop

            assert.are.same(complex_value, retrieved)
            assert.are.same("value", retrieved.nested.deep)
            assert.are.same(3, #retrieved.array)
            assert.are.same("test", retrieved.func())
        end)

        it("should work with recursive table structures", function()
            local obj = {}
            to_accessor.to_accessors(obj, "recursive_prop")

            local recursive_table = { name = "parent" }
            recursive_table.self = recursive_table

            obj.recursive_prop = recursive_table
            local retrieved = obj.recursive_prop

            assert.are.same("parent", retrieved.name)
            assert.are.same(retrieved, retrieved.self)
        end)

        it("should maintain property isolation across multiple table instances", function()
            local obj1 = {}
            local obj2 = {}

            to_accessor.to_accessors(obj1, "shared_name")
            to_accessor.to_accessors(obj2, "shared_name")

            obj1.shared_name = "value1"
            obj2.shared_name = "value2"

            assert.are.same("value1", obj1.shared_name)
            assert.are.same("value2", obj2.shared_name)
        end)

        it("should work correctly when property name conflicts with metatable methods", function()
            local obj = {}
            to_accessor.to_accessors(obj, "__index")
            to_accessor.to_accessors(obj, "__newindex")

            obj.__index = "index_value"
            obj.__newindex = "newindex_value"

            assert.are.same("index_value", obj.__index)
            assert.are.same("newindex_value", obj.__newindex)
        end)
    end)

    describe("Performance and memory considerations", function()
        it("should not leak memory with many accessor properties", function()
            local obj = {}

            -- Create many accessor properties
            for i = 1, 100 do
                to_accessor.to_accessors(obj, "prop" .. i)
                obj["prop" .. i] = "value" .. i
            end

            -- Verify all work correctly
            for i = 1, 100 do
                assert.are.same("value" .. i, obj["prop" .. i])
            end

            -- This test mainly ensures no errors occur with many properties
            -- Memory leak detection would require more sophisticated tooling
        end)

        it("should handle rapid get/set operations", function()
            local obj = {}
            to_accessor.to_accessors(obj, "rapid_prop")

            -- Perform many rapid operations
            for i = 1, 1000 do
                obj.rapid_prop = i
                assert.are.same(i, obj.rapid_prop)
            end
        end)
    end)
end)
