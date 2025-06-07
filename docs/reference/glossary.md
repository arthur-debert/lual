# Glossary

This glossary defines the key terms and concepts used throughout lual.

## Logger Concepts

### Logger
The main interface for emitting log messages. Each logger has a name, level settings, and is part of the logger hierarchy.

```lua
local logger = lual.logger("app.module")
```

### Logger Name
A string that identifies a logger. Names use dot notation to define a hierarchy (e.g., "app.module.submodule").

### Root Logger
The special logger at the top of the hierarchy, internally named `_root`. It's automatically created when lual is loaded and provides default settings for all other loggers.

```lua
-- Configure the root logger
lual.config({ level = lual.debug })
```

### Effective Level
The level actually used by a logger to decide if an event should be processed. This can be:
- The logger's explicitly set level
- If not set (NOTSET), the level inherited from the closest ancestor with an explicit level

### Propagation
The process by which a log event, after being processed by a logger, is passed to its parent logger for processing.

```lua
-- Disable propagation
local logger = lual.logger("app.module", {
    propagate = false
})
```

## Log Levels

### Level
A severity value assigned to both log events and loggers. Used to filter which events should be processed.

### Level Constants
Built-in severity levels, from most to least verbose:
- `lual.debug` - Detailed debugging information
- `lual.info` - General information messages
- `lual.warn` - Warning messages (default root level)
- `lual.error` - Error conditions
- `lual.critical` - Critical failures

### NOTSET
A special level value (`lual.NOTSET`) indicating that a logger should inherit its effective level from its parent.

### Custom Levels
User-defined log levels with meaningful names that supplement the built-in levels. Defined globally and available to all loggers.

```lua
lual.config({
    custom_levels = {
        verbose = 25,  -- Between INFO(20) and WARNING(30)
        trace = 15     -- Between DEBUG(10) and INFO(20)
    }
})

-- Usage
logger:log("verbose", "message")  -- Primary usage
logger:verbose("message")         -- Dynamic method call
```

### Custom Level Rules
- Names must be lowercase valid Lua identifiers (no leading underscores)
- Values must be integers between DEBUG(10) and ERROR(40), exclusive
- Cannot conflict with built-in level values
- Display as uppercase in log output (e.g., `[VERBOSE]`, `[TRACE]`)

## Pipeline Architecture

### Pipeline
The core configuration unit that combines level thresholds, transformers, presenters, and outputs into a complete log processing chain.

```lua
{
    level = lual.debug,
    presenter = lual.json(),
    outputs = { lual.file },
    transformers = { add_metadata }
}
```

### Transformer
A component that modifies a log record before it's formatted. Transformers can add, remove, or change fields in the record.

```lua
local function add_hostname(record)
    record.hostname = os.getenv("HOSTNAME") or "unknown"
    return record
end
```

### Presenter
A component that formats a log record for output. Controls the visual presentation of the log message.

```lua
local text_presenter = lual.text({
    timezone = lual.utc,
    format = "%time% %level% [%logger%] %message%"
})
```

### Output
A component responsible for sending a formatted log message to a destination (console, file, network).

```lua
local file = lual.file({
    path = "app.log",
    max_size = 10 * 1024 * 1024  -- 10 MB
})
```

## Event Concepts

### Log Event
The act of requesting a message to be logged, e.g., `logger:info("message")`. Contains the raw message, level, and any extra data provided at the call site.

### Log Record
A table created from a log event, enriched with additional information like timestamp, logger name, source file/line. This record is passed through pipeline processing.

### Level Matching
The process of comparing an event's level against thresholds:
- Logger level: `event_level >= logger_effective_level`
- Pipeline level: `event_level >= pipeline_level`

## Configuration Concepts

### Root Configuration
Settings applied to the `_root` logger via `lual.config()`. These serve as defaults for all other loggers.

### Logger Configuration
Settings specific to a non-root logger, applied via the second parameter to `lual.logger()` or through imperative methods.

### Pipeline Configuration
The settings for a specific processing pipeline, including its level, presenter, outputs, and transformers.

### Component Configuration
Settings specific to a pipeline component (transformer, presenter, or output), typically passed in a configuration table.

## Technical Terms

### Module Path
The name for a Lua file as used by `require()` (e.g., "lual.core.logging").

### Component Independence
The principle that transformers, presenters, and outputs are independent components that can be mixed and matched within different pipelines.

### Error Isolation
The practice of containing errors within pipeline components to prevent the entire logging system from failing.

---

Additional technical terms can be found in the [API Reference](api.md) and [Pipeline System](../deep-dives/pipeline-system.md) documentation. 