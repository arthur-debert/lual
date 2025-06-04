--- Test helper functions for lual
-- This module provides utilities to create test loggers and spies

local test_helpers = {}

--- Creates a spy dispatcher that records calls
-- @return table Spy object with func and calls
function test_helpers.create_spy_dispatcher()
    local calls = {}

    local function spy_func(record, config)
        -- Implement level filtering like a real dispatcher
        if config and config.level and record.level_no < config.level then
            -- Skip if level is below the configured level
            return
        end

        -- Record the call
        table.insert(calls, {
            level_no = record.level_no,
            level_name = record.level_name,
            message = record.message,
            message_fmt = record.message_fmt,
            timestamp = record.timestamp,
            logger_name = record.logger_name
        })
    end

    return {
        func = spy_func,
        config = { timezone = "local" },
        calls = calls,
        count = function() return #calls end,
        clear = function() calls = {} end
    }
end

--- Creates a test logger with debug and warning level spies
-- @param lual table The lual module
-- @param name string Logger name
-- @return table Logger instance with spies
function test_helpers.create_test_logger(lual, name)
    -- Create spies for different log levels
    local debug_spy = test_helpers.create_spy_dispatcher()
    local warning_spy = test_helpers.create_spy_dispatcher()

    -- Set their levels in the config
    debug_spy.config.level = lual.debug
    warning_spy.config.level = lual.warning

    -- Create the logger with these spies
    local logger = lual.logger(name, {
        level = lual.debug,  -- Logger at debug level
        dispatchers = {
            debug_spy.func,  -- This spy gets everything
            warning_spy.func -- This spy only gets warning+
        }
    })

    -- Add spies to the logger for easy access in tests
    logger.spies = {
        debug = debug_spy,
        warning = warning_spy
    }

    return logger
end

return test_helpers
