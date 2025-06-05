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

See [if lual is not a good fit for your deployment for more](#who-lual-is-not-for)

## Installation

Install via LuaRocks:

```bash
luarocks install lual
```

## Documentation

- **[Getting Started Guide](docs/getting-started/)** - Quick introduction and basic concepts
- **[User Guide](docs/guide/)** - Configuration, hierarchy, and common patterns
- **[Deep Dives](docs/deep-dives/)** - Advanced topics and internals
- **[API Reference](docs/reference/)** - Complete API documentation

## Who lual is not for

Currently, lual has two primary limitations that might be important for your use case:

1.  **Limited Variety of Built-in Output Writers**

    For simpler applications or those with basic logging needs, lual's built-in output writers (like console and file) are generally sufficient. However, larger or more complex applications often require logging to diverse systems, each with unique protocols, formats, and performance considerations.

    In many scenarios, logging to files or syslog provides a good baseline, as these can often be integrated with other systems via adapters. But, if you require direct integration with specialized output targets and cannot use file/syslog adapters, you would need to implement custom output writers.

2.  **Blocking I/O**

    All logging operations in lual, from event dispatch to the final output write, are blocking. This can be a critical limitation for high-throughput systems where logging performance and application responsiveness are paramount.

    Improving this aspect is an area for potential future development. Feedback or suggestions on non-blocking I/O approaches suitable for the Lua ecosystem are welcome.

## Contributing

Contributions welcome! See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

MIT License - see LICENSE file for details.

Made with ❤️ for the Lua community
