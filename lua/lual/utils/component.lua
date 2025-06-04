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

-- Special handling for presenters - allows string identifiers and type tables
local function handle_presenter_special_cases(item, defaults, component_context)
    -- Only handle special cases if the component_context is presenter
    if component_context ~= "presenter" then
        return nil
    end

    -- Handle presenter as string identifier (e.g., "text", "json")
    if type(item) == "string" then
        -- Return a placeholder function that will be processed later
        -- This allows validation to pass even though it's not a real function
        -- The actual resolution will happen in the dispatch module
        return {
            func = function(record)
                -- This function is a placeholder and should never be called directly
                -- The real presenter will be resolved at runtime in the dispatch module
                return "[Unresolved presenter: " .. item .. "]"
            end,
            config = table_utils.deepcopy(defaults),
            _presenter_type = item -- Special flag to indicate this is a presenter type
        }
    end

    -- Handle presenter as table with type property (e.g., { type = "text", pretty = true })
    if type(item) == "table" and item.type and not is_callable(item.type) then
        local presenter_type = item.type

        -- Copy all other properties as config
        local config = table_utils.deepcopy(defaults)
        for k, v in pairs(item) do
            if k ~= "type" then
                config[k] = v
            end
        end

        -- Return with placeholder function
        return {
            func = function(record)
                -- This function is a placeholder and should never be called directly
                return "[Unresolved presenter type: " .. tostring(presenter_type) .. "]"
            end,
            config = config,
            _presenter_type = presenter_type
        }
    end

    -- Not a special case
    return nil
end

--- Normalizes a component from any format to standardized table form
-- @param item function|table The component to normalize
-- @param defaults table Default configuration for this component type
-- @param component_context string|nil Optional context ("presenter", "dispatcher", "transformer")
-- @return table Normalized component
function M.normalize_component(item, defaults, component_context)
    defaults = defaults or {}

    -- Handle nil case
    if item == nil then
        error("Component must be a function or a table with function as first element")
    end

    -- Special handling for presenters
    local presenter_result = handle_presenter_special_cases(item, defaults, component_context)
    if presenter_result then
        return presenter_result
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
            -- Create a merged config that preserves existing configuration
            local merged_config = table_utils.deepcopy(defaults)

            -- If the item has an existing config, merge it in
            if item.config and type(item.config) == "table" then
                for k, v in pairs(item.config) do
                    merged_config[k] = v
                end
            end

            -- Also look for direct config keys in the item itself (like level)
            for k, v in pairs(item) do
                if k ~= "func" and k ~= "dispatcher_func" and k ~= "config" then
                    merged_config[k] = v
                end
            end

            return {
                func = extracted_func,
                config = merged_config
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
