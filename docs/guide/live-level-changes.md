# Live Log Level Changes

lual offers a powerful feature that allows you to change log levels at runtime through environment variables without restarting your application. This is particularly useful for debugging production systems or adjusting verbosity on long-running services.

## Basic Usage

The simplest way to enable live log level changes is:

```lua
local lual = require("lual")

-- Enable live log level changes
lual.set_live_level("APP_LOG_LEVEL")
```

With this configuration, you can change the log level by setting the `APP_LOG_LEVEL` environment variable:

```bash
# Set log level to DEBUG (most verbose)
export APP_LOG_LEVEL=debug

# Set log level to INFO
export APP_LOG_LEVEL=info

# Set log level to WARNING (default)
export APP_LOG_LEVEL=warning

# Set log level to ERROR
export APP_LOG_LEVEL=error

# Set log level to CRITICAL (least verbose)
export APP_LOG_LEVEL=critical

# Set to a custom numeric level
export APP_LOG_LEVEL=25
```

The log level will be updated on the fly as your application continues to run.

## How It Works

When you configure live log level changes:

1. lual periodically checks the specified environment variable (every N log entries)
2. If the variable has changed since the last check, lual parses the new value
3. If the value corresponds to a valid log level, lual updates the root logger's level

This allows you to dynamically adjust the verbosity of your application's logging without interrupting its execution.

## Configuration Options

### Check Interval

You can control how frequently lual checks for environment variable changes:

```lua
-- Check every 10 log entries (more responsive but slightly higher overhead)
lual.set_live_level("APP_LOG_LEVEL", 10)

-- Check every 500 log entries (less responsive but lower overhead)
lual.set_live_level("APP_LOG_LEVEL", 500)
```

The default interval is 100 log entries.

### Full Configuration

For more control, you can use the `lual.config()` function:

```lua
lual.config({
    live_level = {
        env_var = "APP_LOG_LEVEL",    -- Environment variable to monitor
        check_interval = 50,          -- Check every 50 log entries
        enabled = true                -- Enable the feature
    }
})
```

## Supported Level Values

The environment variable can be set to any of the following values:

| Value Type | Examples | Description |
|------------|----------|-------------|
| Level name (uppercase) | `DEBUG`, `INFO`, `WARNING`, `ERROR`, `CRITICAL` | Standard level names |
| Level name (lowercase) | `debug`, `info`, `warning`, `error`, `critical` | Case-insensitive variants |
| Custom level name | `verbose`, `trace` | Names of custom levels if defined |
| Numeric value | `10`, `20`, `30`, `40`, `50` | Standard level values |
| Custom numeric value | `15`, `25`, `35` | Any numeric value |

## Best Practices

1. **Choose a descriptive environment variable name** - Use a name that clearly indicates its purpose and scope, e.g., `MYAPP_LOG_LEVEL`

2. **Balance check interval** - A smaller interval is more responsive but adds overhead; a larger interval reduces overhead but has delayed response

3. **Use with hierarchical logging** - Remember that changing the root logger level affects all loggers that inherit their level from it

4. **Document for operations** - Make sure your operations team knows which environment variables control logging levels

5. **Handle with care in production** - Be cautious when increasing verbosity in production as it might impact performance

## Complete Example

Here's a complete example showing how to use live log level changes:

```lua
local lual = require("lual")

-- Configure with live log level changes and console output
lual.config({
    level = lual.warning,                 -- Default level
    pipelines = {
        {
            outputs = { lual.console },   -- Console output
            presenter = lual.color()      -- With color formatting
        }
    },
    live_level = {
        env_var = "APP_LOG_LEVEL",        -- Monitor this environment variable
        check_interval = 50               -- Check every 50 log entries
    }
})

-- Create logger
local logger = lual.logger("myapp")

-- In a loop or long-running process
while true do
    -- These will be shown or hidden depending on the current level
    logger:debug("Detailed debug information")
    logger:info("General information") 
    logger:warn("Warning message")
    logger:error("Error condition")
    
    -- Do some work...
    -- You can change APP_LOG_LEVEL in another terminal while this runs
    
    -- Sleep or process events
    os.execute("sleep 1")
end
```

## Disabling the Feature

You can disable live level changes without removing the configuration:

```lua
lual.config({
    live_level = {
        env_var = "APP_LOG_LEVEL",
        enabled = false                -- Explicitly disable
    }
})
``` 