# API Reference

This document provides a complete reference for all public functions, methods, and constants in lual v1.0.0.

## Core Functions

### lual.logger(name, [config])

Creates or retrieves a logger with the specified name and optional configuration.

**Parameters:**
- `name` (string, optional): The logger name. If omitted, an auto-generated name based on the calling module will be used.
- `config` (table, optional): Configuration table for the logger.

**Returns:**
- (table): The logger object.

**Examples:**
```lua
-- Create/retrieve a logger with default settings
local logger = lual.logger("app.module")

-- Create/retrieve a logger with specific configuration
local db_logger = lual.logger("app.database", {
    level = lual.debug,
    outputs = {
        { lual.file, path = "database.log" }
    }
})
```

### lual.config(config)

Configures the root logger with the specified settings.

**Parameters:**
- `config` (table): Configuration table for the root logger.

**Configuration Options:**
- `level` (level constant): The minimum level to process.
- `pipelines` (table): Array of pipeline configurations.
- `propagate` (boolean): Whether events propagate (always true for root).
- `custom_levels` (table): Custom level definitions as name = value pairs.
- `command_line_verbosity` (table): Configuration for command line argument driven logging level.
  - `mapping` (table, optional): Custom mapping of command line flags to log level names.
  - `auto_detect` (boolean, optional): Whether to automatically detect and apply CLI verbosity. Defaults to true.
- `live_level` (table): Configuration for environment variable driven live log level changes.
  - `env_var` (string, required): Name of the environment variable to monitor.
  - `check_interval` (number, optional): How often to check for changes, in log entries. Defaults to 100.
  - `enabled` (boolean, optional): Whether the feature is enabled. Defaults to true if env_var is provided.

**Returns:**
- None

**Examples:**
```lua
-- Configure the root logger
lual.config({
    level = lual.info,
    pipelines = {
        { outputs = { lual.console }, presenter = lual.color() }
    }
})

-- Configure with custom levels
lual.config({
    level = lual.debug,
    custom_levels = {
        verbose = 25,
        trace = 15
    },
    pipelines = {
        { outputs = { lual.console }, presenter = lual.text() },
        { outputs = { { lual.file, path = "app.log" } }, presenter = lual.json() }
    }
})

-- Configure with command line verbosity detection
lual.config({
    pipelines = {
        { outputs = { lual.console }, presenter = lual.color() }
    },
    command_line_verbosity = {
        mapping = {
            v = "warning",
            vv = "info", 
            vvv = "debug",
            verbose = "info",
            quiet = "error"
        },
        auto_detect = true
    }
})

-- Configure with live log level changes via environment variable
lual.config({
    pipelines = {
        { outputs = { lual.console }, presenter = lual.color() }
    },
    live_level = {
        env_var = "APP_LOG_LEVEL",     -- Monitor this environment variable
        check_interval = 50,           -- Check every 50 log entries
        enabled = true                 -- Enable the feature (default when env_var is provided)
    }
})
```

### lual.get_levels()

Returns all available log levels (built-in + custom).

**Parameters:**
- None

**Returns:**
- (table): A table mapping level names to level values.

**Examples:**
```lua
local all_levels = lual.get_levels()
print(all_levels.DEBUG)    -- 10
print(all_levels.VERBOSE)  -- 25 (if custom level defined)
```

### lual.set_levels(custom_levels)

Sets or replaces all custom log levels.

**Parameters:**
- `custom_levels` (table): A table mapping custom level names to level values.

**Returns:**
- None

**Examples:**
```lua
-- Define custom levels
lual.set_levels({
    verbose = 25,
    trace = 15
})

-- Clear all custom levels
lual.set_levels({})
```

## Logger Methods

### logger:log(level, message, ...)

Logs a message at the specified level. Accepts both numeric levels and custom level names.

**Parameters:**
- `level` (number or string): The log level (numeric) or custom level name (string).
- `message` (string): The log message. Can include printf-style format specifiers.
- `...` (any): Optional arguments for format specifiers.

