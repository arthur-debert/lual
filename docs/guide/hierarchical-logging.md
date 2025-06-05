# Hierarchical Logging

One of lual's most powerful features is its hierarchical logging system. This guide explains how logger hierarchies work and how to use them effectively.

## Logger Names and Tree Structure

Loggers in lual are organized in a tree structure based on dot-separated names:

```
_root (internal)
├── app
│   ├── app.api
│   │   ├── app.api.auth
│   │   └── app.api.users
│   ├── app.database
│   └── app.worker
└── lib
    └── lib.http
```

Each component of the name represents a level in the hierarchy:

```lua
local lual = require("lual")

-- Creates multiple levels in the hierarchy
local api_logger = lual.logger("app.api")
local auth_logger = lual.logger("app.api.auth")
local db_logger = lual.logger("app.database")
```

## The Root Logger

At the top of the hierarchy is the special **root logger**, internally named `_root`. It's automatically created when lual is loaded and provides default configuration for all other loggers.

You can configure the root logger using `lual.config()`:

```lua
-- Configure the root logger
lual.config({
    level = lual.info,
    outputs = {
        { lual.console, presenter = lual.color() }
    }
})
```

The root logger has these default settings:
- **Level:** `lual.warn`
- **Outputs:** Console with text presenter
- **Propagate:** `true` (though propagation stops at root)

## Level Inheritance

Loggers have an **effective level** that determines which log events they process:

1. If a logger has an explicitly set level, that's its effective level
2. If not (level is `lual.NOTSET`), it inherits from its closest configured ancestor

```lua
-- Root level is INFO
lual.config({ level = lual.info })

-- These loggers inherit INFO from root
local app_logger = lual.logger("app")           -- Effective level: INFO
local api_logger = lual.logger("app.api")       -- Effective level: INFO

-- This logger has its own level
local db_logger = lual.logger("app.database", {
    level = lual.debug                          -- Effective level: DEBUG
})

-- This inherits DEBUG from its parent
local query_logger = lual.logger("app.database.query")  -- Effective level: DEBUG
```

This inheritance mechanism lets you control logging verbosity at any level of your application hierarchy.

## Propagation

When a logger processes a log event, the event automatically **propagates** up the hierarchy to its parent logger, grandparent, and so on, up to the root logger.

Each logger in the chain:
1. Checks if the event level meets its effective level threshold
2. If yes, processes the event through its outputs
3. Passes the event to its parent (unless propagation is disabled)

```lua
local db_logger = lual.logger("app.database", {
    level = lual.debug,
    outputs = {
        { lual.file, path = "database.log" }
    }
})

-- This event:
db_logger:error("Connection failed")

-- 1. Processed by app.database (goes to database.log)
-- 2. Propagates to app
-- 3. Propagates to _root (goes to console by default)
```

### Controlling Propagation

You can disable propagation for specific loggers:

```lua
local auth_logger = lual.logger("app.api.auth", {
    outputs = {
        { lual.file, path = "auth.log" }
    },
    propagate = false  -- Events stop here
})

-- This only goes to auth.log, not to parent loggers
auth_logger:warn("Authentication attempt failed")
```

## Common Hierarchy Patterns

### 1. Centralized Logging

Configure just the root logger for a simple setup:

```lua
-- All logs go through root
lual.config({
    level = lual.info,
    outputs = {
        { lual.file, path = "app.log" }
    }
})

-- Use different loggers throughout the code
local api_logger = lual.logger("app.api")
local db_logger = lual.logger("app.database")
local worker_logger = lual.logger("app.worker")

-- All logs go to app.log
```

### 2. Component-Specific Logging

Give critical components their own output streams:

```lua
-- General logs
lual.config({
    level = lual.info,
    outputs = {
        { lual.console }
    }
})

-- Database gets detailed debug logs in its own file
local db_logger = lual.logger("app.database", {
    level = lual.debug,
    outputs = {
        { lual.file, path = "database.log" }
    }
})

-- Auth gets security-focused logging
local auth_logger = lual.logger("app.api.auth", {
    level = lual.debug,
    outputs = {
        { lual.file, path = "auth.log" }
    }
})
```

### 3. Development/Debugging Setup

Set verbose output for specific modules during development:

```lua
-- Root has normal settings
lual.config({
    level = lual.info,
    outputs = {
        { lual.console }
    }
})

-- During development, make just the feature you're working on verbose
local feature_logger = lual.logger("app.new_feature", {
    level = lual.debug,
    outputs = {
        { lual.console, presenter = lual.color() }
    }
})
```

## Best Practices

1. **Use meaningful hierarchical names** that reflect your application structure
2. **Configure the root logger** for general application logging
3. **Only set explicit levels** where needed - rely on inheritance elsewhere
4. **Add specialized outputs** only to loggers that need them
5. **Use propagation** to ensure important events are seen at all levels
6. **Disable propagation sparingly** - usually only for high-volume or sensitive logs

## Examples

### Server Application Structure

```lua
local lual = require("lual")

-- Root config (server-wide)
lual.config({
    level = lual.info,
    outputs = {
        { lual.file, path = "/var/log/myapp/server.log" }
    }
})

-- API logging with special error tracking
local api_logger = lual.logger("app.api", {
    outputs = {
        { lual.file, path = "/var/log/myapp/api.log", level = lual.error }
    }
})

-- Database with detailed debug output
local db_logger = lual.logger("app.database", {
    level = lual.debug,
    outputs = {
        { lual.file, path = "/var/log/myapp/database.log" }
    }
})

-- Auth with secure logging
local auth_logger = lual.logger("app.api.auth", {
    outputs = {
        { lual.file, path = "/var/log/myapp/auth.log" }
    }
})
```

This setup ensures:
- All INFO+ logs go to server.log
- API ERROR+ logs also go to api.log
- All database DEBUG+ logs go to database.log
- All auth INFO+ logs go to auth.log
- Critical errors from any component appear in multiple logs

---

With these principles, you can create flexible, powerful logging hierarchies tailored to your application's needs. 