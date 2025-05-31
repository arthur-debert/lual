--- Configuration normalization utilities
-- This module handles convenience syntax detection and transformation

local schema = require("lual.config.schema")
local validation = require("lual.config.validation")
local table_utils = require("lual.utils.table")

local M = {}

-- =============================================================================
-- CONVENIENCE SYNTAX MAPPINGS
-- =============================================================================

--- Configuration for transforming convenience syntax to full syntax
local CONVENIENCE_MAPPINGS = {
    -- Core fields that always map from convenience to full syntax
    core = {
        dispatcher = "type",
        presenter = "presenter"
    },

    -- Type-specific fields based on dispatcher type
    type_specific = {
        file = {
            path = { target = "path", required = true }
        },
        console = {
            stream = { target = "stream", required = false }
        }
    },

    -- Validation rules for type-specific fields
    validation_rules = {
        file = {
            path = {
                required = true,
                type = "string",
                error_msg = "File dispatcher must have a 'path' string field"
            }
        },
        console = {
            stream = {
                required = false,
                type = "file_handle",
                error_msg = "Console dispatcher 'stream' field must be a file handle"
            }
        }
    },

    -- Fields to remove after transformation (convenience syntax fields)
    cleanup_fields = { "dispatcher", "presenter", "path", "stream" }
}

--- Validates a field according to mapping rules
-- @param field_name string The field name to validate
-- @param value any The value to validate
-- @param dispatcher_type string The dispatcher type for context
-- @return boolean, string True if valid, or false with error message
local function validate_field_by_mapping(field_name, value, dispatcher_type)
    local rules = CONVENIENCE_MAPPINGS.validation_rules[dispatcher_type]
    if not rules or not rules[field_name] then
        return true -- No specific validation rule
    end

    local rule = rules[field_name]

    -- Check if field is required
    if rule.required and value == nil then
        return false, rule.error_msg or (field_name .. " is required")
    end

    -- Skip validation if field is optional and not provided
    if not rule.required and value == nil then
        return true
    end

    -- Type-specific validation
    if rule.type == "string" then
        if type(value) ~= "string" then
            return false, rule.error_msg or (field_name .. " must be a string")
        end
    elseif rule.type == "file_handle" then
        -- File handle validation - check it's not a primitive type
        if type(value) == "string" or type(value) == "number" or type(value) == "boolean" then
            return false, rule.error_msg or (field_name .. " must be a file handle")
        end
    end

    return true
end

-- =============================================================================
-- NORMALIZATION FUNCTIONS
-- =============================================================================



--- Validates convenience syntax config and returns error with proper prefix
-- @param config table The config to validate
-- @return boolean, string True if valid, or false with error message
local function validate_convenience_config(config)
    -- Validate unknown keys
    local valid, err = validation.validate_unknown_keys(config, true)
    if not valid then
        return false, "Invalid convenience config: " .. err
    end

    -- Validate required fields
    valid, err = validation.validate_convenience_requirements(config)
    if not valid then
        return false, "Invalid convenience config: " .. err
    end

    -- Validate basic fields
    valid, err = validation.validate_basic_fields(config, true)
    if not valid then
        return false, err -- Already has prefix
    end

    -- Validate type-specific fields using mapping
    local dispatcher_type = config.dispatcher
    if dispatcher_type then
        local type_mappings = CONVENIENCE_MAPPINGS.type_specific[dispatcher_type]
        if type_mappings then
            for convenience_field, mapping_config in pairs(type_mappings) do
                local value = config[convenience_field]
                valid, err = validate_field_by_mapping(convenience_field, value, dispatcher_type)
                if not valid then
                    return false, "Invalid convenience config: " .. err
                end
            end
        end
    end

    return true
end

--- Transforms convenience syntax to full syntax using mapping configuration
-- @param config table The convenience syntax config
-- @return table The normalized config in full syntax
local function transform_convenience_to_full(config)
    local normalized = table_utils.deepcopy(config)
    local dispatcher_entry = {}

    -- Apply core field mappings
    for convenience_field, full_field in pairs(CONVENIENCE_MAPPINGS.core) do
        if normalized[convenience_field] then
            dispatcher_entry[full_field] = normalized[convenience_field]
        end
    end

    -- Apply type-specific field mappings
    local dispatcher_type = normalized.dispatcher
    local type_mappings = CONVENIENCE_MAPPINGS.type_specific[dispatcher_type]

    if type_mappings then
        for convenience_field, mapping_config in pairs(type_mappings) do
            local value = normalized[convenience_field]

            -- Copy field if it exists (for optional fields) or if required
            if value ~= nil then
                dispatcher_entry[mapping_config.target] = value
            end
        end
    end

    -- Create dispatchers array with the configured entry
    normalized.dispatchers = { dispatcher_entry }

    -- Clean up convenience syntax fields
    for _, field in ipairs(CONVENIENCE_MAPPINGS.cleanup_fields) do
        normalized[field] = nil
    end

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

--- Gets the convenience syntax mappings (for use by other modules)
-- @return table The mappings configuration
function M.get_mappings()
    return CONVENIENCE_MAPPINGS
end

return M
