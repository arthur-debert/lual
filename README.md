# lual - logging made easy

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
- **Pluggable Log Pipeline**: For processing, formatting, and outputting logs. Use the built-in components or write custom functions.
- **Built-in Components**: Write to the console, files, or syslog; format as JSON, plain text, or colored terminal output.
- **Hierarchical Loggers**: Dot-separated logger names create automatic parent-child relationships with propagation.
- **Performance**: Efficient level filtering and lazy evaluation minimize overhead.

## Lean and Dependency-Free

lual aims to be a good fit for demanding deployments where performance, file size, and dependencies matter. The core library is small and has good performance characteristics.

The base install has no dependencies. If you use these specific components, then you must have their dependencies installed:
- JSON presenter requires dkjson
- Syslog output requires luasocket

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

## Contributing

Contributions welcome! See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

MIT License - see LICENSE file for details.


Made with ❤️ for the Lua community