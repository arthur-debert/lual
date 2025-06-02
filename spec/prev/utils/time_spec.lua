describe("lual.utils.time", function()
    local time_utils = require("lual.utils.time")

    describe("format_timestamp", function()
        local test_timestamp = 1609459200 -- 2021-01-01 00:00:00 UTC

        it("should format timestamp in UTC when timezone is 'utc'", function()
            local result = time_utils.format_timestamp(test_timestamp, "utc")
            assert.are.equal("2021-01-01 00:00:00", result)
        end)

        it("should format timestamp in UTC when timezone is 'UTC' (case insensitive)", function()
            local result = time_utils.format_timestamp(test_timestamp, "UTC")
            assert.are.equal("2021-01-01 00:00:00", result)
        end)

        it("should format timestamp in local time when timezone is 'local'", function()
            local result = time_utils.format_timestamp(test_timestamp, "local")
            -- We can't predict the exact local time, but it should be a valid timestamp format
            assert.matches("%d%d%d%d%-%d%d%-%d%d %d%d:%d%d:%d%d", result)
        end)

        it("should default to local time when timezone is nil", function()
            local result = time_utils.format_timestamp(test_timestamp, nil)
            -- Should be same as local time
            local local_result = time_utils.format_timestamp(test_timestamp, "local")
            assert.are.equal(local_result, result)
        end)

        it("should use custom format when provided", function()
            local result = time_utils.format_timestamp(test_timestamp, "utc", "%Y/%m/%d")
            assert.are.equal("2021/01/01", result)
        end)
    end)

    describe("format_iso_timestamp", function()
        local test_timestamp = 1609459200 -- 2021-01-01 00:00:00 UTC

        it("should format timestamp in ISO format with Z suffix for UTC", function()
            local result = time_utils.format_iso_timestamp(test_timestamp, "utc")
            assert.are.equal("2021-01-01T00:00:00Z", result)
        end)

        it("should format timestamp in ISO format with Z suffix for UTC (case insensitive)", function()
            local result = time_utils.format_iso_timestamp(test_timestamp, "UTC")
            assert.are.equal("2021-01-01T00:00:00Z", result)
        end)

        it("should format timestamp in ISO format without Z suffix for local time", function()
            local result = time_utils.format_iso_timestamp(test_timestamp, "local")
            -- Should match ISO format without Z
            assert.matches("%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%d", result)
            assert.is_not.matches("Z$", result) -- Should not end with Z
        end)

        it("should default to local time when timezone is nil", function()
            local result = time_utils.format_iso_timestamp(test_timestamp, nil)
            -- Should be same as local time
            local local_result = time_utils.format_iso_timestamp(test_timestamp, "local")
            assert.are.equal(local_result, result)
        end)
    end)
end)
