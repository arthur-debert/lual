# lual - A Lua Logger

lual is a focused but powerful and flexible logging library for Lua. Inspired by
Python's stdlib and loguru loggers, it aims at being a simple yet quite flexible
logger.

It borrows from Python but also leverages Lua's strengths, hence the entire
design is done over functions and tables, look ma, no classes.

## Overview

LUAL is a hierarchical logging library for Lua that provides flexible configuration, multiple output formats, and efficient log management.

## Quick Start

```lua
local lual = require("lual.logger")

-- Create a logger with convenience syntax
local logger = lual.logger("app.database", {
    output = lual.console,
    level = lual.debug,
    presenter = lual.color,
    timezone = lual.local_time
})

logger:info("Database connection established")
logger:debug("Query executed in 1.2ms")
```

## API Documentation

### Imperative API (Method-based configuration)

```lua
local logger = lual.logger("app.network") 
logger:add_dispatcher(lual.lib.console, lual.lib.text)
logger:set_level(lual.debug)
```

## Features

- **Hierarchical Logging**: Automatic parent logger creation and log propagation
- **Multiple Output Formats**: Text, colored text, and JSON presenters  
- **Flexible Outputs**: Console and file output with customizable streams
- **Convenience Syntax**: Simple config-based logger creation
- **Level Filtering**: Debug, info, warning, error, and critical levels
- **Timezone Support**: Local time and UTC formatting
- **Memory Efficient**: Logger caching and optimized string formatting

## Configuration Examples

### File Logging
```lua
local logger = lual.logger({
    name = "app.audit",
    output = lual.file,
    path = "app.log",
    presenter = lual.json,
    level = lual.info
})
```

### Multiple Outputs (Full Syntax)
```lua
local logger = lual.logger({
    name = "app.main",
    level = lual.debug,
    outputs = {
        {type = lual.console, presenter = lual.color},
        {type = lual.file, path = "debug.log", presenter = lual.text}
    }
})
```

## Built-in Components

It has a small but useful set of outputs and presenters:

**outputs:**

- `console`: prints to the console
- `file`: writes to a file

**Presenters:**

- `text`: plain text
- `color`: terminal colored
- `json`: as JSON

But presenters and outputs are just functions, pass your own.

Names can be either introspected or set manually. There is hierarchical logging
with propagation, see docs/propagation.txt.

## Installation

Lual is available as a LuaRocks module, so you can install it with:

```bash
luarocks install lual
```

## API

The main API is `lual.logger()` which creates or retrieves a logger:

```lua
local lual = require("lual")

-- Simple logger creation
local logger = lual.logger()           -- Auto-named from filename
local logger = lual.logger("myapp")    -- Named logger with default config

-- Two-parameter API: name + config
local logger = lual.logger("myapp", {
    level = "debug",
    outputs = {
        {type = "console", presenter = "color"}
    }
})

-- Config table API (full syntax)
local logger = lual.logger({
    name = "app.database",
    level = "debug",
    outputs = {
        {type = "console", presenter = "color"},
        {type = "file", path = "app.log", presenter = "text"}
    }
})
```

**Note:** `lual.logger()` is still available for backward compatibility, but
`lual.logger()` is now the official API.

## Features (v1)

- **Hierarchical Loggers:** Loggers are named using dot-separated paths (e.g.,
  `myapp.module.submodule`), allowing for targeted configuration.
- **Log Levels:** Standard severity levels: `DEBUG`, `INFO`, `WARNING`, `ERROR`,
  `CRITICAL`, plus `NONE` to disable logging for a logger.
- Outputs: 
  -  **Console :** `lualog.lib.console` writes log messages to `io.stdout` (default), `io.stderr`, or any custom stream object that provides `write()` and `flush()` methods.
  - **File:** `lualog.lib.file` writes log messages to files with configurable paths and rotation options.  - Presenters: 
- Presenters: 
  - **Text:** `lualog.lib.text` traditional log txt message with ISO datatime: `YYYY-MM-DD HH:MM:S LEVEL [LoggerName] Message`.
  - **Color:** `lualog.lib.color` ANSI color codes for enhanced terminal readability.
  - **JSON:** `lualog.lib.json` s JSON for structured logging and easy parsing by log aggregation systems.
- **Timezone Support:** Configurable timezone for timestamps - supports both UTC and local time formatting (defaults to local time).
  - **String Formatting:** Supports `printf`-style string formatting (e.g., `logger:info("Hello %s", name)`).
  - **Structured Logging:** Supports logging rich, structured data.
    - Pure structured: `logger:info({event = "UserLogin", userId = 123})`
    - Mixed: `logger:info({eventId = "XYZ"}, "Processing event: %s", eventName)`
      (context table first)
  - **Per-Logger Configuration:** Log levels and outputs (with their
    presenters) can be configured for each logger instance using methods like
    `:set_level()` and `:add_dispatcher()`.
- **Message Propagation:** Log messages processed by a logger are passed to its
  parent's outputs by default. Propagation can be disabled per logger
  (`logger.propagate = false`).
- **Contextual Information:** Log records automatically include a UTC timestamp,
  logger name, and the source filename/line number where the log message was
  emitted.
- **Error Handling:** Errors within outputs or presenters are caught and
  reported to `io.stderr`, preventing the logging system from crashing the
  application.
- **Default Setup:** On require, a root logger is configured with:
  - Level: `lualog.levels.INFO`.
  - One output: `lualog.lib.console` writing to `io.stdout`.
  - Presenter for this output: `lualog.lib.text`.

You can create custom outputs and presenters:

- **Custom output:** A function with the signature
  `my_dispatcher(record, config)`
  - `record`: A table containing the log details. Key fields include:
    - `message`: The fully formatted log message string (from the presenter).
    - `level_name`, `level_no`: Severity level.
    - `logger_name`: Name of the logger that owns the output processing the
      record.
    - `timestamp`, `filename`, `lineno`, `source_logger_name` (original
      emitter).
    - `raw_message_fmt`, `raw_args`: Original format string and variadic
      arguments.
    - `context`: The context table, if provided in the log call.
  - `config`: The `dispatcher_config` table passed when adding the output.
- **Custom Presenter:** A function with the signature `my_presenter(record)`
  - `record`: A table with raw log details. Key fields include:
    - `message_fmt`: The raw message format string (e.g., "User %s logged in").
      Can be `nil` if context implies the message.
    - `args`: A packed table of arguments for `message_fmt` (e.g.,
      `{n=1, "john.doe"}`).
    - `context`: The context table, if provided (e.g., `{user_id = 123}`).
    - `level_name`, `level_no`, `logger_name`, `timestamp`, `filename`,
      `lineno`, `source_logger_name`.
  - Should return a single string: the formatted log message.

## Leaning More:

<TK> to come , don't hcange it

## Running Tests

The library uses Busted for testing. To run the tests:

1.  Ensure Busted is installed (e.g., `luarocks install busted`).
2.  Navigate to the root directory of the `lual` project.
3.  Run the command: `busted`

## Contributing

Contributions are welcome! Please feel free to submit issues or pull requests.

## License

`lual` is released under the MIT License.

```

```
