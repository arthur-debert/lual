# lual - Powerful Logging Without the Hassle


lual is a flexible logging library for lua strives for giving developers various ways to manage logging with ease.

It provides one-off, centralized and hierarchical logging with propagation, synchronous, co-routine or libuv based asynchronous logging, and a variety of pluggable transformers, formatters and writers. 

It has some less common features such as automated mapping to -v -vv -vvv
command line options and live log level control via enviroment variables.


It's modeled after Python's std lib logging modules, supporting very similar semantics, but with a lighter, more lua friendly API, like using functions over classes, and a more flexible configuration system.


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
        { level = lual.warn, outputs = { lual.console }, presenter = lual.color },
        { level = lual.debug, outputs = { lual.file, path = "app.log" }, presenter = lual.json() }
    }
})
```

## Key Features

- **Flexible Logging**: Format strings, structured logs - choose what works best for your needs.
- **Hierachical Configuration**: From "set the level and go" to centralized configuration to complex hierarchical logger configurations.
- **Custom Log Levels**: Define named levels like `verbose` or `trace` with meaningful semantics for specialized logging needs.
- **Pluggable Log Pipeline**: For processing, formatting, and outputting logs. Use the built-in components or write custom functions.
- **Built-in Components**: Write to the console, files, or syslog; format as JSON, plain text, or colored terminal output.
- **Runtime Level Control**:  Change log levels on the fly via environment variables or command line flags without restarting your application.
- **AsyncIO**:  [Async I/O Guide](docs/guide/async/async-io.md)  in experimental mode, with coroutines and libluv backend (requires luv lib)

## Lean and Dependency-Free

lual aims to be a good fit for demanding deployments where performance, file size, and dependencies matter. The core library is small and has good performance characteristics.

The base install has no dependencies. If you use these specific components, then you must have their dependencies installed:

- JSON presenter requires dkjson
- Syslog output requires luasocket
- UV async backend requires luv. 

See [if lual is not a good fit for your deployment for more](#who-lual-is-not-for)

## Installation

Install via LuaRocks:

```bash
luarocks install lual
```

## Documentation

- **[Quick Start Guide](docs/getting-started/quick-start.md)** - Get up and running in 5 minutes
- **[User Guide](docs/guide/)** - Configuration, hierarchy, and common patterns
- **[API Reference](docs/reference/)** - Complete API documentation

## Who lual is not for

lual is probably not for you if you need: 

1.  **Large set of outputs for Enterprise Enviroment**

    For simpler applications or those with basic logging needs, lual's built-in output writers (like console and file) are generally sufficient. However, larger or more complex applications often require logging to diverse systems, each with unique protocols, formats, and performance considerations.

    In many scenarios, logging to files or syslog provides a good baseline, as these can often be integrated with other systems via adapters. But, if you require direct integration with specialized output targets and cannot use file/syslog adapters, you would need to implement custom output writers.

2. High Throughput

    while lual has no external dependencies, its not a micro lib with 200 lines
    of code. While programmed with  care, it will have some overhead as
    opposed to a one function micro lib.



## Contributing

Contributions welcome! See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

MIT License - see LICENSE file for details.

Made with ❤️ for the Lua community
