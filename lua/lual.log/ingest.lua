-- (Assuming log.levels, logger object structure, get_logger_internal exist)

-- Compatibility for Lua 5.2+ which moved unpack to table.unpack
local unpack = unpack or table.unpack

--- Safely calls the formatter function.
-- @param formatter_func The formatter function.
-- @param base_record_for_formatter The record for the formatter.
-- @return string The formatted message or a fallback error message.
local function call_formatter(formatter_func, base_record_for_formatter)
    local ok, result = pcall(formatter_func, base_record_for_formatter)
    if not ok then
        io.stderr:write(string.format(
            "Logging system error: Formatter for logger '%s' failed: %s\n",
            base_record_for_formatter.logger_name, tostring(result)
        ))
        -- Create a detailed fallback message
        local raw_msg_fallback
        xpcall(function() raw_msg_fallback = string.format(base_record_for_formatter.message_fmt, unpack(base_record_for_formatter.args or {})) end,
               function() raw_msg_fallback = base_record_for_formatter.message_fmt .. " (formatting args failed)" end)

        return string.format(
            "%s %s [%s] %s:%d - %s (FORMATTER ERROR: %s)",
            os.date("%Y-%m-%d %H:%M:%S", base_record_for_formatter.timestamp),
            base_record_for_formatter.level_name,
            base_record_for_formatter.logger_name,
            base_record_for_formatter.filename or "unknown_file",
            base_record_for_formatter.lineno or 0,
            raw_msg_fallback,
            tostring(result)
        )
    end
    return result
end

--- Safely calls the handler function.
-- @param handler_func The handler function.
-- @param record_for_handler The record for the handler.
-- @param handler_config Configuration specific to this handler instance.
local function call_handler(handler_func, record_for_handler, handler_config)
    local ok, err = pcall(handler_func, record_for_handler, handler_config)
    if not ok then
        io.stderr:write(string.format(
            "Logging system error: Handler for logger '%s' failed: %s\n",
            record_for_handler.logger_name, tostring(err)
        ))
    end
end

--- Processes all handlers for a single logger.
-- @param current_logger The logger object whose handlers are to be processed.
-- @param event_details The original, immutable details of the log event.
local function process_handlers_for_logger(current_logger, event_details)
    local base_record_for_formatter = {
        level_name    = event_details.message_level_name,
        level_no      = event_details.message_level_no,
        logger_name   = current_logger.name,
        message_fmt   = event_details.message_fmt,
        args          = event_details.args,
        timestamp     = event_details.timestamp,
        filename      = event_details.filename,
        lineno        = event_details.lineno,
        source_logger_name = event_details.source_logger_name -- Include this for tests
    }

    for _, handler_entry in ipairs(current_logger.handlers or {}) do
        local formatted_message = call_formatter(handler_entry.formatter_func, base_record_for_formatter)

        local record_for_handler = {
            level_name       = event_details.message_level_name,
            level_no         = event_details.message_level_no,
            logger_name      = current_logger.name,
            message          = formatted_message,
            timestamp        = event_details.timestamp,
            filename         = event_details.filename,
            lineno           = event_details.lineno,
            raw_message_fmt  = event_details.message_fmt,
            raw_args         = event_details.args,
            source_logger_name = event_details.source_logger_name
        }
        call_handler(handler_entry.handler_func, record_for_handler, handler_entry.handler_config)
    end
end

--- Checks if a logger's level is appropriate for the message.
-- @param logger The logger object.
-- @param message_level_no The numeric level of the message.
-- @return boolean True if the logger should process, false otherwise.
local function should_logger_process(logger, message_level_no)
    return message_level_no >= logger.level
end

--- Main dispatch function that handles propagation.
-- This is the primary entry point into the internal processing logic after a log call.
-- @param event_details The original, immutable details of the log event.
function log.dispatch_log_event(event_details) -- Exposed via the log module for internal use
    local current_logger = log.get_logger_internal(event_details.source_logger_name) -- Or however root is found if source_logger_name is nil/root

    while current_logger do
        if should_logger_process(current_logger, event_details.message_level_no) then
            process_handlers_for_logger(current_logger, event_details)
        end

        if current_logger.propagate and current_logger.parent then
            current_logger = current_logger.parent
        else
            break -- Stop propagation
        end
    end
end

-- Example of how a logger method (e.g., logger:info) would initiate this:
-- function logger_prototype:info(message_fmt, ...)
--     -- Early exit if this specific logger won't even consider the message
--     if log.levels.INFO < self.level and not self.propagate then -- simplified check, actual check is complex due to propagation
--          -- A more accurate pre-check would be if NO logger in the chain would handle it.
--          -- For now, the main check is inside dispatch_log_event via should_logger_process
--     end
--
--     local timestamp = os.time()
--     local caller_info = debug.getinfo(AppropriateStackLevel, "Sl") -- e.g., 2 or 3
--
--     local event_details = {
--         message_level_no   = log.levels.INFO,
--         message_level_name = "INFO",
--         message_fmt        = message_fmt,
--         args               = {...},
--         timestamp          = timestamp,
--         filename           = caller_info.short_src, -- Or .source
--         lineno             = caller_info.currentline,
--         source_logger_name = self.name
--     }
--
--     log.dispatch_log_event(event_details)
-- end