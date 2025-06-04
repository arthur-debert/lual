# lual Component System

The lual logging library uses a component-based pipeline architecture for log processing. This document explains how to use the component system and configure the various pipeline stages.

## Overview

A logging pipeline in lual consists of three main component types:

1. **Dispatchers**: Responsible for sending log messages to destinations (console, files, network, etc.)
2. **Transformers**: Modify log records by adding, removing, or transforming fields
3. **Presenters**: Format log records into strings for output (text, JSON, etc.)

## Component Format

All components (dispatchers, transformers, presenters) can be provided in exactly two formats:

### 1. Simple Function

```lua
function(record, config) ... end
```

### 2. Table with Function as First Element

```lua
{ my_func, level = lual.debug, some_config = value }
```

This format allows you to pass configuration options along with the function.

## Configuring Dispatchers

Dispatchers determine where log messages are sent. Built-in dispatchers include:

- `lual.console`: Output to console (stdout/stderr)
- `lual.file`: Write to files with optional rotation
- `lual.syslog`: Send to syslog (if available)

### Console Dispatcher

```lua
-- Basic usage
lual.config({
    dispatchers = { lual.console }
})

-- With configuration
lual.config({
    dispatchers = {
        { lual.console, level = lual.warning, stream = io.stderr }
    }
})
```

### File Dispatcher

```lua
lual.config({
    dispatchers = {
        { 
            lual.file,
            path = "app.log",
            level = lual.info,
            max_size = 10 * 1024 * 1024, -- 10 MB
            max_backups = 5
        }
    }
})
```

## Dispatcher-Specific Levels

Each dispatcher can have its own level filter, which is applied after the logger's level check:

```lua
lual.config({
    level = lual.debug, -- Logger processes all debug and above
    dispatchers = {
        { lual.file, level = lual.debug, path = "debug.log" },  -- File gets all logs
        { lual.console, level = lual.warning }                  -- Console only gets warnings and errors
    }
})
```

## Configuring Presenters

Presenters format log records into strings. Built-in presenters include:

- `lual.text()`: Simple text format
- `lual.json()`: JSON format
- `lual.color()`: Colorized text for terminals

```lua
-- Text presenter with UTC timezone
lual.config({
    dispatchers = {
        { 
            lual.console,
            presenter = lual.text({ timezone = "utc" })
        }
    }
})

-- JSON presenter with pretty printing
lual.config({
    dispatchers = {
        { 
            lual.file,
            path = "app.log",
            presenter = lual.json({ pretty = true })
        }
    }
})
```

## Configuring Transformers

Transformers modify log records before they're formatted by presenters.

```lua
-- Add a custom field to all logs
local function add_app_version(record)
    record.app_version = "1.0.0"
    return record
end

lual.config({
    dispatchers = {
        { 
            lual.file,
            path = "app.log",
            transformers = { add_app_version }
        }
    }
})
```

## Using Multiple Transformers

Transformers are applied in sequence:

```lua
lual.config({
    dispatchers = {
        { 
            lual.file,
            path = "app.log",
            transformers = {
                -- First transformer adds hostname
                function(record)
                    record.hostname = "server1"
                    return record
                end,
                -- Second transformer adds timestamp components
                function(record)
                    local time = os.date("*t", record.timestamp)
                    record.year = time.year
                    record.month = time.month
                    record.day = time.day
                    return record
                end
            },
            presenter = lual.json()
        }
    }
})
```

## Creating Custom Components

You can create custom components for any part of the pipeline:

### Custom Transformer

```lua
function add_request_id(record, config)
    -- Default value or from config
    record.request_id = config.request_id or "unknown"
    return record
end

-- Use with configuration
lual.config({
    dispatchers = {
        { 
            lual.console,
            transformers = {
                { add_request_id, request_id = "123456" }
            }
        }
    }
})
```

### Custom Presenter

```lua
function csv_presenter(record)
    return string.format("%s,%s,%s,%s",
        os.date("%Y-%m-%d %H:%M:%S", record.timestamp),
        record.level_name,
        record.logger_name,
        record.message)
end

lual.config({
    dispatchers = {
        { 
            lual.file,
            path = "metrics.csv",
            presenter = csv_presenter
        }
    }
})
```

## Normalization Process

The component system automatically normalizes all components to a standard internal format:

```lua
{
    func = function_reference,  -- The actual component function
    config = {                  -- Configuration table with merged defaults
        level = level_value,    -- Optional level for dispatchers
        ... other config values
    }
}
```

This normalization happens early in the processing pipeline, making it easier to handle components throughout the codebase.

## Complete Example

See [component_pipeline.lua](examples/component_pipeline.lua) for a complete example using all features of the component system. 