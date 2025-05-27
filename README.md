# lual - A Flexible Logging Library for Lua

## Introduction

`lual` is a Lua logging library inspired by the flexibility and power of
Python's standard logging module. It aims to provide a robust and
developer-friendly solution for application logging, offering hierarchical
loggers, multiple log levels, configurable outputs, and custom message
formatting.

This v1 implementation focuses on the core logger object functionality, allowing
for detailed configuration and control on a per-logger basis.

## Features (v1)

- **Hierarchical Loggers:** Loggers are named using dot-separated paths (e.g.,
  `myapp.module.submodule`), allowing for targeted configuration.
- **Log Levels:** Standard severity levels: `DEBUG`, `INFO`, `WARNING`, `ERROR`,
  `CRITICAL`, plus `NONE` to disable logging for a logger.
- **Console Output:** `lualog.outputs.console_output` writes log messages to
  `io.stdout` (default), `io.stderr`, or any custom stream object that provides
  `write()` and `flush()` methods.
- **File Output:** `lualog.outputs.file_output` writes log messages to files
  with configurable paths and rotation options.
- **Text Formatter:** `lualog.formatters.text` formats messages by default as:
  `YYYY-MM-DD HH:MM:SS LEVEL [LoggerName] Message` (Timestamp is in UTC).
- **Color Formatter:** `lualog.formatters.color` formats messages with ANSI
  color codes for enhanced terminal readability.
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
- **Default Setup:** On require, a root logger is configured with a console
  output (outputting to `io.stdout`) and the text formatter, set at `INFO`
  level.

## Installation

Currently, `lual` is a library distributed as Lua source files. To use it in
your project:

1.  Copy the `lua/lual` directory (containing `logger.lua`, `ingest.lua`, and
    subdirectories like `core/`, `outputs/`, `formatters/`) into your project's
    Lua library path (e.g., into a `lib/` directory or ensure `lua/` is part of
    your `LUA_PATH` such that `lual.logger` can be found).
2.  Require the main module in your code:
    `local lualog = require("lual.logger")`.

(Future versions may support installation via LuaRocks.)

## Getting Started

### 1. Getting a Logger

Loggers are the primary way to interact with the logging system. You obtain
logger instances using `lualog.get_logger(name)`:

```lua
local lualog = require("lual.logger")

-- Get a logger for a specific module
local my_logger = lualog.get_logger("my.app.module")

-- Get the root logger
local root_logger = lualog.get_logger()
-- or
local root_logger_explicit = lualog.get_logger("root")

-- Loggers are cached, so subsequent calls with the same name return the same instance
local same_logger = lualog.get_logger("my.app.module")
assert(my_logger == same_logger) -- This is true
```

Loggers form a hierarchy. For example, the logger `my.app.module` is a child of
`my.app`, which is a child of `my`, which is a child of `root`.

### 2. Logging Messages

Once you have a logger instance, you can log messages using its level-specific
methods:

```lua
my_logger:info("This message will go to stdout due to the default root logger setup.")
my_logger:debug("This debug message will be ignored by default, as my_logger and root are INFO level.")

-- You can use string formatting (Lua's string.format style)
my_logger:info("User %s processed %d records.", "john.doe", 42)
```

### 3. Default Behavior

When `lual` is first required (`local lualog = require("lual.logger")`):

- The `lualog.init_default_config()` function is automatically called.
- This sets up the **root logger** with:
  - Level: `lualog.levels.INFO`.
  - One output: `lualog.outputs.console_output` writing to `io.stdout`.
  - Formatter for this output: `lualog.formatters.text`.

Any logger you create (e.g., `lualog.get_logger("my.app")`):

- Has its log level initially set to `lualog.levels.INFO` (but it can be changed
  via `logger:set_level()`).
- Has no outputs directly attached to it (unless you add them).
- Will propagate messages to its parent logger's outputs (ultimately to the root
  logger if propagation is enabled all the way up).

**Example of default output:**

```lua
local lualog = require("lual.logger")

local app_logger = lualog.get_logger("my.app")
app_logger:info("This will be printed to stdout via the root logger's default output.")
app_logger:debug("This will NOT be printed (app_logger is INFO by default, root is INFO).")

-- To see debug messages from app_logger:
app_logger:set_level(lualog.levels.DEBUG)
app_logger:debug("Now this debug message from app_logger will also print via root.")
```

### 4. Changing Log Level

