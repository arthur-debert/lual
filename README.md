# lual - A Lua Logger

lual is a focused but powerful and flexible logging library for Lua. Inspired by
Python's stdlib and loguru loggers, it aims at being a simple yet quite flexible
logger.

It borrows from Python but also leverages Lua's strengths, hence the entire
design is done over functions and tables, look ma, no classes.

## Quick Example

```lua
local lual = require("lual")
local logger = lual.get_logger()
logger:info("This is an info message")
logger:info("User %s logged in from IP %s", "jane.doe", "192.168.1.100") -- String formatting

-- The usual stuff
logger:set_level("debug")

-- Configure a more involved logger with UTC timestamps:
local logger = lual.logger({
    output = lual.lib.console,
    level = lual.levels.DEBUG,
    formatter = lual.lib.color,
    timezone = "utc"
})

local bigLogging = require("lual").logger({
    name = "app.database",
    level = "debug",
    timezone = "utc",
    outputs = {
        {type = "console", formatter = "color"},
        {type = "file", path = "app.log", formatter = "text"}
    }
})

-- Of course you can imperatively add outputs and formatters:
logger:add_output(lual.lib.console, lual.lib.text)

-- Supports structured logging:
logger:info({destination = "home"}, "Time to leave") -- Context table first
logger:info({msg = "Time to leave", destination = "home"}) -- Pure structured

-- Mixed structured and string formatting:
logger:info({user_id = 123, action = "update"}, "User %s performed action: %s", "JohnDoe", "ItemUpdate")
```

## Built-in Components

It has a small but useful set of outputs and formatters:

**Outputs:**

- `console`: prints to the console
- `file`: writes to a file

**Formatters:**

- `text`: plain text
- `color`: terminal colored
- `json`: as JSON

But formatters and outputs are just functions, pass your own.

Names can be either introspected or set manually. There is hierarchical logging
with propagation, see docs/propagation.txt.

## Installation

Lual is available as a LuaRocks module, so you can install it with:

```bash
luarocks install lual
```

## Features (v1)

- **Hierarchical Loggers:** Loggers are named using dot-separated paths (e.g.,
  `myapp.module.submodule`), allowing for targeted configuration.
- **Log Levels:** Standard severity levels: `DEBUG`, `INFO`, `WARNING`, `ERROR`,
  `CRITICAL`, plus `NONE` to disable logging for a logger.
- **Console Output:** `lualog.lib.console` writes log messages to `io.stdout`
  (default), `io.stderr`, or any custom stream object that provides `write()`
  and `flush()` methods.
- **File Output:** `lualog.lib.file` writes log messages to files with
  configurable paths and rotation options.
- **Text Formatter:** `lualog.lib.text` formats messages by default as:
  `YYYY-MM-DD HH:MM:S LEVEL [LoggerName] Message`.
- **Color Formatter:** `lualog.lib.color` formats messages with ANSI color codes
  for enhanced terminal readability.
- **JSON Formatter:** `lualog.lib.json` formats messages as JSON for structured
  logging and easy parsing by log aggregation systems.
- **Timezone Support:** Configurable timezone for timestamps - supports both UTC
  and local time formatting (defaults to local time).
  - **String Formatting:** Supports `printf`-style string formatting (e.g.,
    `logger:info("Hello %s", name)`).
  - **Structured Logging:** Supports logging rich, structured data.
    - Pure structured: `logger:info({event = "UserLogin", userId = 123})`
    - Mixed: `logger:info({eventId = "XYZ"}, "Processing event: %s", eventName)`
      (context table first)
  - **Per-Logger Configuration:** Log levels and outputs (with their formatters)
    can be configured for each logger instance using methods like `:set_level()`
    and `:add_output()`.
- **Message Propagation:** Log messages processed by a logger are passed to its
  parent's outputs by default. Propagation can be disabled per logger
  (`logger.propagate = false`).
- **Contextual Information:** Log records automatically include a UTC timestamp,
  logger name, and the source filename/line number where the log message was
  emitted.
- **Error Handling:** Errors within outputs or formatters are caught and
  reported to `io.stderr`, preventing the logging system from crashing the
  application.
- **Default Setup:** On require, a root logger is configured with:
  - Level: `lualog.levels.INFO`.
  - One output: `lualog.lib.console` writing to `io.stdout`.
  - Formatter for this output: `lualog.lib.text`.

You can create custom outputs and formatters:

- **Custom Output:** A function with the signature `my_output(record, config)`
  - `record`: A table containing the log details. Key fields include:
    - `message`: The fully formatted log message string (from the formatter).
    - `level_name`, `level_no`: Severity level.
    - `logger_name`: Name of the logger that owns the output processing the
      record.
    - `timestamp`, `filename`, `lineno`, `source_logger_name` (original
      emitter).
    - `raw_message_fmt`, `raw_args`: Original format string and variadic
      arguments.
    - `context`: The context table, if provided in the log call.
  - `config`: The `output_config` table passed when adding the output.
- **Custom Formatter:** A function with the signature `my_formatter(record)`
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
