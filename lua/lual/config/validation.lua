--- Configuration validation utilities
-- This module provides reusable validation functions and patterns

local schema = require("lual.config.schema")

local M = {}

-- =============================================================================
-- VALIDATION UTILITIES
-- =============================================================================

--- Validates a field using schema specification
-- @param field_name string Name of the field
-- @param value any Value to validate
-- @param is_convenience boolean Whether this is convenience syntax (for error messages)
-- @return boolean, string True if valid, or false with error message
local function validate_field(field_name, value, is_convenience)
    local validator = schema.FIELD_VALIDATORS[field_name]
    if not validator then
        return true -- Unknown fields are handled separately
    end

    -- Check if nil value is allowed
    if value == nil then
        return validator.optional, validator.optional and nil or (field_name .. " is required")
    end

    -- Use custom validation function
    local valid, err = validator.validate(value)
    if not valid then
        local prefix = is_convenience and "Invalid shortcut config: " or "Invalid config: "
        return false, prefix .. (err or validator.error_msg or ("Invalid " .. field_name))
    end

    return true
end

--- Validates unknown keys in config
-- @param config table The config to validate
-- @param is_convenience boolean Whether this is convenience syntax
-- @return boolean, string True if valid, or false with error message
local function validate_known_keys(config, is_convenience)
    local valid_keys = schema.get_valid_keys(is_convenience)

    for key, _ in pairs(config) do
        if not valid_keys[key] then
            if is_convenience then
                return false, "Unknown shortcut config key: " .. tostring(key)
            else
                return false, "Unknown config key: " .. tostring(key)
            end
        end
    end

    return true
end

--- Validates a single transformer configuration
-- @param transformer table The transformer config to validate
-- @param index number The index of the transformer (for error messages)
-- @return boolean, string True if valid, or false with error message
local function validate_transformer(transformer, index)
    if type(transformer) ~= "table" then
        return false, "Each transformer must be a table"
    end

    if not transformer.type or type(transformer.type) ~= "string" then
        return false, "Each transformer must have a 'type' string field"
    end

    -- Validate transformer type using constants
    local constants = require("lual.config.constants")
    local valid, err = constants.validate_against_constants(transformer.type, constants.VALID_TRANSFORMER_TYPES, false,
        "string")
    if not valid then
        return false, err
    end

    return true
end

--- Validates type-specific fields using mapping system
-- @param dispatcher table The dispatcher config to validate
-- @return boolean, string True if valid, or false with error message
local function validate_type_specific_fields(dispatcher)
    local normalization = require("lual.config.normalization")
    local mappings = normalization.get_mappings()

    local dispatcher_type = dispatcher.type
    local validation_rules = mappings.validation_rules[dispatcher_type]

    if not validation_rules then
        return true -- No specific validation rules for this type
    end

    for field_name, rule in pairs(validation_rules) do
        local value = dispatcher[field_name]

        -- Check if field is required
        if rule.required and value == nil then
            return false, rule.error_msg or (field_name .. " is required")
        end

        -- Skip validation if field is optional and not provided
        if not rule.required and value == nil then
            goto continue
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

        ::continue::
    end

    return true
end

--- Validates a single dispatcher configuration
-- @param dispatcher table The dispatcher config to validate
-- @param index number The index of the dispatcher (for error messages)
-- @return boolean, string True if valid, or false with error message
local function validate_dispatcher_config(dispatcher, index)
    if type(dispatcher) ~= "table" then
        return false, "Each dispatcher must be a table"
    end

    if not dispatcher.type or type(dispatcher.type) ~= "string" then
        return false, "Each dispatcher must have a 'type' string field"
    end

    if not dispatcher.presenter or type(dispatcher.presenter) ~= "string" then
        return false, "Each dispatcher must have a 'presenter' string field"
    end

    -- Validate dispatcher type using constants directly
    local constants = require("lual.config.constants")
    local valid, err = constants.validate_against_constants(dispatcher.type, constants.VALID_dispatcher_TYPES, false,
        "string")
    if not valid then
        return false, err
    end

    -- Validate presenter type using constants directly
    valid, err = constants.validate_against_constants(dispatcher.presenter, constants.VALID_PRESENTER_TYPES, false,
        "string")
    if not valid then
        return false, err
    end

    -- Validate transformers if present
    if dispatcher.transformers then
        if type(dispatcher.transformers) ~= "table" then
            return false, "Dispatcher transformers must be a table"
        end

        for i, transformer in ipairs(dispatcher.transformers) do
            valid, err = validate_transformer(transformer, i)
            if not valid then
                return false, err
            end
        end
    end

    -- Validate type-specific fields using mapping system
    valid, err = validate_type_specific_fields(dispatcher)
    if not valid then
        return false, err
    end

    return true
end

-- =============================================================================
-- PUBLIC VALIDATION FUNCTIONS
-- =============================================================================

