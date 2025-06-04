--- Generic component processing utilities for dispatchers, transformers, and presenters
-- This module provides unified normalization and configuration merging for all pipeline components
--
-- The component system standardizes how dispatchers, transformers, and presenters are handled
-- by normalizing them to a standard format early in the processing pipeline.
--
-- Components can be provided in only two formats:
-- 1. Simple function: function(record, config) ... end
-- 2. Table with function as first element: { my_func, level = lual.debug, some_config = value }
--
-- All formats are normalized to a standard structure:
-- {
--   func = function_reference,  -- The actual component function
--   config = {                  -- Configuration table with merged defaults
--     level = level_value,      -- Optional level for dispatchers
--     ... other config values
--   }
-- }

local table_utils = require("lual.utils.table")

local M = {}

-- Default configurations for each component type
M.DISPATCHER_DEFAULTS = {
    timezone = "local"
}

M.TRANSFORMER_DEFAULTS = {}

M.PRESENTER_DEFAULTS = {
    timezone = "local"
}

-- Helper function to check if an object is callable (function or table with __call metafunction)
local function is_callable(obj)
    if type(obj) == "function" then
        return true
    end

    if type(obj) == "table" and getmetatable(obj) and type(getmetatable(obj).__call) == "function" then
        return true
    end

    return false
end

-- Expose the is_callable function
M.is_callable = is_callable

-- Special case handling for dispatcher_func and non-standard formats
local function try_extract_function(item)
    -- If we have a dispatcher_func property (legacy compatibility)
    if type(item) == "table" and type(item.dispatcher_func) == "function" then
        return item.dispatcher_func
    end

    -- If we have a func property directly
    if type(item) == "table" and type(item.func) == "function" then
        return item.func
    end

    return nil
end

--- Normalizes a component from any format to standardized table form
-- @param item function|table The component to normalize
-- @param defaults table Default configuration for this component type
-- @return table Normalized component
function M.normalize_component(item, defaults)
    defaults = defaults or {}

    -- Handle nil case
    if item == nil then
        error("Component must be a function or a table with function as first element")
    end

    -- Handle function
    if type(item) == "function" then
        return {
            func = item,
            config = table_utils.deepcopy(defaults)
        }
    end

    -- Handle table
    if type(item) == "table" then
        -- Handle callable table (with __call metatable)
        if is_callable(item) then
            return {
                func = item,
                config = table_utils.deepcopy(defaults)
            }
        end

        -- Check for special dispatcher_func or func properties
        local extracted_func = try_extract_function(item)
        if extracted_func then
            return {
                func = extracted_func,
                config = table_utils.deepcopy(defaults)
            }
        end

        -- Handle new table form: { func, key=val, key=val, ... }
        if #item > 0 then
            if item[1] == nil then
                error("First element of component table cannot be nil")
            end

            if not is_callable(item[1]) then
                error("First element of component table must be a function, got " .. type(item[1]))
            end

            local func = item[1]

            -- Create a shallow copy without the first element
            local user_config = {}
            for k, v in pairs(item) do
                if k ~= 1 then
                    user_config[k] = v
                    print("DEBUG: Adding config key:", k, "=", v)
                end
            end

            -- Merge user config into defaults
            local merged_config = table_utils.deepcopy(defaults)
            for k, v in pairs(user_config) do
                merged_config[k] = v
            end

            return {
                func = func,
                config = merged_config
            }
        end

        error("Component must be a function or a table with function as first element")
    end

    -- Unknown type
    error("Component must be a function or a table with function as first element")
end

--- Normalizes a list of components
-- @param items table Array of components to normalize
-- @param defaults table Default configuration for this component type
-- @return table Array of normalized components
function M.normalize_components(items, defaults)
    if type(items) ~= "table" then
        error("Components must be provided as a table/array")
    end

    local normalized = {}
    for i, item in ipairs(items) do
        normalized[i] = M.normalize_component(item, defaults)
    end

    return normalized
end

return M
