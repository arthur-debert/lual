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

```
_root (internal)
├── myapp
│   ├── myapp.database  
│   ├── myapp.cache
│   └── myapp.auth
│       └── myapp.auth.oauth
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

## Root Logger

The **root logger** (`_root` internally) is automatically created when lual loads. It provides default configuration for all other loggers.

```lua
-- Configure root logger behavior
lual.config({
    level = lual.debug,
    outputs = {
        { lual.console, presenter = lual.color() }
    }
})

-- All loggers inherit from root by default
local logger = lual.logger("any.name")  -- Gets root config
```

## Outputs and Presenters  

**Outputs** determine where logs go (console, files, network).  
**Presenters** determine how logs are formatted (text, JSON, colors).

```lua
lual.config({
    outputs = {
        { lual.console, presenter = lual.text() },      -- Plain text to console
        { lual.file, path = "app.log", presenter = lual.json() }  -- JSON to file
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
    outputs = { { lual.file, path = "db.log" } }
})

db_logger:error("Connection failed")
```

This error message goes to:
1. `db.log` (from myapp.database's output)
2. Console (from root logger's default output)

Propagation can be disabled per logger:

```lua
local db_logger = lual.logger("myapp.database", {
    outputs = { { lual.file, path = "db.log" } },
    propagate = false  -- Stop here, don't go to parent
})
```

## Configuration Approaches

### 1. Global Configuration
```lua
-- Configure root logger for all loggers
lual.config({
    level = lual.info,
    outputs = { { lual.console } }
})
```

### 2. Logger-Specific Configuration  
```lua
-- Configure individual loggers
local logger = lual.logger("myapp", {
    level = lual.debug,
    outputs = { { lual.file, path = "debug.log" } }
})
```

### 3. Imperative Configuration
```lua
-- Configure using methods
local logger = lual.logger("myapp")
logger:set_level(lual.debug)
logger:add_output(lual.file, { path = "debug.log" })
```

## Key Takeaways

1. **Loggers form hierarchies** based on dot-separated names
2. **Levels filter messages** - set appropriate thresholds  
3. **Root logger provides defaults** for all other loggers
4. **Events propagate upward** unless explicitly disabled
5. **Outputs and presenters are independent** - mix and match

## What's Next?

- **Hands-on practice** → [Your First Logger](first-logger.md)
- **See it in action** → [Basic Examples](../examples/basic-examples.md)  
- **Learn hierarchy details** → [Hierarchical Logging](../guide/hierarchical-logging.md)
- **Master configuration** → [Configuration Guide](../guide/configuration.md) 