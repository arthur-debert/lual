# lual - A Hierarchical Logging Library for Lua

lual is a powerful yet simple logging library for Lua, inspired by Python's standard library logging. It provides hierarchical loggers, flexible configuration, and a clean component-based architecture.

## Quick Start

```lua
local lual = require("lual")

-- Simple logging with auto-configuration
local logger = lual.logger("myapp")

logger:info("Application started")      -- Logged to console
logger:debug("Debug info")             -- Not logged (default level is WARN)
logger:error("Something went wrong!")   -- Logged to console
```

## Key Features

- **Hierarchical Loggers**: Dot-separated logger names create automatic parent-child relationships
- **Flexible Configuration**: Simple configs for basic use, powerful options for complex scenarios  
- **Component Pipeline**: Modular transformers, presenters, and outputs
- **Built-in Components**: Console, file, JSON, text, and colored output
- **Propagation**: Log events automatically flow up the logger hierarchy
- **Performance**: Efficient level filtering and lazy evaluation

## Common Usage Patterns
## Common Usage Patterns

### 1. Out-of-the-box Logging

```lua
local lual = require("lual")
local logger = lual.logger("myapp")

logger:warn("This appears in console")   -- Uses built-in root logger
logger:debug("This doesn't")             -- Below default WARN level
```

### 2. Configure Root Logger

```lua
local lual = require("lual")

-- Configure global logging behavior
lual.config({
    level = lual.debug,
    outputs = {
        { lual.console, presenter = lual.color() },
        { lual.file, path = "app.log", presenter = lual.json() }
    }
})

local logger = lual.logger("myapp.database")
logger:debug("Now debug messages appear everywhere")
```

### 3. Logger-Specific Configuration

```lua
-- Create a logger with its own outputs
local db_logger = lual.logger("myapp.database", {
    level = lual.debug,
    outputs = {
        { lual.file, path = "database.log", presenter = lual.text() }
    }
})

db_logger:debug("Database query executed")  -- Goes to database.log
db_logger:error("Connection failed")        -- Goes to database.log AND root logger outputs
```
## Installation

Install via LuaRocks:

```bash
luarocks install lual
```

Or download and require the library directly.

## Documentation

- **[Getting Started Guide](docs/getting-started/)** - Quick introduction and basic concepts
- **[User Guide](docs/guide/)** - Configuration, hierarchy, and common patterns
- **[Deep Dives](docs/deep-dives/)** - Advanced topics and internals
- **[API Reference](docs/reference/)** - Complete API documentation

## Built-in Components

**Outputs:**

- `lual.console` - Write to stdout/stderr
- `lual.file` - Write to files with rotation support

**Presenters:**

- `lual.text()` - Plain text format with timestamps
- `lual.json()` - Structured JSON output
- `lual.color()` - ANSI colored text for terminals

**Levels:**

- `lual.debug`, `lual.info`, `lual.warn`, `lual.error`, `lual.critical`

## Contributing

Contributions welcome! See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

MIT License - see LICENSE file for details.