You can control which messages are processed by a logger by setting its level.
Messages below this severity will be ignored by the logger and its direct
outputs (though they might still be processed by ancestor outputs if the
ancestor's level is lower, due to propagation).

```lua
local lualog = require("lual.logger")
local noisy_logger = lualog.get_logger("my.component.noisy")

-- No need to add a output to see output if root logger is handling it.
noisy_logger:debug("This debug message is initially ignored (logger is INFO by default).")

-- Change the logger's level to DEBUG
oisy_logger:set_level(lualog.levels.DEBUG)
noisy_logger:debug("This debug message will now be processed by noisy_logger and propagate!")
```

### 5. Adding Outputs

Outputs determine what happens to a log record. Each logger can have multiple
outputs. Adding a output to a specific logger allows for output independent of,
or in addition to, propagated messages.

```lua
local lualog = require("lual.logger")
local data_processor_logger = lualog.get_logger("data.processor")
data_processor_logger:set_level(lualog.levels.INFO) -- Process INFO and above

-- Output 1: Log specifically from data_processor_logger to stderr
data_processor_logger:add_output(
  lualog.outputs.console_output,
  lualog.formatters.text,
  { stream = io.stderr }               -- Output-specific config
)

-- Output 2: Log to a file (using file_output)
data_processor_logger:add_output(
  lualog.outputs.file_output({ path = "data_processor.log" }), -- Use file_output factory
  lualog.formatters.text,
  {}                                      -- No additional config needed
)

data_processor_logger:info("Processing started.")
-- This message goes to:
-- 1. stderr (via data_processor_logger's own first output)
-- 2. data_processor.log (via data_processor_logger's own second output)
-- 3. stdout (via propagation to the root logger's default output)
```

The `add_output` method for a logger instance takes:

1.  `output_func`: e.g., `lualog.outputs.console_output`.
2.  `formatter_func`: e.g., `lualog.formatters.text`.
3.  `output_config` (optional table).

### 6. Controlling Propagation

```lua
local lualog = require("lual.logger")

-- Root logger already has a default stdout output.
local parent_logger = lualog.get_logger("app.service")
-- parent_logger:set_level(lualog.levels.INFO) -- Already INFO by default
-- No need to add output to parent_logger if default root output is sufficient for its propagated messages.

local child_logger = lualog.get_logger("app.service.worker")
child_logger:set_level(lualog.levels.DEBUG)

-- Add a specific output for child_logger messages to stderr
child_logger:add_output(lualog.outputs.console_output, lualog.formatters.text, {stream = io.stderr})

child_logger:info("Message from child (to its stderr AND propagates to parent then root for stdout).")

child_logger.propagate = false
child_logger:warn("Another message from child (to its stderr ONLY, does NOT propagate).")
```

## Extending `lual`

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
  - `config`: The `output_config` table passed when adding the output.
- **Custom Formatter:** A function with the signature `my_formatter(record)`
  - `record`: A table with raw log details. Key fields include:
    - `message_fmt`: The raw message format string (e.g., "User %s logged in").
    - `args`: A packed table of arguments for `message_fmt` (e.g.,
      `{n=1, "john.doe"}`).
    - `level_name`, `level_no`, `logger_name`, `timestamp`, `filename`,
      `lineno`, `source_logger_name`.
  - Should return a single string: the formatted log message.

```lua
local lualog = require("lual.logger")
local unpack = unpack or table.unpack -- Needed for some formatters

-- Example: Simple custom formatter that adds a prefix
local function prefix_formatter(record)
  local original_message = string.format(record.message_fmt, unpack(record.args or {}))
  return string.format("[MyPrefix] %s: %s", record.level_name, original_message)
end

-- Example: Simple custom output that prints to console with a bang
local function bang_output(record, config)
  print("BANG!!! " .. record.message) -- record.message is already formatted by prefix_formatter
end

local my_logger = lualog.get_logger("custom.test")
my_logger:set_level(lualog.levels.INFO)
my_logger:add_output(bang_output, prefix_formatter)

my_logger:info("This is a custom test.")
-- Output via bang_output after being formatted by prefix_formatter:
-- BANG!!! [MyPrefix] INFO: This is a custom test.
```

## Future Enhancements (Planned / Considered)

- File rotation and advanced file management features for `file_output`.
- Pattern matching for logger configuration (e.g., setting levels for multiple
  loggers matching a pattern).
- More sophisticated output types (e.g., network, syslog, rotating file).
- Configuration from a table or file.

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
