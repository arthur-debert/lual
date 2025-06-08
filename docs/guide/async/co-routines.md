# Coroutine Backend

The coroutine backend provides cooperative async I/O using Lua's built-in coroutine system. Default backend for lual async operations.

## Implementation

- **Worker coroutine** - Processes queued log events in batches
- **Cooperative yielding** - Returns control to application between batches  
- **Health monitoring** - Auto-restart with backoff on worker failures
- **Time-based flushing** - Sub-second intervals via `socket.gettime()` fallback

## Performance Profile

| Metric | Characteristic |
|--------|----------------|
| **Submission latency** | ~1μs (queue enqueue + coroutine resume) |
| **Processing throughput** | 10K-50K msgs/sec (depends on output complexity) |
| **Memory overhead** | ~100 bytes per queued message |
| **Queue operations** | O(1) via circular buffer |

Bottleneck: I/O operations in output functions, not coroutine overhead.

## Trade-offs

### ✅ Benefits

- **Zero dependencies** - Uses built-in coroutine system
- **Low memory** - Minimal overhead vs synchronous logging  
- **Predictable** - Deterministic scheduling, no thread races
- **Simple debugging** - Single-threaded execution model
- **Sub-second timing** - 100ms flush intervals achievable

### ❌ Limitations

- **Still blocking I/O** - File/network operations block entire process
- **Cooperative only** - Relies on application yielding control
- **Single core** - Cannot utilize multiple CPU cores
- **No isolation** - Worker crashes affect entire process
- **Limited concurrency** - One worker per logger configuration

## Risk Assessment

### Low Risk Scenarios
- **Application-controlled timing** - App calls flush regularly
- **Fast outputs** - Console, memory, local files
- **Moderate throughput** - <10K messages/second
- **Development/testing** - Non-critical environments

### High Risk Scenarios  
- **Slow I/O destinations** - Network logging, slow disks
- **High message rates** - >50K messages/second sustained
- **Real-time applications** - Cannot tolerate I/O blocking
- **Long-running workers** - Processes that rarely yield control

## Configuration Tuning

```lua
-- High throughput, low latency
lual.config({
    async = {
        enabled = true,
        backend = lual.async.coroutines,
        batch_size = 100,        -- Larger batches
        flush_interval = 0.05,   -- 50ms intervals
        max_queue_size = 50000,  -- More memory for bursts
        overflow_strategy = lual.async.drop_oldest
    }
})

-- Memory constrained
lual.config({
    async = {
        enabled = true,
        backend = lual.async.coroutines,
        batch_size = 10,         -- Smaller batches
        flush_interval = 1.0,    -- Less frequent processing
        max_queue_size = 1000,   -- Limit memory usage
        overflow_strategy = lual.async.drop_oldest
    }
})

-- Reliability focused
lual.config({
    async = {
        enabled = true,
        backend = lual.async.coroutines,
        batch_size = 1,          -- Process immediately
        flush_interval = 0.1,    -- Frequent flushes
        overflow_strategy = lual.async.block -- Never drop messages
    }
})
```

## Failure Modes

| Failure | Behavior | Recovery |
|---------|----------|----------|
| Worker crash | Auto-restart with backoff | Max 5 restarts, then sync fallback |
| Queue overflow | Drop or block based on strategy | Monitor `queue_overflows` stat |
| Output errors | Log error, continue processing | Increment `backend_errors` counter |
| Flush timeout | Partial processing, log warning | Resume on next flush attempt |

## When to Use

**Good fit:**
- Development and testing environments
- Applications with natural yield points
- Moderate logging loads (<10K msgs/sec)
- Simple deployment requirements

**Consider alternatives:**
- High-throughput production systems
- Real-time applications  
- Systems with slow I/O backends
- Multi-core utilization requirements

## Monitoring

Key metrics from `get_stats()`:

```lua
local stats = lual.async.get_stats()
-- stats.backend_stats.worker_restarts  -- Worker health
-- stats.queue_overflows                -- Memory pressure  
-- stats.backend_stats.backend_errors   -- I/O failures
-- stats.messages_submitted vs messages_processed -- Throughput
```

Set alerts on:
- `worker_restarts > 0` - Indicates worker instability
- `queue_overflows > 0` - Memory or throughput issues
- `backend_errors` trending up - Output problems

## Alternatives

For production systems requiring higher performance:
- **libuv backend** (planned) - True async I/O
- **lanes backend** (planned) - Multi-threading  
- **Synchronous logging** - If async complexity isn't justified
