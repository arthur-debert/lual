--- Dispatch Module
-- This module implements the new dispatch loop logic from step 2.7
--
-- Dispatcher-Specific Levels:
--
-- Dispatchers can optionally be configured with their own levels. During
-- the dispatch loop, once a logger has determined a log event meets its level
-- requirement, it iterates over its dispatchers and performs a second level check
-- against each dispatcher's level.
--
-- This occurs after the logger's own level check, hence a dispatcher's level
-- set to lower (more verbose) than the logger's level will never receive events
-- because the logger will filter them first.
--
-- By default, dispatchers have level NOTSET (0), meaning they will use the
-- logger's effective level.
--
-- This allows for more granular control over which events are sent to each
-- output. For example, you can configure a file dispatcher to receive all DEBUG
-- and above messages, while a console dispatcher only shows WARNING and above.
--
-- Usage example:
--
--   lual.config({
--     level = lual.DEBUG,  -- Root level is DEBUG
--     dispatchers = {
--       {
--         type = lual.file,
--         level = lual.DEBUG,  -- File receives all logs
--         path = "app.log",
--         presenter = { type = lual.json }
--       },
--       {
--         type = lual.console,
--         level = lual.WARNING,  -- Console only shows warnings and above
--         presenter = { type = lual.text }
--       }
--     }
--   })

local core_levels = require("lua.lual.levels")
local all_presenters = require("lual.presenters.init") -- Added for presenter handling

local M = {}

--- Creates a log record
-- @param logger table The source logger
-- @param level_no number The log level number
-- @param level_name string The log level name
-- @param message_fmt string The message format string
-- @param args table The formatting arguments
-- @param context table|nil Optional context table
-- @return table The log record
local function create_log_record(logger, level_no, level_name, message_fmt, args, context)
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

--- Processes a log record through a single dispatcher
-- @param log_record table The log record to process
-- @param dispatcher_entry table The dispatcher configuration (with dispatcher_func, config, etc.)
-- @param logger table The logger that owns this dispatcher
local function process_dispatcher(log_record, dispatcher_entry, logger)
    -- Create a copy of the log record for this dispatcher
    local dispatcher_record = {}
    for k, v in pairs(log_record) do
        dispatcher_record[k] = v
    end

    -- Check dispatcher-specific level if configured
    if dispatcher_entry.config and dispatcher_entry.config.level then
        -- Dispatcher level check: skip if log_record.level_no < dispatcher.level
        if log_record.level_no < dispatcher_entry.config.level then
            return -- Skip this dispatcher as its level is higher than the log record
        end
    end

    -- For test cases that set the level directly on the dispatcher_entry
    if dispatcher_entry.level and not (dispatcher_entry.config and dispatcher_entry.config.level) then
        if log_record.level_no < dispatcher_entry.level then
            return -- Skip this dispatcher based on level set directly on entry
        end
    end

    -- Add logger context to the record
    dispatcher_record.owner_logger_name = logger.name
    dispatcher_record.owner_logger_level = logger.level
    dispatcher_record.owner_logger_propagate = logger.propagate

    -- Add dispatcher level to the record for informational purposes
    if dispatcher_entry.config and dispatcher_entry.config.level then
        dispatcher_record.dispatcher_level = dispatcher_entry.config.level
    else
        if dispatcher_entry.level then
            dispatcher_record.dispatcher_level = dispatcher_entry.level
        else
            dispatcher_record.dispatcher_level = core_levels.definition.NOTSET
        end
    end

    -- Apply transformers if configured
    if dispatcher_entry.config and dispatcher_entry.config.transformers then
        for _, transformer in ipairs(dispatcher_entry.config.transformers) do
            local ok, result = pcall(function()
                if type(transformer) == "function" then
                    return transformer(dispatcher_record)
                elseif type(transformer) == "table" and type(transformer.func) == "function" then
                    return transformer.func(dispatcher_record, transformer.config)
                end
                return dispatcher_record
            end)
            if ok and result then
                dispatcher_record = result
            else
                dispatcher_record.transformer_error = result
            end
        end
    end

    -- Apply single transformer if configured
    if dispatcher_entry.config and dispatcher_entry.config.transformer then
        local transformer = dispatcher_entry.config.transformer
        local ok, result = pcall(function()
            if type(transformer) == "function" then
                return transformer(dispatcher_record)
            elseif type(transformer) == "table" and type(transformer.func) == "function" then
                return transformer.func(dispatcher_record, transformer.config)
            end
            return dispatcher_record
        end)
        if ok and result then
            dispatcher_record = result
        else
            dispatcher_record.transformer_error = result
        end
    end

    -- Apply presenter if configured
    if dispatcher_entry.config and dispatcher_entry.config.presenter then
        local presenter_config = dispatcher_entry.config.presenter
        local presenter_func = nil

        if type(presenter_config) == "string" then
            -- Legacy: Handle string presenter types like "text", "json"
            if all_presenters and all_presenters[presenter_config] then
                presenter_func = all_presenters[presenter_config]() -- Call factory
            else
                io.stderr:write(string.format("LUAL: Presenter type '%s' not found.\n", presenter_config))
                dispatcher_record.presenter_error = "Presenter type not found: " .. presenter_config
            end
        elseif type(presenter_config) == "table" then
            if presenter_config.type then
                if type(presenter_config.type) == "string" then
                    -- Legacy: Handle table with string type { type = "text" }
                    if all_presenters and all_presenters[presenter_config.type] then
                        presenter_func = all_presenters[presenter_config.type](presenter_config.config) -- Call factory with config
                    else
                        io.stderr:write(string.format("LUAL: Presenter type '%s' not found.\n", presenter_config.type))
                        dispatcher_record.presenter_error = "Presenter type not found: " .. presenter_config.type
                    end
                elseif type(presenter_config.type) == "function" then
                    -- New approach: Handle table with function reference type { type = lual.text }
                    presenter_func = presenter_config.type(presenter_config.config) -- Call factory with config
                end
            else
                -- Assume it's already a presenter function or object
                presenter_func = presenter_config
            end
        elseif type(presenter_config) == "function" then
            -- Direct function - either a presenter or a factory
            -- Try to call it as a factory first
            local ok, result = pcall(presenter_config)
            if ok and type(result) == "function" then
                -- It was a factory that returned a presenter function
                presenter_func = result
            else
                -- It's already a presenter function, not a factory
                presenter_func = presenter_config
            end
        end

        if presenter_func and type(presenter_func) == "function" then
            local ok, result = pcall(presenter_func, dispatcher_record)
            if ok and result then
                dispatcher_record.presented_message = result
                dispatcher_record.message = result -- Overwrite message with presented message
            else
                dispatcher_record.presenter_error = result
                io.stderr:write(string.format("LUAL: Error in presenter function: %s\n", tostring(result)))
            end
        elseif not dispatcher_record.presenter_error then -- Don't overwrite if error already set
            -- This case means presenter_config was a table but not a valid config or function
            io.stderr:write(string.format("LUAL: Invalid presenter configuration: %s\n", type(presenter_config)))
            dispatcher_record.presenter_error = "Invalid presenter configuration"
        end
    end

    -- If we get here, the dispatcher level check passed (or there was no level configured)
    local ok, err = pcall(function()
        dispatcher_entry.dispatcher_func(dispatcher_record, dispatcher_entry.config)
    end)
    if not ok then
        -- Add retry logic if required, or at least log the error
        io.stderr:write(string.format("Error dispatching log record: %s\n", err))
    end
