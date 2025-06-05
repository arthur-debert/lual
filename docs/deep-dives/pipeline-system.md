# Pipeline System

This document explains lual's pipeline architecture, which processes log events through a series of components: transformers, presenters, and outputs.

## Overview: The Log Event Flow

When you call `logger:info("message")`, your log event flows through a series of processing steps:

```
Logger Emit → Log Record Creation → Pipeline Processing → Transformers → Presenter → Outputs → Destinations
```

## Core Concepts

### Pipelines

**Pipelines** are the fundamental unit of configuration in lual. Each pipeline combines:

- A level threshold (when to activate)
- A presenter (how to format)
- One or more outputs (where to send)
- Optional transformers (how to modify)

Pipelines operate independently of each other - if one pipeline fails, others continue processing.

```lua
local lual = require("lual")

lual.config({
    pipelines = {
        {
            level = lual.debug,              -- Pipeline level threshold
            presenter = lual.json(),         -- Format as JSON
            outputs = { lual.file },         -- Send to file
            transformers = { add_hostname }  -- Add hostname field
        },
        {
            level = lual.warn,               -- Only warnings and above
            presenter = lual.color(),        -- Format with colors
            outputs = { lual.console }       -- Send to console
        }
    }
})
```

Each pipeline represents a complete processing chain for logs that meet its level threshold.

### Transformers

**Transformers** modify log record data before formatting. They can:

- Add metadata fields
- Filter sensitive information
- Transform values
- Enrich with contextual data

```lua
-- Simple transformer that adds application version to records
local function add_app_version(record)
    record.app_version = "1.0.0"
    return record
end

-- Usage in configuration
lual.config({
    pipelines = {
        {
            outputs = { lual.console },
            presenter = lual.json(),
            transformers = { add_app_version }
        }
    }
})
```

Transformers are applied sequentially - each transformer receives the output of the previous one.

### Presenters

**Presenters** format log records into strings ready for output. They handle:

- Message formatting with arguments
- Timestamp formatting with timezone support
- Output structure (plain text, JSON, colors)
- Field arrangement and styling

```lua
lual.config({
    pipelines = {
        {
            -- Plain text presenter
            presenter = lual.text({ 
                timezone = lual.utc, 
                format = "[%level%] %time% %message%" 
            }),
            outputs = { lual.console }
        },
        {
            -- JSON presenter
            presenter = lual.json({ pretty = true }),
            outputs = { lual.file }
        },
        {
            -- Color presenter for terminal
            presenter = lual.color(),
            outputs = { lual.console }
        }
    }
})
```

### Outputs

**Outputs** are the final stage of the pipeline. They take formatted messages and send them to destinations:

- Writing to streams (stdout, stderr)
- Writing to files (with rotation)
- Network delivery (syslog, remote servers)
- Custom destinations (databases, message queues)

```lua
lual.config({
    pipelines = {
        {
            presenter = lual.text(),
            outputs = {
                { lual.console, stream = io.stderr },  -- Console output
                { lual.file, path = "app.log" }        -- File output
            }
        }
    }
})
```

## Pipeline Processing in Detail

When a log event is emitted, the processing follows these steps:

1. **Level Check**: The logger checks if the event level meets its effective level threshold
2. **Pipeline Selection**: For each pipeline:
   - Check if event level meets the pipeline's threshold
   - If yes, process through this pipeline
3. **Transformation**: Apply each transformer in sequence
4. **Presentation**: Format the record using the pipeline's presenter
5. **Output**: Send the formatted message through each output
6. **Propagation**: If enabled, pass the original event to the parent logger
7. **Repeat**: Parent logger follows the same steps (if event propagates)

```lua
-- Event flow example
local db_logger = lual.logger("app.database", {
    level = lual.debug,
    pipelines = {
        {
            level = lual.debug,
            presenter = lual.json(),
            outputs = { { lual.file, path = "db.log" } },
            transformers = {
                function(record) record.component = "database"; return record end
            }
        },
        {
            level = lual.error,
            presenter = lual.color(),
            outputs = { lual.console }
        }
    }
})

-- This DEBUG event:
db_logger:debug("Query executed in 10ms")

-- 1. Passes logger level check (DEBUG >= DEBUG)
-- 2. Passes first pipeline level check (DEBUG >= DEBUG)
-- 3. Transformers add component="database"
-- 4. Formatted as JSON by presenter
-- 5. Written to db.log by file output
-- 6. Fails second pipeline level check (DEBUG < ERROR)
-- 7. Propagates to parent loggers
```