**Returns:**
- None

**Examples:**
```lua
-- Numeric levels
logger:log(25, "Custom numeric level")

-- Custom level names (primary usage for custom levels)
logger:log("verbose", "This is a verbose message")
logger:log("trace", "Detailed trace information")
```

### logger:debug(message, ...)

Logs a message at DEBUG level.

**Parameters:**
- `message` (string): The log message. Can include printf-style format specifiers.
- `...` (any): Optional arguments for format specifiers.

**Returns:**
- None

**Examples:**
```lua
logger:debug("Connection established with %s", host)
logger:debug("Query executed in %0.2fms", execution_time)
```

### logger:info(message, ...)

Logs a message at INFO level.

**Parameters:**
- `message` (string): The log message. Can include printf-style format specifiers.
- `...` (any): Optional arguments for format specifiers.

**Returns:**
- None

**Examples:**
```lua
logger:info("User %s logged in", username)
logger:info("Server started on port %d", port)
```

### logger:warn(message, ...)

Logs a message at WARN level.

**Parameters:**
- `message` (string): The log message. Can include printf-style format specifiers.
- `...` (any): Optional arguments for format specifiers.

**Returns:**
- None

**Examples:**
```lua
logger:warn("Resource usage high: %d%%", usage)
logger:warn("Configuration %s is deprecated", option)
```

### logger:error(message, ...)

Logs a message at ERROR level.

**Parameters:**
- `message` (string): The log message. Can include printf-style format specifiers.
- `...` (any): Optional arguments for format specifiers.

**Returns:**
- None

**Examples:**
```lua
logger:error("Failed to connect to %s: %s", server, err)
logger:error("Invalid configuration: %s", reason)
```

### logger:critical(message, ...)

Logs a message at CRITICAL level.

**Parameters:**
- `message` (string): The log message. Can include printf-style format specifiers.
- `...` (any): Optional arguments for format specifiers.

**Returns:**
- None

**Examples:**
```lua
logger:critical("Database connection lost: %s", err)
logger:critical("System shutdown initiated due to %s", reason)
```

## Level Constants

### lual.debug

DEBUG level constant (most verbose).

### lual.info

INFO level constant.

### lual.warn

WARN level constant (default root level).

### lual.error

ERROR level constant.

### lual.critical

CRITICAL level constant (least verbose).

### lual.NOTSET

Special level indicating that a logger should inherit its effective level from its parent.

## Output Components

### lual.console

Console output component. Writes log messages to stdout or stderr.

**Configuration Options:**
- `stream` (file handle, optional): Output stream. Defaults to `io.stdout`.
- `level` (level constant, optional): Minimum level to process. Defaults to logger's level.

**Examples:**
```lua
-- Basic usage
{ lual.console }

-- With configuration
{ lual.console, stream = io.stderr, level = lual.error }
```

### lual.file

File output component. Writes log messages to a file.

**Configuration Options:**
- `path` (string, required): Path to the log file.
- `level` (level constant, optional): Minimum level to process.
- `max_size` (number, optional): Maximum file size in bytes before rotation.
- `max_backups` (number, optional): Maximum number of backup files to keep.

**Examples:**
```lua
-- Basic usage
{ lual.file, path = "app.log" }

-- With configuration
{ lual.file, path = "errors.log", level = lual.error, max_size = 10485760, max_backups = 5 }
```

## Presenter Components

### lual.text([config])

Plain text presenter. Formats log records as text.

**Configuration Options:**
- `timezone` (constant, optional): `lual.utc` or `lual.local_time`. Defaults to `lual.local_time`.
- `format` (string, optional): Format string with placeholders. Defaults to `"%time% %level% [%logger%] %message%"`.

**Returns:**
- (function): Presenter function.

**Examples:**
```lua
-- Basic usage
presenter = lual.text()

-- With configuration
presenter = lual.text({ timezone = lual.utc, format = "[%level%] %time% %message%" })
```

