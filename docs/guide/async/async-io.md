# Async I/O

lual provides pluggable async I/O through a generic interface with backend-specific implementations. This allows different async strategies while maintaining API compatibility.

## Architecture

```
lual.logger() -> async_writer.lua -> async/init.lua -> backends/[strategy].lua
```

- **async_writer.lua** - Backward compatibility wrapper
- **async/init.lua** - Generic coordination layer  
- **backends/*.lua** - Strategy-specific implementations

## Available Backends

| Backend | Path | Documentation | Status |
|---------|------|---------------|--------|
| Coroutines | `lual.async.backends.coroutines` | [co-routines.md](co-routines.md) | Stable |
| libuv | `lual.async.backends.libuv` | [libuv.md](libuv.md) | Stable |

Future backends: lanes, native threads.

## Configuration

```lua
lual.config({
    async = {
        enabled = true,
        backend = lual.async.libuv,           -- lual.async.coroutines, lual.async.libuv
        batch_size = 50,                      -- Messages per batch
        flush_interval = 1.0,                 -- Seconds
        max_queue_size = 10000,               -- Memory protection
        overflow_strategy = lual.async.drop_oldest, -- lual.async.drop_newest, lual.async.block
    },
    -- ... other config
})
```

### Minimal Configuration

```lua
lual.config({
    async = { enabled = true },  -- Use all defaults
    -- ... other config
})
```

### Default Configuration

```lua
-- Equivalent to lual.async.defaults
{
    enabled = false,
    backend = lual.async.coroutines,
    batch_size = 50,
    flush_interval = 1.0,
    max_queue_size = 10000,
    overflow_strategy = lual.async.drop_oldest
}
```

## Core Interface

The generic layer provides:
- Queue management with overflow protection
- Statistics aggregation 
- Error handling and reporting
- Backend lifecycle management
- Backward compatibility

## Backend Contract

Backend authors implement:

```lua
local M = {}

function M.new(config)
    -- config: { batch_size, flush_interval, queue, stats, error_callback }
    -- Returns backend instance
end

function M:submit(work_item)
    -- work_item: { logger, record, dispatch_func, submitted_at }
    -- Returns success boolean
end

function M:flush(timeout)
    -- Process all queued work within timeout seconds
    -- Returns success boolean
end

function M:start(dispatch_func)
    -- Initialize async processing
end

function M:stop()
    -- Clean shutdown, flush pending work
end

function M:get_stats()
    -- Return backend-specific statistics table
end

function M:reset()
    -- Reset for testing
end
```

### Key Requirements

1. **Non-blocking submission** - `submit()` must return quickly
2. **Timeout compliance** - `flush()` must respect timeout parameter
3. **Error isolation** - Backend errors must not crash the application
4. **Statistics** - Provide meaningful metrics via `get_stats()`
5. **Clean lifecycle** - Proper initialization and shutdown

### Queue Integration

Backends receive a shared queue instance with:
- `queue:enqueue(item)` - Add work item
- `queue:extract_batch(size)` - Get up to `size` items
- `queue:size()`, `queue:is_empty()` - Status checks
- `queue:stats()` - Usage statistics

## Testing Backends

Create comprehensive tests covering:

```lua
describe("Your Backend", function()
    local backend, queue, stats
    
    before_each(function()
        -- Setup backend instance
        queue = require("lual.utils.queue").new({max_size = 100})
        stats = {messages_processed = 0, backend_errors = 0}
        backend = your_backend.new({
            batch_size = 5,
            flush_interval = 0.1,
            queue = queue,
            stats = stats,
            error_callback = function(msg) end
        })
    end)
    
    -- Test scenarios:
    -- 1. Basic work submission and processing
    -- 2. Batch processing triggers
    -- 3. Flush timeout behavior
    -- 4. Error handling and recovery
    -- 5. Statistics reporting
    -- 6. Lifecycle management
    -- 7. Performance under load
end)
```

### Critical Test Cases

- **Submission overload** - Queue full scenarios
- **Dispatch errors** - Backend must handle output function failures
- **Flush timeout** - Must not hang indefinitely
- **Worker recovery** - Handle backend-specific failure modes
- **Memory bounds** - Respect queue size limits
- **Statistics accuracy** - Verify counters and timing

Run tests with: `busted spec/your_backend_spec.lua`

## Performance Considerations

- **Queue overhead** - O(1) operations via circular buffer
- **Batch efficiency** - Larger batches reduce per-message overhead
- **Memory usage** - Queue size limits prevent unbounded growth
- **Error costs** - Failed dispatches trigger recovery mechanisms

Monitor via `lual.async.get_stats()` for operational metrics.

## Complete Example

```lua
local lual = require("lual.logger")

-- Configure with new async API
lual.config({
    level = lual.debug,
    async = {
        enabled = true,
        backend = lual.async.libuv,
        batch_size = 25,
        flush_interval = 0.5,
        max_queue_size = 5000,
        overflow_strategy = lual.async.drop_oldest
    },
    pipelines = {
        { level = lual.warn, outputs = { lual.console }, presenter = lual.color },
        { level = lual.debug, outputs = { lual.file, path = "app.log" }, presenter = lual.json() }
    }
})

-- All outputs (console and file) are now async
local logger = lual.logger("myapp")
logger:info("This message is processed asynchronously")

-- Force immediate processing
lual.flush()

-- Monitor performance
local stats = lual.async.get_stats()
print("Messages submitted:", stats.messages_submitted)
print("Queue size:", stats.queue_size)
```

## Integration

Async I/O integrates with all lual features:
- Hierarchical loggers and propagation
- Multiple pipelines and filtering
- Custom levels and transformers
- Error handling and recovery

The async layer sits between logger dispatch and pipeline processing, transparent to application code.
