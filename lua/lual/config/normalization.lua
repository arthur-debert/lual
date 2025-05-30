--- Configuration normalization utilities
-- This module handles convenience syntax detection and transformation

local schema = require("lual.config.schema")
local validation = require("lual.config.validation")

local M = {}

-- =============================================================================
-- NORMALIZATION FUNCTIONS
-- =============================================================================

--- Creates a deep copy of a table
-- @param original table The table to copy
-- @return table The copied table
local function deep_copy(original)
    local copy = {}
    for k, v in pairs(original) do
        if type(v) == "table" then
            copy[k] = deep_copy(v)
        else
            copy[k] = v
        end
    end
    return copy
end

--- Validates convenience syntax config and returns error with proper prefix
-- @param config table The config to validate
-- @return boolean, string True if valid, or false with error message
local function validate_convenience_config(config)
    -- Validate unknown keys
    local valid, err = validation.validate_unknown_keys(config, true)
    if not valid then
        return false, "Invalid shortcut config: " .. err
    end

    -- Validate required fields
    valid, err = validation.validate_convenience_requirements(config)
    if not valid then
        return false, "Invalid shortcut config: " .. err
    end

    -- Validate basic fields
    valid, err = validation.validate_basic_fields(config, true)
    if not valid then
        return false, err -- Already has prefix
    end

    -- Validate type-specific fields
    valid, err = validation.validate_convenience_type_fields(config)
    if not valid then
        return false, "Invalid shortcut config: " .. err
    end

    return true
end

--- Transforms convenience syntax to full syntax
-- @param config table The convenience syntax config
-- @return table The normalized config in full syntax
local function transform_convenience_to_full(config)
    local normalized = deep_copy(config)

    -- Create dispatcher entry
    local dispatcher_entry = {
        type = normalized.dispatcher,
        presenter = normalized.presenter
    }

    -- Add type-specific fields
    if normalized.dispatcher == "file" then
        dispatcher_entry.path = normalized.path
    elseif normalized.dispatcher == "console" and normalized.stream then
        dispatcher_entry.stream = normalized.stream
    end

    -- Create dispatchers array
    normalized.dispatchers = { dispatcher_entry }

    -- Remove convenience syntax fields
    normalized.dispatcher = nil
    normalized.presenter = nil
    normalized.path = nil
    normalized.stream = nil

    return normalized
end

--- Detects conflicting syntax usage
-- @param config table The config to check
-- @return boolean, string True if valid, or false with error message
local function detect_syntax_conflicts(config)
    local has_convenience_fields = schema.is_convenience_syntax(config)
    local has_full_fields = config.dispatchers ~= nil

    if has_convenience_fields and has_full_fields then
        return false,
            "Invalid config: Cannot mix convenience fields (dispatcher/presenter) with full form (dispatchers). " ..
            "Use either: {dispatcher='console', presenter='text'} OR {dispatchers={{type='console', presenter='text'}}}"
    end

    return true
end

-- =============================================================================
-- PUBLIC API
-- =============================================================================

--- Normalizes config format, transforming convenience syntax to full syntax if needed
-- @param config table The input config
-- @return table The normalized config (always in full syntax)
function M.normalize_config_format(config)
    -- Check for syntax conflicts first
    local valid, err = detect_syntax_conflicts(config)
    if not valid then
        error(err)
    end

    -- If convenience syntax, validate and transform
    if schema.is_convenience_syntax(config) then
        valid, err = validate_convenience_config(config)
        if not valid then
            error(err)
        end

        return transform_convenience_to_full(config)
    end

    -- Already in full syntax or no dispatchers, return as-is
    return config
end

--- Checks if config uses convenience syntax (for backward compatibility)
-- @param config table The config to check
-- @return boolean True if convenience syntax
function M.is_convenience_config(config)
    return schema.is_convenience_syntax(config)
end

--- Transforms convenience syntax to full syntax (for backward compatibility)
-- @param config table The convenience syntax config
-- @return table The config in full syntax
function M.convenience_to_full_config(config)
    if not schema.is_convenience_syntax(config) then
        return config
    end

    return transform_convenience_to_full(config)
end

return M
