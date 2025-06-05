# Quick Start Guide

Get up and running with lual in 5 minutes.

## Installation

```bash
luarocks install lual
```

## Your First Log

```lua
local lual = require("lual")
local logger = lual.logger("myapp")

logger:info("Hello, lual!")
```
**Output:**

```text
2024-01-15 14:30:25 INFO [myapp] Hello, lual!
```
```

That's it! The root logger automatically handles console output with a sensible default format.

## Control What Gets Logged

By default, only `WARN` level and above are shown:

```lua
local logger = lual.logger("myapp")

logger:debug("Not shown")        -- Below WARN level  
logger:info("Not shown")         -- Below WARN level
logger:warn("This appears")      -- WARN level - shown
logger:error("This appears")     -- ERROR level - shown
```

Enable debug logging globally:

```lua
local lual = require("lual")

-- Configure root logger for more verbose output
lual.config({
    level = lual.debug
})

local logger = lual.logger("myapp")
logger:debug("Now this appears too!")
```

## Custom Log Levels

Define your own levels for specialized logging:

```lua
local lual = require("lual")

-- Define custom levels
lual.config({
    level = lual.debug,
    custom_levels = {
        verbose = 25,  -- Between INFO(20) and WARNING(30)
        trace = 15     -- Between DEBUG(10) and INFO(20)
    }
})

local logger = lual.logger("myapp")

-- Use custom levels with log() method (primary usage)
logger:log("verbose", "Starting complex operation")
logger:log("trace", "Variable x = %d", 42)

-- Or use dynamic method calls (secondary usage)
logger:verbose("Processing batch 1 of 10")
logger:trace("Loop iteration %d", i)
```

**Output:**
```text
2024-01-15 14:30:25 VERBOSE [myapp] Starting complex operation
2024-01-15 14:30:25 TRACE [myapp] Variable x = 42
2024-01-15 14:30:25 VERBOSE [myapp] Processing batch 1 of 10
```

## Add File Logging

Log to both console and file:

```lua
local lual = require("lual")

lual.config({
    level = lual.info,
    pipelines = {
        { outputs = { lual.console }, presenter = lual.color() },              -- Colored console
        { outputs = { { lual.file, path = "app.log" } }, presenter = lual.text() }  -- Plain text file
    }
})

local logger = lual.logger("myapp")
logger:info("This goes to console AND app.log")
```

## Logger Hierarchy

Loggers automatically form hierarchies based on their names:

```lua
local app_logger = lual.logger("myapp")
local db_logger = lual.logger("myapp.database")
local auth_logger = lual.logger("myapp.auth")

-- Events propagate up the hierarchy
db_logger:error("Connection failed")  
-- This appears in:
-- 1. Any outputs configured on "myapp.database" 
-- 2. Any outputs configured on "myapp"
-- 3. The root logger's outputs (console by default)
```

## Module-Specific Configuration

Create loggers with their own behavior:

```lua
-- Database logger with detailed file logging
local db_logger = lual.logger("myapp.database", {
    level = lual.debug,
    pipelines = {
        { outputs = { { lual.file, path = "database.log" } }, presenter = lual.json() }
    }
})

-- Events still propagate to parent loggers
db_logger:debug("SQL query executed")  -- Goes to database.log
db_logger:error("Connection timeout")  -- Goes to database.log AND console
```

## What's Next?

You now know the basics! Here's where to go next:

- **Learn core concepts** → [Basic Concepts](basic-concepts.md)
- **Understand hierarchy** → [Hierarchical Logging](../guide/hierarchical-logging.md)
- **Explore advanced features** → [Deep Dives](../deep-dives/)
- **Find specific functions** → [API Reference](../reference/api.md)

## Common Questions

**Q: Where do logs go by default?**  
A: Console (stdout) with WARN level and above.

**Q: Can I have multiple outputs?**  
A: Yes! Console, files, custom outputs - all simultaneously.

**Q: Do I need to configure parent loggers?**  
A: No! Child loggers automatically propagate to parents.

**Q: What if I want JSON logs?**  
A: Use `presenter = lual.json()` in your output configuration.

---

**Ready for more?** Continue with [Basic Concepts](basic-concepts.md) or explore [Deep Dives](../deep-dives/).