end

--- Implements the new dispatch loop logic from step 2.7
-- This is the core of event processing for each logger L in the hierarchy
-- @param source_logger table The logger that originated the log event
-- @param log_record table The log record to process
function M.dispatch_log_event(source_logger, log_record)
    local current_logger = source_logger

    -- Process through the hierarchy (from source up to _root)
    while current_logger do
        -- Step 1: Calculate L's effective level using L:_get_effective_level()
        local effective_level = current_logger:_get_effective_level()

        -- Step 2: If event_level >= L.effective_level (level match)
        if log_record.level_no >= effective_level then
            -- Step 2a: For each dispatcher in L's *own* dispatchers list
            for _, dispatcher_entry in ipairs(current_logger.dispatchers) do
                -- Step 2a.i: (Optional) Process record through L's transformers
                -- Step 2a.ii: Format record using the dispatcher's presenter
                -- Step 2a.iii: Send formatted output via the dispatcher
                process_dispatcher(log_record, dispatcher_entry, current_logger)
            end

            -- Step 2b: If L has no dispatchers, it produces no output itself
            -- (This is handled naturally by the empty loop above)
        end

        -- Step 3: If L is _root, stop after processing its dispatchers
        if current_logger.name == "_root" then
            break
        end

        -- Step 4: If L.propagate is false, stop propagation
        if not current_logger.propagate then
            break
        end

        -- Step 5: Continue to parent
        current_logger = current_logger.parent
    end
end

--- Formats arguments for logging
-- @param message_fmt string The message format
-- @param args table The arguments table
-- @return string The formatted message
local function format_message(message_fmt, args)
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

--- Parses log method arguments (similar to v1 system but simplified)
-- @param ... The variadic arguments passed to a log method
-- @return string, table, table The message format, args table, and context table
local function parse_log_args(...)
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

-- @return table Table of logging methods
function M.create_logging_methods()
    local methods = {}

    -- Helper function to create a log method for a specific level
    local function create_log_method(level_no, level_name)
        return function(self, ...)
            -- Check if logging is enabled for this level
            local effective_level = self:_get_effective_level()
            if level_no < effective_level then
                return -- Early exit if level not enabled
            end

            -- Parse arguments
            local msg_fmt, args, context = parse_log_args(...)

            -- Create log record
            local log_record = create_log_record(self, level_no, level_name, msg_fmt, args, context)

            M.dispatch_log_event(self, log_record)
        end
    end

    -- Create methods for each log level
    methods.debug = create_log_method(core_levels.definition.DEBUG, "DEBUG")
    methods.info = create_log_method(core_levels.definition.INFO, "INFO")
    methods.warn = create_log_method(core_levels.definition.WARNING, "WARNING")
    methods.error = create_log_method(core_levels.definition.ERROR, "ERROR")
    methods.critical = create_log_method(core_levels.definition.CRITICAL, "CRITICAL")

    -- Generic log method
    methods.log = function(self, level_no, ...)
        -- Validate level
        if type(level_no) ~= "number" then
            error("Log level must be a number, got " .. type(level_no))
        end

        -- Check if logging is enabled for this level
        local effective_level = self:_get_effective_level()
        if level_no < effective_level then
            return -- Early exit if level not enabled
        end

        -- Get level name
        local level_name = core_levels.get_level_name(level_no)

        -- Parse arguments
        local msg_fmt, args, context = parse_log_args(...)

        -- Create log record
        local log_record = create_log_record(self, level_no, level_name, msg_fmt, args, context)
        M.dispatch_log_event(self, log_record)
    end

    return methods
end

return M
