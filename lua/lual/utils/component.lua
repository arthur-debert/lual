--- Generic component processing utilities for dispatchers, transformers, and presenters
-- This module provides unified normalization and configuration merging for all pipeline components
--
-- The component system standardizes how dispatchers, transformers, and presenters are handled
-- by normalizing them to a standard format early in the processing pipeline.
--
-- Components can be provided in several formats:
-- 1. Simple function: function(record, config) ... end
-- 2. Table with function as first element: { my_func, level = lual.debug, some_config = value }
-- 3. Legacy format with dispatcher_func: { dispatcher_func = my_func, level = lual.debug }
-- 4. Legacy format with type field: { type = "console", level = lual.debug }
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
    return type(obj) == "function" or
        (type(obj) == "table" and getmetatable(obj) and type(getmetatable(obj).__call) == "function")
end

-- Expose the is_callable function
M.is_callable = is_callable

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
        -- Handle new table form: { func, key=val, key=val, ... }
        if #item > 0 then
            if is_callable(item[1]) then
                local func = item[1]

                -- Create a shallow copy without the first element
                local user_config = {}
                for k, v in pairs(item) do
                    if k ~= 1 then
                        user_config[k] = v
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
            else
                error("First element of component table must be a function or callable table")
            end
        end

        -- Special handling for factory-created objects with schema
        if item.schema ~= nil and is_callable(item) then
            -- For presenter/transformer objects with schema, they are already normalized
            return {
                func = item,
                config = table_utils.deepcopy(defaults)
            }
        end

        -- Special handling for spy objects or tables with level/dispatcher_func
        if item.dispatcher_func then
            -- If it has a level, move it to config
            if item.level and not (item.config and item.config.level) then
                if not item.config then
                    item.config = {}
                end
                item.config.level = item.level
            end

            -- Make sure func is set properly
            if not item.func then
                item.func = item.dispatcher_func
            end
        end

        -- Handle table with { type = "presenter_name" } format
        if item.type and not item.func then
            -- This will be handled separately by the dispatcher
            return item
        end

        -- For regular tables with { config = {...}, func = ... } format
        if item.config or item.func then
            -- Already in correct format, ensure config exists
            if not item.config then
                item.config = table_utils.deepcopy(defaults)
            else
                -- Merge default values for keys not in config
                for k, v in pairs(defaults) do
                    if item.config[k] == nil then
                        item.config[k] = v
                    end
                end
            end
            return item
        end

        -- Empty table or invalid format
        if next(item) == nil then
            error("Component must be a function or a table with function as first element")
        end
    end

    -- Unknown type
    if type(item) ~= "function" and type(item) ~= "table" then
        error("Component must be a function or a table with function as first element")
    end

    -- If we get here, it's an unrecognized format but still a table
    return item
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
