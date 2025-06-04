--- Generic component processing utilities for dispatchers, transformers, and presenters
-- This module provides unified normalization and configuration merging for all pipeline components

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
    return type(obj) == "function" or
        (type(obj) == "table" and getmetatable(obj) and type(getmetatable(obj).__call) == "function")
end

--- Normalizes a component from function or table form to standardized table form
-- @param item function|table The component to normalize (function or {func, key=val, ...})
-- @param defaults table Default configuration for this component type
-- @return table Normalized component with func and config fields
function M.normalize_component(item, defaults)
    defaults = defaults or {}

    if is_callable(item) then
        -- Simple function form or callable table: convert to standard form with default config
        return {
            func = item,
            config = table_utils.deepcopy(defaults)
        }
    end

    if type(item) == "table" and #item > 0 then
        -- Table form: { func, key=val, key=val, ... }
        local func = item[1]

        if not is_callable(func) then
            error("First element of component table must be a function or callable table")
        end

        -- Create a shallow copy without the first element
        local user_config = {}
        for k, v in pairs(item) do
            if k ~= 1 then
                user_config[k] = v
            end
        end

        -- Merge user config into defaults (user config overwrites defaults)
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
