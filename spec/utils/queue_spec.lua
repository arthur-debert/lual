package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua;../lua/?.lua;../lua/?/init.lua"

local queue_module = require("lual.utils.queue")

describe("Queue Module", function()
    local queue
    local error_messages

    before_each(function()
        error_messages = {}
        local error_callback = function(msg)
            table.insert(error_messages, msg)
        end

        queue = queue_module.new({
            max_size = 5,
            overflow_strategy = "drop_oldest",
            error_callback = error_callback
        })
    end)

    describe("Basic Operations", function()
        it("should create an empty queue", function()
            assert.is_true(queue:is_empty())
            assert.equals(0, queue:size())
        end)

        it("should enqueue and dequeue items", function()
            assert.is_true(queue:enqueue("item1"))
            assert.is_true(queue:enqueue("item2"))

            assert.is_false(queue:is_empty())
            assert.equals(2, queue:size())

            assert.equals("item1", queue:dequeue())
            assert.equals("item2", queue:dequeue())
            assert.is_true(queue:is_empty())
        end)

        it("should peek at front item without removing it", function()
            queue:enqueue("first")
            queue:enqueue("second")

            assert.equals("first", queue:peek())
            assert.equals(2, queue:size())          -- Size shouldn't change
            assert.equals("first", queue:dequeue()) -- Still first item
        end)

        it("should handle dequeue on empty queue", function()
            assert.is_nil(queue:dequeue())
            assert.is_nil(queue:peek())
        end)

        it("should reset indices when queue becomes empty", function()
            -- Fill and empty the queue
            queue:enqueue("item1")
            queue:enqueue("item2")
            queue:dequeue()
            queue:dequeue()

            -- Add new items - should work with reset indices
            queue:enqueue("item3")
            assert.equals("item3", queue:dequeue())
        end)
    end)

    describe("Batch Operations", function()
        it("should extract batches efficiently", function()
            queue:enqueue("item1")
            queue:enqueue("item2")
            queue:enqueue("item3")

            local batch = queue:extract_batch(2)
            assert.equals(2, #batch)
            assert.equals("item1", batch[1])
            assert.equals("item2", batch[2])
            assert.equals(1, queue:size()) -- One item left
        end)

        it("should extract all items when batch size is larger than queue", function()
            queue:enqueue("item1")
            queue:enqueue("item2")

            local batch = queue:extract_batch(10)
            assert.equals(2, #batch)
            assert.is_true(queue:is_empty())
        end)

        it("should return empty batch when queue is empty", function()
            local batch = queue:extract_batch(5)
            assert.equals(0, #batch)
        end)
    end)

    describe("Overflow Strategies", function()
        it("should handle drop_oldest strategy", function()
            -- Fill queue to capacity
            for i = 1, 5 do
                assert.is_true(queue:enqueue("item" .. i))
            end

            -- This should trigger overflow and drop oldest
            assert.is_true(queue:enqueue("item6"))

            assert.equals(5, queue:size())
            assert.equals(1, queue:overflow_count())
            assert.equals(1, #error_messages)
            assert.matches("dropped oldest", error_messages[1])

            -- Verify oldest was dropped
            assert.equals("item2", queue:dequeue()) -- item1 was dropped
        end)

        it("should handle drop_newest strategy", function()
            local drop_newest_queue = queue_module.new({
                max_size = 3,
                overflow_strategy = "drop_newest",
                error_callback = function(msg)
                    table.insert(error_messages, msg)
                end
            })

            -- Fill queue
            drop_newest_queue:enqueue("item1")
            drop_newest_queue:enqueue("item2")
            drop_newest_queue:enqueue("item3")

            -- This should be dropped
            assert.is_false(drop_newest_queue:enqueue("item4"))

            assert.equals(3, drop_newest_queue:size())
            assert.equals(1, drop_newest_queue:overflow_count())
            assert.equals(1, #error_messages)
            assert.matches("dropped newest", error_messages[1])

            -- Verify newest was dropped
            assert.equals("item1", drop_newest_queue:dequeue())
            assert.equals("item2", drop_newest_queue:dequeue())
            assert.equals("item3", drop_newest_queue:dequeue())
        end)

        it("should handle block strategy (not implemented)", function()
            local block_queue = queue_module.new({
                max_size = 2,
                overflow_strategy = "block",
                error_callback = function(msg)
                    table.insert(error_messages, msg)
                end
            })

            block_queue:enqueue("item1")
            block_queue:enqueue("item2")

            -- Should not add item due to blocking
            assert.is_false(block_queue:enqueue("item3"))
            assert.equals(2, block_queue:size())
            assert.matches("blocking not implemented", error_messages[1])
        end)
    end)

    describe("Statistics", function()
        it("should provide accurate statistics", function()
            queue:enqueue("item1")
            queue:enqueue("item2")

            local stats = queue:stats()
            assert.equals(2, stats.size)
            assert.equals(5, stats.max_size)
            assert.equals("drop_oldest", stats.overflow_strategy)
            assert.equals(0, stats.overflows)
            assert.is_false(stats.is_empty)
        end)

        it("should track overflow count correctly", function()
            -- Fill queue to capacity
            for i = 1, 5 do
                queue:enqueue("item" .. i)
            end

            -- Trigger multiple overflows
            queue:enqueue("overflow1")
            queue:enqueue("overflow2")

            assert.equals(2, queue:overflow_count())
            assert.equals(2, #error_messages)
        end)
    end)

    describe("Clearing and Resetting", function()
        it("should clear all items", function()
            queue:enqueue("item1")
            queue:enqueue("item2")

            queue:clear()

            assert.is_true(queue:is_empty())
            assert.equals(0, queue:size())
        end)

        it("should reset including overflow count", function()
            -- Fill and overflow
            for i = 1, 7 do
                queue:enqueue("item" .. i)
            end

            assert.equals(2, queue:overflow_count())

            queue:reset()

            assert.is_true(queue:is_empty())
            assert.equals(0, queue:overflow_count())
        end)
    end)

    describe("Configuration", function()
        it("should use default configuration when not provided", function()
            local default_queue = queue_module.new()
            local stats = default_queue:stats()

            assert.equals(10000, stats.max_size)
            assert.equals("drop_oldest", stats.overflow_strategy)
        end)

        it("should work without error callback", function()
            local no_callback_queue = queue_module.new({
                max_size = 2,
                overflow_strategy = "drop_oldest"
            })

            no_callback_queue:enqueue("item1")
            no_callback_queue:enqueue("item2")

            -- Should not error even without callback
            assert.has_no.errors(function()
                no_callback_queue:enqueue("item3")
            end)
        end)
    end)

    describe("Performance Characteristics", function()
        it("should handle large numbers of items efficiently", function()
            local large_queue = queue_module.new({
                max_size = 10000
            })

            -- Add many items
            for i = 1, 1000 do
                large_queue:enqueue("item" .. i)
            end

            assert.equals(1000, large_queue:size())

            -- Extract large batch
            local batch = large_queue:extract_batch(500)
            assert.equals(500, #batch)
            assert.equals(500, large_queue:size())

            -- Verify items are in correct order
            assert.equals("item1", batch[1])
            assert.equals("item500", batch[500])
        end)

        it("should maintain FIFO order", function()
            local large_queue = queue_module.new({
                max_size = 1000 -- Large enough to hold all items
            })

            -- Add items 1-20, dequeuing every 5th item
            for i = 1, 20 do
                large_queue:enqueue("item" .. i)

                -- Dequeue some items to test circular buffer behavior
                if i % 5 == 0 then
                    large_queue:dequeue()
                end
            end

            -- We added 20 items and removed 4 (at i=5,10,15,20), so 16 items remain
            -- The removed items were: item1, item2, item3, item4
            -- So the first remaining item should be item5
            assert.equals(16, large_queue:size())
            local first_remaining = large_queue:dequeue()
            assert.equals("item5", first_remaining)
        end)
    end)
end)
