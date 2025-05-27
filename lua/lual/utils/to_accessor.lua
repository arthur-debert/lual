--- Configures an accessor for a specific property on a table using metatables.
-- If custom get/set functions are not provided, a default internal storage is used.
-- @param tbl table The table to add the accessor to.
-- @param property_name string The name of the property to turn into an accessor.
-- @param get_func function? An optional function to call when the property is read.
--                           It receives (table, key, internal_storage_table) and should return the value.
-- @param set_func function? An optional function to call when the property is written.
--                           It receives (table, key, value, internal_storage_table).
local function to_accessors(tbl, property_name, get_func, set_func)
    if type(tbl) ~= "table" then
        error("Expected a table for 'tbl'", 2)
    end
    if type(property_name) ~= "string" or property_name == "" then
        error("Expected a non-empty string for 'property_name'", 2)
    end

    local mt = getmetatable(tbl)
    if not mt then
        mt = {}
        setmetatable(tbl, mt)
    end

    local original_index = mt.__index
    local original_newindex = mt.__newindex

    -- Use a dedicated internal storage table for each accessor property on this specific table.
    -- This table will be local to the `to_accessors` call.
    local _accessor_private_storage = {}

    -- Initialize internal storage with existing value and clear from main table
    if rawget(tbl, property_name) ~= nil then
        _accessor_private_storage[property_name] = rawget(tbl, property_name)
        rawset(tbl, property_name, nil) -- Remove to ensure metatable is always hit
    end

    mt.__index = function(current_tbl, key)
        if key == property_name then
            if get_func then
                -- Pass the internal storage to the custom getter
                return get_func(current_tbl, key, _accessor_private_storage)
            else
                return _accessor_private_storage[property_name]
            end
        elseif original_index then
            if type(original_index) == "function" then
                return original_index(current_tbl, key)
            else
                return rawget(original_index, key)
            end
        else
            return rawget(current_tbl, key)
        end
    end

    mt.__newindex = function(current_tbl, key, value)
        if key == property_name then
            if set_func then
                -- Pass the internal storage to the custom setter
                set_func(current_tbl, key, value, _accessor_private_storage)
            else
                _accessor_private_storage[property_name] = value
            end
        elseif original_newindex then
            if type(original_newindex) == "function" then
                return original_newindex(current_tbl, key, value)
            else
                rawset(original_newindex, key, value)
            end
        else
            rawset(current_tbl, key, value)
        end
    end
end

local M = {}
M.to_accessors = to_accessors
return M
