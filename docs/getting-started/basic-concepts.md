# Basic Concepts

Understanding these core concepts will help you use lual effectively.

## Loggers

**Loggers** are the main interface for emitting log messages. Each logger has a name and can be configured independently.

```lua
local lual = require("lual")

-- Create/get loggers by name
local app_logger = lual.logger("myapp")
local db_logger = lual.logger("myapp.database")
local cache_logger = lual.logger("myapp.cache")
```

### Logger Names and Hierarchy

Logger names use dot notation to create automatic parent-child relationships:
```text
_root (internal)
├── myapp
│   ├── myapp.database
│   ├── myapp.cache
│   └── myapp.auth
│       └── myapp.auth.oauth
```
```

Child loggers inherit configuration from parents and propagate events upward.

## Log Levels

**Levels** control which messages get processed. From most to least verbose:

- `lual.debug` - Detailed debugging information
- `lual.info` - General information messages  
- `lual.warn` - Warning messages (default root level)
- `lual.error` - Error conditions
- `lual.critical` - Critical failures

```lua
local logger = lual.logger("myapp")

logger:debug("Detailed info")     -- Only if level is DEBUG or lower
logger:info("General info")       -- Only if level is INFO or lower  
logger:warn("Warning message")    -- Default level - always shown
logger:error("Error occurred")    -- Always shown
logger:critical("System failing") -- Always shown
```

### Level Inheritance

Loggers inherit their effective level from their closest configured ancestor:

```lua
lual.config({ level = lual.info })  -- Root level

local app_logger = lual.logger("myapp")          -- Inherits INFO
local db_logger = lual.logger("myapp.database", {
    level = lual.debug                            -- Explicitly DEBUG
})
local query_logger = lual.logger("myapp.database.query")  -- Inherits DEBUG from parent
```

### Custom Log Levels

You can define custom log levels with meaningful names for specialized logging needs:

```lua
-- Define custom levels in configuration
lual.config({
    custom_levels = {
        verbose = 25,  -- Between INFO(20) and WARNING(30)
        trace = 15     -- Between DEBUG(10) and INFO(20)
    },
    level = lual.debug  -- Set to allow all custom levels
})

local logger = lual.logger("myapp")

-- Use custom levels with explicit log() method (primary usage)
logger:log("verbose", "This is a verbose message")
logger:log("trace", "Detailed trace information")

-- Or use dynamic method calls (secondary usage)
logger:verbose("This also works")
logger:trace("So does this")

-- Custom levels work with all level filtering
lual.config({ level = 25 })  -- Only verbose(25) and above will be processed
```

**Custom Level Rules:**
- Names must be lowercase valid Lua identifiers (no underscores at start)
- Values must be integers between DEBUG(10) and ERROR(40), exclusive
- Cannot conflict with built-in level values (10, 20, 30, 40, 50)
- Custom levels appear as uppercase in log output (e.g., `[VERBOSE]`, `[TRACE]`)

**API Methods:**
```lua
-- Get all available levels (built-in + custom)
local all_levels = lual.get_levels()

-- Set/replace all custom levels
lual.set_levels({
    verbose = 25,
    trace = 15
})
```

**Legacy Support:** You can still use any numeric level value directly with `logger:log(34, "message")`, which displays as `UNKNOWN_LEVEL_NO_34`.

## Root Logger

The **root logger** (`_root` internally) is automatically created when lual loads. It provides default configuration for all other loggers.

```lua
-- Configure root logger behavior
lual.config({
    level = lual.debug,
    pipelines = {
        { outputs = { lual.console }, presenter = lual.color() }
    }
})

-- All loggers inherit from root by default
local logger = lual.logger("any.name")  -- Gets root config
```

## Pipelines, Outputs and Presenters  

**Pipelines** combine outputs and presenters with optional level filtering.
**Outputs** determine where logs go (console, files, network).  
**Presenters** determine how logs are formatted (text, JSON, colors).

```lua
lual.config({
    pipelines = {
        { outputs = { lual.console }, presenter = lual.text() },                    -- Plain text to console
        { outputs = { { lual.file, path = "app.log" } }, presenter = lual.json() }  -- JSON to file
    }
})
```

### Built-in Components

**Outputs:**

- `lual.console` - stdout/stderr
- `lual.file` - File with rotation

**Presenters:**

- `lual.text()` - Plain text with timestamps
- `lual.json()` - Structured JSON
- `lual.color()` - ANSI colored text

## Propagation

**Propagation** means log events automatically flow up the logger hierarchy:

```lua
local db_logger = lual.logger("myapp.database", {
    pipelines = { { outputs = { { lual.file, path = "db.log" } }, presenter = lual.text() } }
})

db_logger:error("Connection failed")
```

This error message goes to:

1. `db.log` (from myapp.database's pipeline)
2. Console (from root logger's default pipeline)

Propagation can be disabled per logger:

```lua
local db_logger = lual.logger("myapp.database", {
    pipelines = { { outputs = { { lual.file, path = "db.log" } }, presenter = lual.text() } },
    propagate = false  -- Stop here, don't go to parent
})
```

## Configuration Approaches

### 1. Global Configuration

```lua
-- Configure root logger for all loggers
lual.config({
    level = lual.info,
    pipelines = { { outputs = { lual.console }, presenter = lual.text() } }
})
```

### 2. Logger-Specific Configuration

```lua
-- Configure individual loggers
local logger = lual.logger("myapp", {
    level = lual.debug,
    pipelines = { { outputs = { { lual.file, path = "debug.log" } }, presenter = lual.text() } }
})
```

### 3. Imperative Configuration

```lua
-- Configure using methods
local logger = lual.logger("myapp")
logger:set_level(lual.debug)
logger:add_pipeline({
    outputs = { { lual.file, path = "debug.log" } },
    presenter = lual.text()
})
```

## Key Takeaways

1. **Loggers form hierarchies** based on dot-separated names
2. **Levels filter messages** - set appropriate thresholds, including custom levels
3. **Root logger provides defaults** for all other loggers
4. **Events propagate upward** unless explicitly disabled
5. **Pipelines combine outputs and presenters** with optional level filtering
6. **Custom levels** add meaningful names to numeric levels for specialized logging

## What's Next?

- **See it in action** → [Quick Start](quick-start.md)
- **Learn hierarchy details** → [Hierarchical Logging](../guide/hierarchical-logging.md)
- **Explore advanced features** → [Deep Dives](../deep-dives/)
- **Find specific functions** → [API Reference](../reference/api.md)