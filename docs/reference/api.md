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

**Returns:**
- None

**Examples:**
```lua
-- Configure the root logger
lual.config({
    level = lual.info,
    outputs = {
        { lual.console, presenter = lual.color() }
    }
})
```

## Logger Methods

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

### logger:add_output(output, [config])

Adds an output to the logger.

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

---

This is a partial API reference. For complete details on all functions, methods, and options, refer to the source code and examples. 