# Root Logger Configuration System

## Current System (How It Works Now)

### Architecture Overview

The current lual logging system is **logger-centric** with independent configurations:

1. **Entry Point**: `require("lual")` loads `lua/lual/logger.lua`
2. **Logger Creation**:
   - `lual.logger("name")` - Simple logger with auto-generated config
   - `lual.logger({name="app", level="debug", dispatchers={...}})` - Full config
3. **Independence**: Each logger is configured independently
4. **Hierarchy**: Parent-child relationships are **explicit** via config:

   ```lua
   -- Explicit parent relationship
   local child = lual.logger({
     name = "app.module",
     parent = parent_logger,  -- Must be explicitly set
     propagate = true         -- Must be explicitly enabled
   })
   ```

**Current Propagation Model** (in `prototype.lua:get_effective_dispatchers()`):

- Starts from the source logger
- Traverses UP the parent chain only if:
  - `current_logger.propagate == true` AND
  - `current_logger.parent ~= nil`
- Collects dispatchers from each logger in the chain
- Each dispatcher retains its owner logger's name and level

**Key Limitation**: No automatic root inheritance - loggers are islands unless explicitly connected.

### Current Configuration Flow

1. **Config Processing** (`config.lua`):
   - Validates input config (convenience vs full syntax)
   - Normalizes convenience syntax to canonical form
   - Creates dispatcher/presenter/transformer function chains

2. **Logger Creation** (`factory.lua`):
   - Uses canonical config to build logger instance
   - Attaches methods from `prototype.lua`
   - Stores in cache with name as key

3. **Event Dispatch** (`ingest.lua`):
   - Logger calls `ingest.dispatch_log_event()`
   - Retrieves effective dispatchers via `get_effective_dispatchers()`
   - Processes each dispatcher if level threshold is met

## Desired System (Future State)

### Root Logger as Universal Parent (When Configured)

**Core Concept**: Introduce a **root logger** that, when configured via `lual.config({})`, acts as the implicit parent for all loggers unless explicitly overridden. If `lual.config({})` is not called, no root logger instance is created by default.

### New API: `lual.config({})`

This API is the **sole method to create and configure the root logger**.
```lua
-- Creates and configures the root logger.
-- This affects ALL subsequent loggers that propagate to it.
lual.config({
  level = "warn",
  dispatchers = {
    {type = "file", path = "app.log", presenter = "json"}
  },
  timezone = "utc"
})

-- All these loggers now have the configured root as their ultimate ancestor
local app_logger = lual.logger("app")           -- Parent: root (if lual.config was called)
local db_logger = lual.logger("app.database")   -- Parent: app 
local auth_logger = lual.logger("auth")         -- Parent: root (if lual.config was called)
```

### Automatic Hierarchy Construction

**Naming-Based Hierarchy**: Loggers form parent-child relationships based on their names (e.g., "app.database" is a child of "app").
- `"app"` → parent: `"root"` (if root is configured via `lual.config({})`)
- `"app.database"` → parent: `"app"`
- `"app.database.connection"` → parent: `"app.database"`
- `"auth"` → parent: `"root"` (if root is configured via `lual.config({})`)

If no root logger is configured, loggers like `"app"` or `"auth"` become top-level loggers of their respective hierarchies without a predefined common root instance.

### Propagation Model (Not Inheritance)

**Key Principle**: Each logger fires **its own dispatchers** with **its own configuration**, then propagates the raw event to parents.

## Configuration Examples

### Example 1: No Configuration (Simplest Case)

```lua
-- File: app.lua
local lual = require('lual')
-- lual.config({}) is NOT called in this scenario.
local app_logger = lual.logger()  -- No config provided
```

**Behind the scenes:**

1. **Auto-name detection**: Logger name becomes `"app"` (from filename)
2. **Hierarchy consideration**: `"app"` is a potential child of `"root"`. However, since `lual.config({})` has not been called, no actual "root" logger instance with dispatchers exists by default.
3. **Configuration at each level**:
   - `root`: Does not exist as an active logger with configuration unless `lual.config({})` is called.
   - `app`: `{level=info, dispatchers=[], propagate=true, timezone="local"}` (default settings for this logger instance)

**Event: `app_logger:warn("something")`**

1. **app logger**: warn >= info ✅ → fires 0 dispatchers (none configured on `app_logger`)
2. **Propagates to "root" (conceptually)**: Since no root logger has been configured via `lual.config({})`, there are no dispatchers at the root level to process the event.
3. **Result**: No output (no dispatchers configured on `app_logger`, and no default active root logger). To get output, one would either configure `app_logger` directly or call `lual.config({})` to set up root-level dispatchers.

### Example 2: Root Configuration Only

This example demonstrates the behavior when `lual.config({})` *is* used.
```lua
-- Configure root logger for the application
lual.config({
  level = "warn",
  dispatchers = {
    {type = "file", path = "app.log", presenter = "json"}
  },
  timezone = "utc"
})

-- File: app.lua  
local app_logger = lual.logger()  -- Auto-named "app"
```

