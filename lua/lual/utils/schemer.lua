--[[

Schemer - A Lightweight Lua Schema Validation Library

Schemer helps validate configuration or data entry against a defined schema.
It's lightweight, expressive, and has a small footprint, designed for validating
structured data with comprehensive error reporting and data normalization.

Principles:
    - Well-balanced feature set: expressive yet small
    - Field-level validations with descriptive error reporting
    - Cross-field validations for complex configurations
    - Support for recursive schemas and nested validation
    - Data normalization with defaults and enum transformations
    - Consistent error codes for programmatic error handling

Key Features:
    ✓ Basic type validation (string, number, boolean, table, function)
    ✓ Value constraints (enums, allowed values, ranges)
    ✓ String validations (length, patterns)
    ✓ Number validations (min/max ranges)
    ✓ Array/table validations (count, element validation)
    ✓ Nested schema validation
    ✓ Cross-field dependencies and exclusions
    ✓ Default value application
    ✓ Enum reverse lookup and transformation

Example Usage:

    local schemer = require("lual.utils.schemer")

    -- Define an enum with reverse lookup support
    local LEVELS = { DEBUG = 1, INFO = 2, WARN = 3, ERROR = 4 }

    local schema = {
        fields = {
            -- Enum field with reverse lookup (accepts "DEBUG" -> transforms to 1)
            level = {
                type = "number",
                required = false,
                values = schemer.enum(LEVELS, { reverse = true }),
                default = LEVELS.INFO
            },

            -- String field with constraints
            name = {
                type = "string",
                required = true,
                pattern = "^%w+$",
                min_len = 3,
                max_len = 50
            },

            -- Array field with count and element validation
            items = {
                type = "table",
                count = { 1, "*" }, -- At least one item required
                each = { type = "string" }
            },

            -- Nested schema
            config = {
                type = "table",
                fields = {
                    timeout = { type = "number", min = 1, default = 30 },
                    enabled = { type = "boolean", default = true }
                }
            }
        },

        -- Cross-field validations
        one_of = { "items", "config" },                    -- At least one must be present
        depends_on = { field = "config", requires = "name" }, -- If config exists, name must exist
        exclusive = { "debug_mode", "production_mode" }    -- These cannot both be present
    }

    -- Validate data
    local data = { level = "DEBUG", name = "test", items = { "a", "b" } }
    local err, result = schemer.validate(data, schema)

    if err then
        print("Validation failed:", err.error)
        -- Access field-specific errors via err.fields[field_name]
        -- Access cross-field errors via err.all
    else
        -- result contains normalized data with defaults applied
        print("Level:", result.level) -- Will be 1 (transformed from "DEBUG")
    end

API Reference:

Functions:
    schemer.validate(data, schema) -> error_table|nil, normalized_data|nil
        Validates data against the provided schema.

        Parameters:
            data (table): The data to validate
            schema (table): The schema definition

        Returns:
            On success: nil, normalized_data
            On failure: error_table, nil

        Error table structure:
            {
                fields = { field_name = { {error_code, error_message}, ... }, ... },
                all = { {error_code, error_message}, ... }, -- Cross-field errors
                error = "Human readable summary",
                data = original_data,
                schema = schema_used
            }

    schemer.enum(enum_table, options) -> enum_definition
        Creates an enum definition for use in value validation.

        Parameters:
            enum_table (table): Key-value pairs for the enum
            options (table, optional): { reverse = boolean }
                reverse: If true, allows string keys to be transformed to values

        Returns:
            { enum = enum_table, reverse = boolean }

Schema Structure:

Field Schema Properties:
    type (string): Required type ("string", "number", "boolean", "table", "function")
    required (boolean): Whether field is required (default: false)
    default (any): Default value when field is missing

    For all types:
        values (table|enum_def): List of allowed values or enum definition

    For strings:
        min_len (number): Minimum string length
        max_len (number): Maximum string length
        pattern (string): Lua pattern for validation

    For numbers:
        min (number): Minimum value (inclusive)
        max (number): Maximum value (inclusive)

    For tables:
        count (table): {min, max} item count. Use "*" for unlimited max
        each (schema): Schema applied to each array element
        fields (table): Schema for nested object validation

Cross-field Schema Properties:
    one_of (table): List of fields where at least one must be present
    depends_on (table): { field = "field_name", requires = "required_field" }
    exclusive (table): List of fields that cannot be present together

Error Codes:
    INVALID_TYPE: Type mismatch
    REQUIRED_FIELD: Required field missing
    INVALID_VALUE: Value not in allowed set
    STRING_TOO_SHORT: String below minimum length
    STRING_TOO_LONG: String exceeds maximum length
    PATTERN_MISMATCH: String doesn't match pattern
    NUMBER_TOO_SMALL: Number below minimum
    NUMBER_TOO_LARGE: Number above maximum
    INVALID_COUNT: Table item count outside allowed range
    ONE_OF_MISSING: None of the required fields present
    DEPENDENCY_MISSING: Required dependency field missing
    EXCLUSIVE_CONFLICT: Mutually exclusive fields both present

--]]

local schemer = {}

