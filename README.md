# lual.log - A Flexible Logging Library for Lua

## Introduction

`lual.log` is a Lua logging library inspired by the flexibility and power of Python's standard logging module. It aims to provide a robust and developer-friendly solution for application logging, offering hierarchical loggers, multiple log levels, configurable handlers, and custom message formatting.

This v1 implementation focuses on the core logger object functionality, allowing for detailed configuration and control on a per-logger basis.

## Features (v1)

*   **Hierarchical Loggers:** Loggers are named using dot-separated paths (e.g., `myapp.module.submodule`), allowing for targeted configuration.
*   **Log Levels:** Standard severity levels: `DEBUG`, `INFO`, `WARNING`, `ERROR`, `CRITICAL`, plus `NONE` to disable logging for a logger.
*   **Stream Handler:** `lualog.handlers.stream_handler` writes log messages to `io.stdout` (default), `io.stderr`, or any custom stream object that provides `write()` and `flush()` methods.
*   **Plain Text Formatter:** `lualog.formatters.plain_formatter` formats messages by default as:
    `YYYY-MM-DD HH:MM:SS LEVEL [LoggerName] Message` (Timestamp is in UTC).
*   **Per-Logger Configuration:** Log levels and handlers (with their formatters) can be configured for each logger instance.
*   **Message Propagation:** Log messages processed by a logger are passed to its parent's handlers by default. Propagation can be disabled per logger.
*   **Contextual Information:** Log records automatically include a UTC timestamp, logger name, and the source filename/line number where the log message was emitted.
*   **Error Handling:** Errors within handlers or formatters are caught and reported to `io.stderr`, preventing the logging system from crashing the application.

## Installation

Currently, `lual.log` is a library distributed as Lua source files. To use it in your project:

1.  Copy the `lua/lual.log` directory (containing `luallog.lua` and `ingest.lua`) into your project's Lua library path (e.g., into a `lib/` directory or directly into your `LUA_PATH`).
2.  Require the main module in your code: `local lualog = require("lual.log.luallog")`.

(Future versions may support installation via LuaRocks.)

## Getting Started

### 1. Getting a Logger

Loggers are the primary way to interact with the logging system. You obtain logger instances using `lualog.get_logger(name)`:

```lua
local lualog = require("lual.log.luallog")

-- Get a logger for a specific module
local my_logger = lualog.get_logger("my.app.module")

-- Get the root logger (useful for application-wide logging or as a fallback)
local root_logger = lualog.get_logger() 
-- or
local root_logger_explicit = lualog.get_logger("root")

-- Loggers are cached, so subsequent calls with the same name return the same instance
local same_logger = lualog.get_logger("my.app.module")
assert(my_logger == same_logger) -- This is true
```
Loggers form a hierarchy. For example, the logger `my.app.module` is a child of `my.app`, which is a child of `my`, which is a child of `root`.

### 2. Logging Messages

Once you have a logger instance, you can log messages using its level-specific methods:

```lua
my_logger:debug("Detailed diagnostic information for developers.")
my_logger:info("General information about application progress, e.g., user logged in.")
my_logger:warn("Indication of a potential issue or an unexpected event.")
my_logger:error("An error occurred that prevented a specific operation from completing.")
my_logger:critical("A severe error that might lead to application termination.")

-- You can use string formatting (Lua's string.format style)
my_logger:info("User %s processed %d records.", "john.doe", 42)
```

### 3. Default Behavior

By default, a freshly created logger instance:
*   Has its log level set to `lualog.levels.INFO`.
*   Has no handlers directly attached to it.
*   Will propagate messages to its parent logger's handlers.

The root logger also starts with no handlers by default in v1. To see any output, you must add a handler to the logger itself or one of its ancestors (like the root logger).

*(Note: A future `lualog.init_default_config()` function might set up a default handler on the root logger, but in v1, this setup is manual if desired for immediate output without specific logger configuration.)*

**Example: Manually setting up a default console output for all messages (INFO and above) via the root logger:**
```lua
local lualog = require("lual.log.luallog")
local root_logger = lualog.get_logger()

-- Set the root logger's level (e.g., to INFO)
root_logger:set_level(lualog.levels.INFO)

-- Add a stream handler to the root logger to print to io.stdout
root_logger:add_handler(
  lualog.handlers.stream_handler,      -- The handler function
  lualog.formatters.plain_formatter,   -- The formatter function
  { stream = io.stdout }               -- Handler-specific config (optional, defaults to io.stdout)
)

local app_logger = lualog.get_logger("my.app")
app_logger:info("This will be printed to stdout via the root logger's handler.")
app_logger:debug("This will NOT be printed (app_logger is INFO by default, root is INFO).")
```