### lual.json([config])

JSON presenter. Formats log records as JSON.

**Configuration Options:**
- `pretty` (boolean, optional): Whether to format the JSON for readability. Defaults to `false`.
- `timezone` (constant, optional): `lual.utc` or `lual.local_time`. Defaults to `lual.utc`.

**Returns:**
- (function): Presenter function.

**Examples:**
```lua
-- Basic usage
presenter = lual.json()

-- With configuration
presenter = lual.json({ pretty = true })
```

### lual.color([config])

Colored text presenter. Formats log records as text with ANSI color codes.

**Configuration Options:**
- `timezone` (constant, optional): `lual.utc` or `lual.local_time`. Defaults to `lual.local_time`.
- `format` (string, optional): Format string with placeholders. Defaults to `"%time% %level% [%logger%] %message%"`.
- `level_colors` (table, optional): Mapping of level names to colors.

**Returns:**
- (function): Presenter function.

**Examples:**
```lua
-- Basic usage
presenter = lual.color()

-- With configuration
presenter = lual.color({
    level_colors = {
        DEBUG = "blue",
        INFO = "green",
        WARN = "yellow",
        ERROR = "red",
        CRITICAL = "magenta"
    }
})
```

## Time Constants

### lual.utc

Constant for UTC timezone in presenters.

### lual.local_time

Constant for local timezone in presenters.

## Async API

### lual.async.coroutines

Constant for the coroutines async backend.

### lual.async.libuv

Constant for the libuv async backend.

### lual.async.drop_oldest

Constant for the drop_oldest overflow strategy. Oldest messages are dropped when the queue is full.

### lual.async.drop_newest

Constant for the drop_newest overflow strategy. Newest messages are dropped when the queue is full.

### lual.async.block

Constant for the block overflow strategy. The application blocks until there's room in the queue.

### lual.async.defaults

Default configuration values for the async subsystem.

### lual.async.get_stats()

Returns statistics about the async subsystem.

**Parameters:**
- None

**Returns:**
- (table): Statistics including queue size, processed messages, and backend-specific metrics.

**Examples:**
```lua
local stats = lual.async.get_stats()
print("Queue size:", stats.queue_size)
print("Messages processed:", stats.messages_processed)
```

### lual.flush()

Flushes all queued async log events immediately.

**Parameters:**
- None

**Returns:**
- None

**Examples:**
```lua
-- Log some messages
logger:info("First message")
logger:info("Second message")

-- Force immediate processing of queued messages
lual.flush()
```

## Imperative Configuration Methods

### logger:set_level(level)

Sets the logger's level.

**Parameters:**
- `level` (level constant): The level to set.

**Returns:**
- (table): The logger (for method chaining).

**Examples:**
```lua
logger:set_level(lual.debug)
```

### logger:add_pipeline(pipeline)

Adds a pipeline configuration to the logger.

**Parameters:**
- `pipeline` (table): Pipeline configuration with `outputs` and `presenter` fields.

**Returns:**
- (table): The logger (for method chaining).

**Examples:**
```lua
logger:add_pipeline({
    outputs = { lual.console },
    presenter = lual.text()
})
```

### logger:add_output(output, [config])

Adds an output to the logger. This method is deprecated - use `add_pipeline()` instead.

**Parameters:**
- `output` (function): The output function.
- `config` (table, optional): Configuration for the output.

**Returns:**
- (table): The logger (for method chaining).

**Examples:**
```lua
logger:add_output(lual.file, { path = "app.log" })
```

### logger:set_propagate(value)

Sets whether log events propagate to parent loggers.

**Parameters:**
- `value` (boolean): Whether to propagate events.

**Returns:**
- (table): The logger (for method chaining).

**Examples:**
```lua
logger:set_propagate(false)
```

## Log Module

The `lual.log` module provides direct access to the internal log processing functions. These functions are used internally by the logger objects but can be used directly for advanced use cases.

