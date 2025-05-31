--- Main configuration API
-- This module provides the main config processing API

local schema = require("lual.config.schema")
local validation = require("lual.config.validation")
local normalization = require("lual.config.normalization")
local canonicalization = require("lual.config.canonicalization")

local M = {}

-- =============================================================================
-- MAIN CONFIG PROCESSING
-- =============================================================================

--- Main function to process any config syntax and return a validated canonical config
-- @param input_config table The input config (can be convenience or full syntax)
-- @param default_config table Optional default config to merge with
-- @return table The validated canonical config
function M.process_config(input_config, default_config)
    -- Step 1: Normalize convenience syntax to full syntax
    local normalized_config = normalization.normalize_config_format(input_config)

    -- Step 2: Validate the normalized config
    local is_convenience = schema.is_convenience_syntax(input_config)

    -- Validate unknown keys (after normalization, always validate as full syntax)
    local valid, err = validation.validate_unknown_keys(normalized_config, false)
    if not valid then
        local prefix = is_convenience and "Invalid convenience config: " or "Invalid config: "
        error(prefix .. err)
    end

    -- Validate basic fields
    valid, err = validation.validate_basic_fields(normalized_config, is_convenience)
    if not valid then
        error(err) -- Already has prefix
    end

    -- Validate dispatchers
    valid, err = validation.validate_dispatchers(normalized_config.dispatchers)
    if not valid then
        local prefix = is_convenience and "Invalid convenience config: " or "Invalid config: "
        error(prefix .. err)
    end

    -- Step 3: Apply defaults if provided
    local final_config = normalized_config
    if default_config then
        final_config = canonicalization.merge_configs(normalized_config, default_config)
    end

    -- Step 4: Convert to canonical format
    local canonical_config = canonicalization.config_to_canonical(final_config)

    -- Step 5: Validate the final canonical config
    valid, err = validation.validate_canonical_config(canonical_config)
    if not valid then
        error("Invalid canonical config: " .. err)
    end

    return canonical_config
end

-- =============================================================================
-- CONVENIENCE FUNCTIONS
-- =============================================================================

--- Creates a canonical config with defaults
-- @param config table Optional initial config
-- @return table The canonical config
function M.create_canonical_config(config)
    return canonicalization.create_canonical_config(config)
end

--- Clones a config table
-- @param config table The config to clone
-- @return table The cloned config
function M.clone_config(config)
    return canonicalization.clone_config(config)
end

--- Merges configs with user config taking precedence
-- @param user_config table The user config
-- @param default_config table The default config
-- @return table The merged config
function M.merge_configs(user_config, default_config)
    return canonicalization.merge_configs(user_config, default_config)
end

-- =============================================================================
-- VALIDATION FUNCTIONS
-- =============================================================================

--- Validates a canonical config
-- @param config table The config to validate
-- @return boolean, string True if valid, or false with error message
function M.validate_canonical_config(config)
    return validation.validate_canonical_config(config)
end

--- Validates a config (any format)
-- @param config table The config to validate
-- @return boolean, string True if valid, or false with error message
function M.validate_config(config)
    local ok, result = pcall(function()
        local normalized = normalization.normalize_config_format(config)
        local is_convenience = schema.is_convenience_syntax(config)

        local valid, err = validation.validate_unknown_keys(normalized, false)
        if not valid then
            return false, err
        end

        valid, err = validation.validate_basic_fields(normalized, is_convenience)
        if not valid then
            return false, err
        end

        return validation.validate_dispatchers(normalized.dispatchers)
    end)

    if not ok then
        return false, result -- Error message from pcall
    end

    return result
end

--- Converts config to canonical format
-- @param config table The config
-- @return table The canonical config
function M.config_to_canonical(config)
    local normalized = normalization.normalize_config_format(config)
    return canonicalization.config_to_canonical(normalized)
end

-- =============================================================================
-- BACKWARD COMPATIBILITY FUNCTIONS
-- =============================================================================
-- These functions are deprecated and will be removed in a future version.
-- They are aliases for functions that use the term "convenience syntax".

--- Detects if a config uses convenience syntax (backward compatibility)
-- @param config table The config to check
-- @return boolean True if convenience syntax
function M.is_convenience_config_syntax(config)
    return schema.is_convenience_syntax(config)
end

--- Transforms convenience syntax to full syntax (backward compatibility)
-- @param config table The config using convenience syntax
-- @return table The config in full syntax
function M.transform_convenience_config_to_full(config)
    return normalization.convenience_to_full_config(config)
end

return M
