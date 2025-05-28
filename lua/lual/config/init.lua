--- Main configuration module
-- This module provides the public API and orchestrates all config operations

local validation = require("lual.config.validation")
local transformation = require("lual.config.transformation")

local M = {}

--- Main function to process any config format and return a validated canonical config
-- @param input_config table The input config (can be shortcut, declarative, or partial canonical)
-- @param default_config table Optional default config to merge with
-- @return table The validated canonical config
function M.process_config(input_config, default_config)
    -- Handle nil or empty input config
    if not input_config then
        input_config = {}
    end

    local final_declarative_config = input_config

    -- Check if this is a shortcut config and transform it if needed
    if transformation.is_shortcut_config(input_config) then
        -- Validate the shortcut config
        local valid, err = validation.validate_shortcut_config(input_config)
        if not valid then
            error("Invalid shortcut config: " .. err)
        end

        -- Transform shortcut to standard declarative format
        final_declarative_config = transformation.shortcut_to_declarative_config(input_config)
    else
        -- Validate the standard declarative config
        local valid, err = validation.validate_declarative_config(input_config)
        if not valid then
            error("Invalid declarative config: " .. err)
        end
    end

    -- Apply defaults if provided
    if default_config then
        final_declarative_config = transformation.merge_configs(final_declarative_config, default_config)
    end

    -- Convert to canonical format
    local canonical_config = transformation.declarative_to_canonical_config(final_declarative_config)

    -- Validate the final canonical config
    local valid, err = validation.validate_canonical_config(canonical_config)
    if not valid then
        error("Invalid canonical config: " .. err)
    end

    return canonical_config
end

--- Creates a canonical config with defaults
-- @param config table Optional initial config
-- @return table The canonical config
function M.create_canonical_config(config)
    return transformation.create_canonical_config(config)
end

--- Validates a canonical config
-- @param config table The config to validate
-- @return boolean, string True if valid, or false with error message
function M.validate_canonical_config(config)
    return validation.validate_canonical_config(config)
end

--- Detects if a config is in shortcut format
-- @param config table The config to check
-- @return boolean True if shortcut format
function M.is_shortcut_config(config)
    return transformation.is_shortcut_config(config)
end

--- Transforms shortcut config to declarative format
-- @param config table The shortcut config
-- @return table The declarative config
function M.shortcut_to_declarative_config(config)
    return transformation.shortcut_to_declarative_config(config)
end

-- Export sub-modules for testing and advanced usage
M.validation = validation
M.transformation = transformation

return M
