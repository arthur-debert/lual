local M = {}

local function table_key_diff(t1, t2, deep_compare_values)
    deep_compare_values = deep_compare_values or false

    local added_keys = {}   -- Keys in t2 but not in t1
    local removed_keys = {} -- Keys in t1 but not in t2
    local changed_keys = {} -- Keys in both, but values are different

    local seen_keys_t2 = {} -- To keep track of keys in t2

    -- Check keys in t1
    for k, v1 in pairs(t1) do
        if t2[k] == nil then
            -- Key exists in t1 but not in t2
            removed_keys[#removed_keys + 1] = k
        else
            -- Key exists in both, check if values are different
            local v2 = t2[k]
            if deep_compare_values and type(v1) == "table" and type(v2) == "table" then
                -- Recursive deep comparison for nested tables
                -- This will return a table of differences if any
                local nested_diff = table_key_diff(v1, v2, true)
                if next(nested_diff.added_keys) or next(nested_diff.removed_keys) or next(nested_diff.changed_keys) then
                    changed_keys[k] = nested_diff
                end
            elseif v1 ~= v2 then
                -- Values are different (for non-tables or shallow comparison)
                changed_keys[k] = {
                    old_value = v1,
                    new_value = v2
                }
            end
        end
        seen_keys_t2[k] = true
    end

    -- Check keys in t2 that were not in t1
    for k, v2 in pairs(t2) do
        if not seen_keys_t2[k] then
            added_keys[#added_keys + 1] = k
        end
    end

    return {
        added_keys = added_keys,
        removed_keys = removed_keys,
        changed_keys = changed_keys
    }
end

-- Helper to pretty-print tables
local function dump_table(t, indent)
    indent = indent or 0
    local s = {}
    local prefix = string.rep("  ", indent)
    for k, v in pairs(t) do
        if type(v) == "table" then
            s[#s + 1] = prefix .. tostring(k) .. ": {\n" .. dump_table(v, indent + 1) .. prefix .. "}"
        else
            s[#s + 1] = prefix .. tostring(k) .. ": " .. tostring(v)
        end
    end
    return table.concat(s, ",\n")
end

local function deepcopy(original)
    local copies = {} -- Keep track of tables already copied to handle cycles

    local function _copy(obj)
        -- If it's not a table, return it directly (numbers, strings, booleans, nil)
        if type(obj) ~= "table" then
            return obj
        end

        -- If this table has already been copied, return the existing copy
        if copies[obj] then
            return copies[obj]
        end

        -- Create a new table for the copy
        local new_table = {}
        copies[obj] = new_table -- Store the new table in 'copies' immediately to handle cycles

        -- Copy metatable (optional, uncomment if you want to copy metatables)
        local mt = getmetatable(obj)
        if mt then
            setmetatable(new_table, _copy(mt)) -- Recursively copy metatable
        end

        -- Iterate over key-value pairs and recursively copy them
        for k, v in pairs(obj) do
            new_table[_copy(k)] = _copy(v) -- Recursively copy keys and values
        end

        return new_table
    end

    return _copy(original)
end

M.deepcopy = deepcopy
M.key_diff = table_key_diff
M.dump     = dump_table
return M
