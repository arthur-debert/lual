# Transformers

Transformers are functions that modify log records before they are passed to
presenters. They allow you to alter the data in log records without changing the
original logging call.

## Overview

In the lual logging library, the data flow is:

```
Logger -> Transformers -> Presenter -> Dispatcher
```

Transformers sit between the logger and the presenter, allowing you to:

- Add fields to log records
- Modify existing fields
- Filter or enrich log data
- Transform data formats

## Basic Usage

### Declarative Configuration

You can add transformers to dispatchers in your logger configuration:

```lua
local lual = require("lual.logger")

local logger = lual.logger({
    name = "app",
    level = "info",
    dispatchers = {
        {
            type = "console",
            presenter = "text",
            transformers = {
                { type = "noop" }
            }
        }
    }
})
```

### Multiple Transformers

Transformers are applied in sequence. You can chain multiple transformers:

```lua
local logger = lual.logger({
    name = "app",
    level = "info",
    dispatchers = {
        {
            type = "console",
            presenter = "text",
            transformers = {
                { type = "noop" },
                { type = "noop" }
            }
        }
    }
})
```

## Built-in Transformers

### No-op Transformer

The `noop` transformer is a pass-through transformer that returns the record
unchanged. It's useful for testing and as a template for custom transformers.

```lua
transformers = {
    { type = "noop" }
}
```

## Creating Custom Transformers

Transformers follow the same pattern as presenters - they are factory functions
that return callable tables with schemas.

### Basic Transformer Structure

```lua
--- Factory that creates a custom transformer function
-- @param config (table, optional) Configuration for the transformer
-- @return function The transformer function with schema attached
local function custom_transformer_factory(config)
    config = config or {}

    -- Create the actual transformer function
    local function transformer_func(record)
        -- Create a copy of the record
        local transformed_record = {}
        for k, v in pairs(record) do
            transformed_record[k] = v
        end

        -- Modify the record as needed
        -- transformed_record.some_field = "some_value"

        return transformed_record
    end

    -- Create a callable table with schema
    local transformer_with_schema = {
        schema = {} -- Define configuration schema here
    }

    -- Make it callable
    setmetatable(transformer_with_schema, {
        __call = function(_, record)
            return transformer_func(record)
        end
    })

    return transformer_with_schema
end

return custom_transformer_factory
```

### Example: Prefix Transformer

Here's an example transformer that adds a prefix to the message format:

```lua
local function prefix_transformer_factory(config)
    config = config or {}
    local prefix = config.prefix or "[TRANSFORMED] "

    local function transformer_func(record)
        local transformed_record = {}
        for k, v in pairs(record) do
            transformed_record[k] = v
        end

        if transformed_record.message_fmt then
            transformed_record.message_fmt = prefix .. transformed_record.message_fmt
        end

        return transformed_record
    end

    local transformer_with_schema = {
        schema = {
            prefix = { type = "string", required = false }
        }
    }

    setmetatable(transformer_with_schema, {
        __call = function(_, record)
            return transformer_func(record)
        end
    })

    return transformer_with_schema
end
```

## Log Record Structure

Transformers receive log records with the following structure:

```lua
{
    level_name = "INFO",           -- String level name
    level_no = 20,                 -- Numeric level
    logger_name = "app.module",    -- Logger name
    message_fmt = "User %s logged in", -- Message format string
    args = {"john"},               -- Format arguments
    context = {...},               -- Optional context data
    timestamp = 1678886400,        -- Unix timestamp
    filename = "app.lua",          -- Source filename
    lineno = 42,                   -- Source line number
    source_logger_name = "app.module" -- Original logger name
}
```

## Error Handling

If a transformer fails, the logging system will:

1. Log an error message to stderr
2. Continue with the original, unmodified record
3. Process subsequent transformers normally

This ensures that logging continues to work even if a transformer has bugs.

## Public API

Transformers are available through the public API:

```lua
local lual = require("lual.logger")

-- Access transformer factories
local noop = lual.transformers.noop_transformer()

-- Or use shortcuts
local noop_shortcut = lual.lib.noop
```

## Best Practices

1. **Always copy the record**: Don't modify the original record, create a copy
2. **Handle missing fields**: Check if fields exist before modifying them
3. **Keep transformers simple**: Each transformer should do one thing well
4. **Test error conditions**: Ensure your transformers handle edge cases
   gracefully
5. **Document configuration**: Provide clear schemas for transformer
   configuration

## Schema Validation

Transformers are validated using the same schema system as dispatchers and
presenters. The transformer type must be registered in the constants and schema
definitions.

To add a new transformer type:

1. Add it to `VALID_TRANSFORMER_TYPES` in `lua/lual/config/constants.lua`
2. Update the config processing in `lua/lual/config.lua` to handle the new type
3. Add the transformer to `lua/lual/transformers/init.lua`