**Configuration at each level:**

- `root`: `{level=warn, dispatchers=[{file}], timezone="utc"}` (explicitly configured via `lual.config({})`)
- `app`: `{level=info, dispatchers=[], propagate=true, timezone="local"}` (defaults for this logger instance)

**Event: `app_logger:warn("security alert")`**

1. **app logger**: warn >= info ✅ → fires 0 dispatchers  
2. **Propagates to root**: warn >= warn ✅ → fires file dispatcher with UTC timestamp
3. **Result**: One log entry in `app.log` with UTC timestamp

**Event: `app_logger:info("debug info")`**

1. **app logger**: info >= info ✅ → fires 0 dispatchers
2. **Propagates to root**: info >= warn ❌ → fires 0 dispatchers  
3. **Result**: No output (info < warn at root level)

### Example 3: Multi-Level Configuration

```lua
-- Root: Audit logging
lual.config({
  level = "warn", 
  dispatchers = {
    {type = "file", path = "audit.log", presenter = "json"}
  },
  timezone = "utc"
})

-- Child: Development logging
local app_logger = lual.logger({
  name = "app",
  level = "debug",
  dispatchers = {
    {type = "console", presenter = "color"}  
  },
  timezone = "local"
})
```

**Configuration at each level:**

- `root`: `{level=warn, dispatchers=[{file/json/utc}], timezone="utc"}`
- `app`: `{level=debug, dispatchers=[{console/color/local}], timezone="local"}`

**Event: `app_logger:warn("security issue")`**

1. **app logger**: warn >= debug ✅ → fires console with LOCAL timestamp  
2. **Propagates to root**: warn >= warn ✅ → fires file with UTC timestamp
3. **Result**:
   - Console: "2025-05-30 15:30:00 WARN [app] security issue" (local time, color)
   - File: `{"timestamp":"2025-05-30T18:30:00Z","level":"WARN","logger":"root","message":"security issue"}` (UTC)

**Event: `app_logger:debug("trace info")`**

1. **app logger**: debug >= debug ✅ → fires console with local timestamp
2. **Propagates to root**: debug >= warn ❌ → fires 0 dispatchers
3. **Result**: Console only (file doesn't get debug messages)

### Example 4: Hierarchy with Intermediate Loggers

```lua
lual.config({
  level = "error",
  dispatchers = [{type = "file", path = "errors.log"}],
  timezone = "utc"  
})

local db_logger = lual.logger({
  name = "app.database",
  level = "info", 
  dispatchers = [{type = "console", presenter = "text"}]
})
```

**Hierarchy**: `app.database` → `app` → `root`

**Configuration at each level:**

- `root`: `{level=error, dispatchers=[{file}], timezone="utc"}`
- `app`: `{level=info, dispatchers=[], timezone="local"}` (auto-created, defaults)
- `app.database`: `{level=info, dispatchers=[{console}], timezone="local"}`

**Event: `db_logger:error("connection failed")`**

1. **app.database**: error >= info ✅ → fires console
2. **Propagates to app**: error >= info ✅ → fires 0 dispatchers
3. **Propagates to root**: error >= error ✅ → fires file
4. **Result**: Console (local time) + File (UTC time)

## Key Benefits of Propagation Model

### 1. **Guaranteed Root Behavior (When Configured)**

When a root logger is configured using `lual.config({})`, it provides **promises** that can't be broken by child loggers:

- "All errors go to monitoring system"
- "All events get UTC timestamps in audit log"
- "Security events always logged regardless of child config"

### 2. **Flexible Child Customization**

Child loggers can add supplementary behavior without affecting root guarantees:

- Debug console output for development
- Module-specific formatting
- Local timestamps for readability

### 3. **No Configuration Conflicts**

Each logger applies its own settings to its own dispatchers:

- Root file handler always uses UTC (as configured)
- Child console handler can use local time (as configured)  
- No inheritance means no unexpected setting overrides

### 4. **Predictable Multi-Level Output**

Clear separation of concerns:

- Root handles enterprise concerns (audit, monitoring, compliance)
- Children handle developer concerns (debugging, tracing, formatting)
- Same event can produce different outputs at different levels with different configurations

TLDR: 
  - logger(config_table) creates a named logger
  - lual.config() -> creates a root logger
  - propagation walks the tree upwards, and at every level, if there is a logger defined, merges the upwards config



## Migration Path

**Backward Compatibility**:

1. Existing `lual.logger()` calls work. However, if `lual.config({})` is not called, there will be no automatic default root logger. This means if an application relied on an implicit root logger with default handlers (e.g., a console handler just by requiring `lual`), that behavior will change: output will only occur if specific loggers are configured or if `lual.config({})` is used to establish root-level handling.
2. Explicit parent/propagate settings in individual logger configurations still take precedence for how an event propagates up its specific chain.

**New Features**:

1. `lual.config({})` is the explicit way to enable and configure a root logger, providing application-wide baseline behavior.
2. Naming-based parent resolution works automatically for defined loggers.