### 4. Changing Log Level

You can control which messages are processed by a logger by setting its level. Messages below this severity will be ignored by the logger and its direct handlers.

```lua
local lualog = require("lual.log.luallog")
local noisy_logger = lualog.get_logger("my.component.noisy")

-- By default, noisy_logger is at INFO level. Add a handler to see its output.
noisy_logger:add_handler(lualog.handlers.stream_handler, lualog.formatters.plain_formatter)

noisy_logger:debug("This debug message is initially ignored.") -- Logger is INFO by default

-- Change the logger's level to DEBUG
noisy_logger:set_level(lualog.levels.DEBUG)
noisy_logger:debug("This debug message will now be processed!") 
```

### 5. Adding Handlers

Handlers determine what happens to a log record (e.g., print to console, write to file). Each logger can have multiple handlers.

```lua
local lualog = require("lual.log.luallog")
local data_processor_logger = lualog.get_logger("data.processor")
data_processor_logger:set_level(lualog.levels.INFO) -- Process INFO and above

-- Handler 1: Log to console (stdout)
data_processor_logger:add_handler(
  lualog.handlers.stream_handler,
  lualog.formatters.plain_formatter
  -- Config {stream = io.stdout} is default for stream_handler
)

-- Handler 2: Log to a file
local file_stream = io.open("data_processor.log", "a")
if file_stream then
  data_processor_logger:add_handler(
    lualog.handlers.stream_handler,      -- Use stream_handler for files too
    lualog.formatters.plain_formatter,
    { stream = file_stream }             -- Specify the file stream
  )
else
  data_processor_logger:error("Could not open data_processor.log for logging.")
end

data_processor_logger:info("Processing started.") 
-- This message goes to stdout AND data_processor.log
```
The `add_handler` method takes:
1.  `handler_func`: A function that processes the log record (e.g., `lualog.handlers.stream_handler`).
2.  `formatter_func`: A function that formats the log record before it's passed to the handler (e.g., `lualog.formatters.plain_formatter`).
3.  `handler_config` (optional table): Configuration for the handler (e.g., `{stream = io.stderr}`).

### 6. Controlling Propagation

By default, after a logger processes a message with its own handlers, the message is passed to its parent logger's handlers. You can disable this:

```lua
local lualog = require("lual.log.luallog")

local parent_logger = lualog.get_logger("app.service")
parent_logger:set_level(lualog.levels.INFO)
parent_logger:add_handler(lualog.handlers.stream_handler, lualog.formatters.plain_formatter)

local child_logger = lualog.get_logger("app.service.worker")
child_logger:set_level(lualog.levels.DEBUG)
child_logger:add_handler(lualog.handlers.stream_handler, lualog.formatters.plain_formatter, {stream = io.stderr})

-- By default, child_logger.propagate is true
child_logger:info("Message from child (to stderr AND propagates to parent for stdout).")

-- Disable propagation for child_logger
child_logger.propagate = false
child_logger:warn("Another message from child (to stderr ONLY, does NOT propagate).")
```

## Extending `lual.log`

You can create custom handlers and formatters:

*   **Custom Handler:** A function with the signature `my_handler(record, config)`
    *   `record`: A table containing the log details (already formatted message, level info, timestamp, etc.).
    *   `config`: The `handler_config` table passed when adding the handler.
*   **Custom Formatter:** A function with the signature `my_formatter(record)`
    *   `record`: A table with raw log details (message format string, arguments, level info, timestamp, etc.).
    *   Should return a single string: the formatted log message.

```lua
-- Example: Simple custom formatter that adds a prefix
local function prefix_formatter(record)
  local original_message = string.format(record.message_fmt, unpack(record.args or {}))
  return string.format("[MyPrefix] %s: %s", record.level_name, original_message)
end

-- Example: Simple custom handler that prints to console with a bang
local function bang_handler(record, config)
  print("BANG!!! " .. record.message) -- record.message is already formatted
end

local my_logger = lualog.get_logger("custom.test")
my_logger:set_level(lualog.levels.INFO)
my_logger:add_handler(bang_handler, prefix_formatter)

my_logger:info("This is a custom test.") 
-- Output via bang_handler after being formatted by prefix_formatter:
-- BANG!!! [MyPrefix] INFO: This is a custom test.
```

## Running Tests

The library uses Busted for testing. To run the tests:
1.  Ensure Busted is installed (e.g., `luarocks install busted`).
2.  Navigate to the root directory of the `lual.log` project.
3.  Run the command: `busted`

## Contributing

Contributions are welcome! Please feel free to submit issues or pull requests.
(Further details on contribution guidelines can be added here).

## License

`lual.log` is released under the MIT License. (Verify and update if different).
```
