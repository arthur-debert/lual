# Command Line Verbosity

Many command-line applications allow users to control verbosity using flags like `-v`, `-vv`, or `--verbose`. lual makes it easy to integrate this pattern into your applications with the command line verbosity feature.

## Basic Usage

The simplest way to enable command line verbosity is:

```lua
local lual = require("lual")

-- Enable command line verbosity with default settings
lual.config({
    command_line_verbosity = { auto_detect = true }
})
```

This will automatically detect command line flags and set the root logger's level accordingly.

## Default Mapping

By default, lual recognizes these common flags:

| Flag | Logging Level |
|------|--------------|
| `-v` or `--v` | WARNING |
| `-vv` or `--vv` | INFO |
| `-vvv` or `--vvv` | DEBUG |
| `--verbose` | INFO |
| `--quiet` | ERROR |
| `--silent` | CRITICAL |

For example:

```bash
# Run your app with different verbosity levels
$ lua app.lua                 # Default level (usually WARNING)
$ lua app.lua -v              # WARNING level 
$ lua app.lua -vv             # INFO level
$ lua app.lua -vvv            # DEBUG level
$ lua app.lua --verbose       # INFO level
$ lua app.lua --quiet         # ERROR level (shows only errors and critical messages)
```

## Custom Mapping

You can define your own mapping of command line flags to log levels:

```lua
lual.config({
    command_line_verbosity = {
        mapping = {
            trace = "debug",       -- Maps --trace flag to DEBUG level
            standard = "info",     -- Maps --standard flag to INFO level
            terse = "warning",     -- Maps --terse flag to WARNING level
            errors = "error",      -- Maps --errors flag to ERROR level
            critical = "critical"  -- Maps --critical flag to CRITICAL level
        },
        auto_detect = true
    }
})
```

Both short flags (e.g., `-trace`) and long flags (e.g., `--trace`) will be recognized.

## Convenience Function

For easier configuration, you can use the `set_command_line_verbosity` function:

```lua
-- Same as using the command_line_verbosity key in config
lual.set_command_line_verbosity({
    mapping = { ... },
    auto_detect = true
})
```

## Disabling Auto-Detection

If you want to configure verbosity mapping but not apply it automatically:

```lua
lual.config({
    command_line_verbosity = {
        mapping = { ... },
        auto_detect = false
    }
})

-- Later, when you're ready to apply:
local level = lual.get_config().command_line_verbosity.mapping["some_flag"]
if level then
    -- Set the level manually
    lual.config({ level = level })
end
```

## Integration with Other Configuration

Command line verbosity works well with other lual configuration options:

```lua
lual.config({
    -- Enable command line verbosity
    command_line_verbosity = { auto_detect = true },
    
    -- Configure pipelines (will respect the level set by CLI flags)
    pipelines = {
        {
            outputs = { lual.console },
            presenter = lual.color()
        },
        {
            outputs = { 
                { lual.file, path = "app.log" } 
            },
            presenter = lual.text()
        }
    }
})
```

## Complete Example

Here's a complete example showing how to use command line verbosity:

```lua
local lual = require("lual")

-- Configure with command line verbosity
lual.config({
    command_line_verbosity = { auto_detect = true },
    pipelines = {
        {
            -- Level will be set from command line
            outputs = { lual.console },
            presenter = lual.color()
        }
    }
})

-- Create logger
local logger = lual.logger("myapp")

-- Log at different levels
logger:debug("Detailed debug information")
logger:info("General information")
logger:warn("Warning message")
logger:error("Error condition")
logger:critical("Critical failure")
```

## Best Practices

1. **Default to WARNING level** - Let users increase verbosity with flags
2. **Use auto_detect for CLI applications** - Makes integration easy
3. **Consider custom mappings for domain-specific applications** - Use terminology familiar to your users
4. **Document supported flags** - Include in your application's help text
5. **Use with hierarchical loggers** - Command line verbosity sets the root logger level; child loggers inherit it

## How It Works

The command line verbosity feature:

1. Examines the global `arg` table provided by Lua
2. Looks for flags in your mapping
3. Sets the root logger level accordingly
4. Honors the last matching flag if multiple flags are provided

This makes it easy to integrate logging verbosity control into your command-line applications. 