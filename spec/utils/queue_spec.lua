local queue = require("lual.utils.queue")

describe("Queue Module", function()
    local q

    before_each(function()
        q = queue.new()
    end)

    it("should initialize with default capacity", function()
        assert.are.equals(1024, q:capacity())
    end)

    it("should allow setting custom capacity", function()
        q = queue.new({ max_size = 5 })
        assert.are.equals(5, q:capacity())
    end)

    it("should push and pop items in FIFO order", function()
        -- Implementation needed
    end)

    it("should return correct size", function()
        assert.are.equals(0, q:size())
        q:push(1)
        assert.are.equals(1, q:size())
        q:push(2)
        assert.are.equals(2, q:size())
        q:pop()
        assert.are.equals(1, q:size())
    end)

    it("should report as full", function()
        q = queue.new({ max_size = 2 })
        q:push(1)
        q:push(2)
        assert.is_true(q:is_full())
    end)

    it("should report as not full", function()
        q = queue.new({ max_size = 2 })
        q:push(1)
        assert.is_false(q:is_full())
    end)

    it("should report as empty", function()
        assert.is_true(q:is_empty())
        q:push(1)
        assert.is_false(q:is_empty())
    end)

    it("should return nil when popping an empty queue", function()
        assert.is_nil(q:pop())
    end)

    it("should handle mixed types", function()
        -- Implementation needed
    end)

    it("should handle nil values", function()
        -- Implementation needed
    end)

    it("should handle queue of capacity 1", function()
        q = queue.new({ max_size = 1 })
        q:push(1)
        assert.is_true(q:is_full())
        assert.are.equals(1, q:pop())
        assert.is_true(q:is_empty())
        q:push(2)
        assert.are.equals(2, q:pop())
    end)

    it("should handle being full and then becoming not full", function()
        q = queue.new({ max_size = 2 })
        q:push(1)
        q:push(2)
        assert.is_true(q:is_full())
        q:pop()
        assert.is_false(q:is_full())
    end)

    describe("Overflow Behavior", function()
        it("should drop the oldest item on overflow when strategy is 'drop_oldest'", function()
            q = queue.new({ max_size = 2, overflow_strategy = "drop_oldest" })
            q:push(1)
            q:push(2)
            q:push(3)
            assert.are.equals(2, q:pop())
            assert.are.equals(3, q:pop())
        end)

        it("should drop the newest item on overflow when strategy is 'drop_newest'", function()
            q = queue.new({ max_size = 2, overflow_strategy = "drop_newest" })
            q:push(1)
            q:push(2)
            q:push(3) -- This should be dropped
            assert.are.equals(1, q:pop())
            assert.are.equals(2, q:pop())
            assert.is_nil(q:pop())
        end)

        it("should throw an error on overflow when strategy is 'error'", function()
            q = queue.new({ max_size = 2, overflow_strategy = "error" })
            q:push(1)
            q:push(2)
            assert.has_error(function() q:push(3) end, "Queue: Queue overflow")
        end)
    end)
end)