## Creating Custom Components

### Custom Transformer

```lua
local function add_request_id(record, config)
    config = config or {}
    record.request_id = config.request_id or "unknown"
    return record
end

-- Use in configuration:
lual.logger("app.api", {
    pipelines = {
        {
            presenter = lual.json(),
            outputs = { lual.file },
            transformers = {
                { add_request_id, request_id = "12345" }
            }
        }
    }
})
```

### Custom Presenter

```lua
local function csv_presenter(record)
    -- Format record as CSV
    return string.format("%s,%s,%s,%s",
        os.date("%Y-%m-%d %H:%M:%S", record.timestamp),
        record.level_name,
        record.logger_name,
        record.message)
end

-- Use in configuration:
lual.logger("app.metrics", {
    pipelines = {
        {
            presenter = csv_presenter,
            outputs = { { lual.file, path = "metrics.csv" } }
        }
    }
})
```

### Custom Output

```lua
local function redis_output(record, config)
    config = config or {}
    local redis = require("redis")
    local client = redis.connect(config.host or "localhost", config.port or 6379)
    
    -- Publish formatted message to Redis channel
    client:publish(config.channel or "logs", record.message)
    client:close()
end

-- Use in configuration:
lual.logger("app", {
    pipelines = {
        {
            presenter = lual.json(),
            outputs = {
                { redis_output, host = "redis.example.com", channel = "app:logs" }
            }
        }
    }
})
```

## Advanced Pipeline Patterns

### Multiple Output Formats

Send the same logs to different destinations in different formats:

```lua
lual.config({
    pipelines = {
        {
            -- Human-readable console logs
            presenter = lual.color(),
            outputs = { lual.console }
        },
        {
            -- Machine-parseable file logs
            presenter = lual.json(),
            outputs = { { lual.file, path = "app.log" } }
        }
    }
})
```

### Pipeline-Specific Levels

Configure different verbosity levels for different outputs:

```lua
lual.config({
    level = lual.debug,  -- Logger's effective level
    pipelines = {
        {
            level = lual.debug,  -- Detailed debug to file
            presenter = lual.text(),
            outputs = { { lual.file, path = "debug.log" } }
        },
        {
            level = lual.warn,   -- Only warnings to console
            presenter = lual.color(),
            outputs = { lual.console }
        }
    }
})
```

### Complex Transformation Chains

Apply multiple transformers in sequence:

```lua
lual.config({
    pipelines = {
        {
            presenter = lual.json(),
            outputs = { lual.file },
            transformers = {
                -- Add timestamps
                function(record)
                    local time = os.date("*t", record.timestamp)
                    record.date = string.format("%04d-%02d-%02d", 
                        time.year, time.month, time.day)
                    return record
                end,
                -- Add host info
                function(record)
                    record.hostname = os.getenv("HOSTNAME") or "unknown"
                    return record
                end,
                -- Mask sensitive data
                function(record)
                    if record.password then
                        record.password = "********"
                    end
                    return record
                end
            }
        }
    }
})
```

## Best Practices

1. **Keep pipelines focused**: Each pipeline should have a clear purpose
2. **Use pipeline-specific levels**: Send detailed logs only where needed
3. **Design transformers for reuse**: Create modular transformers that do one thing well
4. **Always copy records**: Don't mutate the original record in transformers
5. **Handle errors gracefully**: Add error handling to custom components
6. **Choose appropriate presenters**: JSON for machines, colored text for humans
7. **Consider performance**: For high-volume logging, minimize transformations

## Conclusion

The pipeline architecture provides a flexible, powerful system for processing log events. By understanding the flow from event emission through transformation, presentation, and output, you can build sophisticated logging solutions tailored to your application's needs. 