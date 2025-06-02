--- Logger prototype and instance methods
-- This module defines the logger prototype and all methods that operate on logger instances

local core_levels = require("lual.core.levels")
local caller_info = require("lual.core.caller_info")

local M = {}

-- Forward declaration for ingest dispatch
local ingest_dispatch_log_event

--- Logger prototype table
M.logger_prototype = {}

--- Basic logging methods
function M.logger_prototype:debug(...)
    self:log(core_levels.definition.DEBUG, ...)
end

function M.logger_prototype:info(...)
    self:log(core_levels.definition.INFO, ...)
end

function M.logger_prototype:warn(...)
    self:log(core_levels.definition.WARNING, ...)
end

function M.logger_prototype:error(...)
    self:log(core_levels.definition.ERROR, ...)
end

function M.logger_prototype:critical(...)
    self:log(core_levels.definition.CRITICAL, ...)
end

--- Core logging method with argument parsing and record creation
function M.logger_prototype:log(level_no, ...)
    if not self:is_enabled_for(level_no) then
        return
    end

    local filename, lineno, lua_path = caller_info.get_caller_info()

    local packed_varargs = table.pack(...)
    local msg_fmt_val
    local args_val
    local context_val = nil -- Initialize context as nil

    if packed_varargs.n > 0 and type(packed_varargs[1]) == "table" then
        -- This is Pattern 2: context_table, [message_format_string, ...format_args]
        context_val = packed_varargs[1]
        if packed_varargs.n >= 2 and type(packed_varargs[2]) == "string" then
            msg_fmt_val = packed_varargs[2]
            if packed_varargs.n >= 3 then
                args_val = table.pack(select(3, ...)) -- Args from 3rd element of original '...'
            else
                args_val = table.pack()               -- No further args for formatting
            end
        else
            -- Context only (Pattern 2b), or context + non-string second arg.
            -- message_fmt might be extracted from context_val.msg later if desired.
            msg_fmt_val = nil       -- Or extract from context_val.msg
            args_val = table.pack() -- No args for formatting
            if msg_fmt_val == nil and context_val and context_val.msg and type(context_val.msg) == "string" then
                -- Attempt to extract message_fmt from context.msg for Pattern 2b
                msg_fmt_val = context_val.msg
            end
        end
    else
        -- Pattern 1: String Formatting Only, or no arguments after level_no
        -- The first argument (packed_varargs[1]) is message_fmt, rest are args.
        -- context_val remains nil (as initialized).
        if packed_varargs.n > 0 and type(packed_varargs[1]) == "string" then
            msg_fmt_val = packed_varargs[1]
            if packed_varargs.n >= 2 then
                args_val = table.pack(select(2, ...)) -- Args from 2nd element of original '...'
            else
                args_val = table.pack()               -- No further args for formatting
            end
        elseif packed_varargs.n == 0 then             -- No arguments after level_no
            msg_fmt_val = ""                          -- Default to empty string if no message/context
            args_val = table.pack()
        else                                          -- First argument is not a table and not a string (e.g. a number or boolean)
            -- Treat as a single message to be stringified, no further args.
            msg_fmt_val = tostring(packed_varargs[1])
            args_val = table.pack()
        end
    end

    local log_record = {
        level_no = level_no,
        level_name = core_levels.get_level_name(level_no),
        message_fmt = msg_fmt_val,
        args = args_val,
        context = context_val, -- Add the new context field
        timestamp = os.time(),
        logger_name = self.name,
        source_logger_name = self.name, -- Initially the same as logger_name
        filename = filename,
        file_path = filename,           -- Keep file_path for backward compatibility
        lua_path = lua_path,            -- Add the new lua_path field
        lineno = lineno,
    }

    -- Dispatch the log event using the injected function
    ingest_dispatch_log_event(log_record)
end

--- Checks if a logger is enabled for a given level
function M.logger_prototype:is_enabled_for(message_level_no)
    if self.level == core_levels.definition.NONE then
        return message_level_no == core_levels.definition.NONE
    end
    return message_level_no >= self.level
end

--- Gets all effective dispatchers for this logger (including parent dispatchers via propagation)
-- This implements the propagation model where each logger fires its own dispatchers,
-- then the event propagates upward to parent loggers
function M.logger_prototype:get_effective_dispatchers()
    local effective_dispatchers = {}
    local current_logger = self

    -- Get logger configuration fields from schema for consistency and maintainability
    local config_schema = require("lual.schema.config_schema")
    local owner_config_fields = {}

    -- Extract field names from ConfigSchema, excluding fields that shouldn't be propagated
    local excluded_fields = {
        dispatchers = true, -- Handled separately in propagation logic
        -- Add other fields here if they shouldn't be propagated to dispatcher context
    }

    for field_name, _ in pairs(config_schema.ConfigSchema) do
        if not excluded_fields[field_name] then
            table.insert(owner_config_fields, field_name)
        end
    end

    while current_logger do
        -- Add dispatchers from current logger
        for _, dispatcher_item in ipairs(current_logger.dispatchers or {}) do
            local effective_dispatcher = {
                dispatcher_func = dispatcher_item.dispatcher_func,
                presenter_func = dispatcher_item.presenter_func,
                transformer_funcs = dispatcher_item.transformer_funcs or {},
                dispatcher_config = dispatcher_item.dispatcher_config,
            }

            -- Add owner logger configuration fields based on schema
            for _, field in ipairs(owner_config_fields) do
                local owner_field_name = "owner_logger_" .. field
                effective_dispatcher[owner_field_name] = current_logger[field]
            end

            table.insert(effective_dispatchers, effective_dispatcher)
        end

        -- Check if we should continue propagating
        if not current_logger.propagate or not current_logger.parent then
            break
        end
        current_logger = current_logger.parent
    end

    return effective_dispatchers
end

--- Sets the ingest dispatch function (dependency injection)
-- @param dispatch_func function The ingest.dispatch_log_event function
function M.set_ingest_dispatch(dispatch_func)
    ingest_dispatch_log_event = dispatch_func
end

return M
