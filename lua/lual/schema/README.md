# Schema-based Validation System

This module provides a schema-based validation system for the lual configuration
system. It replaces the previous ad-hoc validation with a structured,
declarative approach.

## Features

- **Declarative schemas**: Define validation rules in a clear, structured format
- **Type validation**: Validate field types (string, number, boolean, table,
  userdata)
- **Enum validation**: Validate against predefined sets of values
  (case-insensitive)
- **Required field validation**: Mark fields as required or optional
- **Conditional validation**: Fields can be required based on other field values
- **Nested validation**: Support for validating arrays and nested objects
- **Comprehensive error reporting**: Returns detailed error information for each
  invalid field

## Usage

```lua
local schema = require("lual.schema")

-- Validate a configuration
local config = {
    name = "my.logger",
    level = "info",
    dispatchers = {
        { type = "console", presenter = "text" }
    }
}

local result = schema.validate_config(config)

-- Check for errors
if next(result._errors) then
    -- Handle validation errors
    for field, error_msg in pairs(result._errors) do
        print("Error in " .. field .. ": " .. error_msg)
    end
else
    -- Use validated data
    local validated_config = result.data
end
```

## Return Format

The validation functions return a table with two keys:

- `data`: Contains all the validated data with the same structure as input
- `_errors`: Contains error messages for invalid fields (empty if no errors)

For fields that fail validation, the original value is preserved in `data`, but
the field will also appear in `_errors`. Always check `_errors` first before
using the data.

## Schema Definition

Schemas are defined as tables where each key represents a field name and the
value defines the validation rules:

```lua
field_name = {
    multiple = false,           -- Whether this is an array field
    type = "string",           -- Expected type(s) - can be string or array
    values = {...},            -- Valid enum values (optional)
    required = true,           -- Whether field is required
    description = "...",       -- Field description
    conditional = {            -- Conditional requirements (optional)
        field = "other_field",
        value = "some_value",
        required = true
    },
    schema = "NestedSchema"    -- Reference to nested schema (optional)
}
```

## Available Schemas

- `ConfigSchema`: Main configuration validation
- `dispatcherschema`: dispatcher configuration validation

## Files

- `config_schema.lua`: Schema definitions
- `validator.lua`: Core validation logic
- `init.lua`: Main module interface
- `README.md`: This documentation