### lual.log.create_log_record(logger, level_no, level_name, message_fmt, args, context)

Creates a log record from the provided parameters.

**Parameters:**
- `logger` (table): The logger object.
- `level_no` (number): The numeric log level.
- `level_name` (string): The log level name.
- `message_fmt` (string): Message format string.
- `args` (table): Arguments for formatting.
- `context` (table): Additional context data.

**Returns:**
- (table): The log record.

### lual.log.parse_log_args(...)

Parses arguments passed to logging methods into message, args, and context.

**Parameters:**
- `...` (any): Arguments passed to a logging method.

**Returns:**
- (string): Message format string.
- (table): Arguments for formatting.
- (table): Context data if provided.

### lual.log.format_message(message_fmt, args)

Formats a message using printf-style formatting.

**Parameters:**
- `message_fmt` (string): Format string.
- `args` (table): Arguments for formatting.

**Returns:**
- (string): Formatted message.

### lual.log.get_logger_tree(source_logger)

Builds a list of loggers that should process a log event, starting with the source logger and following the parent chain.

**Parameters:**
- `source_logger` (table): The source logger that created the log event.

**Returns:**
- (table): Array of loggers to process the event.

### lual.log.get_eligible_pipelines(logger, log_record)

Gets pipelines from a logger that should process a log record based on level.

**Parameters:**
- `logger` (table): The logger to check.
- `log_record` (table): The log record.

**Returns:**
- (table): Array of eligible pipelines with their owning logger.

### lual.log.process_pipeline(log_record, pipeline_entry)

Processes a single pipeline for a log record.

**Parameters:**
- `log_record` (table): The log record to process.
- `pipeline_entry` (table): The pipeline entry containing the pipeline and owning logger.

**Returns:**
- (boolean): Whether processing succeeded.

### lual.log.process_pipelines(logger_pipelines, log_record)

Processes multiple pipelines for a log record.

**Parameters:**
- `logger_pipelines` (table): Array of pipelines with their owning loggers.
- `log_record` (table): The log record to process.

**Returns:**
- None

### lual.log.process_log_record(source_logger, log_record)

Processes a log record through the logging system.

**Parameters:**
- `source_logger` (table): The logger that created the log record.
- `log_record` (table): The log record to process.

**Returns:**
- None

### lual.set_command_line_verbosity(verbosity_config)

Sets the command line verbosity configuration for automatic log level detection from command line arguments.

**Parameters:**
- `verbosity_config` (table): Configuration table for command line verbosity.
  - `mapping` (table, optional): Custom mapping of command line flags to log level names. Defaults to predefined mappings.
  - `auto_detect` (boolean, optional): Whether to automatically detect and apply verbosity from command line. Defaults to true.

**Returns:**
- (table): The updated root logger configuration.

**Examples:**
```lua
-- Enable command line verbosity with default mappings
lual.set_command_line_verbosity({})

-- Custom verbosity mapping
lual.set_command_line_verbosity({
    mapping = {
        v = "warning",
        vv = "info",
        vvv = "debug",
        verbose = "info",
        quiet = "error"
    }
})

-- Configure but disable auto-detection
lual.set_command_line_verbosity({
    auto_detect = false
})
```

### lual.set_live_level(env_var_name, check_interval)

Sets up live log level changes through environment variables, allowing runtime modification of the root logger's level without restarting the application.

**Parameters:**
- `env_var_name` (string): Name of the environment variable to monitor for level changes.
- `check_interval` (number, optional): How often to check for changes, measured in log entries. Defaults to 100.

**Returns:**
- (table): The updated root logger configuration.

**Examples:**
```lua
-- Monitor LOG_LEVEL environment variable with default check interval
lual.set_live_level("LOG_LEVEL")

-- Monitor APP_DEBUG environment variable, checking every 50 log entries
lual.set_live_level("APP_DEBUG", 50)
```

---

This is a partial API reference. For complete details on all functions, methods, and options, refer to the source code and examples. 