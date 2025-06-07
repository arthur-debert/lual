-- Log Record Creation and Processing
-- This module handles the creation and processing of log records

-- Note: For direct execution with 'lua', use require("lua.lual.*")
-- For LuaRocks installed modules or busted tests, use require("lual.*")
local core_levels = require("lua.lual.levels")
local get_logger_tree = require("lual.log.get_logger_tree")
local get_pipelines = require("lual.log.get_pipelines")
local process = require("lual.log.process")

local M = {}

--- Creates a log record
-- @param logger table The source logger
-- @param level_no number The log level number
-- @param level_name string The log level name
-- @param message_fmt string The message format string
-- @param args table The formatting arguments
-- @param context table|nil Optional context table
-- @return table The log record
function M.create_log_record(logger, level_no, level_name, message_fmt, args, context)
    -- Format the message if args are provided
    local formatted_message = message_fmt
    if args and args.n and args.n > 0 then
        local format_args = {}
        for i = 1, args.n do
            format_args[i] = args[i]
        end
        local ok, result = pcall(string.format, message_fmt, table.unpack(format_args))
        if ok then
            formatted_message = result
        else
            formatted_message = message_fmt .. " [FORMAT ERROR: " .. result .. "]"
        end
    end

    return {
        level_no = level_no,
        level_name = level_name,
        message_fmt = message_fmt,
        message = formatted_message,
        formatted_message = formatted_message,
        args = args,
        context = context,
        timestamp = os.time(),
        logger_name = logger.name,
        source_logger_name = logger.name, -- Initially the same as logger_name
        filename = debug.getinfo(4, "S").source:match("([^/\\]+)$") or "unknown",
        lineno = debug.getinfo(4, "l").currentline or 0
    }
end

--- Process log record through logger hierarchy
-- @param source_logger table The logger that originated the log event
-- @param log_record table The log record to process
function M.process_log_record(source_logger, log_record)
    -- Step 1: Get the logger tree (all loggers that should process this record)
    local logger_tree = get_logger_tree.get_logger_tree(source_logger)

    -- Step 2: Get all eligible pipelines from all loggers
    local all_eligible_pipelines = {}
    for _, logger in ipairs(logger_tree) do
        local eligible_pipelines = get_pipelines.get_eligible_pipelines(logger, log_record)
        for _, pipeline_entry in ipairs(eligible_pipelines) do
            table.insert(all_eligible_pipelines, pipeline_entry)
        end
    end

    -- Step 3: Process all eligible pipelines
    process.process_pipelines(all_eligible_pipelines, log_record)
end

--- Parses log method arguments (similar to v1 system but simplified)
-- @param ... The variadic arguments passed to a log method
-- @return string, table, table The message format, args table, and context table
function M.parse_log_args(...)
    local packed_varargs = table.pack(...)
    local msg_fmt_val
    local args_val = table.pack() -- Empty args by default
    local context_val = nil

    if packed_varargs.n == 0 then
        -- No arguments
        msg_fmt_val = ""
    elseif packed_varargs.n > 0 and type(packed_varargs[1]) == "table" then
        -- Pattern 2: context_table, [message_format_string, ...format_args]
        context_val = packed_varargs[1]
        if packed_varargs.n >= 2 and type(packed_varargs[2]) == "string" then
            msg_fmt_val = packed_varargs[2]
            if packed_varargs.n >= 3 then
                args_val = table.pack(select(3, ...))
            end
        else
            -- Context only, try to extract message from context.msg
            msg_fmt_val = context_val.msg or ""
        end
    else
        -- Pattern 1: String formatting or single value
        if type(packed_varargs[1]) == "string" then
            msg_fmt_val = packed_varargs[1]
            if packed_varargs.n >= 2 then
                args_val = table.pack(select(2, ...))
            end
        else
            -- Single non-string value, convert to string
            msg_fmt_val = tostring(packed_varargs[1])
        end
    end

    return msg_fmt_val, args_val, context_val
end

--- Formats arguments for logging
-- @param message_fmt string The message format
-- @param args table The arguments table
-- @return string The formatted message
function M.format_message(message_fmt, args)
    if not message_fmt then
        return ""
    end

    if args and args.n and args.n > 0 then
        -- Convert args table to a regular array for string.format
        local format_args = {}
        for i = 1, args.n do
            format_args[i] = args[i]
        end

        local ok, result = pcall(string.format, message_fmt, table.unpack(format_args))
        if ok then
            return result
        else
            -- Fallback if formatting fails
            return message_fmt .. " [FORMAT ERROR: " .. result .. "]"
        end
    else
        return message_fmt
    end
end

-- Expose internal functions that are needed by other modules
M._process_pipeline = process.process_pipeline
M._process_output = process._process_output

return M
