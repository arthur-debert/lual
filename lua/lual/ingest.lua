local ingest = {}

-- Compatibility for Lua 5.2+ which moved unpack to table.unpack
local unpack = unpack or table.unpack -- Ensure unpack is available

--- Safely calls the formatter function.
-- @param formatter_func The formatter function.
-- @param base_record_for_formatter The record for the formatter.
-- @return string The formatted message or a fallback error message.
local function call_formatter(formatter_func, base_record_for_formatter)
    local ok, result = pcall(formatter_func, base_record_for_formatter)
    if not ok then
        io.stderr:write(string.format(
            "Logging system error: Formatter for logger '%s' failed: %s\n",
            tostring(base_record_for_formatter.logger_name), tostring(result) -- Added tostring for safety
        ))
        -- Create a detailed fallback message
        local raw_msg_fallback
        xpcall(
            function()
                raw_msg_fallback = string.format(base_record_for_formatter.message_fmt,
                    unpack(base_record_for_formatter.args or {}))
            end,
            function(err)
                raw_msg_fallback = base_record_for_formatter.message_fmt ..
                    " (formatting args failed: " .. tostring(err) .. ")"
            end)

        return string.format(
            "%s %s [%s] %s:%s - %s (FORMATTER ERROR: %s)",                                   -- Changed %d to %s for lineno
            os.date("!%Y-%m-%d %H:%M:%S", base_record_for_formatter.timestamp or os.time()), -- UTC timestamp, fallback for timestamp
            base_record_for_formatter.level_name or "UNKNOWN_LVL",
            base_record_for_formatter.logger_name or "UNKNOWN_LGR",
            base_record_for_formatter.filename or "unknown_file",
            tostring(base_record_for_formatter.lineno or 0), -- tostring for lineno
            raw_msg_fallback,
            tostring(result)
        )
    end
    return result
end

--- Safely calls the dispatcher function.
-- @param dispatcher_func The dispatcher function.
-- @param record_for_dispatcher The record for the dispatcher.
-- @param dispatcher_config Configuration specific to this dispatcher instance.
local function call_dispatcher(dispatcher_func, record_for_dispatcher, dispatcher_config)
    local ok, err = pcall(dispatcher_func, record_for_dispatcher, dispatcher_config)
    if not ok then
        io.stderr:write(string.format(
            "Logging system error: dispatcher for logger '%s' failed: %s\n",
            tostring(record_for_dispatcher.logger_name), tostring(err) -- Added tostring for safety
        ))
    end
end

--- Main dispatch function that processes a log event.
-- It retrieves all effective dispatchers from the source logger and processes them.
-- @param log_record (table) The log event details. Expected fields:
--        source_logger_name (string), level_no (number), level_name (string),
--        message_fmt (string), args (table, packed), context (table, optional),
--        timestamp (number), filename (string), lineno (number or string).
-- @param logger_func (function) Function to retrieve a logger instance by name.
-- @param _log_levels (table) Table mapping level names to numbers (e.g., log_levels.INFO). Not directly used here but good for context if needed.
function ingest.dispatch_log_event(log_record, logger_func, _log_levels) -- Renamed log_levels to _log_levels
    if not log_record or not log_record.source_logger_name then
        io.stderr:write(
            "Logging system error: dispatch_log_event called with invalid log_record or missing source_logger_name.\n")
        if log_record and log_record.message_fmt then -- Add more context if possible
            io.stderr:write("Log record contents: message_fmt=" .. tostring(log_record.message_fmt) .. "\n")
        end
        return
    end

    local source_logger = logger_func(log_record.source_logger_name)

    if not source_logger then
        io.stderr:write(string.format(
            "Logging system error: Source logger '%s' not found for message: %s\n",
            tostring(log_record.source_logger_name),
            tostring(log_record.message_fmt)
        ))
        return
    end

    -- The source_logger:get_effective_dispatchers() method is responsible for collecting
    -- all relevant dispatchers according to propagation rules and individual logger levels.
    -- It should return a list of dispatcher entries, where each entry includes
    -- the dispatcher_func, formatter_func, dispatcher_config, owner_logger_name, and owner_logger_level.
    local effective_dispatchers = source_logger:get_effective_dispatchers()

    for _, dispatcher_entry in ipairs(effective_dispatchers) do
        --[[ Expected dispatcher_entry structure from get_effective_dispatchers:
        {
          dispatcher_func = h.dispatcher_func,
          formatter_func = h.formatter_func,
          dispatcher_config = h.dispatcher_config,
          owner_logger_name = logger_that_owns_this_dispatcher.name,
          owner_logger_level = logger_that_owns_this_dispatcher.level
        }
        --]]

        -- Process only if the log record's level is sufficient for THIS dispatcher's owning logger's level.
        if log_record.level_no >= dispatcher_entry.owner_logger_level then
            -- Construct base record for the formatter, specific to this dispatcher's owning logger context
            local base_record_for_formatter = {
                level_name         = log_record.level_name,
                level_no           = log_record.level_no,
                logger_name        = dispatcher_entry.owner_logger_name, -- Use the dispatcher's owner logger name
                message_fmt        = log_record.message_fmt,
                args               = log_record.args,                    -- args are already packed by logger:log
                context            = log_record.context,                 -- Pass context to formatter
                timestamp          = log_record.timestamp,
                filename           = log_record.filename,
                lineno             = log_record.lineno,
                source_logger_name = log_record.source_logger_name -- Original emitter
            }
            local formatted_message = call_formatter(dispatcher_entry.formatter_func, base_record_for_formatter)

            -- Construct record for the dispatcher itself
            local record_for_dispatcher = {
                level_name         = log_record.level_name,
                level_no           = log_record.level_no,
                logger_name        = dispatcher_entry.owner_logger_name, -- Use the dispatcher's owner logger name
                message            = formatted_message,                  -- The fully formatted message string
                timestamp          = log_record.timestamp,
                filename           = log_record.filename,
                lineno             = log_record.lineno,
                raw_message_fmt    = log_record.message_fmt,       -- Original format string
                raw_args           = log_record.args,              -- Original variadic arguments
                context            = log_record.context,           -- Pass context to dispatcher
                source_logger_name = log_record.source_logger_name -- Original emitter
            }
            call_dispatcher(dispatcher_entry.dispatcher_func, record_for_dispatcher, dispatcher_entry.dispatcher_config)
        end
    end
end

return ingest
