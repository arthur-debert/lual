--- Test helper functions for lual
-- This module provides utilities to create test loggers and spies

local test_helpers = {}

--- Creates a spy dispatcher that records log events
-- @return table A spy object with calls and helper methods
function test_helpers.create_spy_dispatcher()
    local spy = {
        calls = {},
        config = {}
    }

    -- The dispatcher function that records calls
    local dispatcher_func = function(log_record)
        table.insert(spy.calls, {
            level_no = log_record.level_no,
            level_name = log_record.level_name,
            message = log_record.message,
            logger_name = log_record.logger_name,
            timestamp = log_record.timestamp,
            formatted_message = log_record.formatted_message,
            presented_message = log_record.presented_message
        })
    end

    -- Set the function in both formats for compatibility
    spy.func = dispatcher_func
    spy.dispatcher_func = dispatcher_func

    -- Helper to get call count
    function spy:count()
        return #self.calls
    end

    -- Helper to clear calls
    function spy:clear()
        self.calls = {}
    end

    -- Helper to get messages only
    function spy:messages()
        local result = {}
        for i, call in ipairs(self.calls) do
            result[i] = call.message
        end
        return result
    end

    -- Helper to filter by level
    function spy:get_by_level(level_name)
        local result = {}
        for _, call in ipairs(self.calls) do
            if call.level_name == level_name then
                table.insert(result, call)
            end
        end
        return result
    end

    return spy
end

--- Creates a test logger with spies at different levels
-- @param lual The lual module
-- @param name string Logger name
-- @param options table Optional settings
-- @return table A logger with preconfigured spies
function test_helpers.create_test_logger(lual, name, options)
    options = options or {}

    -- Create spies for each level
    local debug_spy = test_helpers.create_spy_dispatcher()
    local info_spy = test_helpers.create_spy_dispatcher()
    local warning_spy = test_helpers.create_spy_dispatcher()
    local error_spy = test_helpers.create_spy_dispatcher()

    -- Configure level-specific filtering
    debug_spy.config = { level = lual.debug }
    info_spy.config = { level = lual.info }
    warning_spy.config = { level = lual.warning }
    error_spy.config = { level = lual.error }

    -- Create logger with all spies
    local logger_config = {
        level = options.level or lual.debug,
        dispatchers = {
            debug_spy,
            info_spy,
            warning_spy,
            error_spy
        },
        propagate = options.propagate
    }

    -- Create the logger
    local logger = lual.logger(name, logger_config)

    -- Attach spies to the logger for testing
    logger.spies = {
        debug = debug_spy,
        info = info_spy,
        warning = warning_spy,
        error = error_spy,

        -- Helper to get all calls
        all_calls = function()
            local all = {}
            for i, call in ipairs(debug_spy.calls) do all[#all + 1] = call end
            for i, call in ipairs(info_spy.calls) do all[#all + 1] = call end
            for i, call in ipairs(warning_spy.calls) do all[#all + 1] = call end
            for i, call in ipairs(error_spy.calls) do all[#all + 1] = call end
            return all
        end,

        -- Helper to clear all spies
        clear_all = function()
            debug_spy:clear()
            info_spy:clear()
            warning_spy:clear()
            error_spy:clear()
        end
    }

    return logger
end

return test_helpers