--- Validates basic config fields using schema
-- @param config table The config to validate
-- @param is_convenience boolean Whether this is convenience syntax
-- @return boolean, string True if valid, or false with error message
function M.validate_basic_fields(config, is_convenience)
    for field_name, value in pairs(config) do
        if field_name ~= "dispatchers" then -- Handle dispatchers separately
            local valid, err = validate_field(field_name, value, is_convenience)
            if not valid then
                return false, err
            end
        end
    end

    return true
end

--- Validates unknown keys
-- @param config table The config to validate
-- @param is_convenience boolean Whether this is convenience syntax
-- @return boolean, string True if valid, or false with error message
function M.validate_unknown_keys(config, is_convenience)
    return validate_known_keys(config, is_convenience)
end

--- Validates dispatchers array
-- @param dispatchers table The dispatchers array to validate
-- @return boolean, string True if valid, or false with error message
function M.validate_dispatchers(dispatchers)
    if dispatchers == nil then
        return true -- dispatchers is optional
    end

    if type(dispatchers) ~= "table" then
        return false, "Config.dispatchers must be a table"
    end

    for i, dispatcher in ipairs(dispatchers) do
        local valid, err = validate_dispatcher_config(dispatcher, i)
        if not valid then
            return false, err
        end
    end

    return true
end

--- Validates a canonical config (runtime format)
-- @param config table The canonical config to validate
-- @return boolean, string True if valid, or false with error message
function M.validate_canonical_config(config)
    if type(config) ~= "table" then
        return false, "Config must be a table"
    end

    if config.name and type(config.name) ~= "string" then
        return false, "Config.name must be a string"
    end

    if config.level and type(config.level) ~= "number" then
        return false, "Config.level must be a number"
    end

    if config.dispatchers and type(config.dispatchers) ~= "table" then
        return false, "Config.dispatchers must be a table"
    end

    if config.propagate ~= nil and type(config.propagate) ~= "boolean" then
        return false, "Config.propagate must be a boolean"
    end

    -- Validate timezone using constants directly
    local constants = require("lual.config.constants")
    local valid, err = constants.validate_against_constants(config.timezone, constants.VALID_TIMEZONES, true, "string")
    if not valid then
        return false, err
    end

    -- Validate dispatchers structure (canonical format)
    if config.dispatchers then
        for i, dispatcher in ipairs(config.dispatchers) do
            if type(dispatcher) ~= "table" then
                return false, "Each dispatcher must be a table"
            end
            if not dispatcher.dispatcher_func or type(dispatcher.dispatcher_func) ~= "function" then
                return false, "Each dispatcher must have a dispatcher_func function"
            end
            if not dispatcher.presenter_func or (type(dispatcher.presenter_func) ~= "function" and not (type(dispatcher.presenter_func) == "table" and getmetatable(dispatcher.presenter_func) and getmetatable(dispatcher.presenter_func).__call)) then
                return false, "Each dispatcher must have a presenter_func function"
            end
            -- Validate transformer_funcs if present
            if dispatcher.transformer_funcs then
                if type(dispatcher.transformer_funcs) ~= "table" then
                    return false, "Each dispatcher transformer_funcs must be a table"
                end
                for j, transformer_func in ipairs(dispatcher.transformer_funcs) do
                    if not (type(transformer_func) == "function" or (type(transformer_func) == "table" and getmetatable(transformer_func) and getmetatable(transformer_func).__call)) then
                        return false, "Each transformer must be a function or callable table"
                    end
                end
            end
        end
    end

    return true
end

--- Validates convenience syntax requirements
-- @param config table The config to validate
-- @return boolean, string True if valid, or false with error message
function M.validate_convenience_requirements(config)
    if not config.dispatcher then
        return false, "Shortcut config must have an 'dispatcher' field"
    end
    if not config.presenter then
        return false, "Shortcut config must have a 'presenter' field"
    end
    return true
end

--- Validates type-specific convenience fields (legacy function, now uses mapping system)
-- @param config table The config to validate
-- @return boolean, string True if valid, or false with error message
function M.validate_convenience_type_fields(config)
    -- This function is now handled by the mapping system in normalization.lua
    -- but kept for backward compatibility
    local normalization = require("lual.config.normalization")
    local mappings = normalization.get_mappings()

    local dispatcher_type = config.dispatcher
    local validation_rules = mappings.validation_rules[dispatcher_type]

    if not validation_rules then
        return true -- No specific validation rules for this type
    end

    for field_name, rule in pairs(validation_rules) do
        local value = config[field_name]

        -- Check if field is required
        if rule.required and value == nil then
            return false, rule.error_msg or (field_name .. " is required")
        end

        -- Skip validation if field is optional and not provided
        if not rule.required and value == nil then
            goto continue
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

        ::continue::
    end

    return true
end

return M
