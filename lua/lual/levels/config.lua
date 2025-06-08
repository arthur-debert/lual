--- Levels Configuration Handler
-- This module handles both 'level' and 'custom_levels' configuration keys

local core_levels = require("lual.levels")
local schemer = require("lual.utils.schemer")
local levels_schema_module = require("lual.levels.schema")

local M = {}

--- Validates level configuration
-- @param level number The level value to validate
-- @param full_config table The full configuration context
-- @return boolean, string True if valid, otherwise false and error message
local function validate_level(level, full_config)
    -- Use schemer for validation
    local errors = schemer.validate({ level = level }, levels_schema_module.get_level_schema())
    if errors then
        if errors.fields and errors.fields.level then
            local error_code = errors.fields.level[1][1]
            if error_code == "INVALID_TYPE" then
                return false,
                    "Invalid type for 'level': expected number, got " ..
                    type(level) .. ". Logging level (use lual.DEBUG, lual.INFO, etc.)"
            elseif error_code == "INVALID_VALUE" then
                local all_levels = core_levels.get_all_levels()
                local valid_levels = {}
                for level_name, level_value in pairs(all_levels) do
                    table.insert(valid_levels, string.format("%s(%d)", level_name, level_value))
                end
                table.sort(valid_levels)
                return false,
                    string.format("Invalid level value %d. Valid levels are: %s", level, table.concat(valid_levels, ", "))
            elseif error_code == "FORBIDDEN_VALUE" then
                return false, "Root logger level cannot be set to NOTSET"
            end
        end
        return false, errors.error
    end

    return true
end

--- Validates custom levels configuration
-- @param custom_levels table Custom levels configuration to validate
-- @param full_config table The full configuration context
-- @return boolean, string True if valid, otherwise false and error message
local function validate_custom_levels(custom_levels, full_config)
    -- Use schemer for comprehensive validation (handles all business rules declaratively)
    -- Wrap data to match schema structure
    local errors = schemer.validate({ custom_levels = custom_levels }, levels_schema_module.get_custom_levels_schema())
    if errors then
        -- Extract specific error code and convert to appropriate error message
        if errors.fields and errors.fields.custom_levels then
            local field_error = errors.fields.custom_levels[1]
            if field_error then
                local error_code = field_error[1]
                local error_message = field_error[2]

                -- Convert schema error codes to domain-specific error messages for backward compatibility
                if error_code == "DUPLICATE_VALUE" then
                    -- Extract duplicate value from the message
                    local duplicate_value = error_message:match("duplicate value '([^']+)'")
                    return false, "Duplicate level value " .. duplicate_value
                elseif error_code == "CUSTOM_VALIDATION_FAILED" then
                    -- For custom validation, extract the actual validation error
                    local actual_error = error_message:match("Field 'custom_levels': (.+)")
                    return false, actual_error or error_message
                end

                return false, error_message
            end
        end
        return false, errors.error
    end

    return true
end

--- Creates handlers for both level-related config keys
-- @return table Table with handlers for 'level' and 'custom_levels'
function M.create_handlers()
    local handlers = {}

    -- Handler for 'level' config key
    handlers.level = {
        validate = function(level, full_config)
            return validate_level(level, full_config)
        end,
        apply = function(level, current_config)
            return level
        end
    }

    -- Handler for 'custom_levels' config key
    handlers.custom_levels = {
        validate = function(custom_levels, full_config)
            return validate_custom_levels(custom_levels, full_config)
        end,
        apply = function(custom_levels, current_config)
            -- Apply custom levels to the core levels module
            core_levels.set_custom_levels(custom_levels)

            -- We don't return custom_levels to store in config since they're applied globally
            return nil
        end
    }

    return handlers
end

return M
