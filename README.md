# lual.log

[![License](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)

A Lua library for hierarchical configuration management that elegantly merges
configurations from multiple sources with defined precedence.

Your application has its defaults, as it should. It also allows users to
configurable their preferences, while of course, environment variables should
work too, and lest we forget: command line options.

Even simple apps have a legitimate need for configuration at various points.
lual.log is a library that allows which points to accept, formats to read and
what you master config looks like. Melt will merge these in predictable sensible
precedence order while giving your user plenty of touch points and formats too
choose.

## Get it over with

`lual.log` provides a simple, powerful API to:

1. Merge configuration from multiple sources into a unified view
2. Apply clear precedence rules from less specific to more specific:
   - Application defaults (lowest precedence)
   - User preferences
   - Directory/project-specific settings
   - Environment variables
   - Command-line options (highest precedence)
3. Access configuration values with intuitive dot notation
4. Auto-convert environment variables to appropriate types (string, number,
   boolean)
5. TOML, JSON, YAML, INI, CONFIG file formats supported out of the box

## Installation

Install via LuaRocks:

```bash
luarocks install lual.log
```

For development:

```bash
# Clone the repository
git clone https://github.com/arthur-debert/lual.log.git
cd lual.log

# Install dependencies locally
luarocks --tree ./.luarocks install --only-deps lual.log-0.1.0-1.rockspec

# Set up environment (or use direnv)
source .envrc
```

## Usage

### Basic Example

```lua
local Melt = require("lual.log")

-- Create a new configuration
local config = Melt.new()

-- Add configuration from different sources with increasing precedence
config:add_table({
    app_name = "MyApp",  -- Application defaults (lowest precedence)
    timeout = 5000
  })
  :add_file(os.getenv("HOME").."/.config/myapp/config.toml")  -- User preferences
   -- (TOML format)
  :add_file(".myapp.json")  -- Directory specific settings (JSON)
  :add_env("MYAPP_")  -- Environment variables
  :add_cmdline_options(my_cli_args) -- CLI options (highest precedence)
                                   -- (my_cli_args from CLI parser)

-- Access configuration values with a unified view
local app_name = config:get("app_name")  -- From defaults unless overridden
local db_host = config:get("database.host")  -- From any source based on precedence
local log_level = config:get("log_level")  -- From highest precedence source

-- Get the entire configuration as a table
local all_config = config:get_table()
```

### Alternative API

```lua
local Melt = require("lual.log")

-- Define sources with explicit precedence (first has lowest precedence)
local sources = {
  { type = "table", source = { timeout = 5000 } },  -- Application defaults
  { type = "file", path = os.getenv("HOME").."/.config/myapp/config.toml" },
    -- User config (TOML format)
  { type = "file", path = ".myapp.yaml" },  -- Project-specific config (YAML format)
  { type = "env", prefix = "MYAPP_" },  -- Environment variables
  { type = "cmdline", source = my_cli_args } -- CLI options (highest precedence)
                                            -- (my_cli_args from CLI parser)
}

-- Create configuration object with merged values
local config = Melt.merge(sources)

-- Access configuration values
local timeout = config:get("timeout")  -- From highest precedence source
```

## Key Features

- **Predictable Configuration Layering**: From default settings to environment
  overrides
- **Multiple Format Support**: Lua tables, TOML, JSON, YAML, INI, CONFIG files,
  environment variables, and command-line arguments.
- **Extensible Design**: Add more format readers as needed
- **Hierarchical Access**: Use dot notation (e.g., `database.host`) to access
  nested values
- **Type Conversion**: Environment variables and command-line arguments are
  automatically converted to appropriate types.
- **Clear Precedence Rules**: More specific sources override less specific ones
  (command-line options take ultimate precedence).
- **Array Access**: Access array elements with bracket notation (e.g.,
  `protocols[1]`)

## API Reference

### Creating a Configuration

- `Melt.new()`: Creates a new empty configuration object
- `Melt.merge(sources_list)`: Creates a configuration from a list of sources

### Adding Sources

- `:add_table(table)`: Add configuration from a Lua table
- `:add_file(path, [type_hint])`: Add configuration from a file (supports TOML,
  JSON, YAML, INI, CONFIG formats automatically detected by file extension, or
  optionally specified via type_hint)
- `:add_env(prefix)`: Add configuration from environment variables with prefix
- `:add_cmdline_options(table)`: Add configuration from a pre-parsed table of
  command-line options. Keys with hyphens (e.g., `db-host`) are converted to
  nested structures (`db.host`), and values are type-converted.

### Accessing Values

- `:get(key)`: Get a value by key (with dot notation for nested keys)
- `:get_table()`: Get the entire configuration as a table

## Contributing

Contributions are welcome! From bug reports to PRs, the more the merrier.

### Development Setup

The project uses:

- Lua 5.1+
- Busted for testing
- LuaRocks for dependency management
- Direnv for environment management

See `docs/development.txxt` for detailed development instructions.

## License

This project is licensed under the MIT License - see the LICENSE file for
details.

--

Made with ❤️ for the Lua community
