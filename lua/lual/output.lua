--- Output Module
-- This module implements the new output loop logic from step 2.7
--
-- Output-Specific Levels:
--
-- Outputs can optionally be configured with their own levels. During
-- the output loop, once a logger has determined a log event meets its level
-- requirement, it iterates over its outputs and performs a second level check
-- against each output's level.
--
-- This occurs after the logger's own level check, hence a output's level
-- set to lower (more verbose) than the logger's level will never receive events
-- because the logger will filter them first.
--
-- By default, outputs have level NOTSET (0), meaning they will use the
-- logger's effective level.
--
-- This allows for more granular control over which events are sent to each
-- output. For example, you can configure a file output to receive all DEBUG
-- and above messages, while a console output only shows WARNING and above.
--
-- Usage example:
--
--   lual.config({
--     level = lual.DEBUG,  -- Root level is DEBUG
--     outputs = {
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
local all_presenters = require("lual.presenters.init")
local all_transformers = require("lual.transformers.init")
local component_utils = require("lual.utils.component")

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

--- Processes a single transformer
-- @param record table The log record to process
-- @param transformer function|table The transformer function or config
-- @return table The transformed record, or nil and error message
local function process_transformer(record, transformer)
    -- Create a copy of the record for the transformer
    local transformed_record = {}
    for k, v in pairs(record) do
        transformed_record[k] = v
    end

    -- Normalize transformer to standard format
    local normalized = component_utils.normalize_component(transformer, component_utils.TRANSFORMER_DEFAULTS)
    local transformer_func = normalized.func
    local transformer_config = normalized.config

    -- Apply the transformer
    local ok, result = pcall(transformer_func, transformed_record, transformer_config)
    if not ok then
        return nil, "Transformer error: " .. tostring(result)
    end

    return result or transformed_record
end

--- Processes a single presenter
-- @param record table The log record to process
-- @param presenter function|table The presenter function or config
-- @return string|nil The presented message, or nil and error message
local function process_presenter(record, presenter)
    -- Normalize presenter to standard format
    local normalized = component_utils.normalize_component(presenter, component_utils.PRESENTER_DEFAULTS)
    local presenter_func = normalized.func
    local presenter_config = normalized.config

    -- Apply the presenter
    local ok, result = pcall(presenter_func, record, presenter_config)
    if not ok then
        io.stderr:write(string.format("LUAL: Error in presenter function: %s\n", tostring(result)))
        return nil, result
    end

    return result
end

--- Processes a log record through a single output
-- @param log_record table The log record to process
-- @param output_entry table|function The output configuration or function
-- @param logger table The logger that owns this output
local function process_output(log_record, output_entry, logger)
    -- Create a copy of the log record for this output
    local output_record = {}
    for k, v in pairs(log_record) do
        output_record[k] = v
    end

    -- Normalize output to standard format
    local normalized = component_utils.normalize_component(output_entry, component_utils.DISPATCHER_DEFAULTS)
    local output_func = normalized.func
    local output_config = normalized.config

    -- Add logger context to the record
    output_record.owner_logger_name = logger.name
    output_record.owner_logger_level = logger.level
    output_record.owner_logger_propagate = logger.propagate

    -- Handle output level filtering
    local output_level = output_config.level

    -- Apply level filtering if a level is set
    if output_level and type(output_level) == "number" and output_level > 0 then -- Skip NOTSET (0)
        if log_record.level_no < output_level then
            -- Skip this output as its level is higher than the log record
            return
        end
    end

    -- Add output level to the record for informational purposes
    if output_level then
        output_record.output_level = output_level
    else
        output_record.output_level = core_levels.definition.NOTSET
    end

    -- Apply transformers array if configured
    if output_config.transformers then
        for _, transformer in ipairs(output_config.transformers) do
            local transformed_record, error_msg = process_transformer(output_record, transformer)
            if transformed_record then
                output_record = transformed_record
            else
                output_record.transformer_error = error_msg
                break -- Stop processing transformers if one fails
            end
        end
    end

    -- Apply single transformer if configured
    if output_config.transformer and not output_record.transformer_error then
        local transformed_record, error_msg = process_transformer(output_record, output_config.transformer)
        if transformed_record then
            output_record = transformed_record
        else
            output_record.transformer_error = error_msg
        end
    end

    -- Apply presenter if configured
    if output_config.presenter and not output_record.transformer_error then
        local presented_message, error_msg = process_presenter(output_record, output_config.presenter)
        if presented_message then
            output_record.presented_message = presented_message
            output_record.message = presented_message -- Overwrite message with presented message
        else
            output_record.presenter_error = error_msg
        end
    end

    -- Output the record
    local ok, err = pcall(function()
        -- This is the key fix - make sure we don't lose the level in the config
        output_func(output_record, output_config)
    end)
    if not ok then
        io.stderr:write(string.format("Error outputing log record: %s\n", err))
    end
end

--- Core process output logic
-- @param log_record table The log record to process
-- @param outputs table|function Array or single output
-- @param context_logger table The logger being used for this output
local function process_outputs(log_record, outputs, context_logger)
    if not outputs or #outputs == 0 then
        return -- Nothing to do
    end

    for _, output in ipairs(outputs) do
        process_output(log_record, output, context_logger)
    end
end

--- Implements the new output loop logic from step 2.7
-- This is the core of event processing for each logger L in the hierarchy
-- @param source_logger table The logger that originated the log event
-- @param log_record table The log record to process
function M.output_log_event(source_logger, log_record)
    local current_logger = source_logger

    -- Process through the hierarchy (from source up to _root)
    while current_logger do
        -- Step 1: Calculate L's effective level using L:_get_effective_level()
        local effective_level = current_logger:_get_effective_level()

        -- Step 2: If event_level >= L.effective_level (level match)
        if log_record.level_no >= effective_level then
            -- Step 2a: For each output in L's *own* outputs list
            for _, output_entry in ipairs(current_logger.outputs) do
                -- Step 2a.i: (Optional) Process record through L's transformers
                -- Step 2a.ii: Format record using the output's presenter
                -- Step 2a.iii: Send formatted output via the output
                process_output(log_record, output_entry, current_logger)
            end

            -- Step 2b: If L has no outputs, it produces no output itself
            -- (This is handled naturally by the empty loop above)
        end

        -- Step 3: If L is _root, stop after processing its outputs
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

            M.output_log_event(self, log_record)
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
        M.output_log_event(self, log_record)
    end

    return methods
end

-- Expose internal functions for testing
M._create_log_record = create_log_record
M._process_output = process_output
M._format_message = format_message
M._parse_log_args = parse_log_args

return M
