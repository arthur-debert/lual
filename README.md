# lual - Powerful Logging Withough the Hassle

lual is logging library for lua. Modeled after Python's standard lib, with a leaner API making good usage of Lua idioms, such as using functions over classes. The API is design to scale from a simple personal project to more complex deployments with hierarchical configurations and multiple pipelines.

## Quick Start

```lua
local lual = require("lual")
local logger = lual.logger()
-- Use format strings
logger:info("Application started, init took %f", init_time)      
-- Structured logs when you need them
logger:info("Init complete", {plugins_installed = plugins, os = os_name, version = app_version})


-- Centralized configuration
lual.config({
    level = lual.debug,
    pipelines = {
        { level = lual.warn, outputs = { lual.console }, presenters = { lual.color } },
        { level = lual.debug, outputs = { lual.file, path = "app.log" }, presenter = { lual.json() } }
    }
})
```

## Key Features

- **Flexible Logging**: Format strings, structured logs - choose what works best for your needs.
- **Leveled Configuration**: From "set the level and go" to centralized configuration to complex hierarchical logger configurations.
- **Custom Log Levels**: Define named levels like `verbose` or `trace` with meaningful semantics for specialized logging needs.
- **Pluggable Log Pipeline**: For processing, formatting, and outputting logs. Use the built-in components or write custom functions.
- **Built-in Components**: Write to the console, files, or syslog; format as JSON, plain text, or colored terminal output.
- **Hierarchical Loggers**: Dot-separated logger names create automatic parent-child relationships with propagation.
- **Performance**: Efficient level filtering and lazy evaluation minimize overhead.

## Lean and Dependency-Free

lual aims to be a good fit for demanding deployments where performance, file size, and dependencies matter. The core library is small and has good performance characteristics.

The base install has no dependencies. If you use these specific components, then you must have their dependencies installed:

- JSON presenter requires dkjson
- Syslog output requires luasocket

[See if lual is not a good fit for your deployment for more details.](#who-lual-is-not-for)

## Installation

Install via LuaRocks:

```