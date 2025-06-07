package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua;../lua/?.lua;../lua/?/init.lua"

-- Test suite for libuv backend - optimized for performance
describe("libuv Backend", function()
    local libuv_backend
    local queue_module
    local queue, stats
    local uv_available = false

    -- Check if luv is available
    local ok, uv = pcall(require, "luv")
    if ok then
        uv_available = true
        libuv_backend = require("lual.async.backends.libuv")
        queue_module = require("lual.utils.queue")
    end

    -- Skip all tests if luv is not available
    if not uv_available then
        pending("luv library not available - skipping libuv backend tests")
        return
    end

    before_each(function()
        -- Setup backend instance
        queue = queue_module.new({ max_size = 100 })
        stats = {
            messages_processed = 0,
            backend_errors = 0,
            messages_dropped = 0
        }
    end)

    -- Helper function to wait for async operations with timeout
    local function wait_for_condition(condition_func, timeout_ms, check_interval_ms)
        timeout_ms = timeout_ms or 1000
        check_interval_ms = check_interval_ms or 10
        local start_time = uv.hrtime()

        while (uv.hrtime() - start_time) < (timeout_ms * 1e6) do
            if condition_func() then
                return true
            end
            uv.sleep(check_interval_ms)
        end
        return false
    end

    describe("Backend Creation", function()
        it("should create a new libuv backend instance", function()
            local backend = libuv_backend.new({
                batch_size = 5,
                flush_interval = 0.1,
                queue = queue,
                stats = stats,
                error_callback = function(msg) end
            })

            assert.is_not_nil(backend)
            assert.equals(5, backend.batch_size)
            assert.equals(0.1, backend.flush_interval)
            assert.equals("not_started", backend.worker_status)
            assert.is_false(backend.is_running)
        end)

        it("should use default configuration values", function()
            local backend = libuv_backend.new({
                queue = queue,
                stats = stats
            })

            assert.equals(50, backend.batch_size)
            assert.equals(1.0, backend.flush_interval)
            assert.equals(5, backend.max_restarts)
        end)
    end)

    describe("Backend Lifecycle", function()
        local backend

        before_each(function()
            backend = libuv_backend.new({
                batch_size = 3,
                flush_interval = 0.05, -- Shorter interval for faster tests
                queue = queue,
                stats = stats,
                error_callback = function(msg) end
            })
        end)

        after_each(function()
            if backend then
                backend:stop()
            end
        end)

        it("should start the backend successfully", function()
            local dispatch_func = function(logger, record) end

            backend:start(dispatch_func)

            assert.equals("running", backend.worker_status)
            assert.is_true(backend.is_running)
            assert.is_not_nil(backend.timer_handle)
            assert.is_not_nil(backend.idle_handle)
        end)

        it("should stop the backend cleanly", function()
            local dispatch_func = function(logger, record) end

            backend:start(dispatch_func)
            assert.is_true(backend.is_running)

            backend:stop()

            assert.equals("not_started", backend.worker_status)
            assert.is_false(backend.is_running)
            assert.is_nil(backend.timer_handle)
            assert.is_nil(backend.idle_handle)
        end)
    end)

    describe("Work Submission and Processing", function()
        local backend
        local processed_items

        before_each(function()
            processed_items = {}

            backend = libuv_backend.new({
                batch_size = 3,
                flush_interval = 0.05, -- Shorter interval for faster tests
                queue = queue,
                stats = stats,
                error_callback = function(msg) end
            })

            local dispatch_func = function(logger, record)
                table.insert(processed_items, {
                    logger = logger,
                    record = record
                })
            end

            backend:start(dispatch_func)
        end)

        after_each(function()
            backend:stop()
        end)

        -- note : this test is very slow, taking 1 second to run
        -- which is about 100 slower then the median. for now, let's leave it like tht
        it("should submit work items successfully", function()
            local work_item = {
                logger = "test_logger",
                record = { message = "test message" },
                dispatch_func = function() end,
                submitted_at = os.time()
            }

            local success = backend:submit(work_item)

            assert.is_true(success)
            assert.equals(1, queue:size())
        end)

        it("should handle batch processing", function()
            -- Submit items up to batch size
            for i = 1, 3 do
                local work_item = {
                    logger = "test_logger_" .. i,
                    record = { message = "test message " .. i },
                    dispatch_func = function(logger, record)
                        table.insert(processed_items, { logger = logger, record = record })
                    end,
                    submitted_at = os.time()
                }
                backend:submit(work_item)
            end

            -- Process the queue manually
            backend.flush_requested = true
            backend:process_queue()

            assert.equals(3, #processed_items)
            assert.equals("test_logger_1", processed_items[1].logger)
            assert.equals("test message 1", processed_items[1].record.message)
        end)

        it("should flush all pending work", function()
            -- Temporarily increase batch size to prevent auto-processing
            backend.batch_size = 10

            -- Add some work items
            for i = 1, 5 do
                local work_item = {
                    logger = "test_logger_" .. i,
                    record = { message = "test message " .. i },
                    dispatch_func = function(logger, record)
                        table.insert(processed_items, { logger = logger, record = record })
                    end,
                    submitted_at = os.time()
                }
                backend:submit(work_item)
            end

            assert.equals(5, queue:size())
            assert.equals(0, #processed_items)

            -- Flush should process all items with reasonable timeout
            local success = backend:flush(1.0)

            assert.is_true(success)
            assert.equals(0, queue:size())
            assert.equals(5, #processed_items)
        end)
    end)

    describe("Error Handling", function()
        local backend
        local error_messages

        before_each(function()
            error_messages = {}

            backend = libuv_backend.new({
                batch_size = 2,
                flush_interval = 0.05, -- Shorter interval for faster tests
                queue = queue,
                stats = stats,
                error_callback = function(msg)
                    table.insert(error_messages, msg)
                end
            })
        end)

        after_each(function()
            backend:stop()
        end)

        it("should handle dispatch function errors gracefully", function()
            local dispatch_func = function(logger, record)
                error("Simulated dispatch error")
            end

            backend:start(dispatch_func)

            local work_item = {
                logger = "test_logger",
                record = { message = "test message" },
                dispatch_func = dispatch_func,
                submitted_at = os.time()
            }

            backend:submit(work_item)

            -- Force processing
            backend.flush_requested = true
            backend:process_queue()

            -- Should have recorded the error
            assert.equals(1, stats.backend_errors)
            assert.is_true(#error_messages > 0)
        end)

        it("should fall back to synchronous processing when unhealthy", function()
            -- Don't start the backend, making it unhealthy
            local work_item = {
                logger = "test_logger",
                record = { message = "test message" },
                dispatch_func = function(logger, record) end,
                submitted_at = os.time()
            }

            local success = backend:submit(work_item)

            -- Should fall back to sync processing
            assert.is_false(success)
            assert.is_true(#error_messages > 0)
        end)
    end)

    describe("Statistics and Health", function()
        local backend

        before_each(function()
            backend = libuv_backend.new({
                batch_size = 5,
                flush_interval = 0.05, -- Shorter interval for faster tests
                queue = queue,
                stats = stats,
                error_callback = function(msg) end
            })
        end)

        after_each(function()
            backend:stop()
        end)

        it("should provide comprehensive statistics", function()
            backend:start(function() end)

            local backend_stats = backend:get_stats()

            assert.equals("running", backend_stats.worker_status)
            assert.equals(0, backend_stats.worker_restarts)
            assert.equals(5, backend_stats.batch_size)
            assert.equals(0.05, backend_stats.flush_interval)
            assert.is_true(backend_stats.is_running)
            assert.is_string(backend_stats.libuv_version)
        end)

        it("should report healthy worker when running", function()
            backend:start(function() end)

            assert.is_true(backend:is_worker_healthy())
        end)

        it("should report unhealthy worker when not started", function()
            assert.is_false(backend:is_worker_healthy())
        end)

        it("should report unhealthy worker when shutdown requested", function()
            backend:start(function() end)
            backend.shutdown_requested = true

            assert.is_false(backend:is_worker_healthy())
        end)
    end)
end)