-- Error codes for consistent error reporting
local ERROR_CODES = {
    INVALID_TYPE = "INVALID_TYPE",
    REQUIRED_FIELD = "REQUIRED_FIELD",
    INVALID_VALUE = "INVALID_VALUE",
    STRING_TOO_SHORT = "STRING_TOO_SHORT",
    STRING_TOO_LONG = "STRING_TOO_LONG",
    PATTERN_MISMATCH = "PATTERN_MISMATCH",
    NUMBER_TOO_SMALL = "NUMBER_TOO_SMALL",
    NUMBER_TOO_LARGE = "NUMBER_TOO_LARGE",
    INVALID_COUNT = "INVALID_COUNT",
    ONE_OF_MISSING = "ONE_OF_MISSING",
    DEPENDENCY_MISSING = "DEPENDENCY_MISSING",
    EXCLUSIVE_CONFLICT = "EXCLUSIVE_CONFLICT"
}

-- Helper function for enum definitions
function schemer.enum(enum_table, options)
    options = options or {}
    return { enum = enum_table, reverse = options.reverse or false }
end

-- Helper function to deep copy a table
local function deep_copy(obj)
    if type(obj) ~= 'table' then return obj end
    local copy = {}
    for k, v in pairs(obj) do
        copy[k] = deep_copy(v)
    end
    return copy
end

-- Helper function to check if a value is in a list
local function has_value(list, value)
    for _, v in ipairs(list) do
        if v == value then return true end
    end
    return false
end

-- Helper function to validate count specification
local function validate_count(count, actual_count)
    if type(count) ~= 'table' or #count ~= 2 then
        return false, "Count specification must be a table with exactly 2 elements"
    end

    local min, max = count[1], count[2]

    -- Handle '*' as infinity
    if max == "*" then
        return actual_count >= min, string.format("Expected at least %d items, got %d", min, actual_count)
    end

    if actual_count < min or actual_count > max then
        return false, string.format("Expected between %d and %d items, got %d", min, max, actual_count)
    end

    return true
end

-- Validate a single field against its schema
local function validate_field(value, field_schema, field_name, data)
    local errors = {}

    -- Handle required/optional fields
    if value == nil then
        if field_schema.required then
            table.insert(errors, { ERROR_CODES.REQUIRED_FIELD, string.format("Field '%s' is required", field_name) })
        end
        return errors, field_schema.default
    end

    -- Check if we have an enum with reverse lookup that can transform the value
    local transformed_value = value
    local enum_transformed = false

    if field_schema.values and type(field_schema.values) == 'table' and
        field_schema.values.enum and field_schema.values.reverse then
        -- Check if value is a key in the enum
        for k, v in pairs(field_schema.values.enum) do
            if k == value then
                transformed_value = v
                enum_transformed = true
                break
            end
        end
    end

    -- Type validation (use transformed value if we had enum transformation)
    if field_schema.type then
        local check_value
        if enum_transformed then
            check_value = transformed_value
        else
            check_value = value
        end

        -- Allow nil values from successful enum transformation
        if not (enum_transformed and check_value == nil) then
            local actual_type = type(check_value)
            if actual_type ~= field_schema.type then
                local is_reverse_enum = field_schema.values and type(field_schema.values) == 'table' and
                    field_schema.values.enum and field_schema.values.reverse

                -- For reverse enums, an un-transformed value of the wrong type
                -- is an invalid key, not a type error. Let value validation handle it.
                if not (is_reverse_enum and not enum_transformed) then
                    table.insert(errors, { ERROR_CODES.INVALID_TYPE,
                        string.format("Field '%s' must be of type %s, got %s", field_name, field_schema.type, actual_type) })
                    return errors, value -- Return early on type mismatch
                end
            end
        end
    end

    -- Values/enum validation
    if field_schema.values then
        local is_valid = false
        local final_value = value

        if type(field_schema.values) == 'table' and field_schema.values.enum then
            -- Handle enum
            local enum_def = field_schema.values
            if enum_def.reverse then
                -- For reverse lookup, check if we already transformed it or if it's a valid enum value
                if enum_transformed then
                    is_valid = true
                    final_value = transformed_value
                else
                    -- Check if it's already a valid enum value
                    for _, v in pairs(enum_def.enum) do
                        if v == value then
                            is_valid = true
                            break
                        end
                    end
                end
            else
                -- Normal enum - check if value is in enum values
                for _, v in pairs(enum_def.enum) do
                    if v == value then
                        is_valid = true
                        break
                    end
                end
            end
        else
            -- Simple list of allowed values
            is_valid = has_value(field_schema.values, value)
        end

        if not is_valid then
            table.insert(errors, { ERROR_CODES.INVALID_VALUE,
                string.format("Field '%s' has invalid value", field_name) })
            return errors, value -- Return early on value validation failure
        else
            value = final_value  -- Apply enum transformation if applicable
        end
    end

    -- String-specific validations
    if field_schema.type == 'string' and type(value) == 'string' then
        if field_schema.min_len and #value < field_schema.min_len then
            table.insert(errors, { ERROR_CODES.STRING_TOO_SHORT,
                string.format("Field '%s' must be at least %d characters long", field_name, field_schema.min_len) })
        end

        if field_schema.max_len and #value > field_schema.max_len then
            table.insert(errors, { ERROR_CODES.STRING_TOO_LONG,
                string.format("Field '%s' must be at most %d characters long", field_name, field_schema.max_len) })
        end

        if field_schema.pattern and not string.match(value, field_schema.pattern) then
            table.insert(errors, { ERROR_CODES.PATTERN_MISMATCH,
                string.format("Field '%s' does not match required pattern", field_name) })
        end
    end

    -- Number-specific validations
    if field_schema.type == 'number' and type(value) == 'number' then
        if field_schema.min and value < field_schema.min then
            table.insert(errors, { ERROR_CODES.NUMBER_TOO_SMALL,
                string.format("Field '%s' must be at least %s", field_name, tostring(field_schema.min)) })
        end

        if field_schema.max and value > field_schema.max then
            table.insert(errors, { ERROR_CODES.NUMBER_TOO_LARGE,
                string.format("Field '%s' must be at most %s", field_name, tostring(field_schema.max)) })
        end
    end

    -- Table/array-specific validations
    if field_schema.type == 'table' and type(value) == 'table' then
        -- Count validation
        if field_schema.count then
            local count = 0
            for _ in pairs(value) do count = count + 1 end
            local is_valid, err_msg = validate_count(field_schema.count, count)
            if not is_valid then
                table.insert(errors, { ERROR_CODES.INVALID_COUNT,
                    string.format("Field '%s': %s", field_name, err_msg) })
            end
        end

        -- Each element validation
        if field_schema.each then
            for i, item in ipairs(value) do
                local item_errors, normalized_item = validate_field(item, field_schema.each,
                    field_name .. "[" .. i .. "]", data)
                for _, err in ipairs(item_errors) do
                    table.insert(errors, err)
                end
                value[i] = normalized_item
            end
        end

        -- Nested fields validation
        if field_schema.fields then
            local nested_errors, normalized_nested = schemer.validate(value, { fields = field_schema.fields })
            if nested_errors then
                for field, field_errors in pairs(nested_errors.fields or {}) do
                    for _, err in ipairs(field_errors) do
                        table.insert(errors, { err[1], string.format("%s.%s: %s", field_name, field, err[2]) })
                    end
                end
            else
                value = normalized_nested
            end
        end
    end

    return errors, value
