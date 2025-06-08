--- Test Helper Functions
-- Common utilities for testing validation and error handling

local M = {}

--- Extracts the first error code from a schemer validation result
-- @param validation_result table The result from schemer.validate()
-- @param field_name string Optional specific field to get error code for
-- @return string|nil The error code, or nil if no error
function M.get_error_code(validation_result, field_name)
    if not validation_result then
        return nil
    end

    if field_name and validation_result.fields and validation_result.fields[field_name] then
        local field_errors = validation_result.fields[field_name]
        if field_errors and #field_errors > 0 then
            return field_errors[1][1] -- Return error code from first error
        end
    elseif validation_result.fields then
        -- Return first error code from any field
        for _, field_errors in pairs(validation_result.fields) do
            if field_errors and #field_errors > 0 then
                return field_errors[1][1]
            end
        end
    end

    if validation_result.all and #validation_result.all > 0 then
        return validation_result.all[1][1] -- Cross-field error code
    end

    return nil
end

--- Validates data with schemer and returns error code
-- @param data any The data to validate
-- @param schema table The schemer schema
-- @param field_name string Optional specific field to get error code for
-- @return string|nil The error code, or nil if validation passed
function M.validate_and_get_error_code(data, schema, field_name)
    local schemer = require("lual.utils.schemer")
    local errors = schemer.validate(data, schema)
    return M.get_error_code(errors, field_name)
end

return M