end

-- Cross-field validations
local function validate_cross_fields(data, schema)
    local errors = {}

    -- one_of validation
    if schema.one_of then
        local found = false
        for _, field in ipairs(schema.one_of) do
            if data[field] ~= nil then
                found = true
                break
            end
        end
        if not found then
            table.insert(errors, { ERROR_CODES.ONE_OF_MISSING,
                string.format("At least one of these fields must be present: %s", table.concat(schema.one_of, ", ")) })
        end
    end

    -- depends_on validation
    if schema.depends_on then
        local dep = schema.depends_on
        if data[dep.field] ~= nil and data[dep.requires] == nil then
            table.insert(errors, { ERROR_CODES.DEPENDENCY_MISSING,
                string.format("Field '%s' requires field '%s' to be present", dep.field, dep.requires) })
        end
    end

    -- exclusive validation
    if schema.exclusive then
        local present_fields = {}
        for _, field in ipairs(schema.exclusive) do
            if data[field] ~= nil then
                table.insert(present_fields, field)
            end
        end
        if #present_fields > 1 then
            table.insert(errors, { ERROR_CODES.EXCLUSIVE_CONFLICT,
                string.format("These fields cannot be present together: %s", table.concat(present_fields, ", ")) })
        end
    end

    return errors
end

-- Main validation function
function schemer.validate(data, schema)
    if type(data) ~= 'table' then
        return {
            fields = {},
            all = { { ERROR_CODES.INVALID_TYPE, "Data must be a table" } },
            error = "Data must be a table",
            data = data,
            schema = schema
        }
    end

    local result = deep_copy(data)
    local field_errors = {}

    -- Validate individual fields
    if schema.fields then
        for field_name, field_schema in pairs(schema.fields) do
            local field_errors_list, normalized_value = validate_field(data[field_name], field_schema, field_name, data)

            if #field_errors_list > 0 then
                field_errors[field_name] = field_errors_list
            end

            -- Apply normalized value (including defaults)
            if normalized_value ~= nil or data[field_name] ~= nil then
                result[field_name] = normalized_value
            end
        end
    end

    -- Cross-field validations
    local cross_field_errors = validate_cross_fields(data, schema)

    -- Check if there are any errors
    if next(field_errors) or #cross_field_errors > 0 then
        local error_msg = "Validation failed"
        if next(field_errors) then
            local field_names = {}
            for field_name, _ in pairs(field_errors) do
                table.insert(field_names, field_name)
            end
            error_msg = error_msg .. " for fields: " .. table.concat(field_names, ", ")
        end

        return {
            fields = field_errors,
            all = cross_field_errors,
            error = error_msg,
            data = data,
            schema = schema
        }
    end

    return nil, result
end

-- Export error codes for external use
schemer.ERROR_CODES = ERROR_CODES

return schemer